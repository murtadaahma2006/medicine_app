# -*- coding: utf-8 -*-
"""تحويل مفاهيم SVG إلى PNG + رسم واجهات الويدجت (فاتح/داكن) بدقة البكسل.
كل الألوان من tokens.dart الحقيقي للتطبيق."""
import os, math
import arabic_reshaper
from bidi.algorithm import get_display
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE = r"D:\medicineApp\medicine_app"
OUT = os.path.join(BASE, ".zcode_showcase", "concepts")
CAIRO_BOLD = os.path.join(BASE, "assets", "fonts", "Cairo-Regular.ttf")
CAIRO = os.path.join(BASE, "assets", "fonts", "Cairo-Regular.ttf")

def ar(text):
    """تهيئة النص العربي للرسم (reshaping + bidi)."""
    return get_display(arabic_reshaper.reshape(text))

# ── tokens من tokens.dart ──
LIGHT = dict(
    bg="#F6F8FB", surface="#FFFFFF", surface_alt="#EEF2F7",
    text="#17202E", text2="#5B6879", border="#E3E9F0",
    primary="#1B3C6E", accent="#1B3C6E", pearl_bg="#FBF4DE",
    due_normal="#1B3C6E", due_high="#D64545", gold="#E8A33D",
)
DARK = dict(
    bg="#0F1520", surface="#1A2332", surface_alt="#232E42",
    text="#EAF0F8", text2="#9AA7B8", border="#2C3A50",
    primary="#3E6DB5", accent="#81B4FA", pearl_bg="#33291A",
    due_normal="#81B4FA", due_high="#E46B6B", gold="#F0B45A",
)

# ═══ 1) تحويل SVG إلى PNG — عبر rsvg غير متوفر، نستخدم cairosvg؟ غير مثبت.
#    الحل: نرسم المفاهيم مباشرة بدقة 1024 بـ PIL (نفس الأشكال، بدون تبعيات خارجية).
# ═══

def rr(d, box, r, **kw):
    d.rounded_rectangle(box, radius=r, **kw)

# ── المفهوم 1: درع + قلب + نبض ──
def draw_concept1(size=1024):
    S = size / 512
    img = Image.new("RGB", (size, size), "#1B3C6E")
    # تدرج خلفية
    grad = Image.new("RGB", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        r = int(0x1B + (0x14 - 0x1B) * t)
        g = int(0x3C + (0x2C - 0x3C) * t)
        b = int(0x6E + (0x53 - 0x6E) * t)
        gd.line([(0, y), (size, y)], fill=(r, g, b))
    img = grad
    d = ImageDraw.Draw(img, "RGBA")
    # قناع زوايا مستديرة
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size, size], radius=int(120 * S), fill=255)
    img = Image.composite(img, Image.new("RGB", (size, size), "#F6F8FB"), mask)
    d = ImageDraw.Draw(img, "RGBA")

    # درع
    def shield_path(cx, cy, w, h):
        pts = []
        for i in range(200):
            a = i / 199 * math.pi
            x = cx + w * math.sin(a)
            y = cy - h * math.cos(a) * 0.98
            pts.append((x, y))
        return pts
    # رسم درع مبسط: نصف قوس علوي + انثناء لأسفل
    def draw_shield(d, S):
        cx, top, w, h = 256 * S, 100 * S, 145 * S, 340 * S
        pts = [(cx - w, top + 55 * S)]
        for i in range(60):  # قوس علوي
            a = math.pi - i / 59 * math.pi
            pts.append((cx + w * math.cos(a), top + 55 * S + w * 0.55 * math.sin(a) * -1 + 55 * S * 0 + 55 * S))
        # تبسيط: نستخدم مضلع درع كلاسيكي
        pts = [
            (cx, 96 * S), (cx + w, 156 * S), (cx + w, 300 * S),
            (cx, 448 * S), (cx - w, 300 * S), (cx - w, 156 * S)
        ]
        # إدخال انحناءات عبر نقاط وسطية
        pts2 = [(cx, 96 * S)]
        for i in range(1, 5):
            # قوس علوي من 96 إلى الجانب
            pass
        d.polygon(pts, fill=(233, 240, 250, 14), outline=(233, 240, 250, 64), width=max(2, int(3 * S)))
    draw_shield(d, S)

    # قلب منحنى — نرسمه بقوسين بيزييه يدوياً (تقريب بمقاطع)
    def bezier(p0, p1, p2, p3, n=40):
        pts = []
        for i in range(n + 1):
            t = i / n
            mt = 1 - t
            x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
            y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
            pts.append((x, y))
        return pts

    def draw_heart_outline(d, cx, cy, sc, col, w):
        # قلب من 6 مقاطع بيزييه
        left_lobe = bezier((cx, cy + 130 * sc), (cx - 85 * sc, cy + 55 * sc), (cx - 85 * sc, cy - 45 * sc), (cx - 35 * sc, cy - 72 * sc))
        right_lobe = bezier((cx - 35 * sc, cy - 72 * sc), (cx, cy - 50 * sc), (cx + 35 * sc, cy - 72 * sc), (cx + 85 * sc, cy - 45 * sc))
        bottom = bezier((cx + 85 * sc, cy - 45 * sc), (cx + 85 * sc, cy + 55 * sc), (cx, cy + 130 * sc), (cx, cy + 130 * sc))
        outline = left_lobe + right_lobe + [left_lobe[0]]
        # دمج ناعم
        pts = left_lobe + right_lobe + bottom
        d.line(pts, fill=col, width=w, joint="curve")
        return outline

    gold = (232, 163, 61, 255)
    draw_heart_outline(d, 256 * S, 300 * S, S * 1.0, gold, max(3, int(14 * S)))
    # نبض داخل القلب
    pulse = [(196 * S, 288 * S), (232 * S, 288 * S), (246 * S, 258 * S), (262 * S, 318 * S), (276 * S, 284 * S), (316 * S, 288 * S)]
    d.line(pulse, fill=(233, 240, 250, 255), width=max(2, int(10 * S)), joint="curve")
    # لؤلؤة أسفل
    d.ellipse([246 * S, 414 * S, 266 * S, 434 * S], fill=gold)
    return img

# ── المفهوم 2: كتاب + كبسولة ──
def draw_concept2(size=1024):
    S = size / 512
    grad = Image.new("RGB", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        gd.line([(0, y), (size, y)], fill=(int(0x1B + (0x14 - 0x1B) * t), int(0x3C + (0x2C - 0x3C) * t), int(0x6E + (0x53 - 0x6E) * t)))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size, size], radius=int(120 * S), fill=255)
    img = Image.composite(grad, Image.new("RGB", (size, size), "#F6F8FB"), mask)
    d = ImageDraw.Draw(img, "RGBA")
    cx = 256 * S

    def bezier(p0, p1, p2, p3, n=50):
        pts = []
        for i in range(n + 1):
            t = i / n
            mt = 1 - t
            pts.append((mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0],
                        mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]))
        return pts

    # صفحة يسرى: من الحافة إلى المركز
    left = bezier((cx, 200 * S), (cx - 40 * S, 178 * S), (cx - 80 * S, 172 * S), (cx - 120 * S, 176 * S))
    left2 = bezier((cx - 120 * S, 176 * S), (cx - 100 * S, 240 * S), (cx - 100 * S, 300 * S), (cx - 120 * S, 340 * S))
    spine_l = bezier((cx - 120 * S, 340 * S), (cx - 80 * S, 336 * S), (cx - 40 * S, 345 * S), (cx, 364 * S))
    # صفحة يمنى
    right = bezier((cx, 200 * S), (cx + 40 * S, 178 * S), (cx + 80 * S, 172 * S), (cx + 120 * S, 176 * S))
    right2 = bezier((cx + 120 * S, 176 * S), (cx + 100 * S, 240 * S), (cx + 100 * S, 300 * S), (cx + 120 * S, 340 * S))
    spine_r = bezier((cx + 120 * S, 340 * S), (cx + 80 * S, 336 * S), (cx + 40 * S, 345 * S), (cx, 364 * S))

    book_fill = left + left2 + spine_l + [ (cx, 364*S), (cx, 200*S) ]
    d.polygon(book_fill, fill=(255, 255, 255, 22))
    book_fill_r = right + right2 + spine_r + [(cx, 364 * S), (cx, 200 * S)]
    d.polygon(book_fill_r, fill=(255, 255, 255, 22))
    d.line(left + left2, fill=(233, 240, 250, 90), width=max(2, int(3 * S)))
    d.line(right + right2, fill=(233, 240, 250, 90), width=max(2, int(3 * S)))
    d.line(spine_l, fill=(233, 240, 250, 90), width=max(2, int(3 * S)))
    d.line(spine_r, fill=(233, 240, 250, 90), width=max(2, int(3 * S)))

    # سطور
    for k, (x0, x1, y) in enumerate([(160, 240, 214), (160, 240, 244), (160, 240, 274), (272, 352, 214), (272, 352, 244)]):
        d.line([(x0 * S, y * S), (x1 * S, y * S)], fill=(233, 240, 250, 115), width=max(2, int(6 * S)))

    # كبسولة مائلة
    cap = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cap)
    gold = (232, 163, 61, 255)
    cd.rounded_rectangle([300 * S, 112 * S, 380 * S, 150 * S], radius=19 * S, fill=gold)
    cd.pieslice([300 * S, 112 * S, 338 * S, 150 * S], 90, 270, fill=(255, 255, 255, 72))
    cap = cap.rotate(40, center=(340 * S, 131 * S), resample=Image.BICUBIC)
    img.paste(cap, (0, 0), cap)
    d = ImageDraw.Draw(img, "RGBA")

    # نجمة لؤلؤة
    def star(cx, cy, r, col):
        pts = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            rr_ = r if i % 2 == 0 else r * 0.4
            pts.append((cx + rr_ * math.cos(a), cy + rr_ * math.sin(a)))
        d.polygon(pts, fill=col)
    star(186 * S, 446 * S, 30 * S, gold)
    return img

# ── المفهوم 3: صليب + كوكبة ──
def draw_concept3(size=1024):
    S = size / 512
    grad = Image.new("RGB", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        gd.line([(0, y), (size, y)], fill=(int(0x1B + (0x14 - 0x1B) * t), int(0x3C + (0x2C - 0x3C) * t), int(0x6E + (0x53 - 0x6E) * t)))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size, size], radius=int(120 * S), fill=255)
    img = Image.composite(grad, Image.new("RGB", (size, size), "#F6F8FB"), mask)
    d = ImageDraw.Draw(img, "RGBA")

    # حلقات مدارية
    for rad, alpha in [(176, 26), (146, 36)]:
        d.ellipse([256 * S - rad * S, 256 * S - rad * S, 256 * S + rad * S, 256 * S + rad * S],
                  outline=(233, 240, 250, alpha), width=max(1, int(2 * S)))

    # صليب
    arm = 30 * S
    c = (233, 240, 250, 242)
    cross_pts = [
        (226 * S, 136 * S), (286 * S, 136 * S), (286 * S, 226 * S), (376 * S, 226 * S),
        (376 * S, 286 * S), (286 * S, 286 * S), (286 * S, 376 * S), (226 * S, 376 * S),
        (226 * S, 286 * S), (136 * S, 286 * S), (136 * S, 226 * S), (226 * S, 226 * S)
    ]
    d.polygon(cross_pts, fill=c)
    # مركز ذهبي
    d.ellipse([230 * S, 230 * S, 282 * S, 282 * S], fill=(232, 163, 61, 255))
    d.ellipse([244 * S, 244 * S, 268 * S, 268 * S], fill=(61, 42, 8, 255))

    # كوكبة التخصصات
    modules = [
        (256, 80, "#E14B4B"), (343, 116, "#1E96C8"), (404, 188, "#C77F1E"), (426, 274, "#5F9E3E"),
        (404, 360, "#8B5CC9"), (343, 432, "#B33939"), (256, 468, "#F28436"), (169, 432, "#1FA8A0"),
        (108, 360, "#4A67C4"), (86, 274, "#D4568D"),
    ]
    for x, y, col in modules:
        d.ellipse([(x - 14) * S, (y - 14) * S, (x + 14) * S, (y + 14) * S], fill=col)
    return img

# ═══ 2) واجهات الويدجت — mockups بدقة البكسل ═══

def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def draw_widget(theme, name, scale=2):
    """رسم واجهة الويدجت 4x2 كما في medicine_home_widget.xml — بالأبعاد النسبية."""
    W, H = 320 * scale, 160 * scale  # ويدجت 4x2 تقريباً
    img = Image.new("RGB", (W, H), theme["bg"])
    d = ImageDraw.Draw(img, "RGBA")
    pad = 14 * scale
    rr(d, [4, 4, W - 4, H - 4], 16 * scale, fill=theme["surface"], outline=theme["border"], width=scale)

    f_label = ImageFont.truetype(CAIRO, 12 * scale)
    f_label_b = ImageFont.truetype(CAIRO, 13 * scale)
    f_body = ImageFont.truetype(CAIRO, 12 * scale)
    f_pearl = ImageFont.truetype(CAIRO, 12 * scale)

    x_r = W - pad  # RTL: نبدأ من اليمين
    # ── أهدافي ──
    # أيقونة 📌 نرسمها كمثلث دبوس
    pin_x, pin_y = x_r - 10 * scale, pad + 8 * scale
    d.ellipse([pin_x - 4 * scale, pin_y - 4 * scale, pin_x + 4 * scale, pin_y + 4 * scale], fill=theme["accent"])
    d.line([(pin_x, pin_y + 4 * scale), (pin_x, pin_y + 10 * scale)], fill=theme["accent"], width=scale)
    label = ar("أهدافي")
    d.text((pin_x - 10 * scale - d.textlength(label, f_label_b), pin_y - 6 * scale), label, font=f_label_b, fill=theme["text"])
    # أسطر الأهداف
    goals = ["L4 · URTI — المحاضرة 3: المضادات الحيوية", "L5 · فقر الدم نقص الحديد"]
    y = pad + 24 * scale
    f_goal = ImageFont.truetype(CAIRO, 11 * scale)
    for i, g in enumerate(goals):
        color = theme["due_high"] if i == 0 else theme["due_normal"]
        g_ar = ar(g.split("—")[0].strip())
        d.text((x_r, y), g_ar, font=f_goal, fill=color, anchor="ra")
        y += 16 * scale
    d.text((x_r, y), ar("+ 3 أخرى"), font=f_goal, fill=theme["text2"], anchor="ra")

    # فاصل
    yy = y + 10 * scale
    d.line([(pad, yy), (W - pad, yy)], fill=theme["border"], width=scale)
    yy += 8 * scale

    # ── لؤلؤة اليوم ──
    px = x_r - 10 * scale
    py = yy + 8 * scale
    # أيقونة 💡 كشعلة
    d.ellipse([px - 5 * scale, py - 6 * scale, px + 5 * scale, py + 6 * scale], fill=theme["gold"])
    pearl_label = ar("لؤلؤة اليوم")
    d.text((px - 12 * scale - d.textlength(pearl_label, f_label), py - 6 * scale), pearl_label, font=f_label, fill=theme["text"])
    # صندوق اللؤلؤة
    box_y = yy + 22 * scale
    rr(d, [pad, box_y, W - pad, H - pad], 8 * scale, fill=theme["pearl_bg"])
    pearl_text = ar("أموكسيسيلين هو الخيار الأول في التهاب اللوزت العقدي")
    d.text((W - pad - 6 * scale, box_y + 6 * scale), pearl_text, font=f_pearl, fill=theme["text"])
    return img

# ═══ تنفيذ ═══
os.makedirs(OUT, exist_ok=True)
draw_concept1().save(os.path.join(OUT, "concept1_heart_shield.png"))
draw_concept2().save(os.path.join(OUT, "concept2_capsule_book.png"))
draw_concept3().save(os.path.join(OUT, "concept3_specialty_constellation.png"))
draw_widget(LIGHT, "widget_light").save(os.path.join(OUT, "widget_light.png"))
draw_widget(DARK, "widget_dark").save(os.path.join(OUT, "widget_dark.png"))
print("DONE:", os.listdir(OUT))
