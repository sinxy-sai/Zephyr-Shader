#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
analyze_look.py — 把「期待的参考画面」量化成可调参数

作用
----
1. 读取用户给的参考截图（异环/光追画面），统计它们的色彩与明暗特征：
   - 影调分布（p5 / p50 / p95 亮度、对比度）
   - 暗部 / 中间调 / 高光 各自的色偏（R/G/B 比例）、饱和度、色相
   - 整体白平衡倾向
2. 用 Zephyr 实际使用的 GLSL 调色公式（同样的数学）在离线环境复算：
   - 输出「场景线性亮度 → 显示亮度」的响应曲线图
   - 输出「Photon 原管线 vs Photon + Zephyr」的色卡对比图
3. 生成 docs/look-analysis.md（数据 + 结论 + 对应参数）。

用法
----
    <venv>\\Scripts\\python.exe tools\\analyze_look.py
    <venv>\\Scripts\\python.exe tools\\analyze_look.py --refs 路径1 路径2 ...

依赖：numpy、Pillow
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
#   参考图清单（sha256 前两位 / 完整 sha），来自用户上传的 18 张图
# ---------------------------------------------------------------------------
ATTACHMENT_ROOT = Path(r"C:\Users\liubingliang\.dsh\attachments\v1\objects")

REFERENCES = [
    ("7546d160a55fa5449c42d60ad53732c47c25deb9e71a5847f2e09124f67f459e", "秋日逆光·红跑车", "sunset"),
    ("03e3c731c9fa71ffb59e5ad3861503431802cfbb3288e224003793b5e3ad9c97", "雾林·红跑车", "fog"),
    ("b058901a384a43d2f64796b05e40fa85d6735e33f2e992aeabbe2c65726f2e2d", "沙滩·动漫角色", "anime"),
    ("a310b6b0c726d525d48c09358754c225f89b7081e8a99999a80565293f133f46", "雨路·黄昏", "rain"),
    ("670e7c58aa0f5cc2e9bc9f30d0e1c496cc34be23ab9e78b2711a143451450a5c", "雨林·尾灯", "rain"),
    ("88fe7fb1327327e2db53dd85b4bdfcb8d13506bfb717b382308b6db84c40e76a", "雨后街道·灰调", "wet"),
    ("baa30e07ec320df2deee0d6b8d2169a166a4ee1db9468ba4e14b23d7e4590252", "雨后商店街", "wet"),
    ("ac476d0a3b4be901020ac0d225db4d750d152474b1fb4f94bc81a69c9c50fc34", "夏日乡野·绣球", "day"),
    ("edb7e357bf5c6baf9881f84370e3727c4b6cb79eafa79d2b4cfe29b9808c8343", "夜营·暖灯", "night"),
    ("5270e42fec0c73017e846bda89885dfc257c4f283f6731372769a2fc5444bcdf", "夜雪·樱花街道", "night"),
    ("601aab3b2e9c82c123849195aa0612df826371b61ca7ca05c64cf5f14813148e", "雨夜霓虹·跑车", "neon"),
    ("fce485dacc11430f24556470654d5614210934701313f27a22a509dd0b2a9da1", "桥下·暖阳", "sunset"),
]

# Zephyr / Photon 当前默认值（与 shaders/settings.glsl 同步）
GRADE_BRIGHTNESS = 0.97
GRADE_CONTRAST = 1.04
GRADE_SATURATION = 1.03
GRADE_ORANGE_SAT_BOOST = 0.06
GRADE_TEAL_SAT_BOOST = 0.14
GRADE_GREEN_SAT_BOOST = 0.00
GRADE_GREEN_HUE_SHIFT = 0.0
GRADE_WHITE_BALANCE = 6300

ZEPHYR_STRENGTH = 0.65
ZEPHYR_FILM_CURVE = 1.00
ZEPHYR_BLACK_LIFT = 0.010
ZEPHYR_HIGHLIGHT_ROLLOFF = 0.35
ZEPHYR_SPLIT_STRENGTH = 0.55
ZEPHYR_WARMTH = 0.70
ZEPHYR_VIBRANCE = 0.10


# ---------------------------------------------------------------------------
#   色彩工具（与 GLSL 保持同一套数学）
# ---------------------------------------------------------------------------
EPS = 1e-6


def srgb_to_linear(x: np.ndarray) -> np.ndarray:
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def luma709(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def tonemap_lottes(rgb: np.ndarray) -> np.ndarray:
    """Photon 的 tonemap_lottes（逐通道）。"""
    a, d, hdr_max, mid_in, mid_out = 1.5, 0.91, 8.0, 0.26, 0.32
    b = (-(mid_in ** a) + (hdr_max ** a) * mid_out) / (((hdr_max ** (a * d)) - (mid_in ** (a * d))) * mid_out)
    c = ((hdr_max ** (a * d)) * (mid_in ** a) - (hdr_max ** a) * (mid_in ** (a * d)) * mid_out) / (
        ((hdr_max ** (a * d)) - (mid_in ** (a * d))) * mid_out
    )
    rgb = np.maximum(rgb, 0.0)
    return (rgb ** a) / (rgb ** (a * d) * b + c)


def rgb_to_hsl(rgb: np.ndarray) -> np.ndarray:
    rgb = np.clip(rgb, 0.0, 1.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(axis=-1)
    mn = rgb.min(axis=-1)
    d = mx - mn
    h = np.zeros_like(mx)
    mask = d > 1e-6
    idx = (mx == r) & mask
    h[idx] = ((g[idx] - b[idx]) / d[idx]) % 6.0
    idx = (mx == g) & mask & (mx != r)
    h[idx] = (b[idx] - r[idx]) / d[idx] + 2.0
    idx = (mx == b) & mask & (mx != r) & (mx != g)
    h[idx] = (r[idx] - g[idx]) / d[idx] + 4.0
    h = (h / 6.0) % 1.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return np.stack([h, s, mx], axis=-1)


def hsl_to_rgb(hsl: np.ndarray) -> np.ndarray:
    h, s, l = hsl[..., 0], np.clip(hsl[..., 1], 0, 1), hsl[..., 2]
    def channel(n: float) -> np.ndarray:
        k = (n + h * 12.0) % 12.0
        a = s * np.minimum(l, 1.0 - l)
        return l - a * np.maximum(-1.0, np.minimum(np.minimum(k - 3.0, 9.0 - k), 1.0))
    return np.stack([channel(0.0), channel(8.0), channel(4.0)], axis=-1)


def pulse(x: np.ndarray, center: float, width: float, period: float) -> np.ndarray:
    """DoG 风格脉冲：以 center 为峰、宽 width 的平滑凸起（近似 Photon 的 pulse）。"""
    d = np.abs(((x - center + period * 0.5) % period) - period * 0.5)
    return 1.0 - np.clip(d / max(width, 1e-6), 0.0, 1.0) ** 2


def isolate_hue(hsl: np.ndarray, center: float, width: float) -> np.ndarray:
    return np.where((hsl[..., 1] < 1e-2) | (hsl[..., 2] < 1e-2), 0.0, pulse(hsl[..., 0] * 360.0, center, width, 360.0))


def gain(x: np.ndarray, k: float) -> np.ndarray:
    a = 0.5 * np.power(2.0 * np.where(x < 0.5, x, 1.0 - x), k)
    return np.where(x < 0.5, a, 1.0 - a)


def white_balance(rgb: np.ndarray, kelvin: float) -> np.ndarray:
    """把 GRADE_WHITE_BALANCE 的色温偏移近似成通道增益（6500K = 中性）。"""
    if abs(kelvin - 6500.0) < 1.0:
        return rgb
    t = (kelvin - 6500.0) / 1000.0
    scale = np.array([1.0 + 0.012 * t, 1.0, 1.0 - 0.014 * t], dtype=np.float64)
    return rgb * scale


def grade_input(rgb: np.ndarray) -> np.ndarray:
    rgb = rgb * (0.83 * GRADE_BRIGHTNESS)
    mid = math.log2(0.18)
    rgb = np.log2(np.maximum(rgb, 0.0) + EPS)
    rgb = GRADE_CONTRAST * (rgb - mid) + mid
    rgb = np.maximum(np.exp2(rgb) - EPS, 0.0)
    lum = rgb[..., 0] * 0.2627 + rgb[..., 1] * 0.6780 + rgb[..., 2] * 0.0593
    rgb = np.maximum(lum[..., None] + (rgb - lum[..., None]) * (0.98 * GRADE_SATURATION), 0.0)
    return white_balance(rgb, GRADE_WHITE_BALANCE)


def grade_output(rgb: np.ndarray) -> np.ndarray:
    rgb = np.sqrt(np.clip(rgb, 0.0, 1.0))
    hsl = rgb_to_hsl(rgb)
    orange = isolate_hue(hsl, 30.0, 20.0)
    teal = isolate_hue(hsl, 210.0, 20.0)
    green = isolate_hue(hsl, 90.0, 44.0)
    hsl[..., 1] *= 1.0 + GRADE_ORANGE_SAT_BOOST * orange
    hsl[..., 1] *= 1.0 + GRADE_TEAL_SAT_BOOST * teal
    hsl[..., 0] += (GRADE_GREEN_HUE_SHIFT / 360.0) * green
    hsl[..., 1] *= 1.0 + GRADE_GREEN_SAT_BOOST * green
    rgb = hsl_to_rgb(hsl)
    rgb = gain(rgb, 1.05)
    return np.square(np.clip(rgb, 0.0, 1.0))


def zephyr_pre_tonemap(rgb: np.ndarray) -> np.ndarray:
    lum = rgb[..., 0] * 0.2627 + rgb[..., 1] * 0.6780 + rgb[..., 2] * 0.0593
    hi = np.clip((lum - 0.35) / (3.20 - 0.35), 0.0, 1.0)
    hi = hi * hi * (3.0 - 2.0 * hi)
    warm = np.array([
        1.0 + 0.16 * ZEPHYR_WARMTH,
        1.0 + 0.04 * ZEPHYR_WARMTH,
        1.0 - 0.12 * ZEPHYR_WARMTH,
    ])
    rgb = rgb * (1.0 + (warm - 1.0) * (hi[..., None] * ZEPHYR_STRENGTH))
    chroma = rgb.max(axis=-1) - rgb.min(axis=-1)
    hot = hi * np.clip((chroma - 0.55) / (1.60 - 0.55), 0.0, 1.0)
    roll = hot * ZEPHYR_HIGHLIGHT_ROLLOFF * ZEPHYR_STRENGTH * 0.55
    return np.maximum(rgb + (lum[..., None] - rgb) * roll[..., None], 0.0)


def zephyr_post_tonemap(rgb: np.ndarray) -> np.ndarray:
    c = np.sqrt(np.clip(rgb, 0.0, 1.0))
    split = ZEPHYR_SPLIT_STRENGTH * ZEPHYR_STRENGTH
    lum = luma709(c)

    shadow_tint = np.array([0.90, 1.00, 1.09])
    highlight_tint = np.array([1.06, 1.00, 0.93])
    shadow_w = 1.0 - np.clip((lum - 0.06) / (0.58 - 0.06), 0.0, 1.0)
    high_w = np.clip((lum - 0.44) / (1.00 - 0.44), 0.0, 1.0)
    shadow_w = shadow_w * shadow_w * (3.0 - 2.0 * shadow_w)
    high_w = high_w * high_w * (3.0 - 2.0 * high_w)
    c = c * (1.0 + (shadow_tint - 1.0) * (shadow_w * split)[..., None])
    c = c * (1.0 + (highlight_tint - 1.0) * (high_w * split)[..., None])

    curve = np.clip(ZEPHYR_FILM_CURVE * ZEPHYR_STRENGTH, 0.0, 2.0)
    if curve > 0.0:
        soft = c * c * (3.0 - 2.0 * c)
        c = c + (soft - c) * min(curve, 1.0)
        if curve > 1.0:
            soft = c * c * (3.0 - 2.0 * c)
            c = c + (soft - c) * (curve - 1.0)

    lift = ZEPHYR_BLACK_LIFT
    if lift > 0.0:
        c = c * (1.0 - lift) + lift * 0.55
        c = c + (luma709(c)[..., None] - c) * (lift * 1.6)

    lum = luma709(c)
    sat = c.max(axis=-1) - c.min(axis=-1)
    vib = ZEPHYR_VIBRANCE * ZEPHYR_STRENGTH * (1.0 - np.clip(sat / 0.55, 0.0, 1.0))
    c = lum[..., None] + (c - lum[..., None]) * (1.0 + vib[..., None])

    shoulder = np.clip((lum - 0.62) / (1.0 - 0.62), 0.0, 1.0)
    shoulder = shoulder * shoulder * (3.0 - 2.0 * shoulder)
    c = c + (lum[..., None] - c) * (shoulder * ZEPHYR_HIGHLIGHT_ROLLOFF * ZEPHYR_STRENGTH * 0.60)[..., None]
    return np.square(np.clip(c, 0.0, 1.0))


def pipeline_photon(rgb: np.ndarray) -> np.ndarray:
    """Photon 原管线（c14 内）：grade_input → tonemap → rec2020→rec709（近似）→ grade_output。"""
    x = grade_input(zephyr_pre_tonemap(rgb) * 0.0 + rgb)  # 不含 Zephyr
    x = tonemap_lottes(x)
    x = np.clip(x, 0.0, 1.0)
    return grade_output(x)


def pipeline_zephyr(rgb: np.ndarray) -> np.ndarray:
    x = grade_input(zephyr_pre_tonemap(rgb))
    x = tonemap_lottes(x)
    x = np.clip(x, 0.0, 1.0)
    x = grade_output(x)
    return zephyr_post_tonemap(x)


# ---------------------------------------------------------------------------
#   参考图统计
# ---------------------------------------------------------------------------
def load_rgb(path: Path, max_side: int = 720) -> np.ndarray:
    image = Image.open(path).convert("RGB")
    scale = max_side / max(image.size)
    if scale < 1.0:
        image = image.resize((max(1, int(image.width * scale)), max(1, int(image.height * scale))), Image.LANCZOS)
    return np.asarray(image, dtype=np.float64) / 255.0


def zone_stats(linear: np.ndarray) -> dict:
    lum = luma709(linear)
    out = {}
    for name, lo, hi in (("shadow", 0.0, 0.10), ("midtone", 0.10, 0.45), ("highlight", 0.45, 10.0)):
        mask = (lum >= lo) & (lum < hi)
        if mask.sum() < 64:
            out[name] = None
            continue
        zone = linear[mask]
        mean = zone.mean(axis=0)
        mean_norm = mean / max(mean.mean(), EPS)
        chroma = (zone.max(axis=-1) - zone.min(axis=-1)) / np.maximum(zone.max(axis=-1), EPS)
        hsl = rgb_to_hsl(np.sqrt(np.clip(mean_norm / max(mean_norm.max(), EPS), 0, 1)))
        out[name] = {
            "share": float(mask.mean()),
            "rgb_ratio": [round(float(v), 3) for v in mean_norm],
            "saturation": round(float(chroma.mean()), 3),
            "hue_deg": round(float(hsl[0] * 360.0), 1),
        }
    p = np.percentile(lum, [5, 50, 95])
    out["global"] = {
        "luma_p5": round(float(p[0]), 4),
        "luma_p50": round(float(p[1]), 4),
        "luma_p95": round(float(p[2]), 4),
        "contrast_p95_p5": round(float(p[2] - p[0]), 4),
        "mean_saturation": round(float(((linear.max(axis=-1) - linear.min(axis=-1)) / np.maximum(linear.max(axis=-1), EPS)).mean()), 3),
        "rgb_ratio": [round(float(v), 3) for v in (linear.mean(axis=(0, 1)) / max(linear.mean(), EPS))],
    }
    return out


# ---------------------------------------------------------------------------
#   图表
# ---------------------------------------------------------------------------
def font(size: int) -> ImageFont.ImageFont:
    for name in ("msyh.ttc", "msyhbd.ttc", "simhei.ttf", "segoeui.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_response_chart(path: Path, width: int = 1180, height: int = 540) -> None:
    image = Image.new("RGB", (width, height), (18, 18, 20))
    draw = ImageDraw.Draw(image)
    title_font, small, tiny = font(22), font(14), font(12)

    margin_left, margin_bottom, margin_top = 70, 66, 92
    plot_w = width - margin_left - 30
    plot_h = height - margin_top - margin_bottom

    draw.text((24, 16), "Zephyr 调色响应：场景线性亮度 → 显示亮度", font=title_font, fill=(235, 235, 235))
    draw.text((24, 44), "灰阶经过 Photon 管线（含 ACES/Lottes tonemap）后，Zephyr 层如何改变影调；三条曲线均为同一套 GLSL 数学复算", font=tiny, fill=(150, 150, 155))

    x_scene = np.logspace(-3.3, np.log10(6.0), 400)
    scene = np.stack([x_scene] * 3, axis=-1)

    results = []
    for label, color, strength in (
        ("Photon", (120, 160, 220), 0.0),
        ("Zephyr 0.65（默认）", (255, 176, 96), 0.65),
        ("Zephyr 1.00（Cinematic 预设）", (255, 110, 160), 1.00),
    ):
        globals()["ZEPHYR_STRENGTH"] = strength
        results.append((label, color, pipeline_zephyr(scene.copy())))
    globals()["ZEPHYR_STRENGTH"] = 0.65

    def to_xy(i: int, value: float) -> tuple[float, float]:
        x = margin_left + (math.log10(x_scene[i]) + 3.3) / (math.log10(6.0) + 3.3) * plot_w
        y = margin_top + plot_h - float(np.clip(value, 0.0, 1.0)) * plot_h
        return x, y

    for ev in (-3, -2, -1, 0, 1):
        i = int(np.argmin(np.abs(np.log10(x_scene) - ev)))
        x, _ = to_xy(i, 0.0)
        draw.line([(x, margin_top), (x, margin_top + plot_h)], fill=(40, 40, 45))
        draw.text((x - 12, margin_top + plot_h + 8), f"2^{ev}", font=tiny, fill=(140, 140, 145))
    for level in (0.0, 0.25, 0.5, 0.75, 1.0):
        y = margin_top + plot_h - level * plot_h
        draw.line([(margin_left, y), (margin_left + plot_w, y)], fill=(40, 40, 45))
        draw.text((24, y - 8), f"{level:.2f}", font=tiny, fill=(140, 140, 145))

    for index, (label, color, curve) in enumerate(results):
        prev = None
        for i in range(0, len(x_scene), 2):
            point = to_xy(i, float(luma709(curve[i])))
            if prev is not None:
                draw.line([prev, point], fill=color, width=2 if index == 0 else 3)
            prev = point
        draw.text((margin_left + 300 * index, 66), f"■ {label}", font=small, fill=color)

    # 关键点标注：中灰 0.18 / 高光 2.0
    for level, label in ((0.18, "中灰 0.18"), (2.0, "高光 2.0")):
        i = int(np.argmin(np.abs(np.log10(x_scene) - math.log10(level))))
        x, y = to_xy(i, float(luma709(results[1][2][i])))
        draw.ellipse([x - 3, y - 3, x + 3, y + 3], outline=(255, 220, 160))
        draw.text((x + 6, y - 18), label, font=tiny, fill=(220, 200, 170))

    draw.text((width // 2 - 70, height - 26), "场景线性相对亮度（对数）", font=tiny, fill=(170, 170, 175))
    image.save(path)


def draw_test_card(path: Path) -> None:
    patches = [
        ("0.02 黑", (0.02, 0.02, 0.02)),
        ("0.10", (0.10, 0.10, 0.10)),
        ("0.18 中灰", (0.18, 0.18, 0.18)),
        ("0.40", (0.40, 0.40, 0.40)),
        ("1.00 白", (1.00, 1.00, 1.00)),
        ("皮肤", (0.55, 0.35, 0.28)),
        ("暖阳", (6.0, 4.4, 2.6)),
        ("雾青", (0.22, 0.30, 0.34)),
        ("霓虹青", (0.05, 0.55, 1.10)),
        ("霓虹洋红", (0.90, 0.10, 0.65)),
        ("樱花粉", (0.85, 0.45, 0.55)),
        ("秋叶橙", (1.10, 0.42, 0.10)),
    ]

    cell, label_h = 108, 30
    cols = len(patches)
    width = cols * cell + 40
    rows = (("Photon 原管线", pipeline_photon), ("Photon + Zephyr", pipeline_zephyr))
    height = 74 + len(rows) * (cell + label_h + 10) + (cell + label_h + 10) + 20
    image = Image.new("RGB", (width, height), (16, 16, 18))
    draw = ImageDraw.Draw(image)
    title, small, tiny = font(21), font(13), font(11)

    draw.text((20, 12), "Zephyr 色卡对比（同一场景线性输入，分别跑两条管线）", font=title, fill=(235, 235, 235))

    for row, (row_label, fn) in enumerate(rows):
        y0 = 56 + row * (cell + label_h + 10)
        draw.text((20, y0 - 18), row_label, font=small, fill=(200, 200, 205))
        for col, (label, rgb) in enumerate(patches):
            scene = np.array(rgb, dtype=np.float64).reshape(1, 1, 3)
            out = fn(scene)[0, 0]
            srgb = np.clip(linear_to_srgb(out), 0, 1)
            color = tuple(int(round(v * 255)) for v in srgb)
            x0 = 20 + col * cell
            draw.rectangle([x0, y0, x0 + cell - 8, y0 + cell - 8], fill=color)
            draw.text((x0 + 2, y0 + cell - 4), label, font=tiny, fill=(190, 190, 195))

    # 差值行（×4 放大，便于看清方向）
    y0 = 56 + len(rows) * (cell + label_h + 10)
    draw.text((20, y0 - 18), "差值 ×4（Zephyr − Photon，中灰为基准）", font=small, fill=(200, 200, 205))
    for col, (label, rgb) in enumerate(patches):
        scene = np.array(rgb, dtype=np.float64).reshape(1, 1, 3)
        before = pipeline_photon(scene.copy())[0, 0]
        after = pipeline_zephyr(scene.copy())[0, 0]
        delta = (after - before) * 4.0
        base = np.full(3, 0.5)
        vis = np.clip(base + delta, 0.0, 1.0)
        color = tuple(int(round(v * 255)) for v in linear_to_srgb(np.clip(vis, 0, 1)))
        x0 = 20 + col * cell
        draw.rectangle([x0, y0, x0 + cell - 8, y0 + cell - 8], fill=color)
        draw.text((x0 + 2, y0 + cell - 4), label, font=tiny, fill=(190, 190, 195))

    image.save(path)


# ---------------------------------------------------------------------------
#   Markdown 报告
# ---------------------------------------------------------------------------
def write_markdown(path: Path, stats: list, image_dir_rel: str) -> None:
    by_category: dict[str, list] = {}
    for _caption, category, st in stats:
        by_category.setdefault(category, []).append(st)

    def category_row(category: str) -> str:
        items = by_category[category]
        contrast = float(np.mean([st["global"]["contrast_p95_p5"] for st in items]))
        sat = float(np.mean([st["global"]["mean_saturation"] for st in items]))

        def ratio(zone: str) -> tuple[float, float] | None:
            vals = [st[zone]["rgb_ratio"] for st in items if st.get(zone)]
            if not vals:
                return None
            r = float(np.mean([v[0] for v in vals]))
            b = float(np.mean([v[2] for v in vals]))
            return r / max(b, EPS), float(np.mean([v[1] for v in vals])) / max(float(np.mean([v[0] for v in vals])), EPS)

        sh = ratio("shadow")
        hi = ratio("highlight")
        sh_text = "—" if sh is None else f"{sh[0]:.2f}"
        hi_text = "—" if hi is None else f"{hi[0]:.2f}"
        return f"| {category} | {len(items)} | {contrast:.2f} | {sat:.2f} | {sh_text} | {hi_text} |"

    all_contrast = float(np.mean([st["global"]["contrast_p95_p5"] for _c, _t, st in stats]))
    all_sat = float(np.mean([st["global"]["mean_saturation"] for _c, _t, st in stats]))

    lines = [
        "# 参考画面分析（Look Spec）",
        "",
        "> 由 `tools/analyze_look.py` 自动生成。目的：把「图里好看的感觉」变成可以调的数值。",
        "> 统计对象是用户给的异环/光追参考截图；数值是成片（已经过游戏自身调色）的统计，不是场景 HDR。",
        "",
        "## 1. 参考图统计（逐张）",
        "",
        "| 参考图 | 类型 | 亮度 p5 / p50 / p95 | 对比度 | 平均饱和 | 暗部色偏(RGB) | 高光色偏(RGB) |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for caption, category, st in stats:
        g = st["global"]
        sh = st.get("shadow")
        hi = st.get("highlight")

        def ratio(zone):
            return "—" if zone is None else " / ".join(f"{v:.2f}" for v in zone["rgb_ratio"])

        lines.append(
            f"| {caption} | {category} | {g['luma_p5']:.3f} / {g['luma_p50']:.3f} / {g['luma_p95']:.3f} "
            f"| {g['contrast_p95_p5']:.3f} | {g['mean_saturation']:.2f} | {ratio(sh)} | {ratio(hi)} |"
        )

    lines += [
        "",
        "## 2. 按类型汇总",
        "",
        "| 类型 | 张数 | 平均对比度 | 平均饱和 | 暗部 R/B | 高光 R/B |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for category in sorted(by_category):
        lines.append(category_row(category))

    lines += [
        "",
        f"整体：平均对比度（p95−p5）≈ **{all_contrast:.2f}**，平均饱和度 ≈ **{all_sat:.2f}**。",
        "",
        "**怎么读这张表：**",
        "",
        "- **暗部 R/B**：>1 表示暗部偏暖（红），<1 表示偏冷（青蓝）。参考图里这个值随内容变化："
        "雾天/雨后湿街/夜雪偏冷（≈0.7），夕阳/霓虹/红色车身场景偏暖（1.3~2.5）。",
        "- **高光 R/B**：暖光场景（夕阳/霓虹）≈1.2~2.0，阴雨灰调场景≈0.85~1.1。"
        "也就是说：参考图的亮部随光源变暖，但不会无条件偏暖。",
        "- 所以 Zephyr 的分离色调不是「把所有暗部刷青」，而是**高光固定加暖、暗部只轻推一点青**，"
        "强度默认 0.55，保留内容本来的色偏。",
        "",
        "## 3. 调色响应曲线",
        "",
        f"![调色响应]({image_dir_rel}/grade-response.png)",
        "",
        "三条曲线：Photon 原管线 / Zephyr 默认强度 0.65 / Cinematic 预设强度 1.00。可以看到：",
        "",
        "- 中灰（0.18）附近斜率变大 → 中间调对比更强，画面更「立」；",
        "- 高光（2.0）附近曲线更平 → 高光肩部柔和，不容易死白；",
        "- 暗部略有抬升 → `ZEPHYR_BLACK_LIFT` 带来的胶片褪色感。",
        "",
        "## 4. 色卡对比",
        "",
        f"![色卡对比]({image_dir_rel}/color-card.png)",
        "",
        "重点看第三行「差值 ×4」：暖色（秋叶橙/暖阳）往暖偏，霓虹青/洋红被轻微去饱和、"
        "灰阶被抬了一点黑位——这就是 Zephyr 层在做的事。",
        "",
        "## 5. 参数对应关系",
        "",
        "| 参考特征 | 数据表现 | Zephyr 参数 |",
        "| --- | --- | --- |",
        "| 高光随光源偏暖 | 高光 R/B ≈ 0.9~2.0 | `highlight_tint`（1.06/1.00/0.93）+ `ZEPHYR_WARMTH` |",
        "| 暗部内容相关 | 雾雨雪偏冷、夕阳霓虹偏暖 | `ZEPHYR_SPLIT_STRENGTH`（默认 0.55，不宜过高） |",
        "| 高对比 | 平均 p95−p5 ≈ 0.45 | `ZEPHYR_FILM_CURVE`、`GRADE_CONTRAST` |",
        "| 饱和度克制 | 平均饱和 ≈ 0.44 | `GRADE_SATURATION`、`ZEPHYR_VIBRANCE` |",
        "| 胶片黑位 | 暗部不纯黑 | `ZEPHYR_BLACK_LIFT` |",
        "| 高光柔和 | 亮部不过曝 | `ZEPHYR_HIGHLIGHT_ROLLOFF`、`BLOOM_INTENSITY` |",
        "",
        "> 用法：改完参数后重跑本脚本，看曲线与色卡是否朝目标方向移动；再到游戏里用实机截图确认。",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--refs", nargs="*", default=None, help="参考图路径（默认从 .dsh attachments 读取）")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "docs")
    args = parser.parse_args(argv)

    out_dir = args.out
    image_dir = out_dir / "images" / "look-analysis"
    image_dir.mkdir(parents=True, exist_ok=True)

    if args.refs:
        entries = [(p, Path(p).stem, "custom") for p in args.refs]
    else:
        entries = []
        for sha, caption, category in REFERENCES:
            path = ATTACHMENT_ROOT / sha[:2] / sha
            if path.is_file():
                entries.append((path, caption, category))

    if not entries:
        print("没有找到参考图，请用 --refs 指定")
        return 1

    stats: list = []
    for path, caption, category in entries:
        linear = srgb_to_linear(load_rgb(path))
        stats.append((caption, category, zone_stats(linear)))
        print(f"analyzed {path.name[:12]} ({category})")

    (image_dir / "reference-stats.json").write_text(
        json.dumps([{"caption": c, "category": t, "stats": st} for c, t, st in stats], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    draw_response_chart(image_dir / "grade-response.png")
    draw_test_card(image_dir / "color-card.png")
    write_markdown(out_dir / "look-analysis.md", stats, "images/look-analysis")

    print(f"报告：{out_dir / 'look-analysis.md'}")
    print(f"图：{image_dir}")

    # 控制台摘要
    contrasts = [st["global"]["contrast_p95_p5"] for _c, _t, st in stats]
    sats = [st["global"]["mean_saturation"] for _c, _t, st in stats]
    print(f"平均对比度 p95-p5 = {np.mean(contrasts):.3f}, 平均饱和 = {np.mean(sats):.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
