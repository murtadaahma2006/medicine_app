# -*- coding: utf-8 -*-
"""استخراج لوحة الألوان الفعلية من صور الوحدات الطبية — مرساة الهوية البصرية."""
import os, glob
from collections import Counter
from PIL import Image

BASE = r"D:\medicineApp\medicine_app"
SRC = os.path.join(BASE, "assets", "illustrations", "units")

def quantize(img, n=10):
    q = img.convert("RGB").quantize(colors=n, method=Image.MEDIANCUT)
    pal = q.getpalette()
    counts = Counter(q.getdata())
    out = []
    for idx, cnt in counts.most_common(n):
        r, g, b = pal[idx*3:idx*3+3]
        out.append((f"#{r:02X}{g:02X}{b:02X}", cnt))
    return out

def luminance(hexcol):
    h = hexcol.lstrip("#")
    r, g, b = (int(h[i:i+2], 16)/255 for i in (0, 2, 4))
    def f(c): return c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*f(r) + 0.7152*f(g) + 0.0722*f(b)

files = sorted(glob.glob(os.path.join(SRC, "*.png")))
print(f"عدد الصور: {len(files)}\n")

agg = Counter()
for f in files:
    name = os.path.basename(f)
    img = Image.open(f)
    w, h = img.size
    cols = quantize(img, 8)
    agg.update({c: n for c, n in cols})
    print(f"── {name}  ({w}x{h})")
    for c, n in cols[:6]:
        pct = 100.0 * n / (img.size[0]*img.size[1])
        lum = luminance(c)
        print(f"     {c}   {pct:5.1f}%   L={lum:.3f}")

print("\n══ الألوان الأكثر تكراراً عبر كل الصور ══")
for c, n in agg.most_common(20):
    print(f"   {c}   L={luminance(c):.3f}")