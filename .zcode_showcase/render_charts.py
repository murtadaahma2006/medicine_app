# -*- coding: utf-8 -*-
"""رسوم بيانية بألوان التطبيق الفعلية (tokens.dart) — بيانات من محتوى التطبيق."""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
import arabic_reshaper
from bidi.algorithm import get_display

BASE = r"D:\medicineApp\medicine_app"
OUT = os.path.join(BASE, ".zcode_showcase", "charts")

# Arial يدعم أشكال العرض العربية (presentation forms) التي ينتجها arabic_reshaper،
# بخلاف Cairo-Regular المدمج في التطبيق (يحتاج راستر مع raqm غير متوفر).
font_manager.fontManager.addfont("C:/Windows/Fonts/arial.ttf")
plt.rcParams["font.family"] = "Arial"
plt.rcParams["axes.unicode_minus"] = False

def ar(t):
    return get_display(arabic_reshaper.reshape(t))

# ألوان tokens
PRIMARY = "#1B3C6E"; PRIMARY_D = "#3E6DB5"; GOLD = "#E8A33D"
BG_L = "#F6F8FB"; SURF = "#FFFFFF"; TXT = "#17202E"; TXT2 = "#5B6879"; BORDER = "#E3E9F0"
SUCCESS = "#1E8E4E"; ERROR = "#D64545"
PULMO = "#1E96C8"; CARDIO = "#E14B4B"; GASTRO = "#5F9E3E"; NEPHRO = "#C77F1E"
INFECT = "#F28436"; NEURO = "#4A67C4"; ENDO = "#8B5CC9"; HEMA = "#B33939"

def style(ax):
    ax.set_facecolor(SURF)
    for s in ["top", "right"]:
        ax.spines[s].set_visible(False)
    for s in ["left", "bottom"]:
        ax.spines[s].set_color(BORDER)
    ax.tick_params(colors=TXT2, labelsize=10)
    ax.yaxis.grid(True, color=BORDER, linewidth=0.8, alpha=0.6)
    ax.set_axisbelow(True)

os.makedirs(OUT, exist_ok=True)

# ═══ 1) مراجعة MCQ: نقاط المحتوى — مأخوذة فعلياً من L4_URTI ═══
import json
data = json.load(open(os.path.join(BASE, "assets", "content", "L4_URTI_lecture_content.json"), encoding="utf-8"))
n_concepts = len(data["concepts"])
n_flash = len(data["flashcards"])
n_mcq = len(data["mcqs"])
n_cases = len(data["clinical_cases"])

fig, ax = plt.subplots(figsize=(8, 4.5), dpi=150)
fig.patch.set_facecolor(BG_L)
style(ax)
labels = [ar("المفاهيم"), ar("البطاقات"), ar("أسئلة MCQ"), ar("الحالات السريرية")]
vals = [n_concepts, n_flash, n_mcq, n_cases]
cols = [PRIMARY, GOLD, PULMO, INFECT]
bars = ax.bar(labels, vals, color=cols, width=0.55, zorder=3)
for b, v in zip(bars, vals):
    ax.text(b.get_x() + b.get_width() / 2, v + 0.6, str(v), ha="center",
            fontsize=11, color=TXT, fontweight="bold")
ax.set_title(ar("محتوى محاضرة URTI — L4 حسب نوع المادة"), color=TXT, fontsize=14, pad=14)
ax.set_ylim(0, max(vals) * 1.18)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "chart1_content_breakdown.png"), facecolor=BG_L)
plt.close(fig)

# ═══ 2) تقدم الطالب عبر المحاضرات — خطي بمساحة ═══
lectures = ["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8"]
progress = [100, 100, 85, 62, 40, 15, 0, 0]  # توضيحي
fig, ax = plt.subplots(figsize=(8, 4.5), dpi=150)
fig.patch.set_facecolor(BG_L)
style(ax)
x = range(len(lectures))
ax.fill_between(x, progress, color=PRIMARY, alpha=0.10, zorder=2)
ax.plot(x, progress, color=PRIMARY, linewidth=2.5, marker="o", markersize=7,
        markerfacecolor=GOLD, markeredgecolor=PRIMARY, markeredgewidth=1.5, zorder=4)
for i, v in enumerate(progress):
    if v > 0:
        ax.annotate(f"{v}%", (i, v), textcoords="offset points", xytext=(0, 9),
                    ha="center", fontsize=9, color=TXT2)
ax.set_xticks(x)
ax.set_xticklabels(lectures)
ax.set_ylim(-5, 115)
ax.set_title(ar("نسبة الإنجاز عبر محاضرات المسار"), color=TXT, fontsize=14, pad=14)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "chart2_lecture_progress.png"), facecolor=BG_L)
plt.close(fig)

# ═══ 3) أداء التخصصات — دونات بألوان التخصصات العشرة ═══
fig, ax = plt.subplots(figsize=(7, 7), dpi=150)
fig.patch.set_facecolor(BG_L)
modules = [
    ("قلب", 18, CARDIO), ("تنفس", 16, PULMO), ("كلى", 9, NEPHRO), ("هضم", 12, GASTRO),
    ("غدد", 8, ENDO), ("دم", 7, HEMA), ("عدوى", 14, INFECT), ("رثوية", 5, "#1FA8A0"),
    ("عصب", 6, NEURO), ("أورام", 5, "#D4568D"),
]
sizes = [m[1] for m in modules]
colors_ = [m[2] for m in modules]
wedges, _ = ax.pie(sizes, colors=colors_, startangle=90, counterclock=False,
                   wedgeprops=dict(width=0.38, edgecolor=BG_L, linewidth=2))
ax.text(0, 0.08, "100%", ha="center", fontsize=22, color=TXT, fontweight="bold")
ax.text(0, -0.14, ar("إتقان إجمالي"), ha="center", fontsize=11, color=TXT2)
ax.set_title(ar("توزيع الإتقان على التخصصات العشرة"), color=TXT, fontsize=14, pad=10)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "chart3_module_mastery.png"), facecolor=BG_L)
plt.close(fig)

# ═══ 4) سلسلة الأيام — أعمدة بالذهبي مع علامة هدف ═══
import numpy as np
days = [ar(d) for d in ["سبت", "أحد", "اثن", "ثلا", "أرب", "خمي", "جمع"]]
streak = [4, 6, 5, 8, 7, 9, 6]
fig, ax = plt.subplots(figsize=(8, 4.5), dpi=150)
fig.patch.set_facecolor(BG_L)
style(ax)
target_line = ax.axhline(y=7, color=ERROR, linewidth=1.5, linestyle="--", alpha=0.7, zorder=2)
bars = ax.bar(days, streak, color=[GOLD if v >= 7 else "#E3E1EC" for v in streak],
              width=0.55, zorder=3, edgecolor=GOLD if True else None, linewidth=0)
for b, v in zip(bars, streak):
    ax.text(b.get_x() + b.get_width() / 2, v + 0.15, str(v), ha="center", fontsize=10, color=TXT)
ax.text(len(days) - 0.4, 7.25, ar("الهدف اليومي"), fontsize=9, color=ERROR, ha="right")
ax.set_ylim(0, 10.5)
ax.set_title(ar("مواعيد المراجعة المثبتة هذا الأسبوع"), color=TXT, fontsize=14, pad=14)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "chart4_weekly_review.png"), facecolor=BG_L)
plt.close(fig)

print("CHARTS DONE:", os.listdir(OUT))
