from pathlib import Path
import shutil
import subprocess
import tempfile


APP = Path(__file__).resolve().parents[2]
SOURCES = ["TrainingSettlement", "UserDay"]
TESTS = ["TrainingSettlementTests"]

with tempfile.TemporaryDirectory(prefix="next-training-settlement-") as temporary:
    package = Path(temporary)
    sources = package / "Sources/NextBodySyncCore"
    tests = package / "Tests/NextBodySyncCoreTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in SOURCES:
        shutil.copy2(APP / f"NextBody/Services/Band/{name}.swift", sources)
    for name in TESTS:
        shutil.copy2(APP / f"NextBodySyncCoreTests/{name}.swift", tests)
    (package / "Package.swift").write_text(
        '// swift-tools-version: 6.0\n'
        'import PackageDescription\n'
        'let package = Package(name: "TrainingSettlementChecks", '
        'platforms: [.macOS(.v13)], targets: ['
        '.target(name: "NextBodySyncCore"),'
        '.testTarget(name: "NextBodySyncCoreTests", dependencies: ["NextBodySyncCore"])])\n'
    )
    subprocess.run(["swift", "test", "--package-path", str(package)], check=True)
