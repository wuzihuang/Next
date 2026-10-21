import argparse
import json
import platform
import subprocess
import tempfile
from pathlib import Path


APP = Path(__file__).resolve().parents[2]


def declaration(path, marker):
    source = path.read_text()
    start = source.index(marker)
    opening = source.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


parser = argparse.ArgumentParser()
parser.add_argument("--device")
args = parser.parse_args()
devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "booted", "--json"]
))["devices"]
device = args.device or next(
    (device["udid"] for runtime, entries in devices.items() if ".iOS-" in runtime
     for device in entries if device["state"] == "Booted"), None)
if device is None:
    raise SystemExit("Boot an iOS simulator or pass --device <UDID>.")

source = """
import UIKit
enum ScreenMetrics { static var size = CGSize.zero }
struct Context {}
"""
source += declaration(
    APP / "NextBody/Features/Shared/Chrome.swift",
    "private struct BackdropSnapshot:"
).replace(": UIViewRepresentable", "")
source += """

var failures = 0
func check(_ snapshot: UIView, _ expected: CGRect, _ name: String) {
    let passed = snapshot.frame == expected && snapshot.transform == .identity
    print("\\(passed ? "PASS" : "FAIL"): \\(name) frame=\\(snapshot.frame)")
    if !passed { failures += 1 }
}

for size in [CGSize(width: 390, height: 844), CGSize(width: 402, height: 874),
             CGSize(width: 430, height: 932)] {
    ScreenMetrics.size = size
    let expected = CGRect(origin: .zero, size: size)
    let snapshot = UIView(frame: expected)
    let backdrop = BackdropSnapshot(snapshot: snapshot)
    for attempt in 1...2 {
        let container = backdrop.makeUIView(context: Context())
        container.frame = expected
        container.layoutIfNeeded()
        check(snapshot, expected, "\\(size) drag \\(attempt) first layout")
        container.bounds.size.height -= 93
        container.layoutIfNeeded()
        check(snapshot, expected, "\\(size) safe-area proposal")
        container.bounds.size = size
        backdrop.updateUIView(container, context: Context())
        container.layoutIfNeeded()
        check(snapshot, expected, "\\(size) drag \\(attempt) held")
        snapshot.removeFromSuperview()
    }
    let coverHost = UIView(frame: expected)
    snapshot.frame = coverHost.bounds
    coverHost.addSubview(snapshot)
    coverHost.layoutIfNeeded()
    check(snapshot, expected, "\\(size) committed cover")
    snapshot.removeFromSuperview()
}
exit(failures == 0 ? 0 : 1)
"""

sdk = subprocess.check_output(
    ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True
).strip()
with tempfile.TemporaryDirectory(prefix="nextbody-backdrop-") as temporary:
    directory = Path(temporary)
    swift = directory / "main.swift"
    binary = directory / "backdrop-geometry"
    swift.write_text(source)
    subprocess.run([
        "xcrun", "--sdk", "iphonesimulator", "swiftc", "-sdk", sdk,
        "-target", f"{platform.machine()}-apple-ios18.0-simulator",
        str(swift), "-o", str(binary),
    ], check=True)
    result = subprocess.run(["xcrun", "simctl", "spawn", device, str(binary)])
    raise SystemExit(result.returncode)
