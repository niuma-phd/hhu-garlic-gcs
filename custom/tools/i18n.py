"""HHU zh_CN translation tooling for the QGC custom build.

Layout (all under custom/):
    translations/hhu_source_zh_CN.ts   overlay for upstream C++/QML strings (only entries we (re)translate)
    translations/hhu_json_zh_CN.ts     overlay for upstream JSON metadata strings
    translations/hhu_custom_zh_CN.ts   strings from our own QML and C++ (custom/src), refreshed by lupdate
    res/i18n/*.qm                      compiled output, embedded via custom.qrc

At runtime CustomPlugin installs hhu_source_zh_CN.qm on top of upstream's
translator and loads hhu_json_zh_CN.qm (upstream json + our overlay, merged
here) into JsonParsing::translator().

Commands:
    python custom/tools/i18n.py extract out.tsv   # strings still needing work, customer-reachable scope only
    python custom/tools/i18n.py apply in.tsv      # merge a filled TSV into the overlay .ts files
    python custom/tools/i18n.py lupdate           # refresh hhu_custom_zh_CN.ts from custom/src/qml
    python custom/tools/i18n.py build             # validate + compile .qm files

TSV columns: kind (source|json|custom), context, source, translation. Newlines/tabs escaped as \\n \\t.
"""
import pathlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

CUSTOM = pathlib.Path(__file__).resolve().parent.parent
ROOT = CUSTOM.parent
QT_BIN = pathlib.Path("D:/2Software/Qt/6.11.1/msvc2022_64/bin")
UP_SOURCE = ROOT / "translations" / "qgc_source_zh_CN.ts"
UP_JSON = ROOT / "translations" / "qgc_json_zh_CN.ts"
TR_DIR = CUSTOM / "translations"
QM_DIR = CUSTOM / "res" / "i18n"
OVL = {
    "source": TR_DIR / "hhu_source_zh_CN.ts",
    "json": TR_DIR / "hhu_json_zh_CN.ts",
    "custom": TR_DIR / "hhu_custom_zh_CN.ts",
}

# Source directories the customer UI can reach (vehicle setup / analyze tools are hidden)
SOURCE_DIRS = {
    "API", "AppSettings", "Comms", "FactSystem", "FirmwarePlugin", "FlightMap", "FlyView", "GPS",
    "MainWindow", "MAVLink", "MissionManager", "PlanView", "QmlControls", "QtLocationPlugin",
    "Settings", "Toolbar", "Utilities", "Vehicle", "QGCApplication.cc",
}
# Files inside those dirs that are PX4 / aircraft / hidden-feature only
SOURCE_SKIP = re.compile(
    r"PX4|Px4|VTOL|Vtol|FixedWing|MultiRotor|Copter|Plane|ArduSub|Sub[A-Z.]|Gimbal|Camera|Joystick|Video|"
    r"RemoteID|ADSB|Viewer3D|Takeoff|Landing|Orbit|ROI|Survey|Corridor|Structure|Transect|Esc|EFI|Generator|"
    r"PreFlight|Checklist|VirtualJoystick|Terrain|Obstacle|Proximity|LogReplay|MockLink|Debug|QmlTest|"
    r"Bluetooth|Android|FirstRunPrompt|Gripper|Winch|Instrument|Attitude|Compass|FlightDisplayView|"
    r"RemoteControl|Autotune|FirmwareUpgrade|VehicleConfig|ParameterEditor|Signing|FTP|AppLogging|"
    r"QGCFileDownload|MAVLinkInspector|Calibration|/main\.cc|LogDownload|MAVLinkChart|GeoTag|Vibration|"
    r"PIDTuning|RCChannel|RCToParam|Servo|Motor|Airframe|Sensors|Tuning|Follow|Gimbal|Custom(?!.*Map)|"
    r"Actuators/|VehicleSetup/|ComponentInformation/|ParameterDiff|GCSControl|Platform/"
)
JSON_CONTEXTS = {
    "App.SettingsGroup.json", "AutoConnect.SettingsGroup.json", "BatteryFact.json", "CommLinks.SettingsUI.json",
    "FlightMap.SettingsGroup.json", "FlightMode.SettingsGroup.json", "General.SettingsUI.json", "GPSFact.json",
    "GPSRTKFact.json", "Maps.SettingsGroup.json", "Maps.SettingsUI.json", "MavCmdInfoCommon.json",
    "MavCmdInfoRover.json", "Mavlink.SettingsGroup.json", "NTRIP.SettingsGroup.json", "NTRIP.SettingsUI.json",
    "OfflineMaps.SettingsGroup.json", "PlanView.SettingsGroup.json", "RadioStatusFact.json",
    "RTK.SettingsGroup.json", "SettingsPages.json", "Units.SettingsGroup.json", "VehicleFact.json",
    "Mission.SettingsGroup.json", "MissionSettings.FactMetaData.json", "SpeedSection.FactMetaData.json",
}
# Existing translations using aircraft wording get re-translated for a rover
AVIATION = re.compile(r"返航|飞|无人机|机体|降落|起飞|航空|飞机|多旋翼|固定翼")

PLACEHOLDER = re.compile(r"%L?\d+|%n")
HTML_TAG = re.compile(r"</?(?:a|b|i|u|p|br|hr|font|span|div|strong|em|small|big|tt|code|sub|sup|ul|ol|li|table|tr|td|th|h[1-6]|center|img)[^>]*>", re.I)


def _collect_enum_strings():
    """enumStrings values from upstream JSON metadata: these are split on ',' after translation."""
    found = set()
    for path in (ROOT / "src").rglob("*.json"):
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        found.update(m.group(1) for m in re.finditer(r'"enumStrings"\s*:\s*"((?:[^"\\]|\\.)*)"', text))
    return found


ENUM_STRINGS = _collect_enum_strings()


def esc(s):
    return (s or "").replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")


def unesc(s):
    return re.sub(r"\\(\\|t|n)", lambda m: {"\\": "\\", "t": "\t", "n": "\n"}[m.group(1)], s)


def untranslated(msg):
    tr = msg.find("translation")
    return tr is None or tr.get("type") in ("unfinished", "vanished", "obsolete") or not (tr.text or "").strip()


def iter_messages(path):
    tree = ET.parse(path)
    for ctx in tree.getroot().iter("context"):
        name = ctx.find("name").text
        for msg in ctx.iter("message"):
            yield tree, name, msg


def source_in_scope(msg):
    loc = msg.find("location")
    if loc is None:
        return False
    fname = loc.get("filename").replace("\\", "/")
    rel = fname.split("/src/", 1)[1] if "/src/" in fname else fname
    top = rel.split("/")[0]
    return top in SOURCE_DIRS and not SOURCE_SKIP.search(rel)


def load_overlay(kind):
    """{(context, source): translation}"""
    out = {}
    if OVL[kind].exists():
        for _, ctx, msg in iter_messages(OVL[kind]):
            tr = msg.find("translation")
            if tr is not None and (tr.text or "").strip() and tr.get("type") != "unfinished":
                out[(ctx, msg.find("source").text)] = tr.text
    return out


def cmd_extract(out_path):
    rows = []
    for kind, path, in_scope in (
        ("source", UP_SOURCE, lambda ctx, m: source_in_scope(m)),
        ("json", UP_JSON, lambda ctx, m: ctx in JSON_CONTEXTS),
    ):
        done = load_overlay(kind)
        seen = set()
        for _, ctx, msg in iter_messages(path):
            src = msg.find("source").text or ""
            key = (ctx, src)
            if key in seen or key in done or not src.strip() or not in_scope(ctx, msg):
                continue
            seen.add(key)
            tr = msg.find("translation")
            current = "" if untranslated(msg) else (tr.text or "")
            if current and not AVIATION.search(current):
                continue
            rows.append((kind, ctx, src, current))
    if OVL["custom"].exists():
        for _, ctx, msg in iter_messages(OVL["custom"]):
            if untranslated(msg):
                rows.append(("custom", ctx, msg.find("source").text or "", ""))
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        for kind, ctx, src, cur in rows:
            f.write("\t".join([kind, ctx, esc(src), esc(cur)]) + "\n")
    print(f"{len(rows)} strings -> {out_path}")


def validate(kind, ctx, src, tr):
    errs = []
    if sorted(PLACEHOLDER.findall(src)) != sorted(PLACEHOLDER.findall(tr)):
        errs.append("placeholder mismatch")
    if kind == "json" and src in ENUM_STRINGS:
        if "，" in tr or "、" in tr or tr.count(",") != src.count(","):
            errs.append("enum list must keep %d ASCII commas" % src.count(","))
    if "&" in src and re.search(r"&\w", src) and not re.search(r"&\w", tr):
        pass  # mnemonics are not used by QML; ignore
    if HTML_TAG.findall(src) != HTML_TAG.findall(tr):
        errs.append("markup tags differ")
    return errs


def write_ts(path, entries, language="zh_CN"):
    """entries: {(context, source): translation}"""
    root = ET.Element("TS", version="2.1", language=language)
    by_ctx = {}
    for (ctx, src), tr in sorted(entries.items()):
        by_ctx.setdefault(ctx, []).append((src, tr))
    for ctx, items in by_ctx.items():
        c = ET.SubElement(root, "context")
        ET.SubElement(c, "name").text = ctx
        for src, tr in items:
            m = ET.SubElement(c, "message")
            ET.SubElement(m, "source").text = src
            t = ET.SubElement(m, "translation")
            t.text = tr
            if not tr:
                t.set("type", "unfinished")
    ET.indent(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(b'<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n')
        f.write(ET.tostring(root, encoding="utf-8"))


def cmd_apply(tsv_path):
    per_kind = {k: load_overlay(k) for k in OVL}
    # keep untranslated custom entries so lupdate output is not lost
    if OVL["custom"].exists():
        for _, ctx, msg in iter_messages(OVL["custom"]):
            per_kind["custom"].setdefault((ctx, msg.find("source").text), "")
    bad = 0
    for n, line in enumerate(open(tsv_path, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            print(f"line {n}: expected 4 columns, got {len(parts)}")
            bad += 1
            continue
        kind, ctx, src, tr = parts[0], parts[1], unesc(parts[2]), unesc(parts[3]).strip()
        if not tr:
            continue
        errs = validate(kind, ctx, src, tr)
        if errs:
            print(f"line {n}: {ctx} | {src!r} -> {tr!r}: {', '.join(errs)}")
            bad += 1
            continue
        per_kind[kind][(ctx, src)] = tr
    for kind, entries in per_kind.items():
        if entries:
            write_ts(OVL[kind], entries)
            print(f"{OVL[kind].name}: {sum(1 for v in entries.values() if v)} entries")
    return bad


def cmd_lupdate():
    qml = sorted(str(p) for p in (CUSTOM / "src" / "qml").rglob("*.qml") if p.name != "SettingsPagesModel.qml")
    cpp = sorted(str(p) for p in (CUSTOM / "src").glob("*.cc"))
    subprocess.run([str(QT_BIN / "lupdate.exe"), "-silent", "-no-obsolete", "-locations", "none",
                    *qml, *cpp, "-ts", str(OVL["custom"])], check=True)
    print("refreshed", OVL["custom"].name)


def cmd_build():
    errors = 0
    for kind in ("source", "json", "custom"):
        if not OVL[kind].exists():
            continue
        for _, ctx, msg in iter_messages(OVL[kind]):
            tr = msg.find("translation")
            if tr is None or not (tr.text or "").strip():
                continue
            for e in validate(kind, ctx, msg.find("source").text or "", tr.text):
                print(f"{OVL[kind].name}: {ctx} | {msg.find('source').text!r}: {e}")
                errors += 1
    if errors:
        sys.exit(f"{errors} validation errors")

    # JSON: upstream file with overlay translations substituted (JsonParsing uses a single translator)
    overlay = load_overlay("json")
    tree = ET.parse(UP_JSON)
    applied = set()
    contexts = {}
    for ctx in tree.getroot().iter("context"):
        name = ctx.find("name").text
        contexts[name] = ctx
        for msg in ctx.iter("message"):
            key = (name, msg.find("source").text)
            if key in overlay:
                tr = msg.find("translation")
                tr.text = overlay[key]
                tr.attrib.pop("type", None)
                applied.add(key)
    # Strings newer than upstream's .ts (not listed there yet) are appended
    for (name, source), text in overlay.items():
        if (name, source) in applied:
            continue
        ctx = contexts.get(name)
        if ctx is None:
            ctx = ET.SubElement(tree.getroot(), "context")
            ET.SubElement(ctx, "name").text = name
            contexts[name] = ctx
        msg = ET.SubElement(ctx, "message")
        ET.SubElement(msg, "source").text = source
        ET.SubElement(msg, "translation").text = text
    merged = TR_DIR / "_merged_json_zh_CN.ts"
    tree.write(merged, encoding="utf-8", xml_declaration=True)

    QM_DIR.mkdir(parents=True, exist_ok=True)
    lrelease = str(QT_BIN / "lrelease.exe")
    src_inputs = [str(OVL[k]) for k in ("source", "custom") if OVL[k].exists()]
    subprocess.run([lrelease, "-silent", *src_inputs, "-qm", str(QM_DIR / "hhu_source_zh_CN.qm")], check=True)
    subprocess.run([lrelease, "-silent", str(merged), "-qm", str(QM_DIR / "hhu_json_zh_CN.qm")], check=True)
    merged.unlink()
    print("built", *sorted(p.name for p in QM_DIR.glob("*.qm")))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "extract":
        cmd_extract(sys.argv[2])
    elif cmd == "apply":
        sys.exit(1 if cmd_apply(sys.argv[2]) else 0)
    elif cmd == "lupdate":
        cmd_lupdate()
    elif cmd == "build":
        cmd_build()
    else:
        sys.exit(__doc__)
