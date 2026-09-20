#!/usr/bin/env python3
"""Generates the Sessions / Ideation / Diagrams artboards for the three directions."""
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "project")
os.makedirs(OUT, exist_ok=True)

SERIF = "ui-serif, 'New York', Newsreader, Georgia, serif"
MONO_A = "ui-monospace, 'SF Mono', 'IBM Plex Mono', monospace"
MONO_B = "ui-monospace, 'SF Mono', 'Geist Mono', monospace"
MONO_C = "ui-monospace, 'SF Mono', Menlo, monospace"
ROUND = "ui-rounded, 'SF Pro Rounded', Nunito, system-ui, sans-serif"
SANS = "-apple-system, 'SF Pro Text', system-ui, 'Helvetica Neue', sans-serif"

ICONS = [
    ("Findings", "M12 3v4M12 17v4M3 12h4M17 12h4M7 12a5 5 0 1 0 10 0a5 5 0 1 0-10 0"),
    ("Work", "M4 5h4v14H4zM10 5h4v9h-4zM16 5h4v12h-4z"),
    ("Sessions", "M3 5h18v14H3zM7 10l3 2-3 2M12 15h4"),
    ("Ideation", "M9 18h6M10 21h4M12 3a6 6 0 0 0-4 10.5c.7.7 1 1.5 1 2.5h6c0-1 .3-1.8 1-2.5A6 6 0 0 0 12 3z"),
    ("Diagrams", "M3 4h7v6H3zM14 14h7v6h-7zM14 4h7v6h-7zM10 7h4M17.5 10v4"),
]
COUNTS = {"Findings": "14", "Work": "8", "Sessions": "2", "Ideation": "5", "Diagrams": ""}
GEAR = "M12 9a3 3 0 1 0 0 6a3 3 0 0 0 0-6zM12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"


def svg(d, size, sw="1.6"):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="{sw}" '
            f'stroke-linecap="round" stroke-linejoin="round"><path d="{d}"></path></svg>')


def page(title, fonts, link_css, root_style, inner, accent, swatches):
    sw = ",".join(f'"{s}"' for s in swatches)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?{fonts}&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0}}
button{{font:inherit;cursor:pointer}}
{link_css}
</style>
</helmet>
<div style="width: 1440px; height: 900px; box-sizing: border-box; overflow: hidden; {root_style}">
{inner}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"accent":{{"editor":"color","default":"{accent}","options":[{sw}]}},"$preview":{{"width":1440,"height":900}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{ accent: this.props.accent ?? '{accent}' }};
  }}
}}
</script>
</body>
</html>
"""


# ───────────────────────────── A · Ledger ─────────────────────────────
A_BTN = "height: 28px; padding: 0 12px; border: 1px solid #D6D1C4; border-radius: 6px; background: #FFFEFB; color: #1C1B18; font-size: 12px;"
A_PRI = "height: 28px; padding: 0 14px; border: 0; border-radius: 6px; background: {{accent}}; color: #FFFFFF; font-size: 12px; font-weight: 600;"
A_LABEL = "font-size: 11px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #6B675E;"


def a_shell(sel, body):
    nav = ""
    for label, d in ICONS:
        on = label == sel
        bg, fg, w = ("{{accent}}", "#FFFFFF", 600) if on else ("transparent", "#3D3A33", 400)
        nav += (f'<button style="height: 36px; display: flex; align-items: center; gap: 9px; padding: 0 10px; border: 0; border-radius: 6px; text-align: left; '
                f'background: {bg}; color: {fg}; font-weight: {w};">{svg(d, 18)}<span style="flex-grow: 1;">{label}</span>'
                f'<span style="font-size: 11px;">{COUNTS[label]}</span></button>\n')
    inner = f"""
  <div style="height: 46px; flex-shrink: 0; box-sizing: border-box; padding: 0 16px 0 20px; display: flex; align-items: center; gap: 12px; border-bottom: 1px solid #E2DED4; background: #EFECE4;">
    <div style="font-family: {SERIF}; font-size: 17px; font-weight: 600;">studyhub</div>
    <div style="font-family: {MONO_A}; font-size: 11.5px; color: #6B675E;">~/Developer/studyhub · main</div>
    <div style="flex-grow: 1;"></div>
    <button style="{A_BTN} height: 26px;">Run project</button>
    <button style="{A_BTN} height: 26px;">Files</button>
  </div>
  <div style="flex-grow: 1; min-height: 0; display: flex;">
    <div style="width: 208px; flex-shrink: 0; box-sizing: border-box; padding: 14px 10px; display: flex; flex-direction: column; gap: 4px; background: #EFECE4; border-right: 1px solid #E2DED4;">
      <button style="height: 36px; display: flex; align-items: center; gap: 9px; padding: 0 10px; border: 1px solid #D6D1C4; border-radius: 6px; background: #FFFEFB; color: #1C1B18; font-weight: 500;">{svg("M12 3a9 9 0 1 0 0 18a9 9 0 0 0 0-18zM12 8v8M8 12h8", 18)}<span>Open project</span></button>
      <div style="height: 1px; background: #DDD8CC; margin: 10px 2px 6px;"></div>
      {nav}
      <div style="flex-grow: 1;"></div>
      <button style="height: 36px; display: flex; align-items: center; gap: 9px; padding: 0 10px; border: 0; border-radius: 6px; background: transparent; color: #3D3A33; text-align: left;">{svg(GEAR, 18)}<span>Settings</span></button>
    </div>
    {body}
  </div>"""
    return page(f"{sel} — Ledger", "family=Newsreader:opsz,wght@6..72,400;6..72,500;6..72,600&amp;family=IBM+Plex+Mono:wght@400;500",
                "a{color:#24408E}a:hover{color:#182C66}",
                f"display: flex; flex-direction: column; background: #F7F5F0; color: #1C1B18; font-family: {SANS}; font-size: 13px;",
                inner, "#24408E", ["#24408E", "#1F5C45", "#8A3B12", "#1C1B18"])


def a_header(title, status, tools):
    return f"""<div style="height: 72px; flex-shrink: 0; box-sizing: border-box; padding: 0 28px; display: flex; align-items: center; gap: 14px; border-bottom: 1px solid #E2DED4;">
        <h1 style="margin: 0; font-family: {SERIF}; font-size: 30px; font-weight: 500; letter-spacing: -0.01em;">{title}</h1>
        <div style="color: #6B675E; padding-top: 8px;">{status}</div>
        <div style="flex-grow: 1;"></div>
        {tools}
      </div>"""


def a_filter(title, groups):
    out = f'<div style="width: 252px; flex-shrink: 0; box-sizing: border-box; padding: 18px 16px; display: flex; flex-direction: column; gap: 22px; border-right: 1px solid #E2DED4; background: #F3F0E9;">\n<div style="font-family: {SERIF}; font-size: 15px; font-weight: 600;">{title}</div>\n'
    for gt, opts in groups:
        out += f'<div style="display: flex; flex-direction: column; gap: 2px;"><div style="{A_LABEL} padding-bottom: 6px;">{gt}</div>\n'
        for label, n, on in opts:
            bg, bd, w = ("#FFFEFB", "#D6D1C4", 600) if on else ("transparent", "transparent", 400)
            out += (f'<button style="height: 30px; display: flex; align-items: center; gap: 8px; padding: 0 10px; border: 1px solid {bd}; border-radius: 6px; background: {bg}; color: #1C1B18; text-align: left; font-weight: {w};">'
                    f'<span style="flex-grow: 1;">{label}</span><span style="font-family: {MONO_A}; font-size: 11px; color: #6B675E;">{n}</span></button>\n')
        out += "</div>\n"
    return out + "</div>"


def term(lines, mono, pad="14px 16px", radius="0"):
    body = "\n".join(f"<div>{l}</div>" for l in lines)
    return (f'<div style="flex-grow: 1; min-height: 0; box-sizing: border-box; padding: {pad}; border-radius: {radius}; background: #14161A; color: #D7DBE0; '
            f'font-family: {mono}; font-size: 12px; line-height: 1.6; display: flex; flex-direction: column; gap: 2px;">{body}</div>')


T42 = [
    '<span style="color: #7C8796;">fix/42-course-scroll · ~/.devdesk/wt/studyhub-42 · base main@9c2e410</span>',
    '<span style="color: #7C8796;">10:49</span> <span style="color: #9CC0FF;">Verifier</span> finished: 18 unit checks passed, no runtime reproduction attempted.',
    '<span style="color: #7C8796;">11:07</span> <span style="color: #E7C067;">Reviewer</span> (activity only) flagged a missing cleanup on unmount.',
    '<span style="color: #7C8796;">11:12</span> <span style="color: #7ED492;">Codex</span> patched useScrollRestore.ts',
    '<span style="color: #7ED492;">▍</span><span style="color: #9BA3AE;"> Implementing · phase 3 of 4</span>',
]
T57 = [
    '<span style="color: #7C8796;">feat/57-exam-recovery · ~/.devdesk/wt/studyhub-57</span>',
    '<span style="color: #7C8796;">09:58</span> <span style="color: #7ED492;">Claude</span> finished the investigation and wrote the plan.',
    '<span style="color: #E7C067;">Waiting for a decision before implementation continues</span>',
    '<span style="color: #9BA3AE;">[The run&#39;s question appears here, in its own words.]</span>',
    '<span style="color: #E7C067;">▍</span>',
]

SESSIONS = [
    ("#42 Preserve course-list position", "Codex · running", "#1F8B4C", "24m"),
    ("#57 Improve exam recovery", "Claude · waiting for input", "#B7791F", "1h 12m"),
    ("studyhub dev server", "Project run · running", "#1F8B4C", "3h"),
    ("Findings hunt", "Door · ended", "#8A9099", ""),
    ("zsh", "Terminal", "#8A9099", ""),
]


def a_sessions():
    rows = ""
    for i, (t, s, dot, clock) in enumerate(SESSIONS):
        on = i == 0
        bg = "#FFFEFB" if on else "transparent"
        rows += (f'<button style="display: grid; grid-template-columns: 10px minmax(0, 1fr) auto; column-gap: 10px; align-items: center; min-height: 50px; padding: 0 12px; border: 0; border-bottom: 1px solid #E2DED4; background: {bg}; color: #1C1B18; text-align: left;">'
                 f'<span style="width: 7px; height: 7px; border-radius: 4px; background: {dot};"></span>'
                 f'<span style="display: flex; flex-direction: column; gap: 2px; min-width: 0;"><span style="font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{t}</span><span style="font-size: 11.5px; color: #6B675E;">{s}</span></span>'
                 f'<span style="font-family: {MONO_A}; font-size: 11px; color: #6B675E;">{clock}</span></button>\n')
    body = f"""<div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {a_header("Sessions", "2 running · 5 open", f'<button style="{A_PRI}">New session</button>')}
      <div style="flex-grow: 1; min-height: 0; display: flex;">
        <div style="width: 340px; flex-shrink: 0; display: flex; flex-direction: column; border-right: 1px solid #E2DED4; padding: 6px 16px 0 28px;">
          <div style="display: flex; align-items: baseline; gap: 10px; padding: 18px 0 8px; border-bottom: 1px solid #1C1B18;"><div style="font-family: {SERIF}; font-size: 17px; font-weight: 600;">Open</div><div style="font-family: {MONO_A}; font-size: 11.5px; color: #6B675E;">5</div></div>
          {rows}
          <div style="display: flex; align-items: baseline; gap: 10px; padding: 26px 0 8px; border-bottom: 1px solid #1C1B18;"><div style="font-family: {SERIF}; font-size: 17px; font-weight: 600;">Recovered</div><div style="font-family: {MONO_A}; font-size: 11.5px; color: #6B675E;">1</div></div>
          <div style="display: flex; flex-direction: column; gap: 8px; padding: 12px 0;">
            <div style="font-weight: 600;">Ideation run</div>
            <div style="font-family: {SERIF}; font-style: italic; font-size: 13px; line-height: 1.5; color: #3D3A33;">These were running when Dev Desk last closed unexpectedly. Nothing was restarted — continuing one is your call.</div>
            <div><button style="{A_BTN}">Run the door again</button></div>
          </div>
        </div>
        <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; padding: 24px 28px 28px;">
          <div style="display: flex; align-items: center; gap: 10px; padding-bottom: 14px;">
            <div style="font-family: {SERIF}; font-size: 20px; font-weight: 600;">#42 Preserve course-list position</div>
            <span style="font-size: 11px; font-weight: 500; padding: 2px 8px; border-radius: 10px; color: #1F6B41; background: #E4F4EA;">Running</span>
            <div style="flex-grow: 1;"></div>
            <button style="{A_BTN}">Open the task</button>
            <button style="{A_BTN}">Run fix/42-course-scroll</button>
            <button style="{A_BTN}">Stop</button>
          </div>
          {term(T42, MONO_A, radius="8px")}
        </div>
      </div>
    </div>"""
    return a_shell("Sessions", body)


IDEAS = [
    ("Debounce the lesson search index rebuild", "Confirmed", "High", "Low"),
    ("Virtualise the course list", "Confirmed", "High", "Medium"),
    ("One date helper instead of two", "Confirmed", "Medium", "Low"),
    ("Prefetch the next lesson", "Unconfirmed", "Medium", "Medium"),
    ("Move attempt writes behind a queue", "Rejected", "Low", "High"),
]
IDEA_GROUPS = [("Run", [("All runs", "", False), ("run-0931", "5", True)]),
               ("Verdict", [("Confirmed", "3", False), ("Unconfirmed", "1", False), ("Rejected", "1", False)])]


def a_ideation():
    rows = ""
    for i, (t, v, g, c) in enumerate(IDEAS):
        bg = "#FFFEFB" if i == 0 else "transparent"
        rows += (f'<button style="display: flex; flex-direction: column; gap: 3px; padding: 11px 14px; border: 0; border-bottom: 1px solid #E2DED4; background: {bg}; color: #1C1B18; text-align: left;">'
                 f'<span style="font-weight: 600; line-height: 1.35;">{t}</span><span style="font-size: 11.5px; color: #6B675E;">{v} · gain {g} · cost {c}</span></button>\n')
    cards = ""
    for k, v in [("Gain", "High"), ("Cost", "Low"), ("Doing nothing", "[what it costs to leave it]")]:
        cards += (f'<div style="display: flex; flex-direction: column; gap: 6px; padding: 14px 0; border-top: 1px solid #1C1B18;"><div style="{A_LABEL}">{k}</div>'
                  f'<div style="font-family: {SERIF}; font-size: 19px; font-weight: 500;">{v}</div></div>')
    body = f"""{a_filter("Ideas", IDEA_GROUPS)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {a_header("Ideation", "5 ideas · run-0931", f'<button style="{A_PRI}">Generate ideas</button>')}
      <div style="flex-grow: 1; min-height: 0; display: flex;">
        <div style="width: 320px; flex-shrink: 0; display: flex; flex-direction: column; border-right: 1px solid #E2DED4; background: #F3F0E9;">{rows}</div>
        <div style="flex-grow: 1; min-width: 0; padding: 32px 40px; display: flex; flex-direction: column; gap: 18px;">
          <div style="display: flex; align-items: flex-start; gap: 16px;">
            <div style="flex-grow: 1; font-family: {SERIF}; font-size: 28px; font-weight: 500; line-height: 1.2; letter-spacing: -0.01em;">Debounce the lesson search index rebuild</div>
            <span style="flex-shrink: 0; margin-top: 6px; font-size: 11px; font-weight: 500; padding: 2px 8px; border-radius: 10px; color: #1F6B41; background: #E4F4EA;">Confirmed</span>
            <button style="{A_PRI} flex-shrink: 0;">File…</button>
          </div>
          <div style="font-family: {SERIF}; font-style: italic; font-size: 16px; color: #3D3A33;">→ [the change the run proposes, in one line]</div>
          <div style="font-family: {SERIF}; font-size: 16px; line-height: 1.6; color: #2A2823; max-width: 640px;">[The opportunity&#39;s summary reads here as a paragraph, set for reading rather than scanning.]</div>
          <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 24px; padding-top: 6px;">{cards}</div>
          <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 24px;">
            <div style="display: flex; flex-direction: column; gap: 6px; padding-top: 14px; border-top: 1px solid #E2DED4;"><div style="{A_LABEL}">Source locations</div><div style="font-family: {MONO_A}; font-size: 11.5px; line-height: 1.7;">src/features/search/index.ts:30<br>src/features/search/useSearch.ts:12</div></div>
            <div style="display: flex; flex-direction: column; gap: 6px; padding-top: 14px; border-top: 1px solid #E2DED4;"><div style="{A_LABEL}">Verification limits</div><div style="font-size: 12.5px; line-height: 1.55; color: #3D3A33;">[What this run could not check.]</div></div>
          </div>
        </div>
      </div>
    </div>"""
    return a_shell("Ideation", body)


DRAW_GROUPS_A = [("Draw", [("Architecture", "●", True), ("Data flow", "", False), ("Sequence", "2 of 5", False)])]


def sketch(stroke, fill, ink, muted, accent_fill, font):
    def box(x, y, w, h, label, sub, hot=False):
        f = accent_fill if hot else fill
        return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{f}" stroke="{stroke}"></rect>'
                f'<text x="{x + w / 2}" y="{y + h / 2 - 2}" text-anchor="middle" font-size="14" font-weight="600" fill="{ink}" font-family="{font}">{label}</text>'
                f'<text x="{x + w / 2}" y="{y + h / 2 + 17}" text-anchor="middle" font-size="11" fill="{muted}" font-family="{font}">{sub}</text>')
    lines = "".join(f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="1.5"></path>' for d in [
        "M290 110H400", "M590 110H700", "M495 150V250", "M590 290H700", "M795 150V250"])
    return (f'<svg viewBox="0 0 900 380" width="900" height="380" role="img" aria-label="Placeholder architecture sketch">{lines}'
            + box(100, 70, 190, 80, "web/app", "pages and components")
            + box(400, 70, 190, 80, "web/app/api", "route handlers", True)
            + box(700, 70, 190, 80, "web/app/lib", "shared helpers")
            + box(400, 250, 190, 80, "pipeline", "build and ingest")
            + box(700, 250, 190, 80, "database", "[YOUR STORE]")
            + "</svg>")


def a_diagrams():
    body = f"""{a_filter("Drawings", DRAW_GROUPS_A)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {a_header("Diagrams", "Architecture · studyhub-architecture.html", f'<button style="{A_BTN}">What to draw…</button><button style="{A_PRI}">Redraw</button>')}
      <div style="flex-grow: 1; min-height: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 18px; padding: 28px;">
        <div style="padding: 28px 36px; border: 1px solid #E2DED4; border-radius: 8px; background: #FFFEFB;">{sketch("#B9B3A4", "#F7F5F0", "#1C1B18", "#6B675E", "#E7EFFD", "Georgia, serif")}</div>
        <div style="font-family: {SERIF}; font-style: italic; font-size: 13.5px; color: #6B675E;">[docs/arch/studyhub-architecture.html renders here, full bleed — this sketch is a stand-in]</div>
      </div>
    </div>"""
    return a_shell("Diagrams", body)


# ───────────────────────────── B · Console ─────────────────────────────
B_BTN = "height: 26px; padding: 0 12px; border: 1px solid #343A44; border-radius: 5px; background: #1B1F25; color: #E4E7EB; font-size: 12px;"
B_PRI = "height: 26px; padding: 0 12px; border: 0; border-radius: 5px; background: {{accent}}; color: #0F1114; font-size: 12px; font-weight: 600;"
B_LABEL = f"font-family: {MONO_B}; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #8E96A3;"


ACC_HOLE = "{{accent}}"
PLUS_BTN = ('<button aria-label="New session" style="width: 24px; height: 22px; display: flex; align-items: center; justify-content: center; border: 1px solid #343A44; '
            'border-radius: 4px; background: #1B1F25; color: #E4E7EB; font-size: 14px; line-height: 1;">+</button>')


def dock_strip():
    """The collapsed dock: every live session as one line, and a + to start another without leaving the tab."""
    return f"""<div data-dock="strip" style="height: 34px; flex-shrink: 0; display: flex; align-items: center; gap: 14px; padding: 0 14px; border-top: 1px solid #343A44; background: #14171B; font-family: {MONO_B}; font-size: 11.5px;">
        <button style="display: flex; align-items: center; gap: 7px; border: 0; background: transparent; color: #E4E7EB; font-size: 11.5px;"><span style="color: #8E96A3;">▸</span><span>sessions</span><span style="color: #8E96A3;">3</span></button>
        <span style="display: flex; align-items: center; gap: 6px; color: #C9CDD4;"><span style="width: 6px; height: 6px; border-radius: 3px; background: {{{{accent}}}};"></span>#42 · Codex patched useScrollRestore.ts</span>
        <span style="display: flex; align-items: center; gap: 6px; color: #E7C067;"><span style="width: 6px; height: 6px; border-radius: 3px; background: #E7C067;"></span>#57 · waiting for input</span>
        <span style="display: flex; align-items: center; gap: 6px; color: #8E96A3;"><span style="width: 6px; height: 6px; border-radius: 3px; background: #5A606A;"></span>zsh</span>
        {PLUS_BTN}
        <div style="flex-grow: 1;"></div>
        <span style="color: #8E96A3;">⌘J open · ⌘T new</span>
      </div>"""


def dock_pane(title, sub, dot, lines, extra=""):
    body = "".join(f"<div>{l}</div>" for l in lines)
    return f"""<div style="flex-grow: 1; flex-basis: 0; min-width: 0; display: flex; flex-direction: column; border-right: 1px solid #262B33;">
            <div style="height: 28px; flex-shrink: 0; display: flex; align-items: center; gap: 8px; padding: 0 12px; border-bottom: 1px solid #1E2228; color: #C9CDD4; font-size: 11.5px;">
              <span style="width: 6px; height: 6px; border-radius: 3px; background: {dot};"></span><span style="font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{title}</span><span style="color: #8E96A3; white-space: nowrap;">{sub}</span>
              <div style="flex-grow: 1;"></div><button aria-label="Close pane" style="border: 0; background: transparent; color: #8E96A3; font-size: 12px;">✕</button>
            </div>
            <div style="flex-grow: 1; min-height: 0; overflow: hidden; padding: 9px 12px; display: flex; flex-direction: column; gap: 3px; line-height: 1.45; color: #D7DBE0;">{body}</div>{extra}
          </div>"""


def plus_menu():
    """What + offers: a new shell, or picking up work that stopped."""
    def item(title, sub, dot, kbd=""):
        k = f'<span style="color: #8E96A3; font-size: 11px;">{kbd}</span>' if kbd else ""
        return (f'<button style="display: flex; align-items: center; gap: 10px; min-height: 44px; padding: 4px 10px; border: 0; border-radius: 4px; background: transparent; color: #E4E7EB; text-align: left; font-size: 12px;">'
                f'<span style="width: 6px; height: 6px; flex-shrink: 0; border-radius: 3px; background: {dot};"></span>'
                f'<span style="flex-grow: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0;"><span style="font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{title}</span>'
                f'<span style="font-size: 11px; color: #8E96A3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{sub}</span></span>{k}</button>')
    return (f'<div style="position: absolute; left: 0; top: 28px; z-index: 5; width: 340px; display: flex; flex-direction: column; gap: 2px; padding: 6px; border: 1px solid #343A44; border-radius: 6px; background: #1B1F25; box-shadow: 0 12px 40px rgba(0,0,0,0.55); font-family: {MONO_B};">'
            + item("New session", "A login shell at the project root", ACC_HOLE, "⌘T")
            + '<div style="height: 1px; background: #343A44; margin: 4px 2px;"></div>'
            + '<div style="padding: 4px 10px 2px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #8E96A3;">Resume</div>'
            + item("#66 Cache lesson thumbnails", "Paused at Planned · feat/66-thumbnail-cache", "#E7C067")
            + item("Ideation run", "Was running when Dev Desk last closed", "#5A606A")
            + '</div>')


def dock_open(menu=False):
    """The open dock: several live terminals at once, side by side, with a + at the end of the tab row."""
    tabs = ""
    for label, dot, on in [("#42 course-list · Codex", "{{accent}}", True), ("#57 exam-recovery · Claude", "#E7C067", True), ("zsh", "#5A606A", False)]:
        fg, bg = ("#E4E7EB", "#1B1F25") if on else ("#8E96A3", "transparent")
        tabs += (f'<button style="display: flex; align-items: center; gap: 7px; height: 24px; padding: 0 10px; border: 0; border-radius: 4px; background: {bg}; color: {fg}; font-size: 11.5px;">'
                 f'<span style="width: 6px; height: 6px; border-radius: 3px; background: {dot};"></span><span>{label}</span></button>')
    answer = ('<div style="flex-shrink: 0; display: flex; gap: 6px; padding: 7px 10px; border-top: 1px solid #5C4718; background: #1D180B;">'
              f'<input type="text" aria-label="Answer the run" placeholder="Answer the run…" style="flex-grow: 1; min-width: 0; height: 24px; box-sizing: border-box; padding: 0 8px; border: 1px solid #5C4718; border-radius: 4px; background: #0F1114; color: #E4E7EB; font-family: {MONO_B}; font-size: 11.5px;">'
              '<button style="height: 24px; padding: 0 10px; border: 0; border-radius: 4px; background: {{accent}}; color: #0F1114; font-size: 11.5px; font-weight: 600;">Send</button></div>')
    return f"""<div data-dock="open" style="height: 250px; flex-shrink: 0; display: flex; flex-direction: column; border-top: 1px solid #343A44; background: #0B0D10; font-family: {MONO_B}; font-size: 12px;">
        <div style="height: 34px; flex-shrink: 0; display: flex; align-items: center; gap: 4px; padding: 0 10px; border-bottom: 1px solid #1E2228; background: #14171B;">
          <button style="display: flex; align-items: center; gap: 7px; padding: 0 6px 0 2px; border: 0; background: transparent; color: #E4E7EB; font-size: 11.5px;"><span style="color: #8E96A3;">▾</span><span>sessions</span></button>
          {tabs}
          <div style="position: relative; display: flex;">{PLUS_BTN}{plus_menu() if menu else ""}</div>
          <div style="flex-grow: 1;"></div>
          <span style="color: #8E96A3; font-size: 11px; padding-right: 6px;">2 shown side by side</span>
          <button style="height: 22px; padding: 0 9px; border: 1px solid #343A44; border-radius: 4px; background: #1B1F25; color: #E4E7EB; font-size: 11px;">Open in Sessions</button>
        </div>
        <div style="flex-grow: 1; min-height: 0; display: flex;">
          {dock_pane("#42 Preserve course-list position", "fix/42-course-scroll", ACC_HOLE, T42[1:])}
          {dock_pane("#57 Improve exam recovery", "feat/57-exam-recovery", "#E7C067", T57[1:4], answer)}
        </div>
      </div>"""


def b_shell(sel, body, dock=True):
    nav = ""
    for label, d in ICONS:
        bg, fg = ("#22272F", "#E4E7EB") if label == sel else ("transparent", "#8E96A3")
        nav += f'<button aria-label="{label}" style="width: 44px; height: 44px; display: flex; align-items: center; justify-content: center; border: 0; border-radius: 8px; background: {bg}; color: {fg};">{svg(d, 20)}</button>\n'
    dock_html = ""
    if dock in ("open", "open-menu"):
        dock_html = dock_open(dock == "open-menu")
    elif dock:
        dock_html = dock_strip()
    inner = f"""
  <div style="height: 40px; flex-shrink: 0; box-sizing: border-box; padding: 0 14px 0 18px; display: flex; align-items: center; gap: 10px; border-bottom: 1px solid #262B33; background: #14171B; font-family: {MONO_B}; font-size: 12px;">
    <span style="font-weight: 600;">studyhub</span><span style="color: #8E96A3;">~/Developer/studyhub</span><span style="color: #8E96A3;">on</span><span style="color: {{{{accent}}}};">main</span>
    <div style="flex-grow: 1;"></div>
    <button style="{B_BTN} height: 24px; font-size: 11.5px;">run ⌘R</button>
    <button style="{B_BTN} height: 24px; font-size: 11.5px;">files</button>
  </div>
  <div style="flex-grow: 1; min-height: 0; display: flex;">
    <div style="width: 64px; flex-shrink: 0; box-sizing: border-box; padding: 10px 8px; display: flex; flex-direction: column; align-items: center; gap: 6px; background: #14171B; border-right: 1px solid #262B33;">
      <button aria-label="Open project" style="width: 44px; height: 44px; display: flex; align-items: center; justify-content: center; border: 1px solid #343A44; border-radius: 8px; background: #1B1F25; color: #E4E7EB;">{svg("M12 6v12M6 12h12", 20)}</button>
      <div style="height: 1px; width: 32px; background: #262B33; margin: 6px 0;"></div>
      {nav}
      <div style="flex-grow: 1;"></div>
      <button aria-label="Settings" style="width: 44px; height: 44px; display: flex; align-items: center; justify-content: center; border: 0; border-radius: 8px; background: transparent; color: #8E96A3;">{svg(GEAR, 20)}</button>
    </div>
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      <div style="flex-grow: 1; min-height: 0; display: flex;">{body}</div>
      {dock_html}
    </div>
  </div>"""
    return page(f"{sel} — Console", "family=Geist+Mono:wght@400;500;600", "a{color:#7FD19B}a:hover{color:#A9E3BC}",
                f"display: flex; flex-direction: column; background: #0F1114; color: #E4E7EB; font-family: {SANS}; font-size: 13px;",
                inner, "#7FD19B", ["#7FD19B", "#9CC0FF", "#E7C067", "#F2A7C3"])


def b_header(title, status, tools):
    return f"""<div style="height: 48px; flex-shrink: 0; box-sizing: border-box; padding: 0 16px; display: flex; align-items: center; gap: 12px; border-bottom: 1px solid #262B33;">
        <h1 style="margin: 0; font-family: {MONO_B}; font-size: 15px; font-weight: 600;">{title}</h1>
        <div style="font-family: {MONO_B}; font-size: 12px; color: #8E96A3;">{status}</div>
        <div style="flex-grow: 1;"></div>{tools}</div>"""


def b_filter(groups):
    out = f'<div style="width: 228px; flex-shrink: 0; box-sizing: border-box; padding: 16px 14px; display: flex; flex-direction: column; gap: 20px; border-right: 1px solid #262B33; background: #12151A; font-family: {MONO_B}; font-size: 12px;">\n'
    for gt, opts in groups:
        out += f'<div style="display: flex; flex-direction: column; gap: 2px;"><div style="color: #8E96A3; padding: 0 8px 6px;">{gt}:</div>\n'
        for label, n, on in opts:
            bg, fg, mark = ("#1B1F25", "#E4E7EB", "›") if on else ("transparent", "#B8BEC8", "")
            out += (f'<button style="height: 28px; display: flex; align-items: center; gap: 8px; padding: 0 8px; border: 0; border-radius: 5px; background: {bg}; color: {fg}; text-align: left; font-size: 12px;">'
                    f'<span style="width: 10px; color: {{{{accent}}}};">{mark}</span><span style="flex-grow: 1;">{label}</span><span style="color: #8E96A3;">{n}</span></button>\n')
        out += "</div>\n"
    return out + "</div>"


def b_sessions():
    groups = [("open", [("#42 course-list", "24m", True), ("#57 exam-recovery", "1h", True), ("dev server", "3h", False), ("findings hunt", "ended", False), ("zsh", "", False)]),
              ("recovered", [("ideation run", "", False)])]

    def pane(title, sub, pill, pfg, pbg, lines, extra=""):
        return f"""<div style="flex-grow: 1; flex-basis: 0; min-width: 0; display: flex; flex-direction: column; border-right: 1px solid #262B33;">
          <div style="flex-shrink: 0; display: flex; flex-direction: column; gap: 4px; padding: 12px 16px; border-bottom: 1px solid #262B33; background: #14171B;">
            <div style="display: flex; align-items: center; gap: 8px;"><span style="font-weight: 600;">{title}</span><span style="font-size: 11px; padding: 1px 7px; border-radius: 4px; color: {pfg}; background: {pbg};">{pill}</span><div style="flex-grow: 1;"></div><button style="{B_BTN} height: 22px; font-size: 11px;">Open the task</button></div>
            <div style="font-family: {MONO_B}; font-size: 11px; color: #8E96A3;">{sub}</div>
          </div>
          {term(lines, MONO_B)}
          {extra}
        </div>"""
    answer = f"""<div style="flex-shrink: 0; display: flex; gap: 8px; padding: 10px 12px; border-top: 1px solid #5C4718; background: #1D180B;">
            <input type="text" aria-label="Answer the run" placeholder="Answer the run…" style="flex-grow: 1; height: 28px; box-sizing: border-box; padding: 0 10px; border: 1px solid #5C4718; border-radius: 5px; background: #0F1114; color: #E4E7EB; font-family: {MONO_B}; font-size: 12px;">
            <button style="{B_PRI} height: 28px;">Send</button></div>"""
    body = f"""{b_filter(groups)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {b_header("sessions", "2 running · 5 open · showing 2 side by side", f'<button style="{B_BTN}">Single</button><button style="{B_PRI}">New session</button>')}
      <div style="flex-grow: 1; min-height: 0; display: flex;">
        {pane("#42 Preserve course-list position", "Codex · running · fix/42-course-scroll", "Running", "#7FD19B", "#16301F", T42)}
        {pane("#57 Improve exam recovery", "Claude · waiting for input · feat/57-exam-recovery", "Needs a decision", "#E7C067", "#33280F", T57, answer)}
      </div>
    </div>"""
    return b_shell("Sessions", body, dock=False)


def b_ideation():
    rows = ""
    tone = {"Confirmed": ("#7FD19B", "#16301F"), "Unconfirmed": ("#E7C067", "#33280F"), "Rejected": ("#AEB4BD", "#2A2D33")}
    for i, (t, v, g, c) in enumerate(IDEAS):
        bg = "#1B1F25" if i == 0 else "transparent"
        fg, fill = tone[v]
        rows += (f'<button style="display: grid; grid-template-columns: minmax(0, 1fr) 70px 70px 110px; column-gap: 12px; align-items: center; min-height: 42px; padding: 0 16px; border: 0; border-bottom: 1px solid #1E2228; background: {bg}; color: #E4E7EB; text-align: left;">'
                 f'<span style="font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{t}</span>'
                 f'<span style="font-family: {MONO_B}; font-size: 11.5px; color: #C9CDD4;">{g.lower()}</span><span style="font-family: {MONO_B}; font-size: 11.5px; color: #C9CDD4;">{c.lower()}</span>'
                 f'<span style="justify-self: end; font-size: 11px; padding: 1px 7px; border-radius: 4px; color: {fg}; background: {fill};">{v}</span></button>\n')
    kv = ""
    for k, v in [("gain", "High"), ("cost", "Low"), ("doing nothing", "[what it costs to leave it]")]:
        kv += f'<div style="display: grid; grid-template-columns: 120px minmax(0, 1fr); padding: 9px 12px; border-bottom: 1px solid #1E2228;"><span style="font-family: {MONO_B}; font-size: 11.5px; color: #8E96A3;">{k}</span><span>{v}</span></div>'
    body = f"""{b_filter([("run", [("all", "", False), ("run-0931", "5", True)]), ("verdict", [("confirmed", "3", False), ("unconfirmed", "1", False), ("rejected", "1", False)])])}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {b_header("ideation", "run-0931 · 5 ideas", f'<button style="{B_PRI}">Generate ideas</button>')}
      <div style="flex-grow: 1; min-height: 0; display: flex;">
        <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
          <div style="display: grid; grid-template-columns: minmax(0, 1fr) 70px 70px 110px; column-gap: 12px; height: 32px; align-items: center; padding: 0 16px; background: #14171B; border-bottom: 1px solid #1E2228; {B_LABEL}"><span>idea</span><span>gain</span><span>cost</span><span style="justify-self: end;">verdict</span></div>
          {rows}
        </div>
        <div style="width: 460px; flex-shrink: 0; box-sizing: border-box; padding: 18px 20px; display: flex; flex-direction: column; gap: 16px; border-left: 1px solid #262B33; background: #12151A;">
          <div style="display: flex; gap: 8px; font-size: 11.5px;"><span style="padding: 1px 7px; border-radius: 4px; color: #7FD19B; background: #16301F;">Confirmed</span><span style="padding: 1px 7px; border-radius: 4px; color: #AEB4BD; background: #2A2D33;">performance</span></div>
          <div style="font-size: 17px; font-weight: 600; line-height: 1.3;">Debounce the lesson search index rebuild</div>
          <div style="font-family: {MONO_B}; font-size: 12px; color: {{{{accent}}}};">→ [the change the run proposes, in one line]</div>
          <div style="font-size: 13px; line-height: 1.55; color: #C9CDD4;">[The opportunity&#39;s summary, in the report&#39;s own words.]</div>
          <div style="display: flex; flex-direction: column; border: 1px solid #262B33; border-radius: 6px; background: #0B0D10;">{kv}</div>
          <div style="display: flex; flex-direction: column; gap: 6px;"><div style="{B_LABEL}">Source locations</div><div style="font-family: {MONO_B}; font-size: 11.5px; line-height: 1.7;">src/features/search/index.ts:30<br>src/features/search/useSearch.ts:12</div></div>
          <div style="display: flex; flex-direction: column; gap: 6px;"><div style="{B_LABEL}">Verification limits</div><div style="font-size: 12.5px; line-height: 1.5; color: #C9CDD4;">[What this run could not check.]</div></div>
          <div style="flex-grow: 1;"></div>
          <div style="display: flex;"><button style="{B_PRI} height: 28px;">File…</button></div>
        </div>
      </div>
    </div>"""
    return b_shell("Ideation", body)


def b_diagrams():
    groups = [("draw", [("architecture", "●", True), ("data-flow", "", False), ("sequence", "2 of 5", False)])]
    body = f"""{b_filter(groups)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {b_header("diagrams", "architecture · studyhub-architecture.html", f'<button style="{B_BTN}">What to draw…</button><button style="{B_PRI}">Redraw</button>')}
      <div style="flex-grow: 1; min-height: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; background-color: #0B0D10; background-image: radial-gradient(#1E2228 1px, transparent 1px); background-size: 24px 24px;">
        {sketch("#454A53", "#16191E", "#E4E7EB", "#8E96A3", "#16301F", "Menlo, monospace")}
        <div style="font-family: {MONO_B}; font-size: 11.5px; color: #8E96A3;">[docs/arch/studyhub-architecture.html renders here, full bleed — this sketch is a stand-in]</div>
      </div>
    </div>"""
    return b_shell("Diagrams", body)


# ───────────────────────────── C · Focus ─────────────────────────────
C_SOFT = "height: 28px; padding: 0 12px; border: 0; border-radius: 14px; background: #EEF0F4; color: #171A21; font-size: 12px;"
C_PRI = "height: 32px; padding: 0 16px; border: 0; border-radius: 16px; background: {{accent}}; color: #FFFFFF; font-size: 12.5px; font-weight: 600;"
C_LABEL = f"font-family: {ROUND}; font-size: 12px; font-weight: 700; color: #5B6472;"
C_CARD = "border-radius: 14px; background: #FFFFFF; box-shadow: 0 0 0 1px #E6E8ED;"


def c_shell(sel, body):
    nav = ""
    for label, d in ICONS:
        bg, fg, w = ("#FFFFFF", "{{accent}}", 700) if label == sel else ("transparent", "#4A5261", 500)
        nav += (f'<button style="width: 68px; height: 56px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; border: 0; border-radius: 14px; '
                f'background: {bg}; color: {fg}; font-size: 10.5px; font-weight: {w};">{svg(d, 20, "1.7")}<span>{label}</span></button>\n')
    inner = f"""
  <div style="width: 84px; flex-shrink: 0; box-sizing: border-box; padding: 14px 8px; display: flex; flex-direction: column; align-items: center; gap: 4px;">
    <button aria-label="Open project" style="width: 48px; height: 48px; display: flex; align-items: center; justify-content: center; border: 0; border-radius: 16px; background: #FFFFFF; color: #171A21; box-shadow: 0 1px 2px rgba(23,26,33,0.10);">{svg("M12 6v12M6 12h12", 20, "1.8")}</button>
    <div style="height: 10px;"></div>
    {nav}
    <div style="flex-grow: 1;"></div>
    <button style="width: 68px; height: 56px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; border: 0; border-radius: 14px; background: transparent; color: #4A5261; font-size: 10.5px;">{svg(GEAR, 20, "1.7")}<span>Settings</span></button>
  </div>
  <div style="flex-grow: 1; min-width: 0; margin: 10px 10px 10px 0; display: flex; border-radius: 18px; background: #FFFFFF; box-shadow: 0 1px 3px rgba(23,26,33,0.08); overflow: hidden;">
    {body}
  </div>"""
    return page(f"{sel} — Focus", "family=Nunito:wght@600;700;800", "a{color:#9A3412}a:hover{color:#7C2D12}",
                f"display: flex; background: #EEF0F4; color: #171A21; font-family: {SANS}; font-size: 13px;",
                inner, "#C2410C", ["#C2410C", "#2F6FEB", "#0F766E", "#171A21"])


def c_header(title, status, tools):
    return f"""<div style="height: 76px; flex-shrink: 0; box-sizing: border-box; padding: 0 24px; display: flex; align-items: center; gap: 12px;">
        <div style="display: flex; flex-direction: column; gap: 2px;"><h1 style="margin: 0; font-family: {ROUND}; font-size: 24px; font-weight: 800; letter-spacing: -0.01em;">{title}</h1><div style="font-size: 12px; color: #5B6472;">{status}</div></div>
        <div style="flex-grow: 1;"></div>{tools}</div>"""


def c_side(title, groups):
    out = f'<div style="width: 236px; flex-shrink: 0; box-sizing: border-box; padding: 22px 16px; display: flex; flex-direction: column; gap: 22px; border-right: 1px solid #E6E8ED;">\n'
    for gt, opts in groups:
        out += f'<div style="display: flex; flex-direction: column; gap: 2px;"><div style="{C_LABEL} padding: 0 10px 8px;">{gt}</div>\n'
        for label, n, on in opts:
            bg, w = ("#EEF0F4", 600) if on else ("transparent", 400)
            out += (f'<button style="height: 36px; display: flex; align-items: center; gap: 8px; padding: 0 10px; border: 0; border-radius: 10px; background: {bg}; color: #171A21; text-align: left; font-weight: {w};">'
                    f'<span style="flex-grow: 1;">{label}</span><span style="font-size: 11.5px; color: #5B6472;">{n}</span></button>\n')
        out += "</div>\n"
    return out + "</div>"


def c_sessions():
    others = ""
    for t, s, dot, last in [("#42 Preserve course-list position", "Codex · running · 24m", "#1F8B4C", "11:12 · patched useScrollRestore.ts"),
                            ("studyhub dev server", "Project run · running · 3h", "#1F8B4C", "[last line of output]"),
                            ("Findings hunt", "Door · ended", "#B9BEC6", "14 findings written to docs/findings/"),
                            ("zsh", "Terminal", "#B9BEC6", "")]:
        others += (f'<button style="display: flex; flex-direction: column; gap: 4px; padding: 12px 14px; border: 0; border-radius: 12px; background: #F5F6F9; color: #171A21; text-align: left;">'
                   f'<span style="display: flex; align-items: center; gap: 8px;"><span style="width: 7px; height: 7px; border-radius: 4px; background: {dot};"></span><span style="font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{t}</span></span>'
                   f'<span style="font-size: 11.5px; color: #5B6472;">{s}</span><span style="font-family: {MONO_C}; font-size: 11px; color: #3B4250;">{last}</span></button>\n')
    body = f"""<div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {c_header("Sessions", "2 running · 5 open · 1 needs you", f'<button style="{C_PRI}">New session</button>')}
      <div style="flex-grow: 1; min-height: 0; padding: 0 24px 22px; display: flex; gap: 16px;">
        <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; gap: 12px;">
          <div style="display: flex; flex-direction: column; gap: 12px; padding: 16px 18px; border-radius: 14px; background: #FFFFFF; box-shadow: 0 0 0 1px {{{{accent}}}}, 0 2px 8px rgba(23,26,33,0.06);">
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="flex-grow: 1; font-family: {ROUND}; font-size: 17px; font-weight: 800;">#57 Improve exam recovery</div>
              <span style="font-size: 11.5px; font-weight: 600; padding: 3px 9px; border-radius: 10px; color: #8A6114; background: #FBF2DE;">Needs a decision</span>
              <button style="{C_SOFT}">Open the task</button>
            </div>
            <div style="font-size: 14px; line-height: 1.5; color: #3B4250;">[The run&#39;s question appears here, in its own words — large enough to answer without reading the transcript.]</div>
            <div style="display: flex; gap: 8px;">
              <input type="text" aria-label="Answer the run" placeholder="Answer the run…" style="flex-grow: 1; height: 36px; box-sizing: border-box; padding: 0 14px; border: 0; border-radius: 18px; background: #EEF0F4; font: inherit;">
              <button style="{C_PRI} height: 36px; border-radius: 18px;">Send</button>
            </div>
          </div>
          {term(T57, MONO_C, pad="16px 18px", radius="14px")}
        </div>
        <div style="width: 320px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;">
          <div style="{C_LABEL} font-size: 14px; color: #171A21; padding: 4px 4px 6px;">Also open</div>
          {others}
          <div style="{C_LABEL} font-size: 14px; color: #171A21; padding: 14px 4px 6px;">Recovered</div>
          <div style="display: flex; flex-direction: column; gap: 8px; padding: 12px 14px; border-radius: 12px; background: #F5F6F9;">
            <div style="font-weight: 600;">Ideation run</div>
            <div style="font-size: 12px; line-height: 1.45; color: #5B6472;">Was running when Dev Desk last closed unexpectedly. Nothing was restarted — continuing is your call.</div>
            <div><button style="{C_SOFT} background: #FFFFFF; box-shadow: 0 0 0 1px #DDE0E7;">Run the door again</button></div>
          </div>
        </div>
      </div>
    </div>"""
    return c_shell("Sessions", body)


def c_ideation():
    rows = ""
    dots = {"Confirmed": "#1F8B4C", "Unconfirmed": "#B7791F", "Rejected": "#B9BEC6"}
    for i, (t, v, g, c) in enumerate(IDEAS):
        bg, w = ("#EEF0F4", 700) if i == 0 else ("transparent", 500)
        rows += (f'<button style="display: flex; align-items: center; gap: 10px; min-height: 52px; padding: 6px 10px; border: 0; border-radius: 12px; background: {bg}; color: #171A21; text-align: left;">'
                 f'<span style="width: 8px; height: 8px; flex-shrink: 0; border-radius: 4px; background: {dots[v]};"></span>'
                 f'<span style="display: flex; flex-direction: column; gap: 2px; min-width: 0;"><span style="font-weight: {w}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{t}</span>'
                 f'<span style="font-size: 11.5px; color: #5B6472;">{v} · gain {g} · cost {c}</span></span></button>\n')
    cards = ""
    for k, v, sub in [("Gain", "High", "[why]"), ("Cost", "Low", "[why]"), ("Doing nothing", "—", "[what it costs to leave it]")]:
        cards += (f'<div style="display: flex; flex-direction: column; gap: 4px; padding: 16px 18px; {C_CARD}"><div style="{C_LABEL}">{k}</div>'
                  f'<div style="font-family: {ROUND}; font-size: 22px; font-weight: 800;">{v}</div><div style="font-size: 12px; color: #5B6472;">{sub}</div></div>')
    body = f"""<div style="width: 340px; flex-shrink: 0; box-sizing: border-box; display: flex; flex-direction: column; border-right: 1px solid #E6E8ED;">
      <div style="padding: 22px 20px 14px; display: flex; flex-direction: column; gap: 10px;">
        <div style="display: flex; align-items: baseline;"><h1 style="margin: 0; flex-grow: 1; font-family: {ROUND}; font-size: 24px; font-weight: 800;">Ideation</h1><button style="{C_SOFT}">Generate ideas</button></div>
        <div style="font-size: 12px; color: #5B6472;">run-0931 · 5 ideas</div>
        <div style="display: flex; gap: 6px; padding-top: 4px;">
          <button style="{C_SOFT} background: #171A21; color: #FFFFFF; font-weight: 600;">All</button><button style="{C_SOFT}">Confirmed</button><button style="{C_SOFT}">Unconfirmed</button>
        </div>
      </div>
      <div style="display: flex; flex-direction: column; gap: 2px; padding: 0 10px;">{rows}</div>
    </div>
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; align-items: center; background: #F8F9FB;">
      <div style="width: 720px; padding-top: 44px; display: flex; flex-direction: column; gap: 18px;">
        <div style="display: flex; align-items: center; gap: 8px; font-size: 12px;"><span style="padding: 3px 9px; border-radius: 10px; font-weight: 600; color: #1F6B41; background: #E4F4EA;">Confirmed</span><span style="padding: 3px 9px; border-radius: 10px; color: #4B5563; background: #E6E8ED;">Performance</span></div>
        <div style="font-family: {ROUND}; font-size: 30px; font-weight: 800; line-height: 1.2; letter-spacing: -0.01em;">Debounce the lesson search index rebuild</div>
        <div style="font-size: 15px; font-weight: 600; color: {{{{accent}}}};">→ [the change the run proposes, in one line]</div>
        <div style="font-size: 15px; line-height: 1.6; color: #3B4250;">[The opportunity&#39;s summary, in the report&#39;s own words.]</div>
        <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px;">{cards}</div>
        <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px;">
          <div style="display: flex; flex-direction: column; gap: 6px; padding: 14px 16px; {C_CARD}"><div style="{C_LABEL}">Source locations</div><div style="font-family: {MONO_C}; font-size: 11.5px; line-height: 1.7;">src/features/search/index.ts:30<br>src/features/search/useSearch.ts:12</div></div>
          <div style="display: flex; flex-direction: column; gap: 6px; padding: 14px 16px; {C_CARD}"><div style="{C_LABEL}">Verification limits</div><div style="font-size: 12.5px; line-height: 1.5; color: #3B4250;">[What this run could not check.]</div></div>
        </div>
        <div style="display: flex; gap: 10px; padding-top: 6px;"><button style="{C_PRI} height: 40px; border-radius: 20px; padding: 0 22px; font-size: 14px;">File it…</button><button style="{C_SOFT} height: 40px; border-radius: 20px; padding: 0 18px; font-size: 13px;">Not now</button></div>
      </div>
    </div>"""
    return c_shell("Ideation", body)


def c_diagrams():
    side = c_side("Drawings", [("Draw", [("Architecture", "drawn", True), ("Data flow", "", False), ("Sequence", "2 of 5", False)])])
    body = f"""{side}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {c_header("Diagrams", "Architecture · studyhub-architecture.html", f'<button style="{C_SOFT} height: 32px; border-radius: 16px;">What to draw…</button><button style="{C_PRI}">Redraw</button>')}
      <div style="flex-grow: 1; min-height: 0; margin: 0 24px 22px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; border-radius: 14px; background: #F5F6F9;">
        {sketch("#C5CAD3", "#FFFFFF", "#171A21", "#5B6472", "#FDEBDD", "system-ui, sans-serif")}
        <div style="font-size: 12px; color: #5B6472;">[docs/arch/studyhub-architecture.html renders here, full bleed — this sketch is a stand-in]</div>
      </div>
    </div>"""
    return c_shell("Diagrams", body)


FILES = {
    "Sessions-Ledger.dc.html": a_sessions, "Sessions-Console.dc.html": b_sessions, "Sessions-Focus.dc.html": c_sessions,
    "Ideation-Ledger.dc.html": a_ideation, "Ideation-Console.dc.html": b_ideation, "Ideation-Focus.dc.html": c_ideation,
    "Diagrams-Ledger.dc.html": a_diagrams, "Diagrams-Console.dc.html": b_diagrams, "Diagrams-Focus.dc.html": c_diagrams,
}
if __name__ == "__main__":
  for name, fn in FILES.items():
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as fh:
        fh.write(fn())

