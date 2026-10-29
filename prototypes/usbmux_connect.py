"""Spike: connect to 127.0.0.1:<port> on a paired iOS device through usbmuxd and print what the agent sends.
Usage: python3 usbmux_connect.py <udid> [port]"""
import plistlib
import socket
import struct
import sys

def request(sock, msg, tag):
    body = plistlib.dumps({**msg, "ClientVersionString": "desknet", "ProgName": "desknet"})
    sock.sendall(struct.pack("<IIII", 16 + len(body), 1, 8, tag) + body)  # version 1, type 8 = plist
    size = struct.unpack("<IIII", sock.recv(16, socket.MSG_WAITALL))[0] - 16
    return plistlib.loads(sock.recv(size, socket.MSG_WAITALL))

def main():
    udid, port = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 39391
    with socket.socket(socket.AF_UNIX) as s:
        s.connect("/var/run/usbmuxd")
        devices = request(s, {"MessageType": "ListDevices"}, 1)["DeviceList"]
    matches = [d for d in devices if d["Properties"].get("SerialNumber") == udid]
    if not matches:
        sys.exit("device %s not attached to usbmuxd" % udid)
    # Prefer USB when the device is reachable both ways.
    dev = sorted(matches, key=lambda d: d["Properties"].get("ConnectionType") != "USB")[0]
    print("device id=%d via %s" % (dev["DeviceID"], dev["Properties"].get("ConnectionType")))
    s = socket.socket(socket.AF_UNIX)
    s.connect("/var/run/usbmuxd")
    # usbmuxd wants the port in network byte order inside a host-order integer.
    reply = request(s, {"MessageType": "Connect", "DeviceID": dev["DeviceID"],
                        "PortNumber": socket.htons(port)}, 2)
    if reply.get("Number") != 0:
        sys.exit("connect failed: %s" % reply)  # 3 = connection refused on the device
    s.settimeout(5)
    print("connected; received:", s.recv(4096).decode(errors="replace").strip())
    s.close()

if __name__ == "__main__":
    main()
