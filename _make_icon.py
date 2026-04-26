"""
Generates a 256x256 mod icon for FS25_GlobalSuspensionTuner.

Run once with the mod folder as the working directory:
    python _make_icon.py
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math

W = H = 256
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# --- Background: vertical gradient, dark blue-green to deeper green ---
top    = (24,  56,  46)
bottom = (12,  92,  56)
for y in range(H):
    t = y / (H - 1)
    r = int(top[0] * (1 - t) + bottom[0] * t)
    g = int(top[1] * (1 - t) + bottom[1] * t)
    b = int(top[2] * (1 - t) + bottom[2] * t)
    draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

# Soft vignette ring
overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
od = ImageDraw.Draw(overlay)
od.ellipse((-60, -60, W + 60, H + 60), outline=(0, 0, 0, 0), width=0)
for i in range(40):
    a = int(120 * (i / 40) ** 2)
    od.ellipse((-i, -i, W + i, H + i), outline=(0, 0, 0, a))
img = Image.alpha_composite(img, overlay)
draw = ImageDraw.Draw(img)

# --- Top plate: cab silhouette suggestion ---
PLATE = (220, 220, 220, 255)
draw.rounded_rectangle((40, 30, 216, 70), radius=8, fill=PLATE)
draw.rounded_rectangle((48, 38, 208, 62), radius=4, fill=(60, 90, 80, 255))

# --- Bottom plate: chassis ---
draw.rounded_rectangle((40, 186, 216, 226), radius=8, fill=PLATE)

# Two wheels under the chassis
WHEEL_OUT = (30, 30, 30, 255)
WHEEL_HUB = (200, 200, 200, 255)
for cx in (78, 178):
    draw.ellipse((cx - 22, 210, cx + 22, 254), fill=WHEEL_OUT)
    draw.ellipse((cx - 8,  224, cx + 8,  240), fill=WHEEL_HUB)

# --- Coil spring connecting cab and chassis ---
# Sinusoidal pair of lines forming a stylized coil between y=70 and y=186
SPRING_TOP = 72
SPRING_BOT = 184
TURNS = 7
AMP = 28
CX = W // 2

spring_color = (255, 220, 110, 255)
shadow = (0, 0, 0, 110)

# Draw shadow first
for offset in range(2):
    pts_l = []
    pts_r = []
    for i in range(0, 401):
        t = i / 400
        y = SPRING_TOP + (SPRING_BOT - SPRING_TOP) * t + offset * 2
        phase = t * TURNS * 2 * math.pi
        x = CX + math.sin(phase) * AMP
        # Build two strands by phase shift
        y2 = y + math.cos(phase) * 2
        pts_l.append((x, y2))
    if offset == 0:
        draw.line(pts_l, fill=shadow, width=8, joint="curve")

# Main coil (single sinusoidal stroke gives a clean spring look)
pts = []
for i in range(0, 401):
    t = i / 400
    y = SPRING_TOP + (SPRING_BOT - SPRING_TOP) * t
    phase = t * TURNS * 2 * math.pi
    x = CX + math.sin(phase) * AMP
    pts.append((x, y))
draw.line(pts, fill=spring_color, width=7, joint="curve")

# Highlight stroke (thinner, lighter)
hi_color = (255, 245, 200, 255)
draw.line(pts, fill=hi_color, width=2, joint="curve")

# --- Mounting bolts on plates ---
BOLT = (90, 90, 90, 255)
for (x, y) in [(56, 50), (200, 50), (56, 206), (200, 206)]:
    draw.ellipse((x - 4, y - 4, x + 4, y + 4), fill=BOLT)

# --- Slight blur for smoother look, then resharpen edges ---
img = img.filter(ImageFilter.SMOOTH)

# --- Save PNG (FS25 accepts PNG icons) ---
out_png = "icon.png"
img.save(out_png, "PNG")
print(f"wrote {out_png} ({W}x{H})")
