"""Generates the VeriTrace launcher icon (shield + check, neutral colors).
Run: python tool/generate_icon.py  then  dart run flutter_launcher_icons"""
from PIL import Image, ImageDraw

SIZE = 1024
BG = (236, 239, 241, 255)       # blue-grey 50
SHIELD = (55, 71, 79, 255)      # blue-grey 800
CHECK = (255, 255, 255, 255)


def shield_points(cx, cy, w, h):
    top, bottom = cy - h / 2, cy + h / 2
    left, right = cx - w / 2, cx + w / 2
    return [
        (cx, top), (right, top + h * 0.16), (right, cy + h * 0.02),
        (cx + w * 0.36, cy + h * 0.30), (cx, bottom),
        (cx - w * 0.36, cy + h * 0.30), (left, cy + h * 0.02), (left, top + h * 0.16),
    ]


def draw(scale, background):
    img = Image.new("RGBA", (SIZE * 2, SIZE * 2), background)  # 2x supersampling
    d = ImageDraw.Draw(img)
    c = SIZE
    w, h = SIZE * 2 * 0.56 * scale, SIZE * 2 * 0.66 * scale
    d.polygon(shield_points(c, c, w, h), fill=SHIELD)
    stroke = int(w * 0.11)
    pts = [(c - w * 0.22, c + h * 0.01), (c - w * 0.05, c + h * 0.16), (c + w * 0.25, c - h * 0.15)]
    d.line(pts, fill=CHECK, width=stroke, joint="curve")
    for x, y in (pts[0], pts[2]):
        d.ellipse([x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2], fill=CHECK)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


draw(1.0, BG).save("assets/icon/icon.png")
draw(0.72, (0, 0, 0, 0)).save("assets/icon/icon_foreground.png")
print("wrote assets/icon/icon.png and assets/icon/icon_foreground.png")
