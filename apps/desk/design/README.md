# Dev Desk — design reference

`console-focus-prototype.html` is the clickable reference for the Console × Focus redesign: open it in a browser.

Rail icons or keys `1`–`5` switch tabs, in rail order — Work, Findings, Sessions, Ideation, Diagrams.
The left strip switches project · `h` Home · `j` dock · `s` rail labels.

A session starts from the **dock**, not from a card: its `+` offers a new session in this project and
any session left running when the app last closed, so starting and resuming are the same gesture.

`tools/` regenerates it: `python3 tools/gen_proto.py` (the other `gen*.py` write the canvas artboards into `tools/project/`, which is ignored).
