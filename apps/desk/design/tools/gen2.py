#!/usr/bin/env python3
"""Column D: the Console look carrying the Focus layouts."""
import os
from gen import (OUT, MONO_B as M, B_BTN, B_PRI, B_LABEL, b_shell, b_header, b_filter, term, sketch, T57, IDEAS)

INK, MUTED, BODY, LINE, SURF, RAISED = "#E4E7EB", "#8E96A3", "#C9CDD4", "#262B33", "#16191E", "#1B1F25"
ACC = "{{accent}}"
TONE = {"run": ("#7FD19B", "#16301F"), "wait": ("#E7C067", "#33280F"), "fail": ("#F19A9A", "#331A1A"),
        "info": ("#9CC0FF", "#1B2A45"), "neu": ("#AEB4BD", "#2A2D33")}
PRI = {"P0": "fail", "P1": "wait", "P2": "info", "P3": "neu"}
CARD = f"border: 1px solid {LINE}; border-radius: 6px; background: {SURF};"


def pill(text, tone, bold=False):
    fg, bg = TONE[tone]
    w = "font-weight: 600;" if bold else ""
    return f'<span style="flex-shrink: 0; font-size: 11px; padding: 1px 7px; border-radius: 4px; color: {fg}; background: {bg}; {w}">{text}</span>'


def col_head(title, n, extra=""):
    return (f'<div style="display: flex; align-items: center; gap: 8px; height: 28px; font-family: {M}; font-size: 11.5px; text-transform: uppercase; letter-spacing: 0.05em;">'
            f'<span style="font-weight: 600;">{title}</span><span style="color: {MUTED};">{n}</span><div style="flex-grow: 1;"></div>{extra}</div>')


def small_card(id_, title, pri, note, action):
    return (f'<div style="display: flex; flex-direction: column; gap: 8px; padding: 11px 12px; {CARD}">'
            f'<div style="font-weight: 600; line-height: 1.35;">{title}</div>'
            f'<div style="display: flex; align-items: center; gap: 6px; font-size: 11px;">{pill(pri, PRI[pri], True)}'
            f'<span style="font-family: {M}; color: {MUTED};">{id_} · {note}</span><div style="flex-grow: 1;"></div>'
            f'<button style="{B_BTN} height: 22px; padding: 0 9px; font-size: 11px;">{action}</button></div></div>')


def steps(cur):
    out = ""
    for i, label in enumerate(["Investigated", "Planned", "Implementing", "Verified"]):
        if i < cur:
            st = f"color: {TONE['run'][0]}; background: {TONE['run'][1]};"
        elif i == cur:
            st = f"color: #0F1114; background: {ACC}; font-weight: 600;"
        else:
            st = f"color: {MUTED}; background: {RAISED};"
        out += f'<span style="font-family: {M}; font-size: 11px; padding: 2px 9px; border-radius: 4px; {st}">{label}</span>'
    return out


def big_card(id_, title, status, tone, cur, last, pri, branch, facts, action, primary, hot, compact=False):
    border = ACC if hot else LINE
    btn = ""
    if action:
        btn = f'<button style="{B_PRI if primary else B_BTN}">{action}</button>'
    return f"""<div style="display: flex; flex-direction: column; gap: 11px; padding: 14px 16px; border: 1px solid {border}; border-radius: 6px; background: {SURF};">
            <div style="display: flex; align-items: flex-start; gap: 10px;"><div style="flex-grow: 1; font-size: 15px; font-weight: 600; line-height: 1.3;">{title}</div>{pill(status, tone)}</div>
            <div style="display: flex; align-items: center; gap: 4px; flex-wrap: wrap;">{steps(cur)}</div>
            {"" if compact else f'<div style="font-size: 12.5px; line-height: 1.45; color: {BODY};">{last}</div>'}
            <div style="display: flex; align-items: center; gap: 8px; font-size: 11px; color: {MUTED};">{pill(pri, PRI[pri], True)}<span style="font-family: {M};">{id_} · {branch}</span><span>{facts}</span><div style="flex-grow: 1;"></div>{btn}</div>
          </div>"""


def d_work(dock=True):
    k = dock in ("open", "open-menu")
    groups = [("milestone", [("reliable-study-sessions", 8, True), ("offline-first", 6, False), ("faster-search", 4, False), ("none", 6, False)]),
              ("priority", [("P0", 1, False), ("P1", 3, False), ("P2", 2, False), ("P3", 1, False)]),
              ("type", [("bug", 3, False), ("feature", 4, False), ("epic", 1, False)])]
    tools = (f'<input type="search" placeholder="Search tasks" aria-label="Search tasks" style="width: 190px; height: 26px; box-sizing: border-box; padding: 0 10px; border: 1px solid #343A44; border-radius: 5px; background: {RAISED}; color: {INK}; font: inherit; font-size: 12px;">'
             f'<button style="{B_PRI}">New task</button>')
    live = f'<span style="display: flex; align-items: center; gap: 6px; text-transform: none; letter-spacing: 0; color: {ACC};"><span style="width: 6px; height: 6px; border-radius: 3px; background: {ACC};"></span>1 live</span>'
    body = f"""{b_filter(groups)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {b_header("work", "reliable-study-sessions · 12 of 20 done", tools)}
      <div style="flex-grow: 1; min-height: 0; padding: 12px 16px 16px; display: flex; gap: 14px;">
        <div style="width: 248px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;">
          {col_head("Next up", 3)}
          {small_card("#65", "Reduce initial bundle size", "P1", "no agent yet", "Start")}
          {small_card("#68", "Flashcard deck import", "P2", "waits for #59", "Start")}
          {small_card("#71", "Offline lesson cache", "P3", "no branch yet", "Start")}
        </div>
        <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; gap: 10px;">
          {col_head("In progress", 3, live + f'<button style="{B_BTN} height: 22px; padding: 0 9px; font-size: 11px; text-transform: none; letter-spacing: 0;">Side by side</button>')}
          {big_card("#57", "Improve exam recovery", "Needs a decision", "wait", 1, "Waiting for a decision before implementation continues — the Claude session is paused on a question.", "P0", "feat/57-exam-recovery", "1d ago · 2 ahead", "Answer", True, True, k)}
          {big_card("#42", "Preserve course-list position", "Running", "run", 2, "11:12 · Codex patched useScrollRestore.ts. Reviewer flagged a missing cleanup on unmount.", "P1", "fix/42-course-scroll", "3d ago · 4 ahead", "Show the run", False, False, k)}
          {big_card("#63", "Investigate slow lesson search", "Tracking only", "info", 0, "External checkout at ~/scratch/studyhub-search — not managed here, commits are read as they land.", "P2", "spike/search-profiling", "5d ago · 7 ahead", "", False, False, k)}
        </div>
        <div style="width: 248px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;">
          {col_head("Review", 1)}
          <div style="display: flex; flex-direction: column; gap: 8px; padding: 11px 12px; {CARD}">
            <div style="font-weight: 600; line-height: 1.35;">Rewrite shared date helpers</div>
            <div style="font-family: {M}; font-size: 11px; color: {MUTED};">#59 · refactor/59-date-helpers</div>
            <div style="display: flex; align-items: center; gap: 6px; font-size: 11px;">{pill("Approved", "run")}<span style="color: {MUTED};">6h ago · 9 ahead</span><div style="flex-grow: 1;"></div><button style="{B_BTN} height: 22px; padding: 0 9px; font-size: 11px;">Open PR</button></div>
          </div>
        </div>
        <button aria-label="Show Done, 12 merged" style="width: 52px; flex-shrink: 0; display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 12px 0; {CARD} color: {INK};">
          <span style="font-family: {M}; font-size: 13px; font-weight: 600; color: {TONE['run'][0]};">12</span>
          <span style="writing-mode: vertical-rl; font-family: {M}; font-size: 11.5px; text-transform: uppercase; letter-spacing: 0.05em; color: {MUTED};">Done</span>
        </button>
      </div>
    </div>"""
    return b_shell("Work", body, dock=dock)


def queue_row(title, sub, kind):
    bg = RAISED if kind == "cur" else "transparent"
    dot = {"done": "#454A53", "cur": ACC, "todo": "#1F8B4C", "wait": "#B7791F"}[kind]
    op = "0.55" if kind == "done" else "1"
    w = 600 if kind == "cur" else 400
    return (f'<button style="display: flex; align-items: center; gap: 10px; min-height: 48px; padding: 5px 10px; border: 0; border-radius: 5px; background: {bg}; color: {INK}; text-align: left; opacity: {op};">'
            f'<span style="width: 7px; height: 7px; flex-shrink: 0; border-radius: 4px; background: {dot};"></span>'
            f'<span style="display: flex; flex-direction: column; gap: 2px; min-width: 0;"><span style="font-weight: {w}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{title}</span>'
            f'<span style="font-family: {M}; font-size: 11px; color: {MUTED};">{sub}</span></span></button>\n')


def left_pane(title, status, tool, chips, rows, progress=None):
    bar = ""
    if progress:
        bar = f'<div style="height: 4px; border-radius: 2px; background: {LINE}; display: flex;"><div style="width: {progress}; border-radius: 2px; background: {ACC};"></div></div>'
    chip_html = ""
    for i, c in enumerate(chips):
        st = f"background: {INK}; color: #0F1114; font-weight: 600;" if i == 0 else f"background: {RAISED}; color: {INK};"
        chip_html += f'<button style="height: 24px; padding: 0 10px; border: 0; border-radius: 4px; font-family: {M}; font-size: 11.5px; {st}">{c}</button>'
    return f"""<div style="width: 340px; flex-shrink: 0; box-sizing: border-box; display: flex; flex-direction: column; border-right: 1px solid {LINE}; background: #12151A;">
      <div style="padding: 16px 16px 12px; display: flex; flex-direction: column; gap: 10px;">
        <div style="display: flex; align-items: center;"><h1 style="margin: 0; flex-grow: 1; font-family: {M}; font-size: 15px; font-weight: 600;">{title}</h1><button style="{B_BTN} height: 24px; font-size: 11.5px;">{tool}</button></div>
        <div style="font-family: {M}; font-size: 12px; color: {MUTED};">{status}</div>
        {bar}
        <div style="display: flex; gap: 6px;">{chip_html}</div>
      </div>
      <div style="display: flex; flex-direction: column; gap: 2px; padding: 0 8px;">{rows}</div>
    </div>"""


def info_card(label, main, sub="", mono=False):
    fam = f"font-family: {M}; font-size: 11.5px; line-height: 1.7;" if mono else "font-weight: 600;"
    s = f'<div style="font-size: 12px; line-height: 1.45; color: {MUTED};">{sub}</div>' if sub else ""
    return f'<div style="display: flex; flex-direction: column; gap: 6px; padding: 13px 15px; {CARD}"><div style="{B_LABEL}">{label}</div><div style="{fam}">{main}</div>{s}</div>'


def choice(title, sub, primary=False):
    if primary:
        st, sc = f"border: 1px solid {ACC}; background: {ACC}; color: #0F1114;", "#0F1114"
    else:
        st, sc = f"border: 1px solid #343A44; background: {RAISED}; color: {INK};", BODY
    return (f'<button style="display: flex; flex-direction: column; align-items: flex-start; gap: 4px; padding: 14px 16px; border-radius: 6px; text-align: left; {st}">'
            f'<span style="font-size: 15px; font-weight: 700;">{title}</span><span style="font-size: 12px; line-height: 1.4; color: {sc};">{sub}</span></button>')


def d_findings():
    rows = (queue_row("Navigation resets list state on unmount", "F-108 · added to #42", "done")
            + queue_row("Lesson player leaves its interval running", "F-112 · filed", "done")
            + queue_row("Search index rebuilt per keystroke", "F-093 · declined before", "done")
            + queue_row("Exam attempt store writes twice", "F-111 · needs a decision", "cur")
            + queue_row("Two date helpers format the same field differently", "F-117 · new · architecture", "todo")
            + queue_row("Attempt timer drifts when the tab sleeps", "F-115 · new · defect", "todo"))
    body = f"""{left_pane("findings", "run-0940 · 3 of 6 decided", "Hunt again", ["to decide", "decided", "ignored"], rows, "50%")}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; align-items: center;">
      <div style="width: 700px; padding-top: 40px; display: flex; flex-direction: column; gap: 18px;">
        <div style="display: flex; align-items: center; gap: 8px; font-family: {M}; font-size: 11.5px;"><span style="color: {MUTED};">F-111</span>{pill("Needs a decision", "wait")}{pill("Defect", "neu")}<div style="flex-grow: 1;"></div><span style="color: {MUTED};">4 of 6</span></div>
        <div style="font-size: 28px; font-weight: 700; line-height: 1.2; letter-spacing: -0.01em;">Exam attempt store writes twice</div>
        <div style="font-size: 15px; line-height: 1.6; color: {BODY};">[The finding&#39;s summary, in the report&#39;s own words — the one paragraph you need to decide.]</div>
        <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px;">
          {info_card("Verification", "Unconfirmed observation", "Found, but no checker confirmed it — filed only if you choose to.")}
          {info_card("Sources · 2", "src/features/exam/attemptStore.ts:41<br>src/features/exam/useAttempt.ts:77", mono=True)}
        </div>
        <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; padding-top: 8px;">
          {choice("File it", "A new issue, with the report&#39;s evidence attached", True)}
          {choice("Add to #57", "Improve exam recovery is open and touches the same store")}
          {choice("Drop it", "Ignored until you ask for ignored findings")}
        </div>
        <div style="display: flex; align-items: center; gap: 12px; font-size: 12px; color: {MUTED};">
          <button style="{B_BTN}">Skip for now</button>
          <button style="height: 26px; padding: 0 4px; border: 0; background: transparent; color: {ACC}; font-size: 12px;">Open full finding</button>
          <div style="flex-grow: 1;"></div><span style="font-family: {M};">decide each once · next: F-117</span>
        </div>
      </div>
    </div>"""
    return b_shell("Findings", body)


def d_sessions():
    others = ""
    for t, s, dot, last in [("#42 Preserve course-list position", "Codex · running · 24m", "#1F8B4C", "11:12 · patched useScrollRestore.ts"),
                            ("studyhub dev server", "Project run · running · 3h", "#1F8B4C", "[last line of output]"),
                            ("Findings hunt", "Door · ended", "#454A53", "14 findings written to docs/findings/"),
                            ("zsh", "Terminal", "#454A53", "")]:
        others += (f'<button style="display: flex; flex-direction: column; gap: 4px; padding: 11px 12px; {CARD} color: {INK}; text-align: left;">'
                   f'<span style="display: flex; align-items: center; gap: 8px;"><span style="width: 7px; height: 7px; border-radius: 4px; background: {dot};"></span><span style="font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{t}</span></span>'
                   f'<span style="font-size: 11.5px; color: {MUTED};">{s}</span><span style="font-family: {M}; font-size: 11px; color: {BODY};">{last}</span></button>\n')
    body = f"""<div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {b_header("sessions", "2 running · 5 open · 1 needs you", f'<button style="{B_PRI}">New session</button>')}
      <div style="flex-grow: 1; min-height: 0; padding: 16px; display: flex; gap: 16px;">
        <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; gap: 12px;">
          <div style="display: flex; flex-direction: column; gap: 12px; padding: 14px 16px; border: 1px solid {ACC}; border-radius: 6px; background: {SURF};">
            <div style="display: flex; align-items: center; gap: 10px;"><div style="flex-grow: 1; font-size: 16px; font-weight: 600;">#57 Improve exam recovery</div>{pill("Needs a decision", "wait")}<button style="{B_BTN} height: 24px; font-size: 11.5px;">Open the task</button></div>
            <div style="font-size: 14px; line-height: 1.5; color: {BODY};">[The run&#39;s question appears here, in its own words — large enough to answer without reading the transcript.]</div>
            <div style="display: flex; gap: 8px;">
              <input type="text" aria-label="Answer the run" placeholder="Answer the run…" style="flex-grow: 1; height: 32px; box-sizing: border-box; padding: 0 12px; border: 1px solid #343A44; border-radius: 5px; background: #0F1114; color: {INK}; font-family: {M}; font-size: 12px;">
              <button style="{B_PRI} height: 32px; padding: 0 16px;">Send</button>
            </div>
          </div>
          {term(T57, M, pad="14px 16px", radius="6px")}
        </div>
        <div style="width: 320px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;">
          {col_head("Also open", 4)}
          {others}
          <div style="height: 8px;"></div>
          {col_head("Recovered", 1)}
          <div style="display: flex; flex-direction: column; gap: 8px; padding: 11px 12px; {CARD}">
            <div style="font-weight: 600;">Ideation run</div>
            <div style="font-size: 12px; line-height: 1.45; color: {MUTED};">Was running when Dev Desk last closed unexpectedly. Nothing was restarted — continuing is your call.</div>
            <div><button style="{B_BTN} height: 24px; font-size: 11.5px;">Run the door again</button></div>
          </div>
        </div>
      </div>
    </div>"""
    return b_shell("Sessions", body, dock=False)


def d_ideation():
    kinds = {"Confirmed": "todo", "Unconfirmed": "wait", "Rejected": "done"}
    rows = ""
    for i, (t, v, g, c) in enumerate(IDEAS):
        rows += queue_row(t, f"{v.lower()} · gain {g.lower()} · cost {c.lower()}", "cur" if i == 0 else kinds[v])
    cards = ""
    for k, v, sub in [("Gain", "High", "[why]"), ("Cost", "Low", "[why]"), ("Doing nothing", "—", "[what it costs to leave it]")]:
        cards += (f'<div style="display: flex; flex-direction: column; gap: 4px; padding: 14px 16px; {CARD}"><div style="{B_LABEL}">{k}</div>'
                  f'<div style="font-family: {M}; font-size: 22px; font-weight: 600;">{v}</div><div style="font-size: 12px; color: {MUTED};">{sub}</div></div>')
    body = f"""{left_pane("ideation", "run-0931 · 5 ideas", "Generate ideas", ["all", "confirmed", "unconfirmed"], rows)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; align-items: center;">
      <div style="width: 720px; padding-top: 40px; display: flex; flex-direction: column; gap: 18px;">
        <div style="display: flex; align-items: center; gap: 8px; font-size: 11.5px;">{pill("Confirmed", "run")}{pill("performance", "neu")}</div>
        <div style="font-size: 28px; font-weight: 700; line-height: 1.2; letter-spacing: -0.01em;">Debounce the lesson search index rebuild</div>
        <div style="font-family: {M}; font-size: 13px; color: {ACC};">→ [the change the run proposes, in one line]</div>
        <div style="font-size: 15px; line-height: 1.6; color: {BODY};">[The opportunity&#39;s summary, in the report&#39;s own words.]</div>
        <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px;">{cards}</div>
        <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px;">
          {info_card("Source locations", "src/features/search/index.ts:30<br>src/features/search/useSearch.ts:12", mono=True)}
          {info_card("Verification limits", '<span style="font-weight: 400; color: ' + BODY + ';">[What this run could not check.]</span>')}
        </div>
        <div style="display: flex; gap: 10px; padding-top: 4px;"><button style="{B_PRI} height: 36px; padding: 0 20px; font-size: 13px;">File it…</button><button style="{B_BTN} height: 36px; padding: 0 16px; font-size: 13px;">Not now</button></div>
      </div>
    </div>"""
    return b_shell("Ideation", body)


def d_diagrams():
    groups = [("draw", [("architecture", "●", True), ("data-flow", "", False), ("sequence", "2 of 5", False)])]
    body = f"""{b_filter(groups)}
    <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column;">
      {b_header("diagrams", "architecture · studyhub-architecture.html", f'<button style="{B_BTN}">What to draw…</button><button style="{B_PRI}">Redraw</button>')}
      <div style="flex-grow: 1; min-height: 0; margin: 16px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; border: 1px solid {LINE}; border-radius: 6px; background-color: #0B0D10; background-image: radial-gradient(#1E2228 1px, transparent 1px); background-size: 24px 24px;">
        {sketch("#454A53", "#16191E", "#E4E7EB", "#8E96A3", "#16301F", "Menlo, monospace")}
        <div style="font-family: {M}; font-size: 11.5px; color: {MUTED};">[docs/arch/studyhub-architecture.html renders here — this sketch is a stand-in]</div>
      </div>
    </div>"""
    return b_shell("Diagrams", body)


FILES = {"Work-Mix.dc.html": d_work, "Work-Mix-Dock.dc.html": lambda: d_work("open-menu"), "Findings-Mix.dc.html": d_findings, "Sessions-Mix.dc.html": d_sessions,
         "Ideation-Mix.dc.html": d_ideation, "Diagrams-Mix.dc.html": d_diagrams}
for name, fn in FILES.items():
    html = fn().replace(" — Console</title>", " — Console × Focus</title>")
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as fh:
        fh.write(html)
    print(name)
