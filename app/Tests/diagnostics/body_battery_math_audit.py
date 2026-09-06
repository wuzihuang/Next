#!/usr/bin/env python3
"""Compile the production Swift engine and report reserve calibration/invariant probes.

This is an audit, not a replacement physiological model. An exit status of 1 means
the existing implementation violates an explicitly reported invariant/contract.
No private data, backend connection, or application state is used.
"""
import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "NextBody/Services/Band/BodyBatteryEngine.swift"
RUNNER = r'''
import Foundation

let baseline = BodyBatteryEngine.Baseline(restingHeartRate: 55,
    maximumHeartRate: 190, hrvMS: 50, recoveryMultiplier: 1)
var rows: [[String: Any]] = []
var violations: [String] = []
func run(_ name: String, anchor: Double, tick: BodyBatteryEngine.Tick,
         count: Int, normal: BodyBatteryEngine.Baseline = baseline) -> BodyBatteryEngine.Result {
    let r = BodyBatteryEngine.replay(anchor: anchor,
        ticks: Array(repeating: tick, count: count), baseline: normal)
    let d = r.drivers
    let residual = r.value - anchor - (d.recovery - d.awake - d.movement - d.stress + d.restorativeRest)
    rows.append(["case": name, "anchor": anchor, "minutes": tick.durationMinutes * Double(count),
        "value": r.value, "delta": r.value - anchor, "recovery": d.recovery,
        "awake": d.awake, "movement": d.movement, "stress": d.stress,
        "rest_offset": d.restorativeRest, "attribution_residual": residual,
        "worn_minutes": r.wornMinutes])
    return r
}
for stage in 0...4 {
    _ = run("8h_stage_\(stage)", anchor: 20,
        tick: .init(heartRate: 55, hrvMS: 50, stress: 20, steps: 0, met: 1, sleepStage: stage), count: 96)
}
// Constant q=1 isolates the saturation function; it is not a claim of eight hours of REM.
for multiplier in [0.65, 1.0, 1.3] {
    _ = run("8h_q1_multiplier_\(multiplier)", anchor: 20,
        tick: .init(sleepStage: 2), count: 96,
        normal: .init(restingHeartRate: 55, maximumHeartRate: 190,
                      hrvMS: 50, recoveryMultiplier: multiplier))
}
let quiet = run("2h_verified_quiet", anchor: 50,
    tick: .init(heartRate: 55, hrvMS: 55, stress: 20, steps: 0, met: 1), count: 24)
// Retained calibration is explicitly a drain offset, not a promise of net charging.
if quiet.drivers.restorativeRest <= 0 || quiet.value >= 50 {
    violations.append("Verified quiet rest must moderate awake drain under the retained calibration.")
}
let unsupportedQuiet = run("2h_missing_quiet_evidence", anchor: 50,
    tick: .init(heartRate: 55, met: 1), count: 24)
if unsupportedQuiet.drivers.restorativeRest != 0 {
    violations.append("Missing HRV, stress and steps must not grant restorative credit.")
}
_ = run("16h_sedentary", anchor: 80,
    tick: .init(heartRate: 70, hrvMS: 50, stress: 30, steps: 0, met: 1), count: 192)
_ = run("16h_high_stress", anchor: 80,
    tick: .init(heartRate: 70, hrvMS: 25, stress: 100, steps: 0, met: 1), count: 192)
_ = run("1h_exercise_all_signals", anchor: 80,
    tick: .init(heartRate: 160, hrvMS: 25, stress: 80, steps: 600, met: 6), count: 12)
_ = run("2h_no_wear_evidence", anchor: 50, tick: .init(), count: 24)
let floor = run("5min_near_zero", anchor: 0.1,
    tick: .init(heartRate: 190, hrvMS: 10, stress: 100, steps: 1000, met: 10), count: 1)
let d = floor.drivers
if abs(floor.value - 0.1 - (d.recovery - d.awake - d.movement - d.stress + d.restorativeRest)) > 0.000001 {
    violations.append("Swift attribution spends more than the remaining reserve when clamped at zero; SQL scales effective drivers.")
}
// This pure reference engine is no longer a separate publisher of live app values.
// Check that no rest credit is attributed before 20 completed quiet minutes.
let minute = run("20min_quiet_one_minute_ticks", anchor: 50,
    tick: .init(durationMinutes: 1, heartRate: 55, hrvMS: 55, stress: 20, steps: 0, met: 1), count: 20)
let five = run("20min_quiet_five_minute_ticks", anchor: 50,
    tick: .init(heartRate: 55, hrvMS: 55, stress: 20, steps: 0, met: 1), count: 4)
if minute.drivers.restorativeRest != 0 || five.drivers.restorativeRest != 0 {
    violations.append("Rest credit must start after 20 completed quiet minutes.")
}
if abs(five.value - minute.value) > 0.000001 {
    violations.append("Twenty-minute quiet threshold differs across tick durations.")
}
let data = try! JSONSerialization.data(withJSONObject: ["scenarios": rows,
    "violations": violations, "quiet_tick_resolution_difference": five.value - minute.value],
    options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''


def main():
    with tempfile.TemporaryDirectory(prefix="body-battery-math-") as temp:
        directory = Path(temp)
        source, binary = directory / "main.swift", directory / "audit"
        source.write_text(RUNNER)
        subprocess.run(["swiftc", str(ENGINE), str(source), "-o", str(binary)], check=True)
        result = json.loads(subprocess.check_output([str(binary)], text=True))
    print(json.dumps(result, indent=2))
    return int(bool(result["violations"]))


if __name__ == "__main__":
    raise SystemExit(main())
