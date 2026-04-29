from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path("/Users/srdjankotarlic/Documents/New project/pptbridge-obs-plugin/native-plugin")
OUT_DIR = ROOT / "output" / "social"

W = 1350
H = 1350

BG_TOP = (8, 17, 31)
BG_BOTTOM = (22, 67, 88)
ACCENT = (83, 212, 190)
ACCENT_2 = (248, 180, 94)
CARD = (17, 28, 46)
CARD_2 = (23, 39, 61)
TEXT = (244, 247, 251)
MUTED = (166, 182, 201)
LINE = (43, 69, 96)
DARK = (9, 14, 24)
WHITE = (255, 255, 255)

FONT_BOLD = "/System/Library/Fonts/Supplemental/Verdana Bold.ttf"
FONT_REG = "/System/Library/Fonts/Supplemental/Verdana.ttf"
FONT_MONO = "/System/Library/Fonts/SFNSMono.ttf"


def font(path, size):
    return ImageFont.truetype(path, size=size)


H1 = font(FONT_BOLD, 92)
H2 = font(FONT_BOLD, 54)
H3 = font(FONT_BOLD, 34)
BODY = font(FONT_REG, 28)
BODY_SM = font(FONT_REG, 22)
LABEL = font(FONT_BOLD, 24)
MONO = font(FONT_MONO, 22)


def make_canvas():
    img = Image.new("RGBA", (W, H), BG_TOP)
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        color = tuple(int(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3))
        for x in range(W):
            px[x, y] = (*color, 255)
    draw = ImageDraw.Draw(img)

    # atmospheric glow
    for offset, radius, color in [
        ((-120, -40), 520, (37, 120, 158, 110)),
        ((W - 420, 80), 460, (17, 201, 160, 65)),
        ((W - 340, H - 360), 360, (248, 180, 94, 50)),
    ]:
        glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gdraw = ImageDraw.Draw(glow)
        x0, y0 = offset
        gdraw.ellipse((x0, y0, x0 + radius, y0 + radius), fill=color)
        img.alpha_composite(glow)

    # subtle grid
    for x in range(0, W, 90):
        draw.line((x, 0, x, H), fill=(255, 255, 255, 14), width=1)
    for y in range(0, H, 90):
        draw.line((0, y, W, y), fill=(255, 255, 255, 10), width=1)

    return img, draw


def rounded(draw, box, fill, outline=None, width=1, radius=32):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def pill(draw, xy, text, fill=(17, 28, 46, 220), text_fill=WHITE, border=(255, 255, 255, 26)):
    x, y = xy
    padding_x = 22
    padding_y = 14
    bbox = draw.textbbox((0, 0), text, font=LABEL)
    w = bbox[2] - bbox[0] + padding_x * 2
    h = bbox[3] - bbox[1] + padding_y * 2
    rounded(draw, (x, y, x + w, y + h), fill, outline=border, width=2 if border else 1, radius=26)
    draw.text((x + padding_x, y + padding_y - 2), text, font=LABEL, fill=text_fill)
    return x + w, y + h


def wrap(draw, text, font_obj, max_width):
    words = text.split()
    lines = []
    current = ""
    for word in words:
        trial = word if not current else current + " " + word
        bbox = draw.textbbox((0, 0), trial, font=font_obj)
        if bbox[2] - bbox[0] <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def text_block(draw, x, y, text, font_obj, fill, max_width, line_gap=10):
    lines = wrap(draw, text, font_obj, max_width)
    yy = y
    for line in lines:
        draw.text((x, yy), line, font=font_obj, fill=fill)
        bbox = draw.textbbox((x, yy), line, font=font_obj)
        yy += (bbox[3] - bbox[1]) + line_gap
    return yy


def footer(draw, left, right):
    draw.text((78, H - 92), left, font=BODY_SM, fill=MUTED)
    bbox = draw.textbbox((0, 0), right, font=BODY_SM)
    draw.text((W - 78 - (bbox[2] - bbox[0]), H - 92), right, font=BODY_SM, fill=MUTED)


def fake_window(draw, box, title):
    rounded(draw, box, fill=(11, 18, 31, 210), outline=(255, 255, 255, 30), width=2, radius=34)
    x1, y1, x2, y2 = box
    draw.rectangle((x1, y1, x2, y1 + 64), fill=(255, 255, 255, 16))
    for i, color in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        draw.ellipse((x1 + 24 + i * 24, y1 + 20, x1 + 38 + i * 24, y1 + 34), fill=color)
    draw.text((x1 + 78, y1 + 18), title, font=BODY_SM, fill=MUTED)


def draw_obs_mock(draw, box):
    fake_window(draw, box, "PPTBridge SK in OBS")
    x1, y1, x2, y2 = box
    inner = (x1 + 28, y1 + 88, x2 - 28, y2 - 28)
    mid = (inner[0] + inner[2]) // 2
    preview_height = 250
    lower_top = inner[1] + preview_height + 24
    preview = (inner[0], inner[1], mid - 12, inner[1] + preview_height)
    program = (mid + 12, inner[1], inner[2], inner[1] + preview_height)
    sources = (inner[0], lower_top, inner[0] + 250, inner[3])
    controls = (inner[2] - 250, lower_top, inner[2], inner[3])
    mixer = (sources[2] + 24, inner[1] + 386, controls[0] - 24, inner[3])
    mixer = (sources[2] + 24, lower_top, controls[0] - 24, inner[3])

    rounded(draw, preview, fill=CARD_2, radius=24)
    rounded(draw, program, fill=CARD_2, radius=24)
    rounded(draw, sources, fill=CARD, radius=24)
    rounded(draw, controls, fill=CARD, radius=24)
    rounded(draw, mixer, fill=CARD, radius=24)

    draw.text((preview[0] + 20, preview[1] + 16), "Preview", font=LABEL, fill=MUTED)
    draw.text((program[0] + 20, program[1] + 16), "Program", font=LABEL, fill=MUTED)
    slide = (preview[0] + 28, preview[1] + 56, preview[2] - 28, preview[3] - 28)
    rounded(draw, slide, fill=(24, 18, 78), radius=18)
    draw.rectangle((slide[0] + 14, slide[1] + 14, slide[0] + 20, slide[3] - 14), fill=(165, 116, 255))
    draw.rectangle((slide[2] - 110, slide[1], slide[2], slide[3]), fill=(225, 214, 239))
    draw.text((slide[0] + 120, slide[1] + 122), "PPTBridge SK", font=H3, fill=WHITE)
    draw.text((slide[0] + 120, slide[1] + 170), "PowerPoint source in OBS", font=BODY_SM, fill=(211, 215, 240))

    rounded(draw, (program[0] + 28, program[1] + 56, program[2] - 28, program[3] - 28), fill=DARK, radius=18)
    draw.text((sources[0] + 18, sources[1] + 18), "Sources", font=LABEL, fill=MUTED)
    rounded(draw, (sources[0] + 18, sources[1] + 58, sources[2] - 18, sources[1] + 118), fill=(47, 74, 136), radius=14)
    draw.text((sources[0] + 34, sources[1] + 77), "PPTBridge SK Slide", font=BODY_SM, fill=WHITE)

    draw.text((controls[0] + 18, controls[1] + 18), "Controls", font=LABEL, fill=MUTED)
    for i, label in enumerate(["Start Streaming", "Start Recording", "Studio Mode"]):
        yy = controls[1] + 58 + i * 62
        rounded(draw, (controls[0] + 18, yy, controls[2] - 18, yy + 46), fill=(255, 255, 255, 16), radius=12)
        draw.text((controls[0] + 34, yy + 10), label, font=BODY_SM, fill=WHITE)

    draw.text((mixer[0] + 18, mixer[1] + 18), "Presenter workflow", font=LABEL, fill=MUTED)
    text_block(
        draw,
        mixer[0] + 18,
        mixer[1] + 62,
        "Clean slide output for program. Separate presenter view with notes for the stage monitor.",
        BODY_SM,
        TEXT,
        mixer[2] - mixer[0] - 36,
        line_gap=8,
    )


def draw_presenter_panel(draw, box):
    fake_window(draw, box, "PPTBridge SK Presenter")
    x1, y1, x2, y2 = box
    inner = (x1 + 28, y1 + 88, x2 - 28, y2 - 28)
    top = (inner[0], inner[1], inner[2], inner[1] + 74)
    content_top = inner[1] + 92
    available_width = inner[2] - inner[0]
    available_height = inner[3] - content_top - 20
    main_width = int(available_width * 0.58)
    main = (inner[0], content_top, inner[0] + main_width, inner[3] - 20)
    side_x = main[2] + 24
    side_gap = 22
    side_top_height = int((available_height - side_gap) * 0.42)
    side_top = (side_x, content_top, inner[2], content_top + side_top_height)
    side_bottom = (side_x, side_top[3] + side_gap, inner[2], inner[3] - 20)

    rounded(draw, top, fill=(255, 255, 255, 16), radius=22)
    draw.text((top[0] + 18, top[1] + 18), "Presenter View", font=H3, fill=WHITE)
    draw.text((top[2] - 150, top[1] + 20), "08:32", font=H3, fill=ACCENT)

    rounded(draw, main, fill=DARK, radius=24)
    rounded(draw, side_top, fill=CARD, radius=24)
    rounded(draw, side_bottom, fill=CARD, radius=24)
    rounded(draw, (main[0] + 18, main[1] + 18, main[2] - 18, main[3] - 18), fill=(24, 18, 78), radius=18)
    draw.rectangle((main[0] + 40, main[1] + 40, main[0] + 50, main[3] - 40), fill=(165, 116, 255))
    draw.rectangle((main[2] - 150, main[1] + 18, main[2] - 18, main[3] - 18), fill=(227, 218, 237))

    draw.text((side_top[0] + 18, side_top[1] + 18), "Next Slide", font=LABEL, fill=MUTED)
    rounded(draw, (side_top[0] + 18, side_top[1] + 58, side_top[2] - 18, side_top[3] - 18), fill=(23, 34, 54), radius=18)
    draw.text((side_top[0] + 36, side_top[1] + 128), "Up next preview", font=BODY_SM, fill=TEXT)

    draw.text((side_bottom[0] + 18, side_bottom[1] + 18), "Presenter Notes", font=LABEL, fill=MUTED)
    notes = "Speaker notes stay on the confidence monitor while the audience sees only the clean slide."
    text_block(draw, side_bottom[0] + 18, side_bottom[1] + 64, notes, BODY_SM, TEXT, side_bottom[2] - side_bottom[0] - 36, line_gap=10)


def draw_presenter_mini(draw, box):
    rounded(draw, box, fill=CARD_2, outline=(255, 255, 255, 26), width=2, radius=28)
    x1, y1, x2, y2 = box
    draw.text((x1 + 26, y1 + 22), "Presenter Source", font=H3, fill=WHITE)
    draw.text((x1 + 26, y1 + 64), "Notes, next slide, timer", font=BODY_SM, fill=MUTED)

    top = (x1 + 24, y1 + 120, x2 - 24, y1 + 182)
    content_top = y1 + 206
    content_bottom = y2 - 26
    content_height = content_bottom - content_top
    main = (x1 + 24, content_top, x1 + 300, content_bottom)
    side_x1 = main[2] + 20
    side_top_height = int((content_height - 18) * 0.36)
    side_top = (side_x1, content_top, x2 - 24, content_top + side_top_height)
    side_bottom = (side_x1, side_top[3] + 18, x2 - 24, content_bottom)

    rounded(draw, top, fill=(255, 255, 255, 14), radius=18)
    draw.text((top[0] + 18, top[1] + 14), "Presenter View", font=LABEL, fill=WHITE)
    draw.text((top[2] - 112, top[1] + 14), "08:32", font=LABEL, fill=ACCENT)

    rounded(draw, main, fill=DARK, radius=20)
    rounded(draw, (main[0] + 16, main[1] + 16, main[2] - 16, main[3] - 16), fill=(24, 18, 78), radius=16)
    draw.rectangle((main[0] + 28, main[1] + 30, main[0] + 35, main[3] - 28), fill=(165, 116, 255))
    draw.rectangle((main[2] - 92, main[1] + 16, main[2] - 16, main[3] - 16), fill=(227, 218, 237))

    rounded(draw, side_top, fill=CARD, radius=20)
    rounded(draw, side_bottom, fill=CARD, radius=20)
    draw.text((side_top[0] + 16, side_top[1] + 14), "Next Slide", font=LABEL, fill=MUTED)
    draw.text((side_bottom[0] + 16, side_bottom[1] + 14), "Presenter Notes", font=LABEL, fill=MUTED)


def card_launch(path):
    img, draw = make_canvas()
    pill(draw, (78, 76), "macOS release live", fill=(83, 212, 190, 38), text_fill=WHITE, border=(83, 212, 190))
    draw.text((78, 186), "PPTBridge SK", font=H1, fill=TEXT)
    draw.text((78, 290), "for OBS", font=H1, fill=ACCENT)
    text_block(
        draw,
        78,
        414,
        "Native macOS plugin that brings PowerPoint into OBS as a real source with a clean slide output and a separate presenter view.",
        BODY,
        TEXT,
        760,
        line_gap=12,
    )
    pill(draw, (78, 618), "PowerPoint as an OBS source")
    pill(draw, (430, 618), "Presenter notes")
    pill(draw, (686, 618), "Clicker-ready")
    draw_obs_mock(draw, (78, 726, W - 78, H - 138))
    footer(draw, "Built by Srdjan Kotarlic", "github.com/srdjankotarlic/pptbridge-sk-obs")
    img.save(path)


def card_workflow(path):
    img, draw = make_canvas()
    pill(draw, (78, 76), "conference workflow", fill=(248, 180, 94, 38), text_fill=WHITE, border=(248, 180, 94))
    draw.text((78, 186), "One deck.", font=H1, fill=TEXT)
    draw.text((78, 290), "Two outputs.", font=H1, fill=ACCENT_2)
    text_block(
        draw,
        78,
        414,
        "Use one PPTX for the audience feed and a separate presenter layout with notes, timer, and next-slide context.",
        BODY,
        TEXT,
        760,
        line_gap=12,
    )
    left = (78, 580, 640, 1180)
    right = (710, 580, W - 78, 1180)
    rounded(draw, left, fill=CARD_2, outline=(255, 255, 255, 26), width=2, radius=34)
    rounded(draw, right, fill=CARD_2, outline=(255, 255, 255, 26), width=2, radius=34)
    draw.text((110, 620), "Slide Source", font=H2, fill=WHITE)
    draw.text((742, 620), "Presenter Source", font=H2, fill=WHITE)
    rounded(draw, (110, 706, 608, 1074), fill=DARK, radius=26)
    rounded(draw, (132, 728, 586, 1052), fill=(24, 18, 78), radius=20)
    draw.rectangle((152, 748, 160, 1032), fill=(165, 116, 255))
    draw.rectangle((470, 728, 586, 1052), fill=(227, 218, 237))
    draw.text((232, 868), "Program feed", font=H3, fill=WHITE)
    draw.text((225, 914), "Clean slide only", font=BODY_SM, fill=MUTED)
    draw_presenter_mini(draw, (742, 706, W - 110, 1074))
    pill(draw, (78, 1206), "PPTX input")
    pill(draw, (302, 1206), "Presenter notes")
    pill(draw, (598, 1206), "Timer + next slide")
    pill(draw, (954, 1206), "Stage monitor")
    footer(draw, "PPTBridge SK for OBS", "Free macOS release")
    img.save(path)


def card_download(path):
    img, draw = make_canvas()
    pill(draw, (78, 76), "free download", fill=(83, 212, 190, 38), text_fill=WHITE, border=(83, 212, 190))
    draw.text((78, 186), "Download", font=H1, fill=TEXT)
    draw.text((78, 290), "PPTBridge SK", font=H1, fill=ACCENT)
    text_block(
        draw,
        78,
        414,
        "Native macOS OBS plugin for PowerPoint slides and presenter view. Free to use now. Windows version planned next.",
        BODY,
        TEXT,
        760,
        line_gap=12,
    )
    rounded(draw, (78, 592, W - 78, 836), fill=(9, 14, 24, 220), outline=(83, 212, 190, 110), width=2, radius=34)
    draw.text((112, 634), "Latest release", font=LABEL, fill=MUTED)
    release_url = "github.com/srdjankotarlic/pptbridge-sk-obs/releases/latest"
    text_block(draw, 112, 688, release_url, MONO, WHITE, W - 240, line_gap=12)

    features = [
        "PowerPoint in OBS as a source",
        "Clean slide output for program",
        "Presenter notes for stage monitor",
        "Clicker and hotkey workflow",
    ]
    y = 902
    for feature in features:
        draw.ellipse((92, y + 10, 112, y + 30), fill=ACCENT)
        draw.text((128, y), feature, font=BODY, fill=TEXT)
        y += 82

    rounded(draw, (W - 424, 934, W - 78, 1188), fill=CARD_2, outline=(255, 255, 255, 24), width=2, radius=30)
    draw.text((W - 390, 972), "Built by", font=LABEL, fill=MUTED)
    draw.text((W - 390, 1024), "Srdjan Kotarlic", font=H3, fill=WHITE)
    draw.text((W - 390, 1084), "macOS v0.2.0", font=BODY_SM, fill=ACCENT_2)
    footer(draw, "Use with LinkedIn post copy", "Share screenshots + release link")
    img.save(path)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    card_launch(OUT_DIR / "pptbridge-sk-linkedin-01-launch.png")
    card_workflow(OUT_DIR / "pptbridge-sk-linkedin-02-workflow.png")
    card_download(OUT_DIR / "pptbridge-sk-linkedin-03-download.png")
    print("Generated social assets in", OUT_DIR)


if __name__ == "__main__":
    main()
