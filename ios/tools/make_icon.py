"""Draws the app icon (1024 x 1024, no transparency): a blocky face on a plain dark ground.
Run: python3 ios/tools/make_icon.py"""
from pathlib import Path
from PIL import Image, ImageDraw

S, B = 1024, 120                      # canvas and block size
BG = (12, 13, 16)
TONES = {
    "H": (52, 38, 31), "h": (70, 51, 41),                                              # hair
    "1": (233, 196, 160), "2": (217, 178, 142), "3": (196, 156, 121), "4": (170, 131, 100),  # skin, light to dark
    "e": (150, 112, 88), "m": (188, 130, 108),                                         # where the eyes and mouth would be
}
FACE = [
    ".HHHH.",
    "hHHHHh",
    "321123",
    "3e11e3",
    "321223",
    "42mm34",
    ".4334.",
]

img = Image.new("RGB", (S, S), BG)
d = ImageDraw.Draw(img)
ox, oy = (S - len(FACE[0]) * B) // 2, (S - len(FACE) * B) // 2
for r, row in enumerate(FACE):
    for c, ch in enumerate(row):
        if ch != ".":
            d.rectangle([ox + c * B, oy + r * B, ox + (c + 1) * B - 1, oy + (r + 1) * B - 1], fill=TONES[ch])

out = Path(__file__).resolve().parents[1] / "Witness" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
img.save(out)
print("wrote", out)
