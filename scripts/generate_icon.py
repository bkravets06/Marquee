#!/usr/bin/env python3
"""Generate the Marquee app icon.

Renders a theater-marquee sign: a gold rounded frame lined with warm bulbs
around a bold gold play triangle, on a dark charcoal gradient. The image is
supersampled and downscaled with LANCZOS so every edge is smooth, then saved
as a 1024x1024 RGB PNG without an alpha channel (as App Store Connect requires).

Usage:
    python3 scripts/generate_icon.py [output.png]

Requires Pillow:  pip install Pillow
"""

from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# MARK: - Configuration

OUTPUT_SIZE = 1024
SCALE = 4                      # supersampling factor (renders at 4096)
SIZE = OUTPUT_SIZE * SCALE

BACKGROUND_TOP = (0x1C, 0x1C, 0x1E)
BACKGROUND_BOTTOM = (0x05, 0x05, 0x05)
GLOW_WARM = (0xF5, 0xA6, 0x23)
GOLD = (0xF5, 0xA6, 0x23)
GOLD_HIGHLIGHT = (0xFF, 0xD2, 0x7A)
GOLD_SHADOW = (0xC9, 0x7F, 0x12)
BULB_WHITE = (0xFF, 0xF1, 0xC1)

FRAME_INSET_FRACTION = 0.14    # inset from each edge, as a fraction of width
FRAME_STROKE = 28              # px at 1024
FRAME_RADIUS = 96              # corner radius at 1024
BULB_RADIUS = 11               # px at 1024 (diameter ~22)
BULBS_PER_LONG_SIDE = 9
TRIANGLE_WIDTH_FRACTION = 0.32
TRIANGLE_CORNER_RADIUS = 22    # px at 1024

DEFAULT_OUTPUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Marquee",
    "Assets.xcassets",
    "AppIcon.appiconset",
    "AppIcon.png",
)


def px(value: float) -> int:
    """Convert a length expressed at 1024 px into supersampled pixels."""
    return int(round(value * SCALE))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_color(c1, c2, t: float):
    return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))


# MARK: - Background

def make_background() -> Image.Image:
    """Vertical charcoal gradient with a faint warm radial glow behind the center."""
    gradient = Image.new("RGB", (1, SIZE))
    for y in range(SIZE):
        t = y / (SIZE - 1)
        # Ease slightly so the top stays charcoal a little longer.
        eased = t * t * (3 - 2 * t)
        gradient.putpixel((0, y), lerp_color(BACKGROUND_TOP, BACKGROUND_BOTTOM, eased))
    background = gradient.resize((SIZE, SIZE))

    glow_layer = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    glow_radius = px(300)
    center = SIZE // 2
    glow_draw.ellipse(
        [center - glow_radius, center - glow_radius, center + glow_radius, center + glow_radius],
        fill=lerp_color((0, 0, 0), GLOW_WARM, 0.22),
    )
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(px(140)))
    return ImageChops.add(background, glow_layer)


# MARK: - Geometry helpers

def frame_rect():
    inset = SIZE * FRAME_INSET_FRACTION
    return (inset, inset, SIZE - inset, SIZE - inset)


def rounded_rect_perimeter_points(rect, radius: float, count: int):
    """Evenly spaced points along the centerline of a rounded rectangle."""
    left, top, right, bottom = rect
    straight_w = (right - left) - 2 * radius
    straight_h = (bottom - top) - 2 * radius
    arc = math.pi * radius / 2
    total = 2 * straight_w + 2 * straight_h + 4 * arc

    def point_at(distance: float):
        d = distance % total
        # Start at the top edge just after the top-left corner, moving clockwise.
        if d < straight_w:
            return (left + radius + d, top)
        d -= straight_w
        if d < arc:
            angle = -math.pi / 2 + (d / arc) * (math.pi / 2)
            cx, cy = right - radius, top + radius
            return (cx + radius * math.cos(angle), cy + radius * math.sin(angle))
        d -= arc
        if d < straight_h:
            return (right, top + radius + d)
        d -= straight_h
        if d < arc:
            angle = 0 + (d / arc) * (math.pi / 2)
            cx, cy = right - radius, bottom - radius
            return (cx + radius * math.cos(angle), cy + radius * math.sin(angle))
        d -= arc
        if d < straight_w:
            return (right - radius - d, bottom)
        d -= straight_w
        if d < arc:
            angle = math.pi / 2 + (d / arc) * (math.pi / 2)
            cx, cy = left + radius, bottom - radius
            return (cx + radius * math.cos(angle), cy + radius * math.sin(angle))
        d -= arc
        if d < straight_h:
            return (left, bottom - radius - d)
        d -= straight_h
        angle = math.pi + (d / arc) * (math.pi / 2)
        cx, cy = left + radius, top + radius
        return (cx + radius * math.cos(angle), cy + radius * math.sin(angle))

    step = total / count
    # Offset by half a step so no bulb sits exactly on the corner seam.
    return [point_at(step * i + step / 2) for i in range(count)]


def bulb_positions(rect, radius: float):
    """Bulb centers: BULBS_PER_LONG_SIDE along each straight side plus one on each corner arc."""
    left, top, right, bottom = rect
    points = []
    n = BULBS_PER_LONG_SIDE
    # Straight edges.
    for i in range(n):
        t = (i + 0.5) / n
        x = lerp(left + radius, right - radius, t)
        y = lerp(top + radius, bottom - radius, t)
        points.append((x, top))
        points.append((x, bottom))
        points.append((left, y))
        points.append((right, y))
    # One bulb at the middle of each corner arc so the loop reads as continuous.
    for cx, cy, angle in (
        (right - radius, top + radius, -math.pi / 4),
        (right - radius, bottom - radius, math.pi / 4),
        (left + radius, bottom - radius, 3 * math.pi / 4),
        (left + radius, top + radius, -3 * math.pi / 4),
    ):
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return points


# MARK: - Layers

def gold_gradient_fill(mask: Image.Image, top_color, bottom_color) -> Image.Image:
    """An RGB image filled with a vertical gradient, to be composited through `mask`."""
    strip = Image.new("RGB", (1, SIZE))
    for y in range(SIZE):
        t = y / (SIZE - 1)
        strip.putpixel((0, y), lerp_color(top_color, bottom_color, t))
    return strip.resize((SIZE, SIZE))


def draw_frame(canvas: Image.Image) -> None:
    """Gold rounded-rectangle frame with a soft glow and a subtle highlight gradient."""
    rect = frame_rect()
    radius = px(FRAME_RADIUS)
    stroke = px(FRAME_STROKE)

    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(rect, radius=radius, outline=255, width=stroke)

    # Outer glow.
    glow = mask.filter(ImageFilter.GaussianBlur(px(18)))
    glow_color = Image.new("RGB", (SIZE, SIZE), GOLD)
    canvas.paste(glow_color, (0, 0), glow.point(lambda v: int(v * 0.45)))

    # Body with a highlight-to-shadow gradient.
    fill = gold_gradient_fill(mask, GOLD_HIGHLIGHT, GOLD_SHADOW)
    canvas.paste(fill, (0, 0), mask)

    # Thin inner highlight line to give the frame a bevel.
    highlight = Image.new("L", (SIZE, SIZE), 0)
    inset = stroke * 0.30
    ImageDraw.Draw(highlight).rounded_rectangle(
        (rect[0] + inset, rect[1] + inset, rect[2] - inset, rect[3] - inset),
        radius=max(1, radius - inset),
        outline=255,
        width=max(1, px(3)),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(px(1.5)))
    canvas.paste(Image.new("RGB", (SIZE, SIZE), GOLD_HIGHLIGHT), (0, 0), highlight.point(lambda v: int(v * 0.55)))


def draw_bulbs(canvas: Image.Image) -> None:
    """Warm white bulbs sitting on the frame line, each with a soft gold glow."""
    rect = frame_rect()
    radius = px(FRAME_RADIUS)
    bulb_r = px(BULB_RADIUS)
    points = bulb_positions(rect, radius)

    glow_mask = Image.new("L", (SIZE, SIZE), 0)
    bulb_mask = Image.new("L", (SIZE, SIZE), 0)
    glow_draw = ImageDraw.Draw(glow_mask)
    bulb_draw = ImageDraw.Draw(bulb_mask)
    for (x, y) in points:
        glow_r = bulb_r * 2.4
        glow_draw.ellipse([x - glow_r, y - glow_r, x + glow_r, y + glow_r], fill=255)
        bulb_draw.ellipse([x - bulb_r, y - bulb_r, x + bulb_r, y + bulb_r], fill=255)

    glow_mask = glow_mask.filter(ImageFilter.GaussianBlur(px(10)))
    canvas.paste(Image.new("RGB", (SIZE, SIZE), GOLD_HIGHLIGHT), (0, 0), glow_mask.point(lambda v: int(v * 0.7)))

    # Slightly soften the bulb edge so it does not alias.
    bulb_mask = bulb_mask.filter(ImageFilter.GaussianBlur(px(0.6)))
    canvas.paste(Image.new("RGB", (SIZE, SIZE), BULB_WHITE), (0, 0), bulb_mask)

    # A tiny brighter hot spot on each bulb.
    hot_mask = Image.new("L", (SIZE, SIZE), 0)
    hot_draw = ImageDraw.Draw(hot_mask)
    hot_r = bulb_r * 0.45
    for (x, y) in points:
        hx, hy = x - bulb_r * 0.25, y - bulb_r * 0.25
        hot_draw.ellipse([hx - hot_r, hy - hot_r, hx + hot_r, hy + hot_r], fill=255)
    hot_mask = hot_mask.filter(ImageFilter.GaussianBlur(px(1.2)))
    canvas.paste(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), (0, 0), hot_mask.point(lambda v: int(v * 0.8)))


def rounded_triangle_mask(center, width: float, corner_radius: float) -> Image.Image:
    """Mask of a play triangle with exactly rounded corners, pointing right.

    Built as the Minkowski sum of an inset triangle and a disc: the inset polygon,
    thick lines along its edges and a circle at each vertex.
    """
    height = width * 1.10
    cx, cy = center
    # Optical centering: shift a little left so the visual centroid sits in the middle.
    cx -= width * 0.06
    vertices = [
        (cx - width / 2, cy - height / 2),
        (cx + width / 2, cy),
        (cx - width / 2, cy + height / 2),
    ]

    # Inset each vertex along its angle bisector so the rounded shape keeps the same extents.
    def inset_vertex(index: int):
        prev_v = vertices[index - 1]
        cur_v = vertices[index]
        next_v = vertices[(index + 1) % 3]
        d1 = (prev_v[0] - cur_v[0], prev_v[1] - cur_v[1])
        d2 = (next_v[0] - cur_v[0], next_v[1] - cur_v[1])
        l1 = math.hypot(*d1)
        l2 = math.hypot(*d2)
        u1 = (d1[0] / l1, d1[1] / l1)
        u2 = (d2[0] / l2, d2[1] / l2)
        bis = (u1[0] + u2[0], u1[1] + u2[1])
        bl = math.hypot(*bis)
        bis = (bis[0] / bl, bis[1] / bl)
        half_angle = math.acos(max(-1.0, min(1.0, u1[0] * u2[0] + u1[1] * u2[1]))) / 2
        distance = corner_radius / math.sin(half_angle)
        return (cur_v[0] + bis[0] * distance, cur_v[1] + bis[1] * distance)

    inset = [inset_vertex(i) for i in range(3)]
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon(inset, fill=255)
    for i in range(3):
        a = inset[i]
        b = inset[(i + 1) % 3]
        draw.line([a, b], fill=255, width=int(round(corner_radius * 2)))
        draw.ellipse(
            [a[0] - corner_radius, a[1] - corner_radius, a[0] + corner_radius, a[1] + corner_radius],
            fill=255,
        )
    return mask.filter(ImageFilter.GaussianBlur(px(0.7)))


def draw_play_triangle(canvas: Image.Image) -> None:
    """Bold gold play triangle with a subtle inner gradient and a soft drop glow."""
    width = SIZE * TRIANGLE_WIDTH_FRACTION
    center = (SIZE / 2, SIZE / 2)
    mask = rounded_triangle_mask(center, width, px(TRIANGLE_CORNER_RADIUS))

    # Drop glow, offset slightly downward.
    glow = mask.filter(ImageFilter.GaussianBlur(px(26)))
    glow_layer = Image.new("RGB", (SIZE, SIZE), GOLD)
    offset = Image.new("L", (SIZE, SIZE), 0)
    offset.paste(glow, (0, px(10)))
    canvas.paste(glow_layer, (0, 0), offset.point(lambda v: int(v * 0.6)))

    # Body gradient: highlight at the top-left edge, richer gold toward the bottom.
    fill = gold_gradient_fill(mask, GOLD_HIGHLIGHT, GOLD)
    canvas.paste(fill, (0, 0), mask)

    # Inner sheen: a soft lighter band across the upper third.
    sheen = Image.new("L", (SIZE, SIZE), 0)
    sheen_draw = ImageDraw.Draw(sheen)
    band_top = int(SIZE / 2 - width * 0.55)
    band_bottom = int(SIZE / 2 - width * 0.10)
    sheen_draw.rectangle([0, band_top, SIZE, band_bottom], fill=255)
    sheen = sheen.filter(ImageFilter.GaussianBlur(px(30)))
    sheen = ImageChops.multiply(sheen, mask).point(lambda v: int(v * 0.35))
    canvas.paste(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), (0, 0), sheen)


# MARK: - Main

def render() -> Image.Image:
    canvas = make_background()
    draw_frame(canvas)
    draw_bulbs(canvas)
    draw_play_triangle(canvas)
    return canvas.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.LANCZOS)


def main(argv: list[str]) -> int:
    output = argv[1] if len(argv) > 1 else DEFAULT_OUTPUT
    os.makedirs(os.path.dirname(output), exist_ok=True)
    image = render().convert("RGB")
    image.save(output, format="PNG", optimize=True)
    size = os.path.getsize(output)
    print(f"Wrote {output} ({image.size[0]}x{image.size[1]} {image.mode}, {size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
