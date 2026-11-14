"""CORE logotipi va ilova belgilari (uch rangli pog'onali dizayn: CO - qizil, R - sariq, E - yashil).

Foydalanish: python3 tools/gen_logo.py <repo papkasi>
Yaratadi:
  assets/logo.png, admin_app/assets/... - ilovalar ichida (shaffof fon)
  installer/core.png / .ico             - Linux va Windows belgisi
  installer/icons/android/...           - Android ilova belgilari (asosiy va admin)
  installer/icons/ios/...               - iPhone ilova belgilari
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = "/opt/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf"
FONT_BOLD = "/opt/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf"
RED = (255, 69, 57, 255)
YELLOW = (255, 214, 10, 255)
GREEN = (52, 200, 90, 255)
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
K = 8  # asl rasm (367x261) koordinatalari shu barobar kattalashtiriladi


def logo():
    """Shaffof fondagi logotip: qizil CO, sariq R, yashil E."""
    W, H = 370 * K, 262 * K
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def box(x0, y0, x1, y1, fill, r=13):
        d.rounded_rectangle([x0 * K, y0 * K, x1 * K, y1 * K], radius=r * K, fill=fill)

    def text(bx, s, fill, font=FONT_BOLD, fill_w=0.80, fill_h=0.64):
        """Yozuvni qutiga (bx = x0, y0, x1, y1) sig'diradi va o'rtasiga joylaydi."""
        x0, y0, x1, y1 = bx
        size = 100 * K
        f = ImageFont.truetype(font, size)
        left, top, right, bottom = d.textbbox((0, 0), s, font=f)
        scale = min((x1 - x0) * K * fill_w / (right - left), (y1 - y0) * K * fill_h / (bottom - top))
        f = ImageFont.truetype(font, int(size * scale))
        left, top, right, bottom = d.textbbox((0, 0), s, font=f)
        cx, cy = (x0 + x1) / 2 * K, (y0 + y1) / 2 * K
        d.text((cx - (left + right) / 2, cy - (top + bottom) / 2), s, font=f, fill=fill)

    boxes = {"CO": (4, 4, 134, 84), "R": (113, 53, 207, 169), "E": (180, 141, 367, 258)}
    box(*boxes["CO"], RED)
    box(*boxes["R"], YELLOW)
    box(*boxes["E"], GREEN)
    text(boxes["CO"], "CO", WHITE)
    text(boxes["R"], "R", BLACK, fill_w=0.62, fill_h=0.52)
    text(boxes["E"], "E", WHITE, fill_w=0.5, fill_h=0.64)
    return img.crop(img.getbbox())


def square_icon(size, logo_img, background=(255, 255, 255, 255), fill=0.84, badge=None):
    """Kvadrat belgi: oq fon o'rtasida logotip. badge - admin ilovasi uchun pastdagi yozuv."""
    S = 1024
    canvas = Image.new("RGBA", (S, S), background)
    lw = int(S * fill)
    lh = int(logo_img.height * lw / logo_img.width)
    top = (S - lh) // 2 - (60 if badge else 0)
    canvas.alpha_composite(logo_img.resize((lw, lh), Image.LANCZOS), ((S - lw) // 2, top))
    if badge:
        d = ImageDraw.Draw(canvas)
        f = ImageFont.truetype(FONT_BOLD, 132)
        d.rounded_rectangle([190, 812, S - 190, 972], radius=56, fill=(25, 25, 35, 255))
        d.text((S // 2, 893), badge, font=f, fill=(255, 214, 10, 255), anchor="mm")
    return canvas.resize((size, size), Image.LANCZOS)


ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def main(repo):
    lg = logo()
    os.makedirs(f"{repo}/assets", exist_ok=True)
    small = lg.resize((lg.width // 4, lg.height // 4), Image.LANCZOS)
    small.save(f"{repo}/assets/logo.png", optimize=True)
    os.makedirs(f"{repo}/admin_app/assets", exist_ok=True)
    small.save(f"{repo}/admin_app/assets/logo.png", optimize=True)

    square_icon(512, lg).save(f"{repo}/installer/core.png", optimize=True)
    square_icon(256, lg).save(
        f"{repo}/installer/core.ico",
        sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)],
    )

    for app, badge in (("main", None), ("admin", "ADMIN")):
        for density, px in ANDROID.items():
            out = f"{repo}/installer/icons/android/{app}/mipmap-{density}"
            os.makedirs(out, exist_ok=True)
            square_icon(px, lg, badge=badge).save(f"{out}/ic_launcher.png", optimize=True)

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
        square_icon(px, lg).convert("RGB").save(f"{ios_dir}/{name}", optimize=True)
        done.add(name)
    print("ok:", len(done), "iOS belgi,", 2 * len(ANDROID), "Android belgi")


if __name__ == "__main__":
    main(sys.argv[1])
