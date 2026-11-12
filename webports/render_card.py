#!/usr/bin/env python3
"""Rasterise the balance card the GIF distorts. The ripple itself is applied in ripple-capture.mjs."""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 360, 248
CARD = (30, 18, 300, 188)
PAGE = (240, 232, 214)
INK = np.array([20, 56, 46], dtype=np.float32)
DEEP = np.array([13, 33, 28], dtype=np.float32)
CREAM = (245, 237, 219)
GOLD = (201, 163, 87)
MUTED = (168, 176, 168)

SANS = "/usr/share/fonts/truetype/macos/Inter-Regular.ttf"
SANS_SEMI = "/usr/share/fonts/truetype/macos/Inter-SemiBold.ttf"


def card_image(amount: str) -> tuple[Image.Image, tuple[float, float]]:
    cw, ch = CARD[2], CARD[3]
    yy, xx = np.mgrid[0:ch, 0:cw]
    t = (xx / (cw - 1) + yy / (ch - 1)) / 2
    grad = INK * (1 - t)[..., None] + DEEP * t[..., None]
    base = Image.fromarray(grad.astype(np.uint8), "RGB")
    circle = Image.new("L", (cw, ch), 0)
    ImageDraw.Draw(circle).ellipse((168, -70, 348, 110), fill=18)
    cream = Image.new("RGB", (cw, ch), (245, 237, 219))
    base = Image.composite(cream, base, circle).convert("RGBA")
    draw = ImageDraw.Draw(base, "RGBA")

    title_font = ImageFont.truetype(SANS_SEMI, 12)
    meta_font = ImageFont.truetype(SANS, 12)
    label_font = ImageFont.truetype(SANS, 13)
    amount_font = ImageFont.truetype(SANS_SEMI, 34)

    draw.text((22, 20), "EVERYDAY", font=title_font, fill=(*CREAM, 160))
    account = "···· 4291"
    account_w = draw.textlength(account, font=meta_font)
    draw.text((cw - 22 - account_w, 20), account, font=meta_font, fill=(*CREAM, 160))

    draw.rounded_rectangle((22, 58, 58, 86), radius=5, fill=GOLD)
    draw.rounded_rectangle((27, 63, 53, 81), radius=2, outline=(13, 33, 28, 90), width=1)

    draw.text((22, 108), "Available", font=label_font, fill=(*CREAM, 150))
    amount_at = (22, 128)
    draw.text(amount_at, amount, font=amount_font, fill=(*CREAM, 255))
    bbox = draw.textbbox(amount_at, amount, font=amount_font)
    tap = ((bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2)

    mask = Image.new("L", (cw, ch), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, cw - 1, ch - 1), radius=28, fill=255)
    base.putalpha(mask)
    return base, tap


def page_with(card: Image.Image) -> Image.Image:
    page = Image.new("RGB", (W, H), PAGE)
    page.paste(card, (CARD[0], CARD[1]), card)
    return page


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    shown, tap = card_image("$4,820.16")
    hidden, _ = card_image("$•,•••.••")
    shown_page = page_with(shown)
    hidden_page = page_with(hidden)
    (out / "shown.rgb").write_bytes(shown_page.tobytes())
    (out / "hidden.rgb").write_bytes(hidden_page.tobytes())
    meta = {
        "width": W,
        "height": H,
        "tap": {"x": CARD[0] + tap[0], "y": CARD[1] + tap[1]},
        "card": {"x": CARD[0], "y": CARD[1], "width": CARD[2], "height": CARD[3]},
    }
    (out / "meta.json").write_text(json.dumps(meta))
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
