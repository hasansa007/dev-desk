#!/usr/bin/env python3
"""Settings, task dialog, add task, launcher, side by side — one layout engine, two looks, two layouts.
B = console look + console layout · C = focus look + focus layout · D = console look + focus layout."""
import os
from gen import OUT, MONO_B, MONO_C, ROUND, SANS, page, b_shell, c_shell, term, T42, T57

ACC = "{{accent}}"

CONSOLE = dict(
    name="Console", dark=True, backdrop="#08090B", sheet="#0F1114", head="#14171B", surf="#16191E", raised="#1B1F25", line="#262B33", ctl="#343A44",
    ink="#E4E7EB", muted="#8E96A3", body="#C9CDD4", on_acc="#0F1114", r="5px", R="8px", pill_r="4px", mono=MONO_B,
    title=f"font-family: {SANS}; font-weight: 600;", label=f"font-family: {MONO_B}; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #8E96A3;",
    shadow="0 24px 80px rgba(0,0,0,0.6)", fonts="family=Geist+Mono:wght@400;500;600", links="a{color:#7FD19B}a:hover{color:#A9E3BC}",
    accent="#7FD19B", swatches=["#7FD19B", "#9CC0FF", "#E7C067", "#F2A7C3"],
    tones={"run": ("#7FD19B", "#16301F"), "wait": ("#E7C067", "#33280F"), "fail": ("#F19A9A", "#331A1A"), "info": ("#9CC0FF", "#1B2A45"), "neu": ("#AEB4BD", "#2A2D33")},
)
FOCUS = dict(
    name="Focus", dark=False, backdrop="#D5D9E0", sheet="#FFFFFF", head="#FFFFFF", surf="#F5F6F9", raised="#EEF0F4", line="#E6E8ED", ctl="#DDE0E7",
    ink="#171A21", muted="#5B6472", body="#3B4250", on_acc="#FFFFFF", r="14px", R="18px", pill_r="10px", mono=MONO_C,
    title=f"font-family: {ROUND}; font-weight: 800;", label=f"font-family: {ROUND}; font-size: 12px; font-weight: 700; color: #5B6472;",
    shadow="0 24px 80px rgba(23,26,33,0.25)", fonts="family=Nunito:wght@600;700;800", links="a{color:#9A3412}a:hover{color:#7C2D12}",
    accent="#C2410C", swatches=["#C2410C", "#2F6FEB", "#0F766E", "#171A21"],
    tones={"run": ("#1F6B41", "#E4F4EA"), "wait": ("#8A6114", "#FBF2DE"), "fail": ("#8A1F1F", "#FDEAEA"), "info": ("#1F4FB0", "#E7EFFD"), "neu": ("#4B5563", "#E6E8ED")},
)


def btn(T, text, primary=False, h=28, extra=""):
    if primary:
        st = f"border: 0; background: {ACC}; color: {T['on_acc']}; font-weight: 600;"
    else:
        st = f"border: 1px solid {T['ctl']}; background: {T['raised']}; color: {T['ink']};"
    return f'<button style="height: {h}px; padding: 0 14px; border-radius: {T["r"]}; font-size: 12px; {st} {extra}">{text}</button>'


def pill(T, text, tone):
    fg, bg = T["tones"][tone]
    return f'<span style="flex-shrink: 0; font-size: 11px; font-weight: 500; padding: 2px 8px; border-radius: {T["pill_r"]}; color: {fg}; background: {bg};">{text}</span>'


def field(T, ph, label, h=30, mono=False, grow=True, w=""):
    fam = f"font-family: {T['mono']};" if mono else "font: inherit;"
    size = "flex-grow: 1;" if grow else f"width: {w};"
    return (f'<input type="text" aria-label="{label}" placeholder="{ph}" style="{size} min-width: 0; height: {h}px; box-sizing: border-box; padding: 0 12px; border: 1px solid {T["ctl"]}; '
            f'border-radius: {T["r"]}; background: {T["sheet"]}; color: {T["ink"]}; {fam} font-size: 12.5px;">')


def area(T, ph, label, h=72):
    return (f'<textarea aria-label="{label}" placeholder="{ph}" style="flex-grow: 1; min-width: 0; height: {h}px; box-sizing: border-box; padding: 8px 12px; border: 1px solid {T["ctl"]}; '
            f'border-radius: {T["r"]}; background: {T["sheet"]}; color: {T["ink"]}; font: inherit; font-size: 12.5px; resize: none;"></textarea>')


def select(T, value, label, w="200px"):
    return (f'<button aria-label="{label}" style="width: {w}; height: 30px; display: flex; align-items: center; padding: 0 12px; border: 1px solid {T["ctl"]}; border-radius: {T["r"]}; '
            f'background: {T["raised"]}; color: {T["ink"]}; font-size: 12.5px; text-align: left;"><span style="flex-grow: 1;">{value}</span><span style="color: {T["muted"]};">▾</span></button>')


def seg(T, options, on):
    out = f'<div style="display: flex; gap: 4px; padding: 3px; border-radius: {T["r"]}; background: {T["raised"]};">'
    for o in options:
        st = f"background: {T['sheet']}; color: {T['ink']}; font-weight: 600; box-shadow: 0 0 0 1px {T['ctl']};" if o == on else f"background: transparent; color: {T['muted']};"
        out += f'<button style="height: 26px; padding: 0 14px; border: 0; border-radius: {T["r"]}; font-size: 12px; {st}">{o}</button>'
    return out + "</div>"


def toggle(T, on, label):
    bg = ACC if on else T["ctl"]
    side = "flex-end" if on else "flex-start"
    return (f'<button aria-label="{label}" style="width: 38px; height: 22px; padding: 2px; border: 0; border-radius: 11px; background: {bg}; display: flex; justify-content: {side};">'
            f'<span style="width: 18px; height: 18px; border-radius: 9px; background: #FFFFFF;"></span></button>')


def sheet(T, w, h, inner):
    """A dialog on a dimmed backdrop."""
    return (f'<div style="width: 1440px; height: 900px; display: flex; align-items: center; justify-content: center;">'
            f'<div style="width: {w}px; height: {h}px; display: flex; flex-direction: column; overflow: hidden; border-radius: {T["R"]}; background: {T["sheet"]}; '
            f'box-shadow: 0 0 0 1px {T["line"]}, {T["shadow"]};">{inner}</div></div>')


def sheet_page(T, title, inner):
    return page(title, T["fonts"], T["links"], f"background: {T['backdrop']}; color: {T['ink']}; font-family: {SANS}; font-size: 13px;", inner, T["accent"], T["swatches"])


def dlg_head(T, title, sub_html="", size=20):
    return (f'<div style="flex-shrink: 0; display: flex; flex-direction: column; gap: 10px; padding: 18px 22px 14px; background: {T["head"]}; border-bottom: 1px solid {T["line"]};">'
            f'<div style="display: flex; align-items: flex-start; gap: 12px;"><div style="flex-grow: 1; font-size: {size}px; line-height: 1.25; {T["title"]}">{title}</div>'
            f'<button aria-label="Close" style="width: 28px; height: 28px; border: 0; border-radius: {T["r"]}; background: {T["raised"]}; color: {T["muted"]}; font-size: 14px;">✕</button></div>{sub_html}</div>')


def dlg_foot(T, left, right):
    return (f'<div style="flex-shrink: 0; display: flex; align-items: center; gap: 8px; padding: 13px 22px; background: {T["head"]}; border-top: 1px solid {T["line"]};">'
            f'{left}<div style="flex-grow: 1;"></div>{right}</div>')


# ───────────── Settings ─────────────
SECTIONS = [("This Mac", ["General", "Appearance", "Agents and defaults", "Start with", "Accounts and connections", "Notifications", "Execution"]),
            ("This project", ["Work", "Project overrides", "Run project"])]


def settings(T, layout):
    nav = ""
    for group, items in SECTIONS:
        nav += f'<div style="{T["label"]} padding: 12px 10px 6px;">{group}</div>'
        for it in items:
            on = it == "Work"
            st = f"background: {ACC}; color: {T['on_acc']}; font-weight: 600;" if on else f"background: transparent; color: {T['ink']};"
            nav += f'<button style="height: 32px; padding: 0 10px; border: 0; border-radius: {T["r"]}; text-align: left; font-size: 13px; {st}">{it}</button>'
    rows = [("Done shows", "How many merged cards the Done column lists before it folds the rest.", select(T, "10", "Done shows", "90px")),
            ("Hide Done", "Done only grows; hiding it gives the other columns the width.", toggle(T, True, "Hide Done")),
            ("Working now", "The milestone the first column reads as Next up.", select(T, "Reliable study sessions", "Working now", "240px")),
            ("[Another Work setting]", "[What it changes, in one line.]", toggle(T, False, "Placeholder setting"))]
    if layout == "console":
        body = f'<div style="display: flex; flex-direction: column; border: 1px solid {T["line"]}; border-radius: {T["R"]}; background: {T["surf"]};">'
        for i, (k, help_, ctl) in enumerate(rows):
            bd = f"border-bottom: 1px solid {T['line']};" if i < len(rows) - 1 else ""
            body += (f'<div style="display: grid; grid-template-columns: 190px minmax(0, 1fr) auto; column-gap: 16px; align-items: center; padding: 11px 14px; {bd}">'
                     f'<div style="font-weight: 600;">{k}</div><div style="font-size: 12px; color: {T["muted"]};">{help_}</div>{ctl}</div>')
        body += "</div>"
    else:
        body = '<div style="display: flex; flex-direction: column; gap: 10px;">'
        for k, help_, ctl in rows:
            body += (f'<div style="display: flex; align-items: center; gap: 16px; padding: 16px 18px; border-radius: {T["R"]}; background: {T["surf"]}; box-shadow: 0 0 0 1px {T["line"]};">'
                     f'<div style="flex-grow: 1; display: flex; flex-direction: column; gap: 4px;"><div style="font-size: 14px; font-weight: 600;">{k}</div>'
                     f'<div style="font-size: 12.5px; line-height: 1.45; color: {T["muted"]};">{help_}</div></div>{ctl}</div>')
        body += "</div>"
    inner = (dlg_head(T, "Settings")
             + f'<div style="flex-grow: 1; min-height: 0; display: flex;"><div style="width: 230px; flex-shrink: 0; box-sizing: border-box; padding: 4px 10px 12px; display: flex; flex-direction: column; gap: 2px; border-right: 1px solid {T["line"]}; background: {T["surf"]};">{nav}</div>'
             + f'<div style="flex-grow: 1; min-width: 0; padding: 22px 24px; display: flex; flex-direction: column; gap: 16px;"><div style="font-size: 17px; {T["title"]}">Work</div>'
             + f'<div style="font-size: 12.5px; color: {T["muted"]};">Applies to studyhub only.</div>{body}</div></div>'
             + dlg_foot(T, "", btn(T, "Close")))
    return sheet(T, 900, 660, inner)


# ───────────── Task dialog ─────────────
STEPS = ["Investigated", "Planned", "Implementing", "Verified"]
EVENTS = [("11:12", "Codex", "patched useScrollRestore.ts"), ("11:07", "Reviewer", "(activity only) flagged a missing cleanup on unmount."),
          ("10:49", "Verifier", "finished: 18 unit checks passed, no runtime reproduction attempted.")]
CHECKS = [("Unit tests · courses", "18 passed", "run"), ("Type check", "clean", "run"), ("Lint", "2 warnings", "wait"), ("End-to-end · navigation", "failed to start", "fail")]


def stepper(T, cur, big=False):
    out = ""
    pad, fs = ("6px 14px", "13px") if big else ("3px 9px", "12px")
    for i, s in enumerate(STEPS):
        if i < cur:
            fg, bg = T["tones"]["run"]
            st = f"color: {fg}; background: {bg};"
        elif i == cur:
            st = f"color: {T['on_acc']}; background: {ACC}; font-weight: 700;"
        else:
            st = f"color: {T['muted']}; background: {T['raised']};"
        out += f'<span style="font-size: {fs}; padding: {pad}; border-radius: {T["pill_r"]}; {st}">{s}</span>'
        if i < 3:
            out += f'<span style="color: {T["muted"]};">›</span>'
    return f'<div style="display: flex; align-items: center; gap: 6px; flex-wrap: wrap;">{out}</div>'


def events(T):
    out = ""
    for t, who, what in EVENTS:
        out += (f'<div style="display: grid; grid-template-columns: 44px minmax(0, 1fr); column-gap: 10px; padding: 9px 0; border-bottom: 1px solid {T["line"]}; line-height: 1.45;">'
                f'<span style="font-family: {T["mono"]}; font-size: 11.5px; color: {T["muted"]};">{t}</span><span><span style="font-weight: 600;">{who}</span> {what}</span></div>')
    return out


def task_dialog(T, layout):
    sub = (f'<div style="display: flex; align-items: center; gap: 8px;"><span style="font-family: {T["mono"]}; font-size: 12px; padding: 3px 9px; border: 1px solid {T["line"]}; border-radius: {T["pill_r"]};">#42</span>'
           f'{pill(T, "Running", "run")}{pill(T, "P1", "wait")}{pill(T, "impact High", "neu")}{pill(T, "complexity Medium", "neu")}'
           f'<div style="flex-grow: 1;"></div><span style="font-size: 11.5px; color: {T["muted"]};">last commit 3d ago · 4 ahead</span></div>')
    if layout == "console":
        tabs = ""
        for i, t in enumerate(["Activity", "Overview", "Changes", "Evidence"]):
            st = f"color: {T['ink']}; font-weight: 600; border-bottom: 2px solid {ACC};" if i == 0 else f"color: {T['muted']}; border-bottom: 2px solid transparent;"
            tabs += f'<button style="height: 36px; padding: 0 12px; border-top: 0; border-left: 0; border-right: 0; background: transparent; font-size: 13px; {st}">{t}</button>'
        content = (f'<div style="flex-shrink: 0; display: flex; padding: 0 12px; background: {T["head"]}; border-bottom: 1px solid {T["line"]};">{tabs}</div>'
                   f'<div style="flex-grow: 1; min-height: 0; padding: 18px 22px; display: flex; flex-direction: column; gap: 14px;">'
                   f'<div style="display: flex; align-items: center; gap: 12px;"><div style="{T["label"]}">Pipeline</div>{stepper(T, 2)}</div>'
                   f'<div style="display: flex; flex-direction: column; padding: 2px 14px; border: 1px solid {T["line"]}; border-radius: {T["R"]}; background: {T["surf"]};">{events(T)}</div>'
                   f'<div style="font-family: {T["mono"]}; font-size: 11.5px; color: {T["muted"]};">fix/42-course-scroll · worktree ~/.devdesk/wt/studyhub-42 · base main@9c2e410</div></div>')
    else:
        crit = ""
        for met, text in [(True, "[Acceptance criterion one]"), (True, "[Acceptance criterion two]"), (False, "[Acceptance criterion three]")]:
            mark = (f'<span style="width: 16px; height: 16px; flex-shrink: 0; border-radius: 8px; background: {T["tones"]["run"][1]}; color: {T["tones"]["run"][0]}; font-size: 10px; display: flex; align-items: center; justify-content: center;">✓</span>'
                    if met else f'<span style="width: 14px; height: 14px; flex-shrink: 0; border: 1px solid {T["ctl"]}; border-radius: 8px;"></span>')
            crit += f'<div style="display: flex; align-items: center; gap: 10px; padding: 9px 0; border-bottom: 1px solid {T["line"]};">{mark}<span>{text}</span></div>'
        chips = ""
        for n, o, tone in CHECKS:
            chips += f'<div style="display: flex; align-items: center; gap: 8px; padding: 7px 0;"><span style="flex-grow: 1;">{n}</span>{pill(T, o, tone)}</div>'
        content = (f'<div style="flex-grow: 1; min-height: 0; padding: 18px 22px; display: flex; flex-direction: column; gap: 16px;">'
                   f'<div style="display: flex; flex-direction: column; gap: 10px; padding: 16px 18px; border-radius: {T["R"]}; background: {T["surf"]}; box-shadow: 0 0 0 1px {T["line"]};">{stepper(T, 2, True)}'
                   f'<div style="font-size: 14px; line-height: 1.5; color: {T["body"]};">11:12 · Codex patched useScrollRestore.ts. Reviewer flagged a missing cleanup on unmount.</div></div>'
                   f'<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 20px;">'
                   f'<div style="display: flex; flex-direction: column;"><div style="{T["label"]} padding-bottom: 4px;">Activity</div>{events(T)}</div>'
                   f'<div style="display: flex; flex-direction: column; gap: 14px;"><div style="display: flex; flex-direction: column;"><div style="{T["label"]} padding-bottom: 4px;">Done when · 2 of 3</div>{crit}</div>'
                   f'<div style="display: flex; flex-direction: column;"><div style="{T["label"]} padding-bottom: 2px;">Checks</div>{chips}</div></div></div>'
                   f'<div style="display: flex; gap: 8px;">{btn(T, "Changes · 3 files")}{btn(T, "Full description")}</div></div>')
    inner = dlg_head(T, "Preserve course-list position", sub, 24) + content + dlg_foot(T, btn(T, "Remove worktree"), btn(T, "Show the run", True) + btn(T, "Close"))
    return sheet(T, 900, 660, inner)


# ───────────── Add task ─────────────
def add_task(T, layout):
    dest = f'<div style="font-size: 12px; color: {T["muted"]};">Filed with gh issue create — no agent run and no labels; /dev or the board labels it.</div>'
    if layout == "console":
        def row(label, ctl, top=False):
            al = "flex-start" if top else "center"
            pt = "padding-top: 7px;" if top else ""
            return (f'<div style="display: flex; align-items: {al}; gap: 14px;"><div style="width: 130px; flex-shrink: 0; text-align: right; font-size: 12.5px; color: {T["muted"]}; {pt}">{label}</div>{ctl}</div>')
        form = (row("Files to", f'<div style="display: flex; flex-direction: column; gap: 3px;"><div style="font-family: {T["mono"]}; font-size: 12px;">github · studyhub</div>{dest}</div>')
                + row("Title", field(T, "What needs doing", "Title"))
                + row("Done when", area(T, "One per line — each becomes a checklist item", "Done when"), True)
                + row("Description", area(T, "What it is and why, in your own words — optional", "Description"), True)
                + row("Impact", select(T, "—", "Impact", "140px")) + row("Complexity", select(T, "—", "Complexity", "140px"))
                + row("Milestone", select(T, "None", "Milestone", "300px")))
    else:
        def block(label, ctl):
            return f'<div style="display: flex; flex-direction: column; gap: 6px;"><div style="{T["label"]}">{label}</div><div style="display: flex;">{ctl}</div></div>'
        files_to = '<div style="height: 30px; display: flex; align-items: center; font-weight: 600;">GitHub · studyhub</div>'
        big = (f'<input type="text" aria-label="Title" placeholder="What needs doing" style="width: 100%; height: 48px; box-sizing: border-box; padding: 0 16px; border: 1px solid {T["ctl"]}; '
               f'border-radius: {T["r"]}; background: {T["sheet"]}; color: {T["ink"]}; font: inherit; font-size: 18px; font-weight: 600;">')
        form = (big + block("Done when", area(T, "One per line — each becomes a checklist item", "Done when", 84))
                + f'<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px;">{block("Impact", seg(T, ["—", "High", "Medium", "Low"], "—"))}{block("Complexity", seg(T, ["—", "High", "Medium", "Low"], "—"))}</div>'
                + f'<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px;">{block("Milestone", select(T, "None", "Milestone", "100%"))}{block("Files to", files_to)}</div>'
                + block("Description — optional", area(T, "What it is and why, in your own words", "Description", 64)))
    inner = (dlg_head(T, "Add a task to Next up") + f'<div style="flex-grow: 1; min-height: 0; padding: 20px 24px; display: flex; flex-direction: column; gap: 14px;">{form}</div>'
             + dlg_foot(T, "", btn(T, "Cancel") + btn(T, "Add &amp; start") + btn(T, "Add task", True)))
    return sheet(T, 720, 640, inner)


# ───────────── Launcher ─────────────
STARTS = [("Open local folder…", "Opens read-only. No agent is launched."), ("Clone repository…", "Choose a destination folder and branch."),
          ("Create new project…", "Initialises a folder and PROJECT_MAP.md.")]
RECENT = [("studyhub", "~/Developer/studyhub", "main"), ("dev-desk", "~/Developer/skills/dev-desk", "main"), ("[project]", "[~/path/to/project]", "[branch]")]


def launcher(T, layout):
    if layout == "console":
        rec = ""
        for i, (n, p, b) in enumerate(RECENT):
            bg = T["raised"] if i == 0 else "transparent"
            rec += (f'<button style="display: grid; grid-template-columns: 150px minmax(0, 1fr) auto; column-gap: 12px; align-items: center; height: 40px; padding: 0 12px; border: 0; border-radius: {T["r"]}; background: {bg}; color: {T["ink"]}; text-align: left;">'
                    f'<span style="font-weight: 600;">{n}</span><span style="font-family: {T["mono"]}; font-size: 11.5px; color: {T["muted"]};">{p}</span><span style="font-family: {T["mono"]}; font-size: 11.5px; color: {ACC};">{b}</span></button>')
        st = ""
        for t, s in STARTS:
            st += (f'<button style="display: flex; flex-direction: column; gap: 3px; padding: 11px 12px; border: 1px solid {T["line"]}; border-radius: {T["r"]}; background: {T["surf"]}; color: {T["ink"]}; text-align: left;">'
                   f'<span style="font-weight: 600;">{t}</span><span style="font-size: 12px; color: {T["muted"]};">{s}</span></button>')
        main = (f'<div style="flex-grow: 1; min-height: 0; display: flex;"><div style="flex-grow: 1; min-width: 0; padding: 18px 16px; display: flex; flex-direction: column; gap: 4px;">'
                f'<div style="display: flex; align-items: center; padding: 0 12px 8px;"><div style="flex-grow: 1; {T["label"]}">Recent projects</div>{btn(T, "Clear", h=24)}</div>{rec}</div>'
                f'<div style="width: 320px; flex-shrink: 0; padding: 18px 16px; display: flex; flex-direction: column; gap: 8px; border-left: 1px solid {T["line"]};"><div style="{T["label"]} padding-bottom: 4px;">Start something</div>{st}</div></div>')
    else:
        rec = ""
        for i, (n, p, b) in enumerate(RECENT):
            ring = ACC if i == 0 else T["line"]
            rec += (f'<button style="display: flex; flex-direction: column; gap: 6px; padding: 16px 18px; border: 0; border-radius: {T["R"]}; background: {T["surf"]}; box-shadow: 0 0 0 1px {ring}; color: {T["ink"]}; text-align: left;">'
                    f'<span style="font-size: 17px; {T["title"]}">{n}</span><span style="font-family: {T["mono"]}; font-size: 11.5px; color: {T["muted"]};">{p} · {b}</span></button>')
        st = ""
        for t, s in STARTS:
            st += (f'<button style="display: flex; flex-direction: column; gap: 3px; padding: 12px 14px; border: 0; border-radius: {T["r"]}; background: {T["raised"]}; color: {T["ink"]}; text-align: left;">'
                   f'<span style="font-weight: 600;">{t}</span><span style="font-size: 12px; color: {T["muted"]};">{s}</span></button>')
        main = (f'<div style="flex-grow: 1; min-height: 0; padding: 20px 24px; display: flex; flex-direction: column; gap: 14px;">'
                f'<div style="display: flex; align-items: center;"><div style="flex-grow: 1; {T["label"]}">Recent projects</div>{btn(T, "Clear", h=24)}</div>'
                f'<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px;">{rec}</div>'
                f'<div style="{T["label"]} padding-top: 8px;">Start something</div><div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px;">{st}</div></div>')
    note = f'<div style="max-width: 640px; font-size: 11.5px; line-height: 1.45; color: {T["muted"]};">Opening a project opens its own window and restores its last selected task and pane layout. Opening a project that is already open focuses that window instead of starting anything.</div>'
    inner = dlg_head(T, "Open Project") + main + dlg_foot(T, note, btn(T, "Open", True, 30))
    return sheet(T, 1000, 540, inner)


# ───────────── Side by side ─────────────
NOTE = "Two independent tasks, separate checkouts and branches. Running in parallel does not guarantee the changes integrate."


def parallel(T, layout):
    shell = b_shell if T["dark"] else c_shell

    def pane(title, line, badge, tone, lines, grow, extra=""):
        return (f'<div style="flex-grow: {grow}; flex-basis: 0; min-width: 0; display: flex; flex-direction: column; border-right: 1px solid {T["line"]};">'
                f'<div style="flex-shrink: 0; display: flex; flex-direction: column; gap: 4px; padding: 12px 16px; border-bottom: 1px solid {T["line"]}; background: {T["head"]};">'
                f'<div style="display: flex; align-items: center; gap: 8px;"><span style="font-weight: 600;">{title}</span>{pill(T, badge, tone)}</div>'
                f'<div style="font-family: {T["mono"]}; font-size: 11px; color: {T["muted"]};">{line}</div></div>{extra}'
                f'<div style="flex-grow: 1; min-height: 0; display: flex; padding: {"0" if T["dark"] else "12px"};">{term(lines, T["mono"], radius="0" if T["dark"] else "12px")}</div></div>')
    ask = (f'<div style="flex-shrink: 0; display: flex; flex-direction: column; gap: 10px; margin: 12px; padding: 14px 16px; border-radius: {T["R"]}; background: {T["surf"]}; box-shadow: 0 0 0 1px {ACC};">'
           f'<div style="font-weight: 600;">Waiting for a decision before implementation continues</div>'
           f'<div style="font-size: 13.5px; line-height: 1.5; color: {T["body"]};">[The run&#39;s question appears here, in its own words.]</div>'
           f'<div style="display: flex; gap: 8px;">{field(T, "Answer the run…", "Answer the run", 32)}{btn(T, "Send", True, 32)}</div></div>')
    if layout == "console":
        panes = (pane("#42 Preserve course-list position", "fix/42-course-scroll · ~/.devdesk/wt/studyhub-42", "Running", "run", T42, 1)
                 + pane("#57 Improve exam recovery", "feat/57-exam-recovery · ~/.devdesk/wt/studyhub-57", "Waiting for input", "wait", T57, 1))
    else:
        panes = (pane("#57 Improve exam recovery", "feat/57-exam-recovery · ~/.devdesk/wt/studyhub-57", "Waiting for input", "wait", T57, 3, ask)
                 + pane("#42 Preserve course-list position", "fix/42-course-scroll · ~/.devdesk/wt/studyhub-42", "Running", "run", T42, 2))
    body = (f'<div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">'
            f'<div style="flex-shrink: 0; display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-bottom: 1px solid {T["line"]};">{btn(T, "‹ Back to Board", h=26)}'
            f'<div style="font-size: 15px; {T["title"]}">Side by side</div><div style="font-size: 12px; color: {T["muted"]};">{NOTE}</div></div>'
            f'<div style="flex-grow: 1; min-height: 0; display: flex;">{panes}</div></div>')
    if T["dark"]:
        return shell("Work", body, dock=False)
    return shell("Work", body)


SCREENS = [("Settings", settings), ("Task", task_dialog), ("AddTask", add_task), ("Launcher", launcher), ("SideBySide", parallel)]
COLS = [("Console", CONSOLE, "console"), ("Focus", FOCUS, "focus"), ("Mix", CONSOLE, "focus")]
NAMES = {"Settings": "Settings", "Task": "Task dialog", "AddTask": "Add task", "Launcher": "Open Project", "SideBySide": "Side by side"}

if __name__ == "__main__":
    for key, fn in SCREENS:
        for col, T, layout in COLS:
            out = fn(T, layout)
            if key != "SideBySide":
                out = sheet_page(T, f"{NAMES[key]} — {col}", out)
            else:
                out = out.replace("<title>Work — ", f"<title>{NAMES[key]} — ")
            with open(os.path.join(OUT, f"{key}-{col}.dc.html"), "w", encoding="utf-8") as fh:
                fh.write(out)
            print(f"{key}-{col}.dc.html")
