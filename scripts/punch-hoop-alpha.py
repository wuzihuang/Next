#!/usr/bin/env python3
"""Drop the leftover pure-black studio background trapped inside HOOP cutouts.

The source shots were composited on #000, so the ring interior and any gap
between the strap and the frame stayed opaque black after the first pass. The
band's own texture never reaches pure black, so a tight threshold plus a
connected-component pass isolates only background.
"""

from __future__ import annotations

import shutil
import sys
from collections import deque
from pathlib import Path

from PIL import Image

THEME = Path("shopify-theme/assets")
WEB = Path("shopify-web/public/kit")

# Background is composited #000; the darkest band texture sits above this.
BLACK = 8
# Ignore speckle inside the weave; only lift real holes.
MIN_AREA_RATIO = 0.002
# Soften the rim left behind so the cutout does not read as a hard stencil.
FEATHER_MAX = 56


def lift_background(image: Image.Image) -> tuple[Image.Image, int]:
    px = image.load()
    width, height = image.size
    seen = bytearray(width * height)
    removed: list[tuple[int, int]] = []
    holes = 0

    def is_black(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return a > 0 and max(r, g, b) <= BLACK

    for start_y in range(height):
        for start_x in range(width):
            index = start_y * width + start_x
            if seen[index] or not is_black(start_x, start_y):
                continue
            queue = deque([(start_x, start_y)])
            seen[index] = 1
            region: list[tuple[int, int]] = []
            while queue:
                x, y = queue.popleft()
                region.append((x, y))
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if not (0 <= nx < width and 0 <= ny < height):
                        continue
                    n_index = ny * width + nx
                    if seen[n_index] or not is_black(nx, ny):
                        continue
                    seen[n_index] = 1
                    queue.append((nx, ny))
            if len(region) >= width * height * MIN_AREA_RATIO:
                removed.extend(region)
                holes += 1

    for x, y in removed:
        px[x, y] = (0, 0, 0, 0)

    # One-pixel ramp so the frame edge keeps its anti-aliasing.
    edge: set[tuple[int, int]] = set()
    for x, y in removed:
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height:
                r, g, b, a = px[nx, ny]
                if a == 255 and max(r, g, b) <= FEATHER_MAX:
                    edge.add((nx, ny))
    for x, y in edge:
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, int(255 * min(1.0, max(r, g, b) / FEATHER_MAX)))

    return image, holes


def main() -> int:
    targets = sorted(THEME.glob("hoop-*.png"))
    if not targets:
        print("no hoop-*.png found under", THEME)
        return 1

    for path in targets:
        image = Image.open(path).convert("RGBA")
        image, holes = lift_background(image)
        image.save(path)
        mirror = WEB / path.name
        if mirror.exists():
            shutil.copy2(path, mirror)
        print(f"{path.name}: lifted {holes} region(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
