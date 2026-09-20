#!/usr/bin/env python3
"""Column E: the multi-project container, five ways, in the Console × Focus look."""
import os
from gen import OUT, MONO_B as M, SANS, B_BTN, B_PRI, page, svg, b_shell, b_header, b_filter, dock_pane, dock_strip, PLUS_BTN, T42, T57, ACC_HOLE as ACC
from gen2 import d_work, small_card, big_card, col_head, pill, CARD, INK, MUTED, BODY, LINE, SURF, RAISED, TONE

PROJECTS = [("SH", "studyhub", "#E7C067", True), ("DS", "dev-skill", "#7FD19B", False), ("SD", "studyhub-deploy", "", False)]
COLOR = {"studyhub": "#9CC0FF", "dev-skill": "#F2A7C3", "studyhub-deploy": "#B8A7F2"}
HOME = "M4 11l8-7 8 7M6 10v9h12v-9M10 19v-5h4v5"
RAIL_MARK = '    <div style="width: 64px; flex-shrink: 0;'
BODY_MARK = '  <div style="flex-grow: 1; min-height: 0; display: flex;">'


def strip(current="studyhub", home=False):
    def pill_mark(on):
        return f'<span style="position: absolute; left: -10px; top: 8px; width: 4px; height: 20px; border-radius: 0 3px 3px 0; background: {INK if on else "transparent"};"></span>'
    out = (f'<div data-strip="1" style="width: 56px; flex-shrink: 0; box-sizing: border-box; padding: 10px 0; display: flex; flex-direction: column; align-items: center; gap: 8px; background: #0B0D10; border-right: 1px solid {LINE};">'
           f'<button aria-label="Home" style="position: relative; width: 36px; height: 36px; display: flex; align-items: center; justify-content: center; border: 0; border-radius: 10px; background: {ACC if home else SURF}; color: {"#0F1114" if home else BODY};">{pill_mark(home)}{svg(HOME, 20)}</button>'
           f'<div style="height: 1px; width: 28px; background: {LINE};"></div>')
    for code, name, dot, needs in PROJECTS:
        on = name == current and not home
        if needs:
            d = f'<span style="position: absolute; bottom: -4px; right: -5px; min-width: 16px; height: 16px; box-sizing: border-box; padding: 0 4px; border-radius: 8px; border: 2px solid #0B0D10; background: #E7C067; color: #0F1114; font-size: 10px; font-weight: 700; line-height: 12px;">1</span>'
        elif dot:
            d = f'<span style="position: absolute; bottom: -3px; right: -3px; width: 10px; height: 10px; box-sizing: border-box; border-radius: 5px; border: 2px solid #0B0D10; background: {dot};"></span>'
        else:
            d = ""
        out += (f'<button aria-label="{name}" style="position: relative; width: 36px; height: 36px; border: 0; border-radius: 10px; background: {COLOR[name] if on else SURF}; color: {"#0F1114" if on else COLOR[name]}; '
                f'font-family: {M}; font-size: 11.5px; font-weight: 600;">{pill_mark(on)}{code}{d}</button>')
    out += (f'<div style="flex-grow: 1;"></div><button aria-label="Open project" style="width: 36px; height: 36px; border: 1px dashed #454A53; border-radius: 10px; background: transparent; color: {MUTED}; font-size: 16px;">+</button></div>')
    return out


CAMERA = "M4 8h3l2-2h6l2 2h3v11H4zM12 17a3.5 3.5 0 1 0 0-7a3.5 3.5 0 0 0 0 7z"


def avatar(name="studyhub", code="SH"):
    """The rail's top slot: the project's own icon. Open project moved to the strip, so the + here was redundant."""
    return (f'<button data-avatar="1" aria-label="Project icon — change" title="Change project icon" style="position: relative; width: 44px; height: 44px; border: 0; border-radius: 12px; background: {COLOR[name]}; color: #0F1114; '
            f'font-family: {M}; font-size: 14px; font-weight: 600;"><span data-pcode>{code}</span>'
            f'<span style="position: absolute; right: -4px; bottom: -4px; width: 18px; height: 18px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; border-radius: 9px; border: 2px solid #14171B; background: #2A2D33; color: {INK};">{svg(CAMERA, 10, "2")}</span></button>')


def with_strip(html, current="studyhub"):
    a = html.index('<button aria-label="Open project" style="width: 44px; height: 44px;')
    b = html.index("</button>", a) + len("</button>")
    html = html[:a] + avatar() + html[b:]
    return html.replace(RAIL_MARK, strip(current) + "\n" + RAIL_MARK, 1)


# E1 — strip, per-project dock
def e_strip():
    return with_strip(d_work(True))


RAIL_COUNTS = {"Findings": "3", "Work": "8", "Sessions": "2", "Ideation": "5", "Diagrams": "", "Settings": ""}


def expand_rail(html, name="studyhub"):
    """The same rail, widened: labels and counts beside the icons. One toggle (the app's Compact Sidebar, shift-cmd-S) flips between the two."""
    import re
    html = html.replace('<div style="width: 64px; flex-shrink: 0; box-sizing: border-box; padding: 10px 8px; display: flex; flex-direction: column; align-items: center; gap: 6px;',
                        '<div style="width: 204px; flex-shrink: 0; box-sizing: border-box; padding: 10px 10px; display: flex; flex-direction: column; align-items: stretch; gap: 4px;', 1)
    html = html.replace('<div style="height: 1px; width: 32px; background: #262B33; margin: 6px 0;"></div>', '<div style="height: 1px; background: #262B33; margin: 8px 2px;"></div>', 1)

    def lab(m):
        label, rest, icon = m.group(1), m.group(2), m.group(3)
        n = RAIL_COUNTS[label]
        cnt = f'<span style="font-family: {M}; font-size: 11px; color: {MUTED};">{n}</span>' if n else ""
        return (f'<button aria-label="{label}" style="height: 40px; display: flex; align-items: center; gap: 10px; padding: 0 10px;{rest} font-size: 13px; text-align: left;">{icon}'
                f'<span style="flex-grow: 1;">{label}</span>{cnt}</button>')
    html = re.sub(r'<button aria-label="(Findings|Work|Sessions|Ideation|Diagrams|Settings)" style="width: 44px; height: 44px; display: flex; align-items: center; justify-content: center;(.*?)">(<svg.*?</svg>)</button>', lab, html)
    a = html.index('<button data-avatar="1"'); b = html.index("</button>", a) + 9
    row = (f'<div style="display: flex; align-items: center; gap: 10px; padding: 0 2px;">{html[a:b]}<div style="display: flex; flex-direction: column; gap: 2px; min-width: 0;">'
           f'<span data-prail style="font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{name}</span><span style="font-family: {M}; font-size: 11px; color: {MUTED};">main</span></div></div>')
    return html[:a] + row + html[b:]


def e_strip_labels():
    return expand_rail(with_strip(d_work(True)))


# E3 — strip, global dock
def global_dock():
    tabs = ""
    for proj, label, dot, on in [("studyhub", "#42 course-list", ACC, True), ("studyhub", "#57 exam-recovery", "#E7C067", True), ("dev-skill", "zsh", ACC, True), ("studyhub-deploy", "dev server", "#5A606A", False)]:
        fg, bg = (INK, RAISED) if on else (MUTED, "transparent")
        tabs += (f'<button style="display: flex; align-items: center; gap: 7px; height: 24px; padding: 0 10px; border: 0; border-radius: 4px; background: {bg}; color: {fg}; font-size: 11.5px;">'
                 f'<span style="width: 6px; height: 6px; border-radius: 3px; background: {dot};"></span><span style="color: {MUTED};">{proj} ·</span><span>{label}</span></button>')

    def item(title, sub, dot, kbd=""):
        k = f'<span style="color: {MUTED}; font-size: 11px;">{kbd}</span>' if kbd else ""
        return (f'<button style="display: flex; align-items: center; gap: 10px; min-height: 40px; padding: 3px 10px; border: 0; border-radius: 4px; background: transparent; color: {INK}; text-align: left; font-size: 12px;">'
                f'<span style="width: 6px; height: 6px; flex-shrink: 0; border-radius: 3px; background: {dot};"></span><span style="flex-grow: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0;">'
                f'<span style="font-weight: 600;">{title}</span><span style="font-size: 11px; color: {MUTED};">{sub}</span></span>{k}</button>')
    lab = f"padding: 4px 10px 2px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: {MUTED};"
    menu = (f'<div style="position: absolute; left: 0; top: 28px; z-index: 5; width: 340px; display: flex; flex-direction: column; gap: 1px; padding: 6px; border: 1px solid #343A44; border-radius: 6px; background: {RAISED}; box-shadow: 0 12px 40px rgba(0,0,0,0.55);">'
            f'<div style="{lab}">New session in</div>' + item("studyhub", "this project · ~/Developer/studyhub", ACC, "⌘T") + item("dev-skill", "~/Developer/skills/dev-skill", "#5A606A") + item("studyhub-deploy", "~/Developer/studyhub-deploy", "#5A606A")
            + f'<div style="height: 1px; background: #343A44; margin: 4px 2px;"></div><div style="{lab}">Resume</div>' + item("studyhub · #66 Cache lesson thumbnails", "Paused at Planned", "#E7C067") + "</div>")
    devskill = ['<span style="color: #7C8796;">~/Developer/skills/dev-skill · main</span>', '<span style="color: #7ED492;">❯</span> apps/desk/install.sh', '[build output]', '<span style="color: #7ED492;">▍</span>']
    return f"""<div data-dock="open" style="height: 250px; flex-shrink: 0; display: flex; flex-direction: column; border-top: 1px solid #343A44; background: #0B0D10; font-family: {M}; font-size: 12px;">
        <div style="height: 34px; flex-shrink: 0; display: flex; align-items: center; gap: 4px; padding: 0 10px; border-bottom: 1px solid #1E2228; background: #14171B;">
          <button style="display: flex; align-items: center; gap: 7px; padding: 0 6px 0 2px; border: 0; background: transparent; color: {INK}; font-size: 11.5px;"><span style="color: {MUTED};">▾</span><span>all sessions</span><span style="color: {MUTED};">4</span></button>
          {tabs}
          <div style="position: relative; display: flex;">{PLUS_BTN}{menu}</div>
          <div style="flex-grow: 1;"></div>
          <span style="color: {MUTED}; font-size: 11px;">3 shown · every project</span>
        </div>
        <div style="flex-grow: 1; min-height: 0; display: flex;">
          {dock_pane("studyhub · #42 Preserve course-list position", "", ACC, T42[1:])}
          {dock_pane("studyhub · #57 Improve exam recovery", "", "#E7C067", T57[1:4])}
          {dock_pane("dev-skill · zsh", "", ACC, devskill)}
        </div>
      </div>"""


def e_global():
    html = with_strip(d_work("open"))
    a = html.index('<div data-dock="open"')
    b = html.index("\n    </div>\n  </div>", a)
    return html[:a] + global_dock() + html[b:]


# E4 — macOS window tabs
def e_tabs():
    tabs = ""
    for _, name, dot, _ in PROJECTS:
        on = name == "studyhub"
        d = f'<span style="width: 6px; height: 6px; border-radius: 3px; background: {dot};"></span>' if dot else ""
        tabs += (f'<button style="flex-grow: 1; flex-basis: 0; height: 28px; display: flex; align-items: center; justify-content: center; gap: 7px; border: 0; border-right: 1px solid {LINE}; '
                 f'background: {"#0F1114" if on else "#14171B"}; color: {INK if on else MUTED}; font-size: 12px;">{d}<span>{name}</span></button>')
    bar = f'  <div style="height: 28px; flex-shrink: 0; display: flex; border-bottom: 1px solid {LINE}; background: #14171B;">{tabs}<button aria-label="New tab" style="width: 32px; border: 0; background: transparent; color: {MUTED}; font-size: 15px;">+</button></div>\n'
    return d_work(True).replace(BODY_MARK, bar + BODY_MARK, 1)


# E5 — one merged board
def e_merged():
    groups = [("project", [("all", 19, True), ("studyhub", 8, False), ("dev-skill", 7, False), ("studyhub-deploy", 4, False)]),
              ("milestone", [("studyhub / reliable-study…", 8, False), ("studyhub / offline-first", 6, False), ("dev-skill / [milestone]", 5, False), ("deploy / [milestone]", 4, False), ("none", 9, False)]),
              ("priority", [("P0", 2, False), ("P1", 6, False), ("P2", 7, False), ("P3", 4, False)])]
    tools = f'<button style="{B_PRI}">New task in…</button>'
    body = f"""{b_filter(groups)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {b_header("work", "all projects · 3 repos · 19 open", tools)}
      <div style="flex-grow: 1; min-height: 0; padding: 12px 16px 16px; display: flex; gap: 14px;">
        <div style="width: 248px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;">
          {col_head("Next up", 7)}
          {small_card("studyhub #65", "Reduce initial bundle size", "P1", "no agent", "Start")}
          {small_card("dev-skill #[n]", "[task title]", "P1", "no agent", "Start")}
          {small_card("studyhub #68", "Flashcard deck import", "P2", "waits for #59", "Start")}
          {small_card("deploy #[n]", "[task title]", "P2", "no agent", "Start")}
        </div>
        <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; gap: 10px;">
          {col_head("In progress", 5)}
          {big_card("studyhub · #57", "Improve exam recovery", "Needs a decision", "wait", 1, "Waiting for a decision before implementation continues.", "P0", "feat/57-exam-recovery", "1d ago", "Answer", True, True)}
          {big_card("dev-skill · #[n]", "[task title]", "Running", "run", 2, "[last activity line]", "P1", "[branch]", "[age]", "Show the run", False, False)}
          {big_card("studyhub · #42", "Preserve course-list position", "Running", "run", 2, "11:12 · Codex patched useScrollRestore.ts.", "P1", "fix/42-course-scroll", "3d ago", "Show the run", False, False)}
        </div>
        <div style="width: 248px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;">
          {col_head("Review", 2)}
          {small_card("studyhub #59", "Rewrite shared date helpers", "P1", "approved", "Open PR")}
          {small_card("deploy #[n]", "[task title]", "P2", "PR open", "Open PR")}
        </div>
      </div>
    </div>"""
    return with_strip(b_shell("Work", body), current="")


# E2 — Home
def proj_card(name, path, branch, counts, need, lines, hot):
    border = ACC if hot else LINE
    need_html = ""
    if need:
        need_html = (f'<div style="display: flex; flex-direction: column; gap: 10px; padding: 12px 14px; border: 1px solid #5C4718; border-radius: 6px; background: #1D180B;">'
                     f'<div style="display: flex; align-items: center; gap: 8px;">{pill("Needs a decision", "wait")}<span style="font-weight: 600;">{need}</span></div>'
                     f'<div style="font-size: 13px; line-height: 1.5; color: {BODY};">[The run&#39;s question appears here, in its own words.]</div>'
                     f'<div style="display: flex; gap: 8px;"><button style="{B_PRI}">Answer</button><button style="{B_BTN}">Open the task</button></div></div>')
    sess = ""
    for dot, text in lines:
        sess += f'<div style="display: flex; align-items: center; gap: 8px; font-family: {M}; font-size: 11.5px; color: {BODY};"><span style="width: 6px; height: 6px; flex-shrink: 0; border-radius: 3px; background: {dot};"></span><span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{text}</span></div>'
    stats = ""
    for k, v in counts:
        stats += f'<div style="display: flex; flex-direction: column; gap: 2px;"><span style="font-family: {M}; font-size: 18px; font-weight: 600;">{v}</span><span style="font-size: 11px; color: {MUTED};">{k}</span></div>'
    return (f'<div style="display: flex; flex-direction: column; gap: 14px; padding: 16px 18px; border: 1px solid {border}; border-radius: 6px; background: {SURF};">'
            f'<div style="display: flex; align-items: baseline; gap: 10px;"><span style="font-size: 17px; font-weight: 600;">{name}</span><span style="font-family: {M}; font-size: 11.5px; color: {MUTED};">{path} · {branch}</span>'
            f'<div style="flex-grow: 1;"></div><button style="{B_BTN} height: 24px; font-size: 11.5px;">Open</button></div>'
            f'{need_html}<div style="display: flex; gap: 28px;">{stats}</div><div style="display: flex; flex-direction: column; gap: 6px;">{sess}</div></div>')


def e_home():
    left = proj_card("studyhub", "~/Developer/studyhub", "main", [("in progress", 3), ("in review", 1), ("next up", 3), ("findings to decide", 3)],
                     "#57 Improve exam recovery", [(ACC, "#42 · Codex patched useScrollRestore.ts"), ("#E7C067", "#57 · waiting for input"), ("#5A606A", "zsh")], True)
    right = (proj_card("dev-skill", "~/Developer/skills/dev-skill", "main", [("in progress", "[n]"), ("in review", "[n]"), ("next up", "[n]")], "", [(ACC, "zsh · apps/desk/install.sh")], False)
             + proj_card("studyhub-deploy", "~/Developer/studyhub-deploy", "[branch]", [("in progress", "[n]"), ("in review", "[n]"), ("next up", "[n]")], "", [("#5A606A", "nothing running")], False))
    inner = f"""
  <div style="height: 40px; flex-shrink: 0; box-sizing: border-box; padding: 0 14px 0 18px; display: flex; align-items: center; gap: 10px; border-bottom: 1px solid {LINE}; background: #14171B; font-family: {M}; font-size: 12px;">
    <span style="font-weight: 600;">dev desk</span><span style="color: {MUTED};">home · 3 projects</span><div style="flex-grow: 1;"></div>
    <button style="{B_BTN} height: 24px; font-size: 11.5px;">open project ⌘O</button>
  </div>
  <div style="flex-grow: 1; min-height: 0; display: flex;">
    {strip(home=True)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      <div style="flex-grow: 1; min-height: 0; padding: 28px 32px; display: flex; flex-direction: column; gap: 18px;">
        <div style="display: flex; align-items: baseline; gap: 12px;"><h1 style="margin: 0; font-size: 26px; font-weight: 700; letter-spacing: -0.01em;">1 thing needs you</h1><span style="font-family: {M}; font-size: 12px; color: {MUTED};">3 sessions running across 2 projects</span></div>
        <div style="display: grid; grid-template-columns: minmax(0, 3fr) minmax(0, 2fr); gap: 16px; align-items: start;">
          {left}
          <div style="display: flex; flex-direction: column; gap: 16px;">{right}</div>
        </div>
      </div>
      {dock_strip().replace("<span>sessions</span>", "<span>all sessions</span>")}
    </div>
  </div>"""
    return page("Home — multi-project", "family=Geist+Mono:wght@400;500;600", "a{color:#7FD19B}a:hover{color:#A9E3BC}",
                f"display: flex; flex-direction: column; background: #0F1114; color: {INK}; font-family: {SANS}; font-size: 13px;", inner, "#7FD19B", ["#7FD19B", "#9CC0FF", "#E7C067", "#F2A7C3"])


FILES = [("Multi-Strip.dc.html", e_strip, "1 · Project strip, per-project dock"), ("Multi-Strip-Labels.dc.html", e_strip_labels, "1 · same, rail widened"), ("Multi-Home.dc.html", e_home, "2 · Home — what needs you"),
         ("Multi-GlobalDock.dc.html", e_global, "Dock b · global, + asks which project"), ("Multi-WindowTabs.dc.html", e_tabs, "Cheapest · macOS window tabs"),
         ("Multi-Merged.dc.html", e_merged, "3 · One merged board (not recommended)")]
if __name__ == "__main__":
    for name, fn, _ in FILES:
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as fh:
            fh.write(fn().replace("<title>Work — Console</title>", f"<title>{name[:-8]}</title>"))
        print(name)
