"""ANYtoANY logotipi va ilova belgilari (foydalanuvchi bergan dizayn asosida, yuqori o'lchamda).

Foydalanish: python3 tools/gen_logo.py <repo papkasi>
Yaratadi:
  assets/logo.png, admin_app/assets/... - ilovalar ichida (shaffof fon)
  installer/anytoany.png / .ico         - Linux va Windows belgisi
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
    """Shaffof fondagi logotip: qizil ANY, sariq to, yashil ANY."""
    W, H = 370 * K, 262 * K
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def box(x0, y0, x1, y1, fill, r=13):
        d.rounded_rectangle([x0 * K, y0 * K, x1 * K, y1 * K], radius=r * K, fill=fill)

    def text(x0, x1, cy, s, fill, font=FONT_BOLD):
        """Yozuvni asl rasmdagi kengligiga (x0..x1) moslab, cy balandlik markazida chizadi."""
        size = 100 * K
        f = ImageFont.truetype(font, size)
        left, top, right, bottom = d.textbbox((0, 0), s, font=f)
        size = int(size * (x1 - x0) * K / (right - left))
        f = ImageFont.truetype(font, size)
        left, top, right, bottom = d.textbbox((0, 0), s, font=f)
        x = x0 * K - left
        y = cy * K - (top + bottom) / 2
        d.text((x, y), s, font=f, fill=fill)

    box(4, 4, 134, 84, RED)
    box(113, 53, 207, 169, YELLOW)
    box(180, 141, 367, 258, GREEN)
    # kengliklar va markazlar asl rasmdagi o'lchovlardan olingan
    text(10, 129, 45.5, "ANY", WHITE)
    text(122, 195, 115.5, "to", BLACK)
    text(189, 361, 202, "ANY", WHITE)
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

    square_icon(512, lg).save(f"{repo}/installer/anytoany.png", optimize=True)
    square_icon(256, lg).save(
        f"{repo}/installer/anytoany.ico",
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
