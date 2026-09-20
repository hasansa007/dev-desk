#!/usr/bin/env python3
"""The agreed design, end to end: every shell screen carries the project strip and the project icon."""
import os
from gen import OUT
from gen2 import d_work, d_findings, d_sessions, d_ideation, d_diagrams
from gen3 import parallel, CONSOLE
from gen4 import with_strip

FILES = {
    "Main.dc.html": (lambda: d_work(True), "Work"),
    "Work-Mix-Dock.dc.html": (lambda: d_work("open-menu"), "Work, dock open"),
    "Findings-Mix.dc.html": (d_findings, "Findings"),
    "Sessions-Mix.dc.html": (d_sessions, "Sessions"),
    "Ideation-Mix.dc.html": (d_ideation, "Ideation"),
    "Diagrams-Mix.dc.html": (d_diagrams, "Diagrams"),
    "SideBySide-Mix.dc.html": (lambda: parallel(CONSOLE, "focus"), "Side by side"),
}
for name, (fn, title) in FILES.items():
    html = with_strip(fn())
    a = html.index("<title>"); b = html.index("</title>")
    html = html[:a] + f"<title>{title} — Dev Desk" + html[b:]
    open(os.path.join(OUT, name), "w", encoding="utf-8").write(html)
    print(name, html.count('data-strip'), html.count('data-avatar'))
