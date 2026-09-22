#!/usr/bin/env python3
"""Capture the app's actual deep-space renderer from an iOS Simulator.

Run from the repository root with the existing Pillow environment:
    output/fx/.venv/bin/python output/fx/capture_deep_space.py
    output/fx/.venv/bin/python output/fx/capture_deep_space.py \
        --app /tmp/NextBody.app --device booted --plates 1 7 16 --clock 12

The simulator must already be booted. Use --scale 2 on a 2x device; the default
3 matches 3x iPhones. Each launch holds the requested timestamp, waits for the
real Metal surface, then crops its centered 358 x 470 point review frame.
"""

import argparse
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image, ImageDraw


BUNDLE_ID = "com.nextbody.hoop"
BOARD_POINTS = (358, 470)
THUMB_WIDTH = 214


def positive_scale(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("scale must be a positive finite number")
    return number


def finite_clock(value):
    number = float(value)
    if not math.isfinite(number):
        raise argparse.ArgumentTypeError("clock must be a finite number")
    return number


def arguments():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", type=Path, help="Optional .app directory to install before capture")
    parser.add_argument("--device", default="booted", help="Simulator UDID or booted (default)")
    parser.add_argument("--plates", type=int, nargs="+", choices=range(1, 29),
                        default=list(range(1, 29)), metavar="N")
    parser.add_argument("--clock", type=finite_clock, default=0, help="Exact renderer time in seconds")
    parser.add_argument("--scale", type=positive_scale, default=3, help="Simulator screenshot pixels per point")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent / "deep-space")
    args = parser.parse_args()
    if args.app is not None and not args.app.is_dir():
        parser.error(f"--app is not a directory: {args.app}")
    if min(round(points * args.scale) for points in BOARD_POINTS) < 1:
        parser.error("--scale produces an empty capture")
    args.plates = list(dict.fromkeys(args.plates))
    return args


def simctl(*command, env=None, check=True):
    return subprocess.run(["xcrun", "simctl", *map(str, command)],
                          env=env, check=check, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def crop_plate(screenshot, destination, scale):
    width, height = (round(points * scale) for points in BOARD_POINTS)
    with Image.open(screenshot) as source:
        if source.width < width or source.height < height:
            raise ValueError(
                f"Screenshot is {source.width} x {source.height}, smaller than the "
                f"{width} x {height} capture. Check --scale and simulator orientation."
            )
        left = (source.width - width) // 2
        top = (source.height - height) // 2
        source.crop((left, top, left + width, top + height)).convert("RGB").save(destination)


def contact_sheet(captures, destination):
    columns = min(7, len(captures))
    rows = math.ceil(len(captures) / columns)
    thumb_height = round(THUMB_WIDTH * BOARD_POINTS[1] / BOARD_POINTS[0])
    gap, caption_height = 12, 22
    cell_height = thumb_height + caption_height
    sheet = Image.new("RGB", (gap + columns * (THUMB_WIDTH + gap),
                              gap + rows * (cell_height + gap)), "#07090f")
    draw = ImageDraw.Draw(sheet)
    for index, (plate, path) in enumerate(captures):
        left = gap + (index % columns) * (THUMB_WIDTH + gap)
        top = gap + (index // columns) * (cell_height + gap)
        with Image.open(path) as source:
            thumbnail = source.resize((THUMB_WIDTH, thumb_height), Image.Resampling.LANCZOS)
            sheet.paste(thumbnail, (left, top))
        draw.text((left + 4, top + thumb_height + 5), f"{plate:02d}", fill="#bac3d3")
    sheet.save(destination, quality=94, subsampling=0)


def main():
    args = arguments()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.app is not None:
        simctl("install", args.device, args.app.resolve())

    environment = os.environ.copy()
    environment.update({
        "SIMCTL_CHILD_NB_DEBUG_STAGE": "root",
        "SIMCTL_CHILD_NB_DEBUG_CONSENT": "granted",
        "SIMCTL_CHILD_NB_DUMP_PLATES": "1",
        "SIMCTL_CHILD_NB_DUMP_CLOCK": str(args.clock),
        "SIMCTL_CHILD_NB_DUMP_LIVE": "0",
    })
    captures = []
    with tempfile.TemporaryDirectory(prefix="deep-space-capture-") as temporary:
        screenshot = Path(temporary) / "screen.png"
        for plate in args.plates:
            # A non-running app is expected on the first iteration.
            simctl("terminate", args.device, BUNDLE_ID, check=False)
            environment["SIMCTL_CHILD_NB_DUMP_PLATE"] = str(plate)
            simctl("launch", args.device, BUNDLE_ID, env=environment)
            time.sleep(3)
            simctl("io", args.device, "screenshot", "--type=png", screenshot)
            destination = args.out / f"plate{plate:02d}.png"
            crop_plate(screenshot, destination, args.scale)
            captures.append((plate, destination))
            print(f"Captured {plate:02d}: {destination}", flush=True)

    destination = args.out / "contact-sheet.jpg"
    contact_sheet(captures, destination)
    print(f"Contact sheet: {destination}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or str(error)).strip()
        raise SystemExit(f"simctl failed: {detail}") from error
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
