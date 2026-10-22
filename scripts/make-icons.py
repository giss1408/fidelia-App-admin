#!/usr/bin/env python3
"""Draws Fidelia Admin's Android launcher icons.

    python3 scripts/make-icons.py     (needs rsvg-convert)

The mark is the Fidelia logo (fidelia-brand/fidelia-app-icon.svg): the
geometric F with its orange point, in paper on the brand green. Admin is told
apart from Fidelia Pro by a small dark round badge with a paper "A" at the
lower right.

The adaptive icon's background layer is the green (@color/fidelia_green); the
foreground holds the F and the badge inside the circle a launcher keeps when
it crops (61% of the canvas).

Writes, for each density: mipmap-*/ic_launcher_foreground.png (adaptive icon)
and mipmap-*/ic_launcher.png (pre-Android 8 launchers: the full green tile).
"""

import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"

PAPER, GREEN, GREEN_DARK, ORANGE, INK = "#f5f1e8", "#234b39", "#173427", "#e65e32", "#10150f"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def letter(cx: float, cy: float, scale: float) -> str:
    """The F and its point, drawn on the logo's 100 grid, centred on (cx, cy)."""
    tx, ty = cx - 51.25 * scale, cy - 50 * scale
    return (
        f'<g transform="translate({tx:.1f} {ty:.1f}) scale({scale})">'
        f'<rect x="31" y="24" width="11" height="52" rx="1.5" fill="{PAPER}"/>'
        f'<rect x="31" y="24" width="40" height="11" rx="1.5" fill="{PAPER}"/>'
        f'<rect x="31" y="45" width="26" height="10" rx="1.5" fill="{PAPER}"/>'
        f'<circle cx="66" cy="50" r="5.5" fill="{ORANGE}"/>'
        "</g>"
    )


def badge(cx: float, cy: float, r: float) -> str:
    """Dark disc with a paper ring and a bold geometric "A"."""
    w = r * 0.62  # half width of the A at the base
    top, bottom = cy - r * 0.55, cy + r * 0.52
    bar_y = cy + r * 0.18
    sw = r * 0.26
    return (
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{INK}" stroke="{PAPER}" stroke-width="{r * 0.1:.1f}"/>'
        f'<path d="M{cx - w:.1f} {bottom:.1f} L{cx:.1f} {top:.1f} L{cx + w:.1f} {bottom:.1f} '
        f'M{cx - w * 0.5:.1f} {bar_y:.1f} H{cx + w * 0.5:.1f}" fill="none" stroke="{PAPER}" '
        f'stroke-width="{sw:.1f}" stroke-linecap="square" stroke-linejoin="miter"/>'
    )


def composition() -> str:
    """F plus badge on a transparent 1024 canvas, inside the safe circle."""
    return letter(480, 450, 5.0) + badge(655, 655, 132)


def tile() -> str:
    return (
        '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{GREEN}"/><stop offset="1" stop-color="{GREEN_DARK}"/>'
        '</linearGradient></defs><rect width="1024" height="1024" rx="246" fill="url(#g)"/>'
    )


def svg(body: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>'


def render(source: str, out: Path, size: int, tmp: Path) -> None:
    src = tmp / "icon.svg"
    src.write_text(source)
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(src), "-o", str(out)], check=True)


def main() -> None:
    art = composition()
    foreground = svg(art)
    # Legacy launchers: no mask, so draw the tile and enlarge the art to fill it.
    tiled = svg(tile() + f'<g transform="translate(512 512) scale(1.3) translate(-512 -512)">{art}</g>')
    with tempfile.TemporaryDirectory() as tmp:
        for density, k in DENSITIES.items():
            render(foreground, RES / f"mipmap-{density}/ic_launcher_foreground.png", round(108 * k), Path(tmp))
            render(tiled, RES / f"mipmap-{density}/ic_launcher.png", round(48 * k), Path(tmp))
    print("Wrote Fidelia Admin icons for", ", ".join(DENSITIES))


if __name__ == "__main__":
    main()
