# -*- coding: utf-8 -*-
"""تصنيف كل أصول الرسم: طبي (على لوحة tokens) مقابل ألماني (لوحة قديمة).
التصنيف قائم على مسافة RGB إلى لوحتين مرجعيتين — لا حدس."""
import os, re, glob
from collections import Counter
from PIL import Image

BASE = r"D:\medicineApp\medicine_app"

# لوحة الألمانية القديمة (من style_bible + ملفات SVG المتبقية)
GERMAN = ["#10B981","#2563EB","#38BDF8","#F59E0B","#FDE047","#0F172A",
          "#1E293B","#334155","#D4AF37","#AA7C11","#F3C65E","#EF4444",
          "#050B14","#0A1628","#14243E","#121929","#1A2336","#FFFFFF"]
# لوحة التطبيق الطبي (tokens.dart) + خلفية الصور الطبية
MEDICAL = ["#1B3C6E","#1B3B6F","#3E6DB5","#E8A33D","#F0B45A","#E14B4B",
           "#1E96C8","#C77F1E","#5F9E3E","#8B5CC9","#B33939","#F28436",
           "#1FA8A0","#4A67C4","#D4568D","#F6F8FB","#17202E","#F7F0E2",
           "#0F1520","#1A2332","#EAF0F8","#EEF2F7"]

def h2r(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def d(a, b):
    return sum((x-y)**2 for x, y in zip(a, b)) ** 0.5

def nearest(c, pal):
    return min(d(h2r(c), h2r(p)) for p in pal)

def png_dominant(path, n=6):
    im = Image.open(path).convert("RGB")
    q = im.quantize(colors=n, method=Image.MEDIANCUT)
    pal = q.getpalette()
    cnt = Counter(q.getdata())
    total = im.size[0] * im.size[1]
    out = []
    for idx, c in cnt.most_common(n):
        r, g, b = pal[idx*3:idx*3+3]
        out.append((f"#{r:02X}{g:02X}{b:02X}", c / total))
    return out, im.size

def verdict(colors):
    """يصنّف بالتصويت الموزون: أي لوحة أقرب لمجموع البكسلات."""
    g = sum(w * nearest(c, GERMAN) for c, w in colors)
    m = sum(w * nearest(c, MEDICAL) for c, w in colors)
    return ("GERMAN" if g < m else "medical"), g, m

def svg_hexes(path):
    txt = open(path, encoding="utf-8", errors="ignore").read()
    return sorted(set(re.findall(r"#[0-9A-Fa-f]{6}", txt))), txt

print("=" * 74)
print(" أ) ملفات PNG — تصنيف كل مجموعة")
print("=" * 74)
groups = ["illustrations/units","illustrations/badges","illustrations/empty",
          "illustrations/levels","illustrations/misc","illustrations/onboarding",
          "brand/icon","brand/final","brand/logo/rejected_round1","icon"]
for g in groups:
    files = sorted(glob.glob(os.path.join(BASE, "assets", g, "*.png")))
    if not files:
        print(f"\n-- {g}: (لا ملفات)")
        continue
    print(f"\n-- {g}  ({len(files)} ملف)")
    for f in files:
        cols, size = png_dominant(f)
        v, gs, ms = verdict(cols)
        tag = "🔴 ألماني" if v == "GERMAN" else "🟢 طبي   "
        top = " ".join(c for c, _ in cols[:3])
        print(f"   {tag} {os.path.basename(f):34s} {size[0]}x{size[1]}  {top}")

print("\n" + "=" * 74)
print(" ب) ملفات SVG — هل تحمل ألوان الألمانية القديمة؟")
print("=" * 74)
svgs = sorted(glob.glob(os.path.join(BASE, "assets", "**", "*.svg"), recursive=True))
for f in svgs:
    hexes, txt = svg_hexes(f)
    hits = [h for h in hexes if nearest(h, GERMAN) < nearest(h, MEDICAL)]
    rel = os.path.relpath(f, os.path.join(BASE, "assets"))
    mark = "🔴" if hits else "🟢"
    print(f"   {mark} {rel:52s} {','.join(hits[:5])}")
    for word in ("German", "Deutsch", "chevron", "Chevron", "Eagle", "Letter D"):
        if word in txt:
            print(f"        ⚠ نص ألماني: «{word}»")