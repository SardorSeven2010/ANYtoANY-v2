"""ANYtoANY ilova belgisini (ikon) chizadi: installer/anytoany.png va installer/anytoany.ico"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
S = 1024  # katta o'lchamda chizilib, keyin kichraytiriladi


def gradient():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / (S - 1)
    t = np.clip((xx + yy) / 2, 0, 1)
    pos = [0.0, 0.5, 1.0]
    cols = np.array([(255, 196, 107), (255, 107, 139), (123, 77, 255)], np.float32)
    out = np.stack([np.interp(t, pos, cols[:, i]) for i in range(3)], axis=-1)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).convert("RGBA")


def icon():
    base = gradient()
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=230, fill=255)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.paste(base, (0, 0), mask)

    # yumshoq yorug'lik
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse([-200, -350, S + 100, S * 0.55], fill=70)
    glow = Image.composite(glow.filter(ImageFilter.GaussianBlur(60)), Image.new("L", (S, S), 0), mask)
    img = Image.alpha_composite(img, Image.merge("RGBA", [Image.new("L", (S, S), 255)] * 3 + [glow]))

    big = ImageFont.truetype(FONT, 330)
    arrow = ImageFont.truetype(FONT, 250)
    # "A ⇄ A": ikki A va o'rtada aylantirish o'qi; avval soya, keyin oq yozuv
    marks = [((300, 520), "A", big), ((724, 520), "A", big), ((512, 535), "\u21c4", arrow)]
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for (x, y), text, font in marks:
        sd.text((x + 10, y + 12), text, font=font, fill=(60, 20, 90, 120), anchor="mm")
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(12)))
    d = ImageDraw.Draw(img)
    for (x, y), text, font in marks:
        d.text((x, y), text, font=font, fill=(255, 255, 255, 255), anchor="mm")
    return img


if __name__ == "__main__":
    out_dir = sys.argv[1]
    im = icon()
    im.resize((512, 512), Image.LANCZOS).save(f"{out_dir}/anytoany.png", optimize=True)
    im.resize((256, 256), Image.LANCZOS).save(
        f"{out_dir}/anytoany.ico", sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    )
    print("ok")
