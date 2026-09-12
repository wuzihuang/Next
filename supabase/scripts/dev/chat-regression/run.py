#!/usr/bin/env python3
"""Run the real turn handler with mocked model/auth/DB and no external calls."""
from pathlib import Path
import subprocess
import tempfile

SCRIPT_DIR = Path(__file__).resolve().parent
FUNCTIONS_DIR = SCRIPT_DIR.parents[2] / "functions"
HANDLER = FUNCTIONS_DIR / "turn" / "index.ts"


def main():
    # Production code is fully type checked; only the test doubles skip TS checks.
    subprocess.run(["deno", "check", "--no-config", str(HANDLER)], check=True)
    with tempfile.TemporaryDirectory(prefix="next-chat-regression-") as directory:
        temp = Path(directory)
        for name in ("mock-ai.ts", "mock-db.ts", "mock-model.ts", "handler_test.ts"):
            source = (SCRIPT_DIR / name).read_text()
            if name == "mock-db.ts":
                source = source.replace(
                    "../../../functions/_shared/db.ts",
                    (FUNCTIONS_DIR / "_shared" / "db.ts").as_uri(),
                )
            (temp / name).write_text(source)
        source = HANDLER.read_text()
        source = source.replace('"npm:ai@4.3.16"', '"./mock-ai.ts"')
        source = source.replace('"../_shared/model.ts"', '"./mock-model.ts"')
        source = source.replace('"../_shared/db.ts"', '"./mock-db.ts"')
        source = source.replace('"../_shared/', f'"{(FUNCTIONS_DIR / "_shared").as_uri()}/')
        (temp / "handler.ts").write_text(source)
        subprocess.run([
            "deno", "test", "--no-config", "--no-check", "--allow-env", "--allow-read",
            str(temp / "handler_test.ts"),
        ], check=True)


if __name__ == "__main__":
    main()
