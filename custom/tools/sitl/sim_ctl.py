#!/usr/bin/env python3
"""sim_ctl.py: change the simulated chassis (sim_vcu.lua) of the SITL rover.

Runs in WSL next to SITL (mavproxy output tcp:127.0.0.1:5763, which the ground station does not use):
    python3 sim_ctl.py set SVCU_WFB_FLT 1      # set a parameter (SVCU_*, VCU_WORK_EN …)
    python3 sim_ctl.py get SVCU_WFB_T VCU_WORK_EN
    python3 sim_ctl.py aux 2                   # SCRIPTING1 (300) high (2) / low (0), like the ground station
    python3 sim_ctl.py watch [seconds]         # print VCU_WORKFB / VCU_WREQ / VCU: texts
--url tcp:127.0.0.1:5763 picks another MAVLink endpoint.
"""
import sys
import time

from pymavlink import mavutil


def connect(url):
    m = mavutil.mavlink_connection(url, source_system=252)
    if not m.wait_heartbeat(timeout=10):
        sys.exit("no heartbeat on " + url)
    return m


def get(m, name):
    for _ in range(3):
        m.mav.param_request_read_send(m.target_system, 1, name.encode(), -1)
        t = time.time()
        while time.time() - t < 1.5:
            p = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
            if p and p.param_id == name:
                return p.param_value
    return None


def main():
    args = sys.argv[1:]
    url = "tcp:127.0.0.1:5763"
    if len(args) >= 2 and args[0] == "--url":
        url, args = args[1], args[2:]
    if not args:
        sys.exit(__doc__)
    m = connect(url)
    cmd = args[0]
    if cmd == "set" and len(args) == 3:
        name, value = args[1], float(args[2])
        for _ in range(3):
            m.mav.param_set_send(m.target_system, 1, name.encode(), value, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.5)
            got = get(m, name)
            if got is not None and abs(got - value) < 1e-4:
                print(name, "=", "%g" % got)
                return
        sys.exit("FAILED: %s is %s" % (name, got))
    elif cmd == "get":
        for name in args[1:]:
            v = get(m, name)
            print(name, "MISSING" if v is None else "%g" % v)
    elif cmd == "aux" and len(args) == 2:
        m.mav.command_long_send(m.target_system, 1, mavutil.mavlink.MAV_CMD_DO_AUX_FUNCTION, 0,
                                300, float(args[1]), 0, 0, 0, 0, 0)
        ack = m.recv_match(type="COMMAND_ACK", blocking=True, timeout=3)
        print("DO_AUX_FUNCTION(300, %s):" % args[1], ack.result if ack else "no ack")
    elif cmd == "watch":
        end = time.time() + (float(args[1]) if len(args) > 1 else 30)
        while time.time() < end:
            msg = m.recv_match(type=["NAMED_VALUE_FLOAT", "STATUSTEXT", "HEARTBEAT"], blocking=True, timeout=1)
            if not msg:
                continue
            t = time.strftime("%H:%M:%S")
            if msg.get_type() == "NAMED_VALUE_FLOAT" and msg.name in ("VCU_WORKFB", "VCU_WREQ"):
                print(t, msg.name, "%g" % msg.value)
            elif msg.get_type() == "STATUSTEXT":
                print(t, "TEXT", msg.text)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
