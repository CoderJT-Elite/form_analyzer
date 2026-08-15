"""Generate the Android launcher icon set from the Form Analyzer brand logo.

The published logo is a wide wordmark: an athlete figure on the left, the words
"FORM ANALYZER" on the right. That shape cannot be a launcher icon, which is
square and rendered small, so this crops the figure alone and places it on the
app's dark background, recoloured to the cyan accent used throughout the UI.

Outputs (in app/assets/icon/):
  icon.png            1024x1024 full-bleed icon
  icon_foreground.png 1024x1024 transparent foreground for Android adaptive icons

Run from the repository root:
    python tools/make_icons.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "web" / "OFFICIAL FORM ANALYZER LOGO.png"
OUT_DIR = ROOT / "app" / "assets" / "icon"

SIZE = 1024

# Horizontal span of the athlete figure within the source wordmark.
FIGURE_X = (54, 261)

# App palette (lib/core/app_colors.dart).
BG_INNER = (18, 26, 38)
BG_OUTER = (5, 5, 5)
ACCENT = (0, 229, 255)


def load_figure() -> Image.Image:
    """Crop the athlete out of the wordmark and trim to its own bounds."""
    logo = Image.open(SOURCE).convert("RGBA")
    figure = logo.crop((FIGURE_X[0], 0, FIGURE_X[1], logo.height))
    bbox = figure.getbbox()
    if bbox is None:
        raise SystemExit("Could not find the figure in the source logo.")
    return figure.crop(bbox)


def recolour(figure: Image.Image) -> Image.Image:
    """Repaint the figure in the accent colour.

    The source art is dark blue, chosen to sit on the website's white page. On
    the app's near-black icon background that would be almost invisible, so
    each pixel's luminance is stretched across its own range and used to shade
    the accent colour. Alpha is preserved untouched so the silhouette and its
    anti-aliased edges survive intact.
    """
    rgb = figure.convert("RGB")
    alpha = figure.split()[3]
    grey = rgb.convert("L")

    pixels = [p for p, a in zip(grey.getdata(), alpha.getdata()) if a > 8]
    low, high = (min(pixels), max(pixels)) if pixels else (0, 255)
    span = max(high - low, 1)

    out = Image.new("RGBA", figure.size)
    out_px = out.load()
    grey_px = grey.load()
    alpha_px = alpha.load()

    for y in range(figure.height):
        for x in range(figure.width):
            a = alpha_px[x, y]
            if a == 0:
                continue
            norm = min(max((grey_px[x, y] - low) / span, 0.0), 1.0)
            # Floor at 0.62 so shadowed muscle detail still reads at 48px, and
            # lift the brightest areas toward white so the figure has highlights
            # rather than reading as one flat silhouette.
            t = 0.62 + 0.38 * norm
            highlight = max(norm - 0.72, 0.0) / 0.28 * 0.55
            out_px[x, y] = (
                int(min(ACCENT[0] * t + 255 * highlight, 255)),
                int(min(ACCENT[1] * t + 255 * highlight, 255)),
                int(min(ACCENT[2] * t + 255 * highlight, 255)),
                a,
            )
    return out


def background(size: int) -> Image.Image:
    """Soft radial wash from a deep blue centre to near-black corners."""
    bg = Image.new("RGBA", (size, size), BG_OUTER + (255,))
    draw = ImageDraw.Draw(bg)
    steps = 160
    for i in range(steps, 0, -1):
        t = i / steps
        radius = int(size * 0.78 * t)
        blend = 1.0 - t
        colour = tuple(
            int(BG_OUTER[c] + (BG_INNER[c] - BG_OUTER[c]) * blend) for c in range(3)
        )
        draw.ellipse(
            [
                size // 2 - radius,
                size // 2 - radius,
                size // 2 + radius,
                size // 2 + radius,
            ],
            fill=colour + (255,),
        )
    return bg


def place(figure: Image.Image, canvas_size: int, coverage: float) -> Image.Image:
    """Scale the figure to `coverage` of the canvas and centre it."""
    target = canvas_size * coverage
    scale = min(target / figure.width, target / figure.height)
    resized = figure.resize(
        (max(int(figure.width * scale), 1), max(int(figure.height * scale), 1)),
        Image.LANCZOS,
    )
    layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    layer.paste(
        resized,
        (
            (canvas_size - resized.width) // 2,
            (canvas_size - resized.height) // 2,
        ),
        resized,
    )
    return layer


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    figure = recolour(load_figure())

    # Full-bleed icon.
    icon = Image.alpha_composite(background(SIZE), place(figure, SIZE, 0.66))
    icon.save(OUT_DIR / "icon.png")

    # Adaptive foreground. flutter_launcher_icons already insets this drawable
    # by 16%, which lands it inside the launcher's safe zone, so the figure
    # fills most of this canvas rather than being padded a second time here.
    foreground = place(figure, SIZE, 0.80)
    foreground.save(OUT_DIR / "icon_foreground.png")

    # In-app mark used by the splash screen. That widget tints the image with
    # `color:`, so only the silhouette matters — but it previously pointed at an
    # "ANTIGRAVITY" logo, a different brand entirely, squashed into a 60px
    # circle. A square figure mark reads correctly at that size.
    app_logo = place(figure, 512, 0.92)
    app_logo_path = ROOT / "app" / "assets" / "logo.png"
    app_logo.save(app_logo_path)

    print(f"Wrote {OUT_DIR / 'icon.png'}, {OUT_DIR / 'icon_foreground.png'} "
          f"and {app_logo_path}")


if __name__ == "__main__":
    main()
