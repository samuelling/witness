"""Draws the app icon (1024 x 1024, no transparency). Run: python3 ios/tools/make_icon.py"""
import random
from pathlib import Path
from PIL import Image, ImageDraw

S, B = 1024, 64                       # canvas and mosaic block size
img = Image.new("RGB", (S, S), (12, 13, 16))
d = ImageDraw.Draw(img)
random.seed(7)

# backdrop: faint checker, like the app's start screen
for y in range(0, S, 128):
    for x in range(0, S, 128):
        if (x // 128 + y // 128) % 2 == 0:
            d.rectangle([x, y, x + 127, y + 127], fill=(17, 19, 23))

# shoulders
d.ellipse([112, 690, 912, 1400], fill=(30, 33, 40))
d.rectangle([432, 600, 592, 760], fill=(30, 33, 40))

# the mosaic face: blocks whose centres fall inside an oval, in warm tones that darken at the edge
cx, cy, rx, ry = 512, 400, 262, 320
tones = [(214, 176, 141), (201, 162, 126), (176, 138, 105), (163, 124, 91), (141, 106, 78), (124, 92, 67), (229, 196, 164)]
for y in range(0, S, B):
    for x in range(0, S, B):
        px, py = (x + B / 2 - cx) / rx, (y + B / 2 - cy) / ry
        r2 = px * px + py * py
        if r2 > 1.08:
            continue
        c = random.choice(tones)
        k = 1.0 - 0.38 * r2 + random.uniform(-0.06, 0.06)
        if -0.75 < px < 0.75 and -0.42 < py < -0.12:      # the band where the eyes would be: darker, as on TV
            k *= 0.62
        d.rectangle([x, y, x + B - 1, y + B - 1], fill=tuple(max(0, min(255, int(v * k))) for v in c))

# lower third
d.rectangle([96, 800, 128, 928], fill=(200, 40, 30))
d.rectangle([128, 800, 760, 880], fill=(244, 241, 234))
d.rectangle([128, 880, 600, 928], fill=(14, 15, 18))
d.rectangle([160, 828, 560, 852], fill=(17, 17, 17))
d.rectangle([160, 897, 440, 911], fill=(244, 241, 234))

out = Path(__file__).resolve().parents[1] / "Witness" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
img.save(out)
print("wrote", out)
