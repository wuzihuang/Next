from pathlib import Path
import shutil
import subprocess
import tempfile


APP = Path(__file__).resolve().parents[2]
SOURCES = [
    "SportMetricAccumulator",
    "SportLiveInfo",
    "SportEnergyEvidence",
    "SportHeartRateEvidence",
    "SportRecapMath",
    "SportSessionRecap",
]
TESTS = [
    "SportMetricAccumulatorTests",
    "SportLiveInfoTests",
    "SportEnergyEvidenceTests",
    "SportHeartRateEvidenceTests",
    "SportRecapMathTests",
    "SportRecapArchiveTests",
]

with tempfile.TemporaryDirectory(prefix="next-sport-energy-") as temporary:
    package = Path(temporary)
    sources = package / "Sources/NextBodySyncCore"
    tests = package / "Tests/NextBodySyncCoreTests"
    local = package / "Sources/NextBodyLocalData"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in SOURCES:
        shutil.copy2(APP / f"NextBody/Services/Band/{name}.swift", sources)
    for name in TESTS:
        shutil.copy2(APP / f"NextBodySyncCoreTests/{name}.swift", tests)
    shutil.copytree(APP / "NextBody/Services/Storage", local)
    (package / "Package.swift").write_text(
        '// swift-tools-version: 6.0\n'
        'import PackageDescription\n'
        'let package = Package(name: "SportEnergyChecks", '
        'platforms: [.macOS(.v13)], targets: ['
        '.target(name: "NextBodyLocalData", linkerSettings: [.linkedLibrary("sqlite3")]),'
        '.target(name: "NextBodySyncCore", dependencies: ["NextBodyLocalData"]),'
        '.testTarget(name: "NextBodySyncCoreTests", '
        'dependencies: ["NextBodySyncCore", "NextBodyLocalData"])])\n'
    )
    subprocess.run(["swift", "test", "--package-path", str(package)], check=True)
