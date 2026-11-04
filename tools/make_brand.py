#!/usr/bin/env python3
"""Generate Syllapace's shared vector geometry; --render also makes PNG previews.

Brand/geometry.json owns the design tokens. Derived values and geometric checks
are regenerated there, so the independent logo and Icon Composer layers cannot
quietly drift apart. --check verifies existing generated files without writing.
Only the optional raster preview step depends on rsvg-convert.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "Brand/geometry.json"
EPSILON = 1e-8


def number(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".")


def point(value: tuple[float, float]) -> str:
    return ",".join(number(v) for v in value)


def rounded_rect(x: float, y: float, width: float, height: float, radius: float) -> str:
    right, bottom = x + width, y + height
    n = number
    return (f"M{n(x + radius)},{n(y)}H{n(right - radius)}"
            f"A{n(radius)},{n(radius)} 0 0 1 {n(right)},{n(y + radius)}V{n(bottom - radius)}"
            f"A{n(radius)},{n(radius)} 0 0 1 {n(right - radius)},{n(bottom)}H{n(x + radius)}"
            f"A{n(radius)},{n(radius)} 0 0 1 {n(x)},{n(bottom - radius)}V{n(y + radius)}"
            f"A{n(radius)},{n(radius)} 0 0 1 {n(x + radius)},{n(y)}Z")


def circle_path(x: float, y: float, radius: float) -> str:
    n = number
    return (f"M{n(x + radius)},{n(y)}A{n(radius)},{n(radius)} 0 1 1 {n(x - radius)},{n(y)}"
            f"A{n(radius)},{n(radius)} 0 1 1 {n(x + radius)},{n(y)}Z")


def close(a: float, b: float) -> bool:
    return math.isclose(a, b, rel_tol=0, abs_tol=EPSILON)


def calculate(config: dict) -> dict:
    token, layout = config["tokens"], config["layout"]
    assert config["schemaVersion"] == 1, "Unsupported geometry schema"
    assert layout["gridColumns"] == layout["gridRows"] == 2, "This mark has a 2×2 date grid"
    assert all(isinstance(v, (int, float)) and v > 0 for v in token.values()), "Positive tokens required"
    unit = token["unit"]
    gap = unit * token["gapUnits"]
    paper = unit * token["paperRadiusUnits"]
    detail = unit * token["detailRadiusUnits"]
    tip = unit * token["tipRadiusUnits"]
    pad = gap * token["contentPaddingGaps"]
    space = gap * token["contentGapGaps"]
    cell = gap * token["cellSizeGaps"]
    header_height = gap * token["headerHeightGaps"]
    offset = gap * token["stackOffsetGaps"]
    canvas = unit * layout["canvasUnits"]
    center = canvas / 2
    content_width = 2 * cell + space
    content_height = header_height + space + 2 * cell + space
    width, height = content_width + 2 * pad, content_height + 2 * pad
    x, y = center + offset / 2 - width / 2, center + offset / 2 - height / 2
    right, bottom = x + width, y + height
    bx, by, br, bb = x - offset, y - offset, right - offset, bottom - offset
    content_x, content_y = x + pad, y + pad
    first_y = content_y + header_height + space
    step = cell + space
    date_centers = [(content_x + cell / 2 + column * step, first_y + cell / 2 + row * step)
                    for row in range(2) for column in range(2)]
    selected_x, selected_y = date_centers[-1]
    selected_outer, selected_inner = cell / 2, cell / 2 - gap
    concave, inner = gap * token["foldConcaveRadiusGaps"], gap * (token["foldConcaveRadiusGaps"] - 1)
    back_inner = paper + gap
    exposure = offset - gap
    cx, cy = right, bottom
    assert inner > tip and selected_inner > 0 and exposure == 2 * paper
    # The tip centers lie on vertical/horizontal offset lines. Their distances
    # from the fold center are R+t (external tangency) and r-t (internal tangency).
    f = math.sqrt((concave + tip) ** 2 - tip ** 2)
    q = math.sqrt((inner - tip) ** 2 - tip ** 2)
    a = (cx - concave * tip / (concave + tip), cy - concave * f / (concave + tip))
    b = (cx - concave * f / (concave + tip), cy - concave * tip / (concave + tip))
    c = (cx - inner * q / (inner - tip), cy - inner * tip / (inner - tip))
    d = (cx - inner * tip / (inner - tip), cy - inner * q / (inner - tip))
    n = number
    front = (f"M{n(x + paper)},{n(y)}H{n(right - paper)}A{n(paper)},{n(paper)} 0 0 1 {n(right)},{n(y + paper)}"
             f"V{n(cy - f)}A{n(tip)},{n(tip)} 0 0 1 {point(a)}"
             f"A{n(concave)},{n(concave)} 0 0 0 {point(b)}A{n(tip)},{n(tip)} 0 0 1 {n(cx - f)},{n(bottom)}"
             f"H{n(x + paper)}A{n(paper)},{n(paper)} 0 0 1 {n(x)},{n(bottom - paper)}V{n(y + paper)}"
             f"A{n(paper)},{n(paper)} 0 0 1 {n(x + paper)},{n(y)}Z")
    back = (f"M{n(bx + paper)},{n(by)}H{n(br - paper)}A{n(paper)},{n(paper)} 0 0 1 {n(br - paper)},{n(by + exposure)}"
            f"H{n(x + paper)}A{n(back_inner)},{n(back_inner)} 0 0 0 {n(bx + exposure)},{n(y + paper)}"
            f"V{n(bb - paper)}A{n(paper)},{n(paper)} 0 0 1 {n(bx)},{n(bb - paper)}V{n(by + paper)}"
            f"A{n(paper)},{n(paper)} 0 0 1 {n(bx + paper)},{n(by)}Z")
    fold = (f"M{n(right)},{n(bottom - q)}V{n(bottom - paper)}A{n(paper)},{n(paper)} 0 0 1 {n(right - paper)},{n(bottom)}"
            f"H{n(right - q)}A{n(tip)},{n(tip)} 0 0 1 {point(c)}A{n(inner)},{n(inner)} 0 0 1 {point(d)}"
            f"A{n(tip)},{n(tip)} 0 0 1 {n(right)},{n(bottom - q)}Z")
    cutouts = [rounded_rect(content_x, content_y, content_width, header_height, detail)]
    cutouts += [rounded_rect(px - cell / 2, py - cell / 2, cell, cell, detail) for px, py in date_centers[:-1]]
    cutouts.append(circle_path(selected_x, selected_y, selected_outer))
    scale = layout["iconScaleNumerator"] / layout["iconScaleDenominator"]
    crop_margin = layout["logoCropMarginUnits"] * unit
    clearance = math.dist((selected_x, selected_y), (cx, cy)) - concave - selected_outer
    checks = []

    def verify(name: str, passed: bool, detail_value) -> None:
        checks.append({"name": name, "passed": bool(passed), "evidence": detail_value})
        if not passed:
            raise ValueError(f"Geometry check failed: {name}: {detail_value}")

    content_edges = [content_x - x, right - content_x - content_width, content_y - y, bottom - content_y - content_height]
    verify("equal_content_padding", all(close(v, pad) for v in content_edges), content_edges)
    verify("equal_date_grid_step", all(close(math.dist(date_centers[i], date_centers[j]), step)
           for i, j in [(0, 1), (2, 3), (0, 2), (1, 3)]), {"step": step, "centers": date_centers})
    verify("equal_content_gaps", close(first_y - content_y - header_height, space) and close(step - cell, space), space)
    verify("header_aligns_date_grid", close(date_centers[0][0] - cell / 2, content_x)
           and close(date_centers[1][0] + cell / 2, content_x + content_width), [content_x, content_x + content_width])
    verify("selected_date_matches_cell", close(selected_outer * 2, cell) and close(selected_outer - selected_inner, gap),
           {"cell": cell, "outerRadius": selected_outer, "innerRadius": selected_inner, "ring": gap})
    verify("back_page_spacing", close(y - by - exposure, gap) and close(x - bx - exposure, gap)
           and close(back_inner - paper, gap), {"exposure": exposure, "gap": gap, "radii": [paper, back_inner]})
    verify("fold_concentric_spacing", close(concave - inner, gap), {"center": [cx, cy], "radii": [concave, inner], "gap": gap})
    tangent_cases = [(a, (right - tip, bottom - f), concave), (b, (right - f, bottom - tip), concave),
                     (c, (right - q, bottom - tip), inner), (d, (right - tip, bottom - q), inner)]
    for index, (joint, tip_center, radius) in enumerate(tangent_cases):
        radial = (joint[0] - cx, joint[1] - cy)
        tip_radial = (joint[0] - tip_center[0], joint[1] - tip_center[1])
        cross = radial[0] * tip_radial[1] - radial[1] * tip_radial[0]
        verify(f"fold_tip_{index + 1}_tangent", close(math.dist(joint, (cx, cy)), radius)
               and close(math.dist(joint, tip_center), tip) and abs(cross) < EPSILON,
               {"join": joint, "arcRadius": radius, "tipRadius": tip, "radialCrossProduct": cross})
    verify("date_to_fold_clearance", clearance >= gap, {"actual": clearance, "minimum": gap})
    verify("centered_total_bounds", close((bx + right) / 2, center) and close((by + bottom) / 2, center),
           {"bounds": [bx, by, right, bottom], "center": [center, center]})
    verify("paper_and_fold_outer_radius", paper == exposure / 2, paper)
    for name, path in {"back": back, "front": front, "cutouts": " ".join(cutouts), "fold": fold}.items():
        verify(f"{name}_uses_only_circular_arcs", set(re.findall(r"[A-Za-z]", path)) <= set("MHVAZ"), "Only M/H/V/A/Z path commands")
    derived = {
        "unit": unit, "gap": gap, "paperRadius": paper, "detailRadius": detail, "tipRadius": tip,
        "contentPadding": pad, "contentGap": space, "cellSize": cell, "headerHeight": header_height,
        "stackOffset": offset, "backExposure": exposure,
        "frontPage": {"x": x, "y": y, "width": width, "height": height},
        "backPage": {"x": bx, "y": by, "width": width, "height": height},
        "contentBounds": [content_x, content_y, content_x + content_width, content_y + content_height],
        "headerBounds": [content_x, content_y, content_x + content_width, content_y + header_height],
        "dateCenters": date_centers, "dateStep": step,
        "selectedDate": {"center": [selected_x, selected_y], "outerRadius": selected_outer, "innerRadius": selected_inner},
        "fold": {"center": [cx, cy], "concaveRadius": concave, "innerRadius": inner, "outerRadius": paper,
                 "tipRadius": tip, "dateClearance": clearance},
        "overallBounds": [bx, by, right, bottom], "logoViewBox": [crop_margin, crop_margin, canvas - 2 * crop_margin, canvas - 2 * crop_margin],
        "iconScale": scale, "iconGlyphWidth": (right - bx) * scale, "iconGlyphHeight": (bottom - by) * scale,
    }
    return {"canvas": canvas, "center": center, "scale": scale, "front": front + " " + " ".join(cutouts),
            "back": back, "fold": fold, "selected": (selected_x, selected_y, selected_inner), "derived": derived, "checks": checks}


def svg(geo: dict, colors: dict, view_box: list, monochrome: str | None = None, layer: str | None = None) -> str:
    primary = monochrome or colors["primary"]
    accent = monochrome or colors["accent"]
    if layer == "schedule-page":
        primary = colors["white"]
    selected_x, selected_y, radius = geo["selected"]
    parts = {
        "back-page": f'<path fill="{accent}" d="{geo["back"]}"/>',
        "schedule-page": f'<path fill="{primary}" fill-rule="evenodd" d="{geo["front"]}"/>',
        "selected-date": f'<circle cx="{number(selected_x)}" cy="{number(selected_y)}" r="{number(radius)}" fill="{accent}"/>',
        "turned-corner": f'<path fill="{accent}" d="{geo["fold"]}"/>',
    }
    names = {None: list(parts), "course-back": ["back-page"], "schedule-page": ["schedule-page"],
             "date-corner": ["selected-date", "turned-corner"]}[layer]
    groups = "\n".join(f'  <g id="{name}">{parts[name]}</g>' for name in names)
    if layer is not None:
        center, scale = number(geo["center"]), f'{geo["scale"]:.12f}'
        groups = f'  <g id="icon-glyph" transform="translate({center} {center}) scale({scale}) translate(-{center} -{center})">\n{groups}\n  </g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{number(view_box[2])}" height="{number(view_box[3])}" '
            f'viewBox="{" ".join(number(v) for v in view_box)}" role="img" aria-labelledby="title desc">\n'
            '  <title id="title">Syllapace</title>\n'
            '  <desc id="desc">Course pages, an aligned date grid, and a turning corner built from shared spacing and circular-radius tokens.</desc>\n'
            f'{groups}\n</svg>\n')


def outputs(config: dict, geo: dict) -> dict[Path, str]:
    colors = config["colors"]
    for key in ["primary", "accent", "black", "white", "previewBackground"]:
        assert re.fullmatch(r"#[0-9a-fA-F]{6}", colors[key]), f"Invalid color token: {key}"
    crop, full = geo["derived"]["logoViewBox"], [0, 0, geo["canvas"], geo["canvas"]]
    files = {ROOT / "Brand/logo.svg": svg(geo, colors, crop),
             ROOT / "Brand/logo-black.svg": svg(geo, colors, crop, colors["black"]),
             ROOT / "Brand/logo-white.svg": svg(geo, colors, crop, colors["white"]),
             ROOT / "Brand/logo-teal.svg": svg(geo, colors, crop, colors["primary"]),
             ROOT / "Brand/concepts-v2/course-stack.svg": svg(geo, colors, full)}
    for layer in ["course-back", "schedule-page", "date-corner"]:
        files[ROOT / f"Icon/AppIcon.icon/Assets/{layer}.svg"] = svg(geo, colors, full, layer=layer)
    icon = {
        "groups": [{"layers": [{"glass": True, "image-name": f"{name}.svg", "name": label} for name, label in
                                 [("date-corner", "Date and turning corner"), ("schedule-page", "Schedule page"), ("course-back", "Course materials")]],
                    "shadow": {"kind": "neutral", "opacity": config["icon"]["shadowOpacity"]},
                    "translucency": {"enabled": True, "value": config["icon"]["translucency"]}}],
        "supported-platforms": {"squares": ["macOS"]},
        "fill-specializations": [{"value": {"automatic-gradient": colors["iconBackgroundDefault"]}},
                                 {"appearance": "dark", "value": {"automatic-gradient": colors["iconBackgroundDark"]}}],
    }
    files[ROOT / "Icon/AppIcon.icon/icon.json"] = json.dumps(icon, indent=2) + "\n"
    for path, content in files.items():
        if path.suffix == ".svg":
            ET.fromstring(content)
            assert not any(part in content for part in ["<image", "<text", "<filter", "href=", "font-family", "stroke="]), path
    # Compare shape attributes independently of color and grouping for all flat variants.
    def shape_signature(content: str):
        return [(node.tag, {key: value for key, value in node.attrib.items() if key != "fill"})
                for node in ET.fromstring(content).iter() if node.tag.rsplit("}", 1)[-1] in ["path", "circle"]]
    master = shape_signature(files[ROOT / "Brand/concepts-v2/course-stack.svg"])
    assert all(shape_signature(files[ROOT / f"Brand/{name}.svg"]) == master
               for name in ["logo", "logo-black", "logo-white", "logo-teal"]), "Variant geometry diverged"
    recorded = copy.deepcopy(config)
    recorded["derived"] = geo["derived"]
    recorded["checks"] = geo["checks"] + [{"name": "exported_vectors_share_geometry", "passed": True,
                                            "evidence": "Four logo variants retain the master shape attributes and evenodd cutouts."},
                                           {"name": "self_contained_vectors", "passed": True,
                                            "evidence": "SVG XML parses; no bitmap, font, filter, stroke or external reference."}]
    files[CONFIG] = json.dumps(recorded, indent=2) + "\n"
    return files


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", action="store_true", help="Also render two 512px previews with rsvg-convert")
    parser.add_argument("--check", action="store_true", help="Verify geometry and generated files without modifying them")
    args = parser.parse_args()
    if args.check and args.render:
        parser.error("--check and --render are mutually exclusive")
    config = json.loads(CONFIG.read_text())
    geo = calculate(config)
    files = outputs(config, geo)
    if args.check:
        stale = [str(path.relative_to(ROOT)) for path, content in files.items() if not path.exists() or path.read_text() != content]
        if stale:
            raise SystemExit("Generated brand files differ; run tools/make_brand.py:\n" + "\n".join(stale))
    else:
        for path, content in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    if args.render:
        renderer = shutil.which("rsvg-convert")
        if renderer is None:
            raise SystemExit("SVGs generated. PNG previews need rsvg-convert; omit --render to generate vectors only.")
        for name in ["Brand/logo", "Brand/concepts-v2/course-stack"]:
            output = "Brand/logo-preview.png" if name == "Brand/logo" else name + ".png"
            subprocess.run([renderer, "-b", config["colors"]["previewBackground"], "-w", "512", "-h", "512",
                            "-o", str(ROOT / output), str(ROOT / (name + ".svg"))], check=True)
    count = len(geo["checks"]) + 2
    print(f"PASS {count} geometry/export checks; {len(files)} generated vector/config files {'verified' if args.check else 'written'}.")
    print(f"Date-to-fold clearance: {geo['derived']['fold']['dateClearance']:.6f} ≥ {geo['derived']['gap']}; "
          f"native icon glyph: {geo['derived']['iconGlyphWidth']:.6f} × {geo['derived']['iconGlyphHeight']:.6f}.")


if __name__ == "__main__":
    main()
