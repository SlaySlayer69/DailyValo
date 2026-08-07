"""Regenerates DailyValo's launcher icon at every density.

    python3 tool/generate_app_icon.py
    cp -r mipmap-* ../android/app/src/main/res/   # from the output directory

Writes, per density: the adaptive background/foreground/monochrome layers, and
legacy square + round PNGs for API 24-25 (below adaptive icon support). Also
writes preview.png so the result can be eyeballed before it is installed.

Requires Pillow.
"""
import os, math
from PIL import Image, ImageDraw, ImageFilter

RED       = (255, 70, 85)     # AppColors.accent
RED_DEEP  = (198, 45, 60)
INK       = (11, 12, 15)      # AppColors.background
GREY      = (32, 36, 43)      # lifted centre so the ground is not flat black

S = 1024                      # master size; everything scales from here

def ground(size):
    """Dark radial ground: grey centre falling to near-black at the edges."""
    img = Image.new("RGB", (size, size), INK)
    px = img.load()
    c, r = size / 2, size * 0.72
    for y in range(size):
        for x in range(size):
            d = min(1.0, math.hypot(x - c, y - c) / r)
            t = (1 - d) ** 2.1
            px[x, y] = tuple(int(INK[i] + (GREY[i] - INK[i]) * t) for i in range(3))
    return img

GREY_FACE = (140, 149, 163)   # the receding plane
FOLD      = (22, 12, 16)      # where the two planes cross

def monogram(size):
    """A D/V monogram built like the Flutter mark: flat geometric planes with a
    dark facet where they fold across each other.

    Three planes, three colours — grey D behind, red V in front, near-black
    where they cross. No curves and no outlines; the letterforms are chamfered
    at 45 degrees so they stay crisp when a launcher scales them to 48px.

    Geometry is constrained to a 48x44 box centred in the 108 grid, which keeps
    every corner inside the 66dp keyline circle. Overshooting that is why the
    first attempt had its V sliced off by round and squircle masks.
    """
    u = size / 108.0

    def poly(points):
        return [(x * u, y * u) for x, y in points]

    # --- D: chamfered outer form with the counter punched out -------------
    d_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dd = ImageDraw.Draw(d_layer)
    dd.polygon(poly([(30, 32), (46, 32), (54, 40), (54, 68), (46, 76),
                     (30, 76)]), fill=GREY_FACE)
    # The counter has to be cleared, not drawn in the background colour: the
    # adaptive background shows through it, and it must survive theming.
    dd.polygon(poly([(38, 40), (44, 40), (47, 43), (47, 65), (44, 68),
                     (38, 68)]), fill=(0, 0, 0, 0))

    # --- V: one chevron, apex on the D's baseline -------------------------
    v_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(v_layer).polygon(
        poly([(50, 32), (58, 32), (64, 56), (70, 32), (78, 32), (64, 76)]),
        fill=RED)

    from PIL import ImageChops
    overlap = ImageChops.multiply(
        d_layer.getchannel("A"), v_layer.getchannel("A"),
    ).point(lambda a: 255 if a > 8 else 0)

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(d_layer)
    out.alpha_composite(v_layer)
    out.paste(Image.new("RGBA", (size, size), FOLD + (255,)), (0, 0), overlap)
    return out

def rounded_mask(size, radius_ratio):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    return m

def circle_mask(size):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse([0, 0, size - 1, size - 1], fill=255)
    return m

# Masters
bg_master = ground(S)
fg_master = monogram(S)

# Legacy icon: adaptive layers composited, then cropped to the 72/108 viewport
# so the glyph is not left swimming in space on pre-26 launchers.
crop = int(S * (72 / 108) / 2)
flat = bg_master.convert("RGBA")
flat.alpha_composite(fg_master)
flat = flat.crop((S // 2 - crop, S // 2 - crop, S // 2 + crop, S // 2 + crop))

OUT = os.path.dirname(os.path.abspath(__file__))
DENS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

for name, scale in DENS.items():
    d = os.path.join(OUT, "mipmap-" + name)
    os.makedirs(d, exist_ok=True)

    legacy = int(48 * scale)
    sq = flat.resize((legacy, legacy), Image.LANCZOS)
    sq.putalpha(rounded_mask(legacy, 0.22))
    sq.save(os.path.join(d, "ic_launcher.png"))

    rd = flat.resize((legacy, legacy), Image.LANCZOS)
    rd.putalpha(circle_mask(legacy))
    rd.save(os.path.join(d, "ic_launcher_round.png"))

    adaptive = int(108 * scale)
    bg_master.resize((adaptive, adaptive), Image.LANCZOS).save(
        os.path.join(d, "ic_launcher_background.png"))
    fg_master.resize((adaptive, adaptive), Image.LANCZOS).save(
        os.path.join(d, "ic_launcher_foreground.png"))

# Preview sheet so the result can actually be looked at before shipping.
prev = Image.new("RGB", (760, 260), (24, 24, 28))
big = flat.resize((192, 192), Image.LANCZOS); big.putalpha(rounded_mask(192, 0.22))
prev.paste(big, (30, 34), big)
rnd = flat.resize((192, 192), Image.LANCZOS); rnd.putalpha(circle_mask(192))
prev.paste(rnd, (250, 34), rnd)
for i, px in enumerate((96, 72, 48)):
    t = flat.resize((px, px), Image.LANCZOS); t.putalpha(rounded_mask(px, 0.22))
    prev.paste(t, (470 + (i * 100 if i else 0), 34 + (96 - px) // 2), t)
prev.save(os.path.join(OUT, "preview.png"))
print("generated")
