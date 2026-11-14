"""CORE logotipi va ilova belgilari.

G'oya: "yadro". Ochiq gradient halqa (ma'lumot oqimi) va uning markazidagi o'yin (play) belgisi:
konvertor, pleyer va yuklagich bitta yadroda. Halqaning ochiq joyida sariq nuqta: oqib ketayotgan fayl.

Foydalanish: python3 tools/gen_logo.py <repo papkasi>
Yaratadi:
  assets/logo.png, admin_app/assets/logo.png - ilovalar ichida (shaffof fon, belgi + CORE yozuvi)
  installer/core.png / .ico                  - Linux va Windows belgisi
  installer/icons/android/...                - Android ilova belgilari (asosiy va admin)
  installer/icons/ios/...                    - iPhone ilova belgilari (shaffoflik yo'q)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

FONTS = [
    "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf",
    "/opt/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf",
]
FONT_BOLD = next(f for f in FONTS if os.path.exists(f))

TEAL = (25, 230, 195)
VIOLET = (124, 92, 255)
YELLOW = (255, 214, 10)
NAVY = (13, 19, 48)
INK = (16, 22, 52)  # yozuv rangi (oq fonda)

SS = 2  # chizish aniqligi (supersampling)


def gradient(size, c0, c1, angle_deg=45.0):
    """Diagonal chiziqli gradient (RGBA, to'liq ko'rinadigan)."""
    w, h = size
    a = math.radians(angle_deg)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    t = (xs * math.cos(a) + ys * math.sin(a)) / (w * abs(math.cos(a)) + h * abs(math.sin(a)))
    t = np.clip(t, 0, 1)[..., None]
    arr = np.array(c0, np.float32) * (1 - t) + np.array(c1, np.float32) * t
    out = np.dstack([arr, np.full((h, w, 1), 255, np.float32)])
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def mark(size=1024, with_dot=True):
    """Belgi: gradient halqa + play + sariq nuqta. Shaffof fonda, size x size."""
    S = size * SS
    cx = cy = S / 2
    outer = S * 0.43
    thick = S * 0.125
    gap = 40  # halqaning o'ng tomondagi ochiq joyi (har tomonga, gradus)

    # --- halqa maskasi (yumaloq uchlari bilan)
    ring = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(ring)
    d.arc([cx - outer, cy - outer, cx + outer, cy + outer], gap, 360 - gap, fill=255, width=int(thick))
    rc = outer - thick / 2  # o'rta chiziq radiusi
    for ang in (gap, 360 - gap):
        x = cx + rc * math.cos(math.radians(ang))
        y = cy + rc * math.sin(math.radians(ang))
        d.ellipse([x - thick / 2, y - thick / 2, x + thick / 2, y + thick / 2], fill=255)

    # --- play belgisi (yumaloq burchakli uchburchak)
    tri = Image.new("L", (S, S), 0)
    td = ImageDraw.Draw(tri)
    r = S * 0.028  # burchak yumaloqligi
    pts = [(-0.105, -0.165), (-0.105, 0.165), (0.178, 0.0)]
    shift = S * 0.012  # optik markaz
    poly = [(cx + shift + x * S, cy + y * S) for x, y in pts]
    # ichkariga qisqartirib, so'ng chiziq qalinligi bilan yumaloqlaymiz (o'lcham saqlanadi)
    gx = sum(p[0] for p in poly) / 3
    gy = sum(p[1] for p in poly) / 3
    inner = []
    for px, py in poly:
        dx, dy = px - gx, py - gy
        dist = math.hypot(dx, dy)
        k = (dist - r * 1.9) / dist
        inner.append((gx + dx * k, gy + dy * k))
    td.polygon(inner, fill=255)
    td.line(inner + [inner[0]], fill=255, width=int(r * 2), joint="curve")
    for x, y in inner:
        td.ellipse([x - r, y - r, x + r, y + r], fill=255)

    grad = gradient((S, S), TEAL, VIOLET, 50)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(grad, (0, 0), ring)
    out.paste(gradient((S, S), TEAL, VIOLET, 50), (0, 0), tri)

    if with_dot:
        # ochiq joydagi sariq nuqta: oqib ketayotgan ma'lumot
        dot = Image.new("L", (S, S), 0)
        dd = ImageDraw.Draw(dot)
        dr = thick * 0.40
        x = cx + rc * math.cos(0)
        dd.ellipse([x - dr, cy - dr, x + dr, cy + dr], fill=255)
        yellow = Image.new("RGBA", (S, S), YELLOW + (255,))
        out.paste(yellow, (0, 0), dot)
    return out.resize((size, size), Image.LANCZOS)


def logo():
    """Ilova ichidagi logotip (shaffof fon): belgi va pastida CORE yozuvi. Oq fonda yaxshi ko'rinadi."""
    m = mark(900)
    text = "CORE"
    font = ImageFont.truetype(FONT_BOLD, 215)
    spacing = 30
    widths = [font.getlength(ch) for ch in text]
    total = int(sum(widths) + spacing * (len(text) - 1))
    asc, desc = font.getmetrics()
    W = max(m.width, total) + 40
    H = m.height + asc + desc
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    img.alpha_composite(m, ((W - m.width) // 2, 0))
    d = ImageDraw.Draw(img)
    x = (W - total) / 2
    y = m.height - 10
    for ch, w in zip(text, widths):
        d.text((x, y), ch, font=font, fill=INK + (255,))
        x += w + spacing
    return img.crop(img.getbbox())


def background(size, rounded=True):
    """Ilova belgisi foni: to'q ko'k, yuqorida yengil nur. rounded=False: iPhone uchun (butun kvadrat)."""
    S = size * SS
    base = gradient((S, S), (22, 33, 82), (7, 10, 26), 80)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([S * 0.15, S * -0.25, S * 0.85, S * 0.45], fill=TEAL + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.12))
    base.alpha_composite(glow)
    if rounded:
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.225), fill=255)
        base.putalpha(ImageChops.multiply(base.getchannel("A"), mask))
    return base.resize((size, size), Image.LANCZOS)


def square_icon(size, rounded=True, badge=None, fill=0.74):
    """Kvadrat belgi: to'q fon ustida belgi. badge - admin ilovasi uchun pastdagi yozuv."""
    S = 1024
    canvas = background(S, rounded)
    m = mark(int(S * fill))
    top = (S - m.height) // 2 - (70 if badge else 0)
    canvas.alpha_composite(m, ((S - m.width) // 2, top))
    if badge:
        d = ImageDraw.Draw(canvas)
        f = ImageFont.truetype(FONT_BOLD, 120)
        d.rounded_rectangle([210, 800, S - 210, 950], radius=75, fill=YELLOW + (255,))
        d.text((S // 2, 876), badge, font=f, fill=NAVY + (255,), anchor="mm")
    img = canvas.resize((size, size), Image.LANCZOS)
    return img if rounded else img.convert("RGB")


ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def main(repo):
    lg = logo()
    os.makedirs(f"{repo}/assets", exist_ok=True)
    scale = 900 / lg.width
    small = lg.resize((900, int(lg.height * scale)), Image.LANCZOS)
    small.save(f"{repo}/assets/logo.png", optimize=True)
    os.makedirs(f"{repo}/admin_app/assets", exist_ok=True)
    small.save(f"{repo}/admin_app/assets/logo.png", optimize=True)

    square_icon(512).save(f"{repo}/installer/core.png", optimize=True)
    square_icon(256).save(
        f"{repo}/installer/core.ico",
        sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)],
    )

    for app, badge in (("main", None), ("admin", "ADMIN")):
        for density, px in ANDROID.items():
            out = f"{repo}/installer/icons/android/{app}/mipmap-{density}"
            os.makedirs(out, exist_ok=True)
            square_icon(px, badge=badge).save(f"{out}/ic_launcher.png", optimize=True)

    # iPhone: Flutter shablonidagi AppIcon fayl nomlari va o'lchamlari (shaffoflik bo'lmasligi kerak)
    ios_dir = f"{repo}/installer/icons/ios"
    os.makedirs(ios_dir, exist_ok=True)
    contents = json.load(open(f"{repo}/installer/icons/ios-Contents.json"))
    done = set()
    for item in contents["images"]:
        name = item.get("filename")
        if not name or name in done:
            continue
        base = float(item["size"].split("x")[0])
        px = int(round(base * int(item["scale"].rstrip("x"))))
        square_icon(px, rounded=False).save(f"{ios_dir}/{name}", optimize=True)
        done.add(name)
    print("ok:", len(done), "iOS belgi,", 2 * len(ANDROID), "Android belgi")


if __name__ == "__main__":
    main(sys.argv[1])
