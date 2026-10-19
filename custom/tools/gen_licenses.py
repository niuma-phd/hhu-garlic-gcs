"""Regenerate custom/deploy/licenses/ — the open source notices shipped in <install dir>\\licenses
and shown by the installer (README.txt is the license page of the NSIS wizard).

    python custom/tools/gen_licenses.py [--qt D:/2Software/Qt/6.11.1/msvc2022_64]

Sources:
    LICENSE-APACHE / LICENSE-GPL               QGroundControl (repo root)
    <Qt>/../../Licenses/LICENSE                Qt: the LGPLv3 part is extracted
    <Qt>/sbom/<repo>-<ver>.spdx.json           Qt: bundled third-party code of the deployed Qt repos
    .cache/CPM/<pkg>/*/LICENSE|COPYING...      libraries QGC builds in (statically linked)
    custom/res/fonts/*LICENSE*, *OFL*          fonts (copied unchanged; fonts/ keeps its own copies)
README.txt is written by hand (custom/deploy/licenses/README.txt) and only checked to exist.
"""
import argparse
import json
import pathlib
import shutil
import sys

CUSTOM = pathlib.Path(__file__).resolve().parent.parent
ROOT = CUSTOM.parent
OUT = CUSTOM / "deploy" / "licenses"

# Qt repositories whose libraries / plugins windeployqt puts next to GCS.exe
# (Qt6Core..Qt6Xml, Quick / Controls / Dialogs, Location, Positioning, Multimedia, SerialPort,
# Sensors, TextToSpeech, ShaderTools, Quick3D, Lottie, VirtualKeyboard, Graphs, Bluetooth, StateMachine)
QT_REPOS = [
    "qtbase", "qtdeclarative", "qtsvg", "qtimageformats", "qtlocation", "qtpositioning",
    "qtmultimedia", "qtserialport", "qtsensors", "qtspeech", "qtshadertools", "qtquick3d",
    "qtlottie", "qtvirtualkeyboard", "qtgraphs", "qtconnectivity", "qtscxml",
]

# CPM packages QGC fetches and builds in; vulkanheaders / sdl_gamecontrollerdb / ardupilotparams are
# headers or data, listed anyway when they carry a license file
LICENSE_NAMES = ("LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING", "COPYING.md", "LICENSE-MIT",
                 "LICENSE-LGPL", "LICENSE.from_folly")


def write_text(path, text):
    path.write_text(text.replace("\r\n", "\n").replace("\n", "\r\n"), encoding="utf-8", newline="")


def copy_text(src, dst):
    write_text(dst, src.read_text(encoding="utf-8", errors="replace"))


def qt_lgpl(qt):
    lic = (qt / ".." / ".." / "Licenses" / "LICENSE").resolve()
    text = lic.read_text(encoding="utf-8", errors="replace")
    start = text.index("GNU LESSER GENERAL PUBLIC LICENSE", text.index("GNU GENERAL PUBLIC LICENSE"))
    start = text.rfind("\n", 0, start) + 1
    write_text(OUT / "Qt_LGPL-3.0.txt", text[start:].rstrip() + "\n")


def qt_third_party(qt):
    version = qt.parent.name
    seen = {}
    for repo in QT_REPOS:
        sbom = qt / "sbom" / f"{repo}-{version}.spdx.json"
        if not sbom.exists():
            sys.exit(f"missing {sbom}")
        doc = json.loads(sbom.read_text(encoding="utf-8"))
        extracted = {e["licenseId"]: e for e in doc.get("hasExtractedLicensingInfos", [])}
        for p in doc["packages"]:
            sid = p.get("SPDXID", "")
            if "3rdparty" not in sid or p["name"].startswith("Bootstrap"):
                continue
            name = p["name"].split("_Attribution_")[-1]
            lic = p.get("licenseConcluded") or p.get("licenseDeclared") or "NOASSERTION"
            key = (name, lic)
            if key in seen:
                continue
            refs = [extracted[r] for r in extracted if r in lic]
            seen[key] = (repo, name, lic, (p.get("copyrightText") or "").strip(), p.get("versionInfo", ""), refs)

    lines = [
        f"Third-party components bundled in Qt {version} (as deployed with this software)",
        "Qt 自带的第三方组件（随本软件部署的 Qt 模块）",
        "",
        f"Generated from the Qt SPDX SBOMs (<Qt>/sbom/<repo>-{version}.spdx.json) of: " + ", ".join(QT_REPOS),
        "License identifiers are SPDX identifiers (https://spdx.org/licenses/). Texts of non-standard",
        "licenses (LicenseRef-*) follow the entry.",
        "",
    ]
    for repo, name, lic, copyright_text, ver, refs in sorted(seen.values(), key=lambda v: v[1].lower()):
        lines.append("=" * 78)
        lines.append(f"{name}{(' ' + ver) if ver and ver != 'NOASSERTION' else ''}   [{repo}]")
        lines.append(f"License: {lic}")
        if copyright_text and copyright_text != "NOASSERTION":
            lines.append(copyright_text)
        for r in refs:
            lines.append("")
            lines.append(f"--- {r['licenseId']} ---")
            lines.append(r.get("extractedText", "").strip())
        lines.append("")
    write_text(OUT / "Qt_third_party.txt", "\n".join(lines))
    return len(seen)


def cpm_licenses():
    dst = OUT / "third_party"
    dst.mkdir(exist_ok=True)
    names = []
    for pkg in sorted((ROOT / ".cache" / "CPM").iterdir()):
        for src_dir in sorted(p for p in pkg.iterdir() if p.is_dir()):
            for f in sorted(src_dir.iterdir()):
                if f.is_file() and (f.name in LICENSE_NAMES or f.name.startswith("COPYING")):
                    base = f.stem if f.suffix in (".txt", ".md") else f.name
                    copy_text(f, dst / f"{pkg.name}_{base}.txt")
                    names.append(f"{pkg.name}_{base}.txt")
            break  # one source dir per package
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qt", default="D:/2Software/Qt/6.11.1/msvc2022_64")
    qt = pathlib.Path(ap.parse_args().qt)

    if not (OUT / "README.txt").exists():
        sys.exit("custom/deploy/licenses/README.txt is missing (written by hand)")
    for p in OUT.iterdir():
        if p.name == "README.txt":
            continue
        shutil.rmtree(p) if p.is_dir() else p.unlink()

    copy_text(ROOT / "LICENSE-APACHE", OUT / "QGroundControl_LICENSE-APACHE.txt")
    copy_text(ROOT / "LICENSE-GPL", OUT / "QGroundControl_LICENSE-GPL-3.0.txt")
    qt_lgpl(qt)
    n_qt = qt_third_party(qt)
    shutil.copyfile(CUSTOM / "res" / "fonts" / "HarmonyOS_Sans_LICENSE.txt", OUT / "HarmonyOS_Sans_LICENSE.txt")
    shutil.copyfile(CUSTOM / "res" / "fonts" / "Barlow-OFL.txt", OUT / "Barlow_OFL-1.1.txt")
    # FFmpeg (Qt Multimedia's ffmpeg backend: avcodec / avformat / avutil / swresample / swscale DLLs)
    copy_text(ROOT / ".cache" / "CPM" / "liblzma" / next(iter(sorted(p.name for p in (ROOT / ".cache" / "CPM" / "liblzma").iterdir()))) / "COPYING.LGPLv2.1",
              OUT / "FFmpeg_LGPL-2.1.txt")
    cpm = cpm_licenses()
    print(f"licenses: Qt third-party {n_qt} entries, CPM {len(cpm)} files -> {OUT}")


if __name__ == "__main__":
    main()
