"""ANYtoANY mavzulari uchun fon rasmlarini chizadi (1080x1920).
Hammasi shu skript bilan yaratiladi - tashqi rasm ishlatilmaydi."""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1080, 1920
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
ny, nx = yy / (H - 1), xx / (W - 1)


def hexc(s):
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


def vgrad(stops):
    pos = np.array([p for p, _ in stops], np.float32)
    cols = np.stack([hexc(c) for _, c in stops])
    t = np.linspace(0, 1, H, dtype=np.float32)
    out = np.stack([np.interp(t, pos, cols[:, i]) for i in range(3)], axis=1)
    return np.repeat(out[:, None, :], W, axis=1).astype(np.float32)


def noise(seed, cells_x, cells_y=None):
    rng = np.random.default_rng(seed)
    cy = cells_y or max(2, int(cells_x * H / W))
    small = rng.random((cy, cells_x)).astype(np.float32)
    im = Image.fromarray((small * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255


def fbm(seed, base=4, octaves=4):
    out = np.zeros((H, W), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * noise(seed + o * 17, base * (2 ** o))
        tot += amp
        amp *= 0.5
    return out / tot


def noise1d(seed, n, w=W):
    rng = np.random.default_rng(seed)
    pts = rng.random(n + 3) * 2 - 1
    x = np.linspace(0, n, w)
    i = np.floor(x).astype(int)
    f = x - i
    f = (1 - np.cos(f * np.pi)) / 2
    return (pts[i] * (1 - f) + pts[i + 1] * f).astype(np.float32)


def ridge(seed, base, amp, n=5, rough=0.35):
    p = noise1d(seed, n) * amp + noise1d(seed + 1, n * 4) * amp * rough \
        + noise1d(seed + 2, n * 16) * amp * rough * 0.3
    return (base + p) * H


def layer(img, prof, color, soft=1.5):
    a = np.clip((yy - prof[None, :]) / soft, 0, 1)[..., None]
    return img * (1 - a) + color * a


def screen(img, add):
    return 1 - (1 - img) * (1 - np.clip(add, 0, 1))


def blur(arr, r):
    im = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255


def stars(seed, n, ymax=1.0):
    rng = np.random.default_rng(seed)
    s = np.zeros((H, W), np.float32)
    xs = rng.integers(0, W, n)
    ys = (rng.random(n) ** 1.3 * ymax * H).astype(int).clip(0, H - 1)
    s[ys, xs] = rng.random(n) ** 2.0
    big = np.zeros_like(s)
    k = rng.random(n) > 0.94
    big[ys[k], xs[k]] = 1
    return np.clip(blur(s, 0.7) * 3.2 + blur(big, 1.8) * 6.0, 0, 1)


def glow(cx, cy, radius, power=2.0):
    d = np.sqrt((xx - cx * W) ** 2 + (yy - cy * H) ** 2) / (radius * W)
    return np.clip(1 - d, 0, 1) ** power


def vignette(img, strength=0.35):
    d = (nx - 0.5) ** 2 * 1.2 + (ny - 0.5) ** 2
    return img * (1 - strength * np.clip(d * 2.2, 0, 1))[..., None]


def grain(img, seed, amt=0.010):
    rng = np.random.default_rng(seed)
    return img + (rng.random((H, W, 1)).astype(np.float32) - 0.5) * amt * 2


def trees(prof, seed, count, hmin, hmax, wratio=0.42):
    """Tizma chizig'iga archa siluetlarini qo'shadi (y kichik = balandroq)."""
    rng = np.random.default_rng(seed)
    out = prof.copy()
    xs = np.arange(W, dtype=np.float32)
    for _ in range(count):
        x0 = rng.uniform(-20, W + 20)
        h = rng.uniform(hmin, hmax) * H
        w = h * wratio * rng.uniform(0.8, 1.2)
        d = np.abs(xs - x0) / (w / 2)
        base = np.interp(x0, xs, prof)
        tiers = 5
        shape = np.where(d < 1, (1 - d) + 0.10 * ((1 - d) * tiers % 1.0), 0)
        out = np.minimum(out, base + 6 - h * np.clip(shape, 0, 1.08))
    return out


def save(img, name, q=85):
    arr = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(arr).save(name, quality=q, optimize=True, progressive=True)
    print('saved', name)


# ------------------------------------------------------------------ sahnalar
def galaxy():
    img = vgrad([(0, '#05051a'), (0.45, '#140a3a'), (0.8, '#2a1454'), (1, '#3b1b5e')])
    n1, n2 = fbm(11, 3, 5), fbm(29, 5, 5)
    band = np.exp(-(((nx * 0.9 + ny * 0.55) - 0.78) / 0.20) ** 2)
    neb = np.clip(n1 * 1.5 - 0.42, 0, 1) * (0.35 + band)
    img = screen(img, neb[..., None] * hexc('#7b3fe4') * 0.70)
    img = screen(img, (np.clip(n2 * 1.6 - 0.62, 0, 1) * band)[..., None] * hexc('#ff5fa8') * 0.75)
    img = screen(img, (np.clip(n1 * n2 * 3 - 0.55, 0, 1) * band)[..., None] * hexc('#49c6ff') * 0.6)
    st = stars(5, 2600) * (0.55 + 0.9 * band) + stars(6, 900) * band
    img = screen(img, st[..., None] * np.array([1, 0.97, 0.92], np.float32))
    img = layer(img, ridge(41, 0.86, 0.035, 5), hexc('#1c1140'))
    img = layer(img, trees(ridge(43, 0.92, 0.03, 4), 7, 70, 0.02, 0.05), hexc('#0b0720'))
    return grain(vignette(img, 0.30), 1)


def aurora():
    img = vgrad([(0, '#020b1c'), (0.5, '#062a3a'), (0.78, '#0b4a4a'), (1, '#0a2a33')])
    img = screen(img, stars(21, 1700, 0.75)[..., None] * 0.9)
    total = np.zeros((H, W, 3), np.float32)
    xs = np.arange(W)
    for k, (y0, amp, col_lo, col_hi, power) in enumerate([
            (0.50, 0.07, '#35ffb0', '#6a5cff', 1.0),
            (0.38, 0.09, '#2fe6d0', '#b25cff', 0.75),
            (0.60, 0.05, '#7dff8a', '#3fd0ff', 0.55)]):
        c = (y0 + noise1d(60 + k * 7, 3) * amp + noise1d(61 + k * 7, 9) * amp * 0.3) * H
        streak = 0.55 + 0.45 * (noise1d(62 + k * 7, 70) * 0.5 + 0.5) ** 1.5
        dy = yy - c[None, :]
        below = np.exp(-(np.clip(dy, 0, None) / (0.012 * H)) ** 2)
        above = np.exp(np.clip(dy, None, 0) / (0.20 * H))
        inten = np.where(dy > 0, below, above) * streak[None, :] * power
        t = np.clip(-dy / (0.30 * H), 0, 1)[..., None]
        col = hexc(col_lo) * (1 - t) + hexc(col_hi) * t
        total += inten[..., None] * col
    total = blur(np.clip(total, 0, 1), 5)
    img = screen(img, total * 0.95)
    hz = 0.80
    img = layer(img, ridge(71, hz - 0.035, 0.05, 4), hexc('#0c2f3d'))
    img = layer(img, trees(ridge(73, hz + 0.01, 0.02, 4), 9, 60, 0.02, 0.055), hexc('#041a22'))
    # ko'ldagi aks
    hy = int((hz + 0.035) * H)
    refl = img[:hy][::-1][: H - hy]
    rows = np.arange(refl.shape[0])
    shift = (np.sin(rows * 0.35) * (1.5 + rows * 0.012)).astype(int)
    refl = np.stack([np.roll(refl[i], shift[i], axis=0) for i in rows])
    fade = np.linspace(0.62, 0.25, refl.shape[0], dtype=np.float32)[:, None, None]
    img[hy:hy + refl.shape[0]] = refl * fade + hexc('#031018') * (1 - fade)
    return grain(vignette(img, 0.28), 2)


def sunset():
    img = vgrad([(0, '#241046'), (0.30, '#6a1b6e'), (0.52, '#d6455d'), (0.66, '#ff8a4c'), (0.74, '#ffc46b'), (1, '#ffb86b')])
    sun_y = 0.70
    img = screen(img, glow(0.5, sun_y, 0.75, 2.2)[..., None] * hexc('#ff9a4a') * 0.75)
    disc = np.clip((0.115 * W - np.sqrt((xx - 0.5 * W) ** 2 + (yy - sun_y * H) ** 2)) / 2.0, 0, 1)[..., None]
    img = img * (1 - disc) + hexc('#fff1c2') * disc
    cl = np.clip(fbm(81, 3, 5) * 1.7 - 0.72, 0, 1) * np.clip(1 - np.abs(ny - 0.42) / 0.30, 0, 1)
    cl = blur(cl * np.clip(noise(83, 2, 9) * 1.6, 0, 1), 6)
    img = img * (1 - cl[..., None] * 0.55) + hexc('#ff7a6b') * cl[..., None] * 0.55
    cols = ['#b0507a', '#7d3a72', '#522a63', '#321b4b', '#1b0f2e']
    bases = [0.72, 0.77, 0.83, 0.89, 0.95]
    amps = [0.05, 0.05, 0.045, 0.04, 0.03]
    for i, (c, b, a) in enumerate(zip(cols, bases, amps)):
        prof = ridge(90 + i * 5, b, a, 4 + i)
        if i >= 3:
            prof = trees(prof, 12 + i, 55, 0.018, 0.045)
        img = layer(img, prof, hexc(c))
    return grain(vignette(img, 0.22), 3)


def ocean():
    img = vgrad([(0, '#39d0e8'), (0.18, '#1596c9'), (0.5, '#0a4f8f'), (0.8, '#062a5e'), (1, '#03143a')])
    ang = np.arctan2(yy + 0.25 * H, xx - 0.30 * W)
    rays = np.zeros((H, W), np.float32)
    rng = np.random.default_rng(100)
    for _ in range(16):
        a0 = rng.uniform(0.75, 2.0)
        wdt = rng.uniform(0.012, 0.05)
        rays += np.exp(-((ang - a0) / wdt) ** 2) * rng.uniform(0.25, 0.9)
    rays = blur(np.clip(rays, 0, 1), 7) * np.clip(1.15 - ny * 1.15, 0, 1) ** 1.3
    img = screen(img, rays[..., None] * hexc('#bff6ff') * 0.60)
    caust = np.clip(fbm(103, 9, 3) * 2.2 - 1.0, 0, 1) * np.clip(1 - ny * 3.2, 0, 1)
    img = screen(img, caust[..., None] * 0.45)
    bub = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(bub)
    for _ in range(70):
        r = rng.uniform(3, 20)
        x, y = rng.uniform(0, W), rng.uniform(0.15 * H, H)
        d.ellipse([x - r, y - r, x + r, y + r], outline=int(rng.uniform(70, 170)), width=max(1, int(r / 6)))
        d.ellipse([x - r * 0.45, y - r * 0.55, x - r * 0.15, y - r * 0.25], fill=int(rng.uniform(120, 220)))
    img = screen(img, (np.asarray(bub.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255)[..., None] * 0.7)
    img = layer(img, ridge(105, 0.93, 0.03, 5), hexc('#04214a'))
    img = layer(img, ridge(107, 0.975, 0.02, 7), hexc('#020f28'))
    return grain(vignette(img, 0.30), 4)


def forest():
    img = vgrad([(0, '#dfeedd'), (0.30, '#b7d7b9'), (0.6, '#7fb08e'), (1, '#3d6b55')])
    img = screen(img, glow(0.72, 0.16, 0.6, 2.0)[..., None] * hexc('#fff4c4') * 0.55)
    cols = ['#9cc4a4', '#78a98a', '#568c70', '#3a7058', '#255444', '#153a30', '#0a241e']
    bases = [0.40, 0.50, 0.60, 0.69, 0.78, 0.87, 0.95]
    for i, (c, b) in enumerate(zip(cols, bases)):
        prof = trees(ridge(120 + i * 3, b, 0.03, 4 + i), 20 + i, 46 + i * 6, 0.03 + i * 0.006, 0.07 + i * 0.012)
        img = layer(img, prof, hexc(c))
        if i < 5:
            fog = np.clip(1 - np.abs(ny - (b + 0.05)) / 0.05, 0, 1) * (0.35 + 0.65 * noise(140 + i, 3, 12))
            fog = blur(fog, 14)[..., None]
            img = img * (1 - fog * 0.42) + hexc('#eaf5ea') * fog * 0.42
    return grain(vignette(img, 0.20), 5)


def sakura():
    img = vgrad([(0, '#ffd9e6'), (0.45, '#ffe9ef'), (0.75, '#fff4ee'), (1, '#ffe2d6')])
    rng = np.random.default_rng(160)
    bok = np.zeros((H, W, 3), np.float32)
    for _ in range(60):
        r = rng.uniform(40, 170)
        cx, cy = rng.uniform(0, W), rng.uniform(0, H)
        m = np.clip((r - np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)) / 6, 0, 1)
        col = hexc(rng.choice(['#ff9cc0', '#ffffff', '#ffc2d6', '#ffb3a6', '#f7a8ff']))
        bok += m[..., None] * col * rng.uniform(0.05, 0.16)
    img = np.clip(img + blur(np.clip(bok, 0, 1), 3) * 0.55 - 0.06, 0, 1)
    S = 2
    ov = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)

    def blossom(x, y, r, a):
        petal = (255, int(rng.uniform(170, 215)), int(rng.uniform(200, 232)), 245)
        for k in range(5):
            t = a + k * 2 * np.pi / 5
            px, py = x + np.cos(t) * r * 0.62, y + np.sin(t) * r * 0.62
            d.ellipse([px - r * 0.52, py - r * 0.52, px + r * 0.52, py + r * 0.52], fill=petal)
        d.ellipse([x - r * 0.24, y - r * 0.24, x + r * 0.24, y + r * 0.24], fill=(230, 80, 120, 255))

    def branch(x, y, ang, length, width, depth):
        if depth == 0 or length < 18:
            return
        segs = 6
        for _ in range(segs):
            ang += rng.uniform(-0.22, 0.22)
            nx_, ny_ = x + np.cos(ang) * length / segs, y + np.sin(ang) * length / segs
            d.line([x, y, nx_, ny_], fill=(74, 44, 52, 255), width=max(2, int(width)))
            x, y = nx_, ny_
            width *= 0.93
            if rng.random() < 0.80:
                blossom(x + rng.uniform(-26, 26), y + rng.uniform(-26, 26), rng.uniform(13, 27) * S / 2, rng.uniform(0, 6.28))
            if rng.random() < 0.34:
                branch(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0), length * 0.55, width * 0.7, depth - 1)
        branch(x, y, ang + rng.uniform(-0.3, 0.3), length * 0.62, width * 0.8, depth - 1)

    branch(-20 * S, 150 * S, 0.30, 900 * S, 22 * S, 4)
    branch(W * S + 20, 520 * S, np.pi - 0.42, 760 * S, 18 * S, 4)
    branch(W * S + 20, 1500 * S, np.pi + 0.35, 520 * S, 13 * S, 3)
    for _ in range(90):
        x, y = rng.uniform(0, W * S), rng.uniform(0, H * S)
        r = rng.uniform(7, 15) * S / 2
        p = Image.new('RGBA', (int(r * 4), int(r * 4)), (0, 0, 0, 0))
        ImageDraw.Draw(p).ellipse([r * 0.6, r * 1.3, r * 3.4, r * 2.7], fill=(255, int(rng.uniform(160, 205)), int(rng.uniform(195, 225)), int(rng.uniform(150, 235))))
        p = p.rotate(rng.uniform(0, 360), resample=Image.BICUBIC)
        ov.alpha_composite(p, (int(x), int(y)))
    ov = ov.resize((W, H), Image.LANCZOS)
    a = np.asarray(ov, np.float32) / 255
    img = img * (1 - a[..., 3:4]) + a[..., :3] * a[..., 3:4]
    return grain(img, 6, 0.006)


def desert():
    img = vgrad([(0, '#3a2a6b'), (0.25, '#a8527a'), (0.45, '#f08a5d'), (0.58, '#ffd08a'), (1, '#ffd9a0')])
    sy = 0.50
    img = screen(img, glow(0.68, sy, 0.6, 2.4)[..., None] * hexc('#ffd28a') * 0.7)
    disc = np.clip((0.085 * W - np.sqrt((xx - 0.68 * W) ** 2 + (yy - sy * H) ** 2)) / 2.0, 0, 1)[..., None]
    img = img * (1 - disc) + hexc('#fff3cf') * disc
    img = layer(img, ridge(180, 0.585, 0.022, 6, 0.6), hexc('#b9667a'))
    lit = ['#f2b06a', '#e89a55', '#d98044', '#bf6635', '#9a4c2b']
    dark = ['#c98050', '#b0683f', '#93512f', '#733c25', '#52291c']
    bases = [0.63, 0.70, 0.78, 0.86, 0.94]
    for i in range(5):
        prof = (bases[i] + noise1d(190 + i * 3, 2 + i % 2) * 0.045 + noise1d(191 + i * 3, 5) * 0.012) * H
        slope = np.gradient(prof)
        face = 0.5 + 0.5 * np.tanh(slope * 3.2)
        depth = np.clip((yy - prof[None, :]) / (0.16 * H), 0, 1)
        shade = (face[None, :] * (1 - depth * 0.55))[..., None]
        col = hexc(lit[i]) * shade + hexc(dark[i]) * (1 - shade)
        ripple = (np.sin((yy - prof[None, :]) * 0.55 + nx * 9) * 0.5 + 0.5)[..., None] * 0.035
        img = layer(img, prof, col - ripple, 2.0)
    return grain(vignette(img, 0.22), 7)


def snow():
    img = vgrad([(0, '#7fb2e6'), (0.35, '#b9d7f2'), (0.62, '#e9f3fb'), (1, '#f6fbff')])
    img = screen(img, glow(0.25, 0.20, 0.55, 2.0)[..., None] * 0.45)
    specs = [(0.50, 0.11, '#c9dcf0', '#9fbfe0', 3), (0.60, 0.09, '#eef6ff', '#a8c4e2', 4), (0.70, 0.07, '#ffffff', '#bcd3ea', 5)]
    for i, (b, a, lit, sh, n) in enumerate(specs):
        prof = ridge(210 + i * 5, b, a, n, 0.5)
        k = np.hanning(61)
        smooth = np.convolve(np.pad(prof, 30, mode='edge'), k / k.sum(), mode='valid')
        face = (0.5 + 0.5 * np.tanh(np.gradient(smooth) * 2.2))[None, :, None]
        depth = np.clip((yy - prof[None, :]) / (0.22 * H), 0, 1)[..., None]
        col = (hexc(lit) * face + hexc(sh) * (1 - face)) * (1 - depth * 0.10) + hexc('#f4f9ff') * depth * 0.10
        img = layer(img, prof, col, 2.0)
    for i, (b, c, cnt) in enumerate([(0.80, '#6d8fb3', 70), (0.87, '#46688f', 60), (0.95, '#2b4669', 50)]):
        prof = trees(ridge(230 + i * 3, b, 0.02, 4), 30 + i, cnt, 0.03 + i * 0.012, 0.07 + i * 0.02)
        img = layer(img, prof, hexc(c))
    rng = np.random.default_rng(240)
    fl = np.zeros((H, W), np.float32)
    n = 900
    fl[rng.integers(0, H, n), rng.integers(0, W, n)] = rng.random(n)
    img = screen(img, np.clip(blur(fl, 1.6) * 9, 0, 1)[..., None] * 0.9)
    return grain(img, 8, 0.006)


def neon():
    img = vgrad([(0, '#07021a'), (0.35, '#1b0540'), (0.56, '#5b0f6b'), (0.62, '#ff3d8b'), (0.625, '#12032e'), (1, '#070116')])
    hz = 0.62
    img[: int(hz * H)] = screen(img, stars(250, 900, 0.5)[..., None] * 0.9)[: int(hz * H)]
    cy, r = 0.50, 0.30 * W
    dist = np.sqrt((xx - 0.5 * W) ** 2 + (yy - cy * H) ** 2)
    disc = np.clip((r - dist) / 2.0, 0, 1)
    t = np.clip((yy - (cy * H - r)) / (2 * r), 0, 1)[..., None]
    suncol = hexc('#ffe45c') * (1 - t) + hexc('#ff2e88') * t
    stripes = np.ones((H, W), np.float32)
    for k in range(7):
        y0 = cy * H + r * (0.05 + k * 0.135)
        stripes *= 1 - np.clip(1 - np.abs(yy - y0) / (3 + k * 2.6), 0, 1)
    disc = (disc * stripes * (yy < hz * H))[..., None]
    img = screen(img, (glow(0.5, cy, 0.62, 2.0) * (ny < hz))[..., None] * hexc('#ff3d8b') * 0.5)
    img = img * (1 - disc) + suncol * disc
    img = layer(img, np.maximum(ridge(260, hz - 0.03, 0.035, 9, 0.9), 0) * 1.0, hexc('#1a0638'))
    img[int(hz * H):] = vgrad([(0, '#12032e'), (hz, '#12032e'), (1, '#070116')])[int(hz * H):]
    S = 2
    g = Image.new('L', (W * S, H * S), 0)
    d = ImageDraw.Draw(g)
    hy = hz * H * S
    for i in range(-22, 23):
        d.line([W * S / 2 + i * 14 * S, hy, W * S / 2 + i * 170 * S, H * S], fill=255, width=3)
    for k in range(1, 19):
        y = hy + (k / 18) ** 2.3 * (H * S - hy)
        d.line([0, y, W * S, y], fill=255, width=3)
    d.line([0, hy, W * S, hy], fill=255, width=4)
    g = g.resize((W, H), Image.LANCZOS)
    ga = np.asarray(g, np.float32) / 255
    gl = blur(ga, 6)
    fade = np.clip((ny - hz) / (1 - hz), 0, 1) * 0.75 + 0.25
    img = screen(img, (gl * 0.9 * fade)[..., None] * hexc('#ff2e88'))
    img = screen(img, (ga * fade)[..., None] * hexc('#5ff3ff'))
    return grain(vignette(img, 0.25), 9)


def classic():
    img = np.zeros((H, W, 3), np.float32) + hexc('#071b1f')
    for cx, cy, r, c, a in [(0.15, 0.12, 0.85, '#19c8b0', 0.55), (0.95, 0.38, 0.8, '#1c6fd6', 0.50),
                            (0.30, 0.80, 0.9, '#0fa58f', 0.45), (0.90, 0.98, 0.7, '#6b3fd9', 0.40)]:
        img = screen(img, glow(cx, cy, r, 2.2)[..., None] * hexc(c) * a)
    n = fbm(270, 3, 4)[..., None]
    img = img * (0.86 + 0.28 * n)
    wav = np.zeros((H, W), np.float32)
    for k in range(7):
        c = (0.30 + k * 0.085 + noise1d(280 + k, 2) * 0.07 + nx[0] * 0.10) * H
        wav += np.exp(-((yy - c[None, :]) / 2.4) ** 2) * (0.22 + 0.06 * k)
    img = screen(img, blur(wav, 1.2)[..., None] * hexc('#7ff5e1') * 0.35)
    return grain(vignette(img, 0.35), 10)


def auth():
    img = vgrad([(0, '#0b1033'), (0.28, '#3b1f6b'), (0.46, '#b0457f'), (0.56, '#ff8f5e'), (0.62, '#ffd08a'), (1, '#ffd08a')])
    hz = 0.62
    img = screen(img, stars(300, 900, 0.30)[..., None] * 0.8 * np.clip(1 - ny * 3.0, 0, 1)[..., None])
    img = screen(img, glow(0.5, hz - 0.015, 0.7, 2.4)[..., None] * hexc('#ffb36b') * 0.75)
    disc = np.clip((0.075 * W - np.sqrt((xx - 0.5 * W) ** 2 + (yy - (hz - 0.012) * H) ** 2)) / 2.0, 0, 1)[..., None]
    img = img * (1 - disc) + hexc('#fff3cf') * disc
    cl = blur(np.clip(fbm(310, 3, 5) * 1.8 - 0.80, 0, 1) * np.clip(1 - np.abs(ny - 0.36) / 0.20, 0, 1) * np.clip(noise(312, 2, 10) * 1.6, 0, 1), 5)
    img = img * (1 - cl[..., None] * 0.5) + hexc('#ff9d8a') * cl[..., None] * 0.5
    for i, (b, a, c, n) in enumerate([(hz - 0.075, 0.07, '#7a3f7f', 4), (hz - 0.035, 0.05, '#4a2a66', 5), (hz - 0.008, 0.028, '#241542', 6)]):
        prof = np.minimum(ridge(320 + i * 5, b, a, n, 0.5), hz * H)
        if i == 2:
            prof = np.minimum(trees(prof, 40, 60, 0.012, 0.03), hz * H)
        img = layer(img, prof, hexc(c))
    hy = int(hz * H)
    refl = img[:hy][::-1][: H - hy].copy()
    rows = np.arange(refl.shape[0])
    shift = (np.sin(rows * 0.22) * (1.0 + rows * 0.016) + np.sin(rows * 0.057) * rows * 0.01).astype(int)
    refl = np.stack([np.roll(refl[i], shift[i], axis=0) for i in rows])
    fade = np.linspace(0.80, 0.30, refl.shape[0], dtype=np.float32)[:, None, None]
    img[hy:hy + refl.shape[0]] = refl * fade + hexc('#0d0b2b') * (1 - fade)
    rip = np.clip(fbm(330, 2, 3)[hy:] * 1.6 - 0.75, 0, 1) * (np.sin(yy[hy:] * 0.9) * 0.5 + 0.5)
    img[hy:] = screen(img[hy:], rip[..., None] * 0.20)
    return grain(vignette(img, 0.28), 11)


SCENES = dict(galaxy=galaxy, aurora=aurora, sunset=sunset, ocean=ocean, forest=forest,
              sakura=sakura, desert=desert, snow=snow, neon=neon, classic=classic, auth=auth)

if __name__ == '__main__':
    out = sys.argv[1]
    names = sys.argv[2:] or list(SCENES)
    for name in names:
        save(SCENES[name](), f'{out}/{name}.jpg')
