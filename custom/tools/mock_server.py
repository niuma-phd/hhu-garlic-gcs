"""Test server for the HHU ground station: 4G relay + update / log upload API.

Implements the protocol of 需求说明 V1.0 §4.2 / §4.4 (and the log upload proposal documented in
custom/src/HHUService.h) so the ground station can be tested without the real server:

  4G relay (TCP, optional TLS), default port 7000
    GCS sends one JSON line {"type":"auth",...}; the server answers {"type":"auth_result",...};
    then MAVLink bytes are relayed between the GCS and the vehicle. The "vehicle" is a TCP
    connection to SITL (default 127.0.0.1:5762, the second SITL serial port). The first GCS gets
    "control", further ones "readonly". An "ntrip" object in the login is stored (ntrip_saved).

  HTTP API, default port 7080
    GET  /api/version                 -> {"version","url","sha256","notes"}
    GET  /download/<file>             -> installer file (from --installer)
    POST /api/logs                    -> {"upload_id","received"}
    GET  /api/logs/<id>               -> {"received"}
    PUT  /api/logs/<id>?offset=<n>    -> {"received"}
    POST /api/logs/<id>/complete      -> {"ticket"}  (file stored in --upload-dir, sha256 checked)

  NTRIP caster, default port 2101: user test / password test, mountpoints RTCM32 and VRS
    (401 on a wrong account, 404 on an unknown mountpoint, "/" gives the source table)

Usage (Windows or WSL):
    python mock_server.py --vehicle HHU001 --password 123456 --sitl 127.0.0.1:5762
    python mock_server.py --offline          # every login answers code 2 (vehicle offline)
    python mock_server.py --force-readonly   # every login is read only (another GCS has control)
    python mock_server.py --tls cert.pem key.pem   # TLS on the relay port
Commands on stdin while running: "drop" closes all GCS connections (simulated 4G outage),
"quit" stops the server.
"""
import argparse
import asyncio
import base64
import hashlib
import json
import os
import pathlib
import ssl
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ARGS = None
LOG_UPLOADS = {}           # id -> {"path", "size", "sha256", "received"}
NTRIP_ACCOUNTS = {}        # vehicle -> ntrip dict


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, flush=True)


# ---- 4G relay ---------------------------------------------------------------------------------

class Relay:
    def __init__(self):
        self.vehicle_writer = None
        self.gcs = []              # list of (writer, access)
        self.vehicle_task = None

    async def vehicle_loop(self):
        host, port = ARGS.sitl.rsplit(":", 1)
        while True:
            try:
                reader, writer = await asyncio.open_connection(host, int(port))
                self.vehicle_writer = writer
                log("vehicle (SITL) connected", ARGS.sitl)
                while True:
                    data = await reader.read(4096)
                    if not data:
                        break
                    for w, _ in list(self.gcs):
                        try:
                            w.write(data)
                        except Exception:
                            pass
            except OSError as e:
                log("vehicle not reachable:", e)
            self.vehicle_writer = None
            await asyncio.sleep(2)

    async def handle_gcs(self, reader, writer):
        peer = writer.get_extra_info("peername")
        try:
            line = await asyncio.wait_for(reader.readline(), timeout=10)
        except asyncio.TimeoutError:
            writer.close()
            return
        if len(line) > 1024:
            writer.close()
            return
        try:
            auth = json.loads(line.decode("utf-8"))
        except ValueError:
            writer.close()
            return

        def answer(ok, code, msg="", access="", ntrip_saved=None):
            result = {"type": "auth_result", "ok": ok, "code": code, "msg": msg, "access": access}
            if ntrip_saved is not None:
                result["ntrip_saved"] = ntrip_saved
            writer.write((json.dumps(result) + "\n").encode("utf-8"))

        log("login from", peer, {k: v for k, v in auth.items() if k != "password"})
        if auth.get("ver") != 1:
            answer(False, 4, "unsupported protocol version")
        elif auth.get("vehicle") != ARGS.vehicle or auth.get("password") != ARGS.password:
            answer(False, 1, "wrong vehicle or password")
        elif ARGS.offline or self.vehicle_writer is None:
            answer(False, 2, "vehicle offline")
        else:
            ntrip_saved = None
            if "ntrip" in auth:
                NTRIP_ACCOUNTS[auth["vehicle"]] = auth["ntrip"]
                ntrip_saved = True
                log("RTK account stored:", {k: v for k, v in auth["ntrip"].items() if k != "password"})
            access = "control" if not any(a == "control" for _, a in self.gcs) and not ARGS.force_readonly else "readonly"
            answer(True, 0 if access == "control" else 3, "", access, ntrip_saved)
            await writer.drain()
            entry = (writer, access)
            self.gcs.append(entry)
            log("GCS online", peer, access)
            try:
                while True:
                    data = await reader.read(4096)
                    if not data:
                        break
                    if access == "control" and self.vehicle_writer:
                        self.vehicle_writer.write(data)
            except OSError:
                pass
            finally:
                self.gcs.remove(entry)
                log("GCS offline", peer)
        try:
            await writer.drain()
            writer.close()
        except OSError:
            pass

    def drop_all(self):
        for w, _ in list(self.gcs):
            w.close()
        log("dropped all GCS connections")


# ---- NTRIP caster ------------------------------------------------------------------------------

async def ntrip_caster(reader, writer):
    """Minimal NTRIP caster: user test / password test, mountpoints RTCM32 and VRS; sends dummy RTCM"""
    try:
        head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=10)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError, asyncio.LimitOverrunError):
        writer.close()
        return
    lines = head.decode("latin1").split("\r\n")
    path = lines[0].split(" ")[1] if " " in lines[0] else "/"
    auth = next((l.split(" ", 2)[2] for l in lines if l.lower().startswith("authorization: basic ")), "")
    user = base64.b64decode(auth).decode("utf-8", "replace") if auth else ""
    log("ntrip request", path, "user", user.split(":")[0])
    mounts = ["RTCM32", "VRS"]
    if path == "/":
        table = "".join(f"STR;{m};{m};RTCM 3.2;;2;GPS+BDS;SNIP;CHN;31.91;118.79;1;0;sNTRIP;none;B;N;9600;\r\n" for m in mounts)
        writer.write(("SOURCETABLE 200 OK\r\nContent-Type: text/plain\r\n\r\n" + table + "ENDSOURCETABLE\r\n").encode())
    elif user != "test:test":
        writer.write(b"HTTP/1.1 401 Unauthorized\r\n\r\n")
    elif path[1:] not in mounts:
        writer.write(b"HTTP/1.1 404 Not Found\r\n\r\n")
    else:
        writer.write(b"ICY 200 OK\r\n\r\n")
        try:
            for _ in range(600):
                writer.write(b"\xd3\x00\x13" + bytes(22))   # RTCM3 frame shape, dummy content
                await writer.drain()
                await asyncio.sleep(1)
        except OSError:
            pass
    try:
        await writer.drain()
        writer.close()
    except OSError:
        pass


# ---- HTTP API ---------------------------------------------------------------------------------

class Api(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        vehicle, _, password = base64.b64decode(header[6:]).decode("utf-8").partition(":")
        return vehicle == ARGS.vehicle and password == ARGS.password

    def _body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))

    def log_message(self, fmt, *args):
        log("http", self.address_string(), fmt % args)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/version":
            installer = pathlib.Path(ARGS.installer) if ARGS.installer else None
            sha = hashlib.sha256(installer.read_bytes()).hexdigest() if installer and installer.exists() else ""
            self._json(200, {"version": ARGS.latest, "url": "/download/" + (installer.name if installer else "setup.exe"),
                             "sha256": sha, "notes": ARGS.notes})
        elif url.path.startswith("/download/") and ARGS.installer:
            data = pathlib.Path(ARGS.installer).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif url.path.startswith("/api/logs/"):
            if not self._authorized():
                return self._json(401, {"error": "unauthorized"})
            up = LOG_UPLOADS.get(url.path.split("/")[3])
            self._json(200 if up else 404, {"received": up["received"]} if up else {"error": "unknown upload"})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        url = urlparse(self.path)
        if not self._authorized():
            return self._json(401, {"error": "unauthorized"})
        if url.path == "/api/logs":
            info = json.loads(self._body() or b"{}")
            upload_id = uuid.uuid4().hex[:12]
            path = pathlib.Path(ARGS.upload_dir) / f"{upload_id}_{os.path.basename(info.get('name', 'logs.zip'))}"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"")
            LOG_UPLOADS[upload_id] = {"path": path, "size": int(info.get("size", 0)), "sha256": info.get("sha256", ""), "received": 0}
            log("log upload started", upload_id, info)
            self._json(200, {"upload_id": upload_id, "received": 0})
        elif url.path.endswith("/complete"):
            up = LOG_UPLOADS.get(url.path.split("/")[3])
            if not up:
                return self._json(404, {"error": "unknown upload"})
            sha = hashlib.sha256(up["path"].read_bytes()).hexdigest()
            if up["sha256"] and sha != up["sha256"]:
                return self._json(422, {"error": "checksum mismatch"})
            ticket = time.strftime("LOG%Y%m%d-") + uuid.uuid4().hex[:6].upper()
            log("log upload complete", up["path"], "ticket", ticket)
            self._json(200, {"ticket": ticket})
        else:
            self._json(404, {"error": "not found"})

    def do_PUT(self):
        url = urlparse(self.path)
        if not self._authorized():
            return self._json(401, {"error": "unauthorized"})
        up = LOG_UPLOADS.get(url.path.split("/")[3]) if url.path.startswith("/api/logs/") else None
        if not up:
            return self._json(404, {"error": "unknown upload"})
        offset = int(parse_qs(url.query).get("offset", ["0"])[0])
        data = self._body()
        if offset != up["received"]:
            return self._json(409, {"received": up["received"]})
        if ARGS.fail_chunk and offset > 0 and offset // (1024 * 1024) == ARGS.fail_chunk and not up.get("failed"):
            up["failed"] = True   # one simulated failure to test resuming
            return self._json(503, {"error": "simulated failure"})
        with open(up["path"], "ab") as f:
            f.write(data)
        up["received"] += len(data)
        self._json(200, {"received": up["received"]})


# ---- Main -------------------------------------------------------------------------------------

async def main():
    relay = Relay()
    ssl_ctx = None
    if ARGS.tls:
        ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_ctx.load_cert_chain(ARGS.tls[0], ARGS.tls[1])
    server = await asyncio.start_server(relay.handle_gcs, ARGS.bind, ARGS.port, ssl=ssl_ctx)
    log(f"4G relay on port {ARGS.port} ({'TLS' if ssl_ctx else 'plain'}), vehicle {ARGS.vehicle}")
    asyncio.get_running_loop().create_task(relay.vehicle_loop())

    ntrip = await asyncio.start_server(ntrip_caster, ARGS.bind, ARGS.ntrip_port)
    log(f"NTRIP caster on port {ARGS.ntrip_port} (user test / password test, mountpoints RTCM32, VRS)")

    http = ThreadingHTTPServer((ARGS.bind, ARGS.http_port), Api)
    threading.Thread(target=http.serve_forever, daemon=True).start()
    log(f"HTTP API on port {ARGS.http_port}")

    loop = asyncio.get_running_loop()

    def stdin_reader():
        for line in sys.stdin:
            cmd = line.strip()
            if cmd == "drop":
                loop.call_soon_threadsafe(relay.drop_all)
            elif cmd == "quit":
                loop.call_soon_threadsafe(loop.stop)
    threading.Thread(target=stdin_reader, daemon=True).start()

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--bind", default="127.0.0.1", help="listen address (0.0.0.0 to accept other computers)")
    p.add_argument("--port", type=int, default=7000)
    p.add_argument("--http-port", type=int, default=7080)
    p.add_argument("--ntrip-port", type=int, default=2101)
    p.add_argument("--vehicle", default="HHU001")
    p.add_argument("--password", default="123456")
    p.add_argument("--sitl", default="127.0.0.1:5762", help="vehicle side: SITL TCP host:port")
    p.add_argument("--offline", action="store_true", help="answer every login with code 2")
    p.add_argument("--force-readonly", action="store_true", help="every login gets read-only access (code 3)")
    p.add_argument("--tls", nargs=2, metavar=("CERT", "KEY"))
    p.add_argument("--latest", default="1.0.0", help="version reported by /api/version")
    p.add_argument("--notes", default="")
    p.add_argument("--installer", help="file served as the update")
    p.add_argument("--upload-dir", default="uploads")
    p.add_argument("--fail-chunk", type=int, default=0, help="fail the n-th 1 MB piece once (resume test)")
    ARGS = p.parse_args()
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, RuntimeError):
        pass
