#!/usr/bin/env python3
"""Рисует карту реки (вид сверху) из build/map.json → docs/img/map.png. Нужен Pillow."""
import json, sys
from PIL import Image, ImageDraw

src = sys.argv[1] if len(sys.argv) > 1 else "build/map.json"
dst = sys.argv[2] if len(sys.argv) > 2 else "build/map.png"
d = json.load(open(src))

xs = [b["lx"] for b in d["banks"]] + [b["rx"] for b in d["banks"]]
zs = [b["lz"] for b in d["banks"]] + [b["rz"] for b in d["banks"]]
pad = 90
minX, maxX, minZ, maxZ = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad
S = 1400 / (maxX - minX)
W, H = int((maxX - minX) * S), int((maxZ - minZ) * S)
img = Image.new("RGB", (W, H), (88, 128, 70))
dr = ImageDraw.Draw(img)


def P(x, z):
    return ((x - minX) * S, (z - minZ) * S)


# русло: четырёхугольники между соседними сечениями
banks = d["banks"]
for a, b in zip(banks, banks[1:]):
    poly = [P(a["lx"], a["lz"]), P(a["rx"], a["rz"]), P(b["rx"], b["rz"]), P(b["lx"], b["lz"])]
    dr.polygon(poly, fill=(52, 120, 150))
dr.line([P(p["x"], p["z"]) for p in d["path"]], fill=(255, 240, 200), width=2)
for r in d["rocks"]:
    x, y = P(r["x"], r["z"]); rr = max(2, r["r"] * S)
    dr.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(110, 108, 104), outline=(230, 240, 245))
for c in d["coins"]:
    x, y = P(c["x"], c["z"]); rr = 3 if c["gold"] else 1.6
    dr.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(255, 200, 40))
for g in d["gates"]:
    a, b = P(g["ax"], g["az"]), P(g["bx"], g["bz"])
    dr.line([a, b], fill=(255, 90, 60), width=2)
wp = d.get("whirlpool")
if wp:
    x, y = P(wp["x"], wp["z"]); rr = wp["r"] * S
    for k in (1.0, 0.66, 0.33):
        dr.ellipse([x - rr * k, y - rr * k, x + rr * k, y + rr * k], outline=(230, 245, 255), width=1)
dr.line([P(d["drop"]["a"]["x"], d["drop"]["a"]["z"]), P(d["drop"]["b"]["x"], d["drop"]["b"]["z"])], fill=(255, 255, 255), width=4)
dr.line([P(d["finish"]["a"]["x"], d["finish"]["a"]["z"]), P(d["finish"]["b"]["x"], d["finish"]["b"]["z"])], fill=(80, 230, 120), width=4)
x, y = P(d["dock"]["x"], d["dock"]["z"])
dr.rectangle([x - 5, y - 4, x + 5, y + 4], fill=(170, 120, 70))
for s in d["sections"]:
    x, y = P(s["x"], s["z"])
    dr.text((x - 20, y), s["id"].upper(), fill=(255, 255, 255))
img.save(dst)
print("saved", dst, img.size)
