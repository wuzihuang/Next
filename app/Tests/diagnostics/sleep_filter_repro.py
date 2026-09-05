"""Replay the actual adapter mapping for the captured late-wake night."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
adapter = (root / 'NextBody/Services/Band/VeepooBand.swift').read_text()
assert 'hour < 12' not in adapter, "legacy noon gate survives in SDK adapter"
assert 'HealthSampleMapping.sleepRecordIndices' in adapter
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'main.swift').write_text('''
import Foundation
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let now = HealthSampleMapping.sleepInstant("2026-09-05 14:00", calendar: calendar)!
let rows: [(String?, String?)] = [("2026-09-05 03:59", "2026-09-05 13:09")]
let kept = HealthSampleMapping.sleepRecordIndices(stamps: rows, wakeDay: "2026-09-05", now: now, calendar: calendar)
precondition(kept == [0], "13:09 wake must survive actual adapter mapping")
print("PASS: actual SDK sleep ending 13:09 survives adapter mapping")
''')
    subprocess.run(['swiftc', str(root / 'NextBody/Services/Band/HealthSampleMapping.swift'), str(path / 'main.swift'), '-o', str(path / 'test')], check=True)
    raise SystemExit(subprocess.run([str(path / 'test')]).returncode)
