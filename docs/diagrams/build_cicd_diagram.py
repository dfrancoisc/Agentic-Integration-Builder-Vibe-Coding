"""Render the CI/CD Pipeline Flow diagram (Section 10.4) as a PNG image.

Outputs:  docs/img/16_cicd_pipeline.png

Requires: pip install Pillow
"""
import os
from PIL import Image, ImageDraw, ImageFont

DOCS = os.path.dirname(os.path.dirname(__file__)) if os.path.basename(os.path.dirname(__file__)) == "diagrams" else os.path.dirname(__file__)
OUT = os.path.join(os.path.dirname(DOCS), "docs", "img", "16_cicd_pipeline.png")

# Ensure output directory exists
os.makedirs(os.path.dirname(OUT), exist_ok=True)

# ── fonts ──────────────────────────────────────────────────────────────────
def load_font(size, bold=False):
    paths = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()

FONT_TITLE = load_font(26)
FONT_SUBTITLE = load_font(14)
FONT_STEP_LABEL = load_font(13)
FONT_STEP_TEXT = load_font(12)
FONT_ACTOR = load_font(11)
FONT_NUM = load_font(13)
FONT_DETAIL_ACTOR = load_font(12)
FONT_DETAIL_TEXT = load_font(12)
FONT_LEGEND = load_font(11)
FONT_API = load_font(11)

# ── colours ────────────────────────────────────────────────────────────────
BG = (248, 249, 252)
CARD_BG = (255, 255, 255)
CARD_SHADOW = (230, 232, 238)
TITLE_COLOR = (26, 26, 46)
SUBTITLE_COLOR = (136, 144, 164)
ARROW_COLOR = (176, 184, 204)
TEXT_COLOR = (58, 63, 84)
DETAIL_LINE = (238, 240, 245)
WHITE = (255, 255, 255)

THEMES = {
    "builder": {"bg": (238, 243, 255), "border": (184, 205, 248), "icon": (74, 124, 247), "label": (50, 100, 214), "actor_bg": (219, 230, 253), "actor_fg": (44, 89, 184)},
    "agent":   {"bg": (243, 238, 255), "border": (201, 181, 240), "icon": (124, 77, 255),  "label": (98, 54, 201),  "actor_bg": (230, 219, 250), "actor_fg": (90, 47, 179)},
    "iris":    {"bg": (232, 248, 245), "border": (163, 221, 210), "icon": (0, 168, 142),   "label": (0, 138, 116),  "actor_bg": (201, 240, 231), "actor_fg": (0, 122, 102)},
    "git":     {"bg": (255, 245, 235), "border": (240, 207, 160), "icon": (232, 133, 12),  "label": (192, 110, 0),  "actor_bg": (253, 229, 197), "actor_fg": (165, 94, 0)},
    "cicd":    {"bg": (237, 249, 238), "border": (168, 219, 169), "icon": (45, 164, 78),   "label": (26, 127, 55),  "actor_bg": (212, 240, 213), "actor_fg": (24, 105, 46)},
    "deploy":  {"bg": (232, 235, 245), "border": (169, 178, 214), "icon": (26, 26, 46),    "label": (26, 26, 46),   "actor_bg": (209, 213, 230), "actor_fg": (26, 26, 46)},
}

# ── pipeline steps ─────────────────────────────────────────────────────────
STEPS = [
    ("builder", "REQUEST",  "Int. Eng. asks agent\nto create a production", "Int. Eng."),
    ("agent",   "COMPILE",  "$System.OBJ.Compile()\ncreates the class",   "Agent"),
    ("iris",    "HOOK",     "%SourceControl fires,\nexports to Git repo",  "IRIS"),
    ("git",     "PUSH",     "Int. Eng. commits\nand pushes to GitLab",       "Int. Eng."),
    ("cicd",    "VALIDATE", "CI/CD pipeline:\nlint, validate, test",       "GitLab CI"),
    ("deploy",  "DEPLOY",   "On success: staging\nthen production",        "Pipeline"),
]

DETAILS = [
    ("builder", "Int. Eng.",  "Asks the agent to create a new production, DTL, BPL, or routing rule via the chatbot"),
    ("agent",   "Agent",     "Creates the class definition via $System.OBJ.Compile() using standard %Dictionary APIs"),
    ("iris",    "IRIS",      "%SourceControl hook fires automatically, exports the class definition to the local Git working directory"),
    ("git",     "Int. Eng.",  "Commits the exported class definitions and pushes to the GitLab remote repository"),
    ("cicd",    "GitLab CI", "CI/CD pipeline triggers: lint class definitions, validate configuration, run integration tests"),
    ("deploy",  "Pipeline",  "On success: deploy to staging environment, then promote to production after approval"),
]

# ── layout constants ───────────────────────────────────────────────────────
PIPE_TOP = 80
STEP_W = 138
STEP_H = 130
STEP_GAP = 18
ARROW_W = 26
PIPE_TOTAL = len(STEPS) * STEP_W + (len(STEPS) - 1) * (ARROW_W + STEP_GAP * 2)

DETAIL_H = 36
DETAIL_TOP = PIPE_TOP + STEP_H + 38
LEGEND_TOP = DETAIL_TOP + len(DETAILS) * DETAIL_H + 20

W = PIPE_TOTAL + 120          # fit content with side margins
H = LEGEND_TOP + 32           # trim to just below the legend
CARD_X, CARD_Y = 28, 0
CARD_W, CARD_H = W - 56, H
CARD_R = 16
PIPE_LEFT = (W - PIPE_TOTAL) // 2
DETAIL_LEFT = PIPE_LEFT
DETAIL_RIGHT = W - PIPE_LEFT


# ── drawing helpers ────────────────────────────────────────────────────────
def rounded_rect(draw, xy, r, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def circle(draw, cx, cy, r, fill):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def centered_text(draw, cx, cy, text, font, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text((cx - tw // 2, cy - th // 2), text, font=font, fill=fill)


def multiline_centered(draw, cx, y, text, font, fill, line_spacing=4):
    lines = text.split("\n")
    total_h = 0
    widths = []
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        widths.append(bbox[2] - bbox[0])
        total_h += bbox[3] - bbox[1] + line_spacing
    total_h -= line_spacing
    cy = y
    for i, line in enumerate(lines):
        bbox = draw.textbbox((0, 0), line, font=font)
        lw = bbox[2] - bbox[0]
        lh = bbox[3] - bbox[1]
        draw.text((cx - lw // 2, cy), line, font=font, fill=fill)
        cy += lh + line_spacing
    return cy


def draw_arrow(draw, x, cy):
    """Draw a small right-pointing arrow."""
    aw = 20
    ah = 7
    draw.line([(x, cy), (x + aw, cy)], fill=ARROW_COLOR, width=2)
    # arrowhead
    draw.polygon([
        (x + aw, cy),
        (x + aw - ah, cy - ah),
        (x + aw - ah, cy + ah),
    ], fill=ARROW_COLOR)


# ── step icons (simple geometric) ─────────────────────────────────────────
def draw_icon(draw, cx, cy, r, theme_name, icon_color):
    """Draw a small thematic icon inside the circle."""
    circle(draw, cx, cy, r, icon_color)
    ic = WHITE
    if theme_name == "builder":
        # person silhouette
        circle(draw, cx, cy - 4, 5, ic)
        draw.arc([cx - 8, cy + 1, cx + 8, cy + 14], 0, 180, fill=ic, width=2)
    elif theme_name == "agent":
        # terminal bracket
        draw.text((cx - 7, cy - 8), ">_", font=load_font(13), fill=ic)
    elif theme_name == "iris":
        # gear / asterisk
        for angle in range(0, 360, 60):
            import math
            ex = cx + int(7 * math.cos(math.radians(angle)))
            ey = cy + int(7 * math.sin(math.radians(angle)))
            draw.line([(cx, cy), (ex, ey)], fill=ic, width=2)
    elif theme_name == "git":
        # branching dots
        circle(draw, cx, cy, 3, ic)
        circle(draw, cx + 7, cy - 6, 2, ic)
        circle(draw, cx - 7, cy + 6, 2, ic)
        draw.line([(cx, cy), (cx + 5, cy - 4)], fill=ic, width=1)
        draw.line([(cx, cy), (cx - 5, cy + 4)], fill=ic, width=1)
    elif theme_name == "cicd":
        # checkmark
        draw.line([(cx - 6, cy), (cx - 2, cy + 5), (cx + 7, cy - 5)], fill=ic, width=2)
    elif theme_name == "deploy":
        # play triangle
        draw.polygon([
            (cx - 4, cy - 7),
            (cx - 4, cy + 7),
            (cx + 7, cy),
        ], fill=ic)


# ── main render ────────────────────────────────────────────────────────────
img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

# Card background with shadow
rounded_rect(draw, (CARD_X + 3, CARD_Y + 3, CARD_X + CARD_W + 3, CARD_Y + CARD_H + 3), CARD_R, fill=CARD_SHADOW)
rounded_rect(draw, (CARD_X, CARD_Y, CARD_X + CARD_W, CARD_Y + CARD_H), CARD_R, fill=CARD_BG)

# Title
draw.text((PIPE_LEFT, 18), "Section 10.4 -- CI/CD Pipeline Flow", font=FONT_TITLE, fill=TITLE_COLOR)
draw.text((PIPE_LEFT, 48), "How agent-created artifacts flow from conversation to production deployment", font=FONT_SUBTITLE, fill=SUBTITLE_COLOR)

# ── draw pipeline steps ────────────────────────────────────────────────────
x = PIPE_LEFT
step_cy = PIPE_TOP + STEP_H // 2

for i, (theme_name, label, text, actor) in enumerate(STEPS):
    t = THEMES[theme_name]

    # Step card
    sx0, sy0 = x, PIPE_TOP
    sx1, sy1 = x + STEP_W, PIPE_TOP + STEP_H
    rounded_rect(draw, (sx0, sy0, sx1, sy1), 10, fill=t["bg"], outline=t["border"], width=2)

    # Icon circle
    icon_cx = sx0 + STEP_W // 2
    icon_cy = sy0 + 24
    draw_icon(draw, icon_cx, icon_cy, 18, theme_name, t["icon"])

    # Label
    centered_text(draw, sx0 + STEP_W // 2, sy0 + 50, label, FONT_STEP_LABEL, t["label"])

    # Text
    multiline_centered(draw, sx0 + STEP_W // 2, sy0 + 68, text, FONT_STEP_TEXT, TEXT_COLOR, line_spacing=3)

    # Actor badge
    bbox = draw.textbbox((0, 0), actor, font=FONT_ACTOR)
    aw = bbox[2] - bbox[0] + 14
    ah = bbox[3] - bbox[1] + 6
    acx = sx0 + STEP_W // 2
    aby = sy1 - 24
    rounded_rect(draw, (acx - aw // 2, aby, acx + aw // 2, aby + ah), 8, fill=t["actor_bg"])
    centered_text(draw, acx, aby + ah // 2, actor, FONT_ACTOR, t["actor_fg"])

    # Arrow to next step
    if i < len(STEPS) - 1:
        arrow_x = sx1 + STEP_GAP
        draw_arrow(draw, arrow_x, step_cy)

    x += STEP_W + ARROW_W + STEP_GAP * 2

# ── separator line ─────────────────────────────────────────────────────────
sep_y = DETAIL_TOP - 16
draw.line([(DETAIL_LEFT, sep_y), (DETAIL_RIGHT, sep_y)], fill=DETAIL_LINE, width=1)

# ── detail rows ────────────────────────────────────────────────────────────
for i, (theme_name, actor, text) in enumerate(DETAILS):
    t = THEMES[theme_name]
    ry = DETAIL_TOP + i * DETAIL_H
    num_cx = DETAIL_LEFT + 14
    num_cy = ry + DETAIL_H // 2

    # Number circle
    circle(draw, num_cx, num_cy, 13, t["icon"])
    centered_text(draw, num_cx, num_cy, str(i + 1), FONT_NUM, WHITE)

    # Actor
    draw.text((DETAIL_LEFT + 36, ry + DETAIL_H // 2 - 7), actor, font=FONT_DETAIL_ACTOR, fill=t["label"])

    # Text
    text_x = DETAIL_LEFT + 120
    draw.text((text_x, ry + DETAIL_H // 2 - 7), text, font=FONT_DETAIL_TEXT, fill=TEXT_COLOR)

    # Bottom line
    if i < len(DETAILS) - 1:
        draw.line([(DETAIL_LEFT, ry + DETAIL_H), (DETAIL_RIGHT, ry + DETAIL_H)], fill=DETAIL_LINE, width=1)

# ── legend ─────────────────────────────────────────────────────────────────
legend_items = [
    ("builder", "Interface Engineer (End User)"),
    ("agent",   "AI Agent"),
    ("iris",    "IRIS Platform"),
    ("git",     "Git / Version Control"),
    ("cicd",    "CI/CD Pipeline"),
    ("deploy",  "Deployment"),
]
legend_x = PIPE_LEFT
for theme_name, legend_text in legend_items:
    t = THEMES[theme_name]
    circle(draw, legend_x + 5, LEGEND_TOP + 5, 5, t["icon"])
    draw.text((legend_x + 16, LEGEND_TOP - 1), legend_text, font=FONT_LEGEND, fill=SUBTITLE_COLOR)
    bbox = draw.textbbox((0, 0), legend_text, font=FONT_LEGEND)
    legend_x += bbox[2] - bbox[0] + 36

# ── save ───────────────────────────────────────────────────────────────────
img.save(OUT, "PNG", dpi=(144, 144))
print(f"Saved: {OUT}  ({img.width}x{img.height})")
