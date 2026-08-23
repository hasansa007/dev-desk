# `dev:launch` — say which iOS device class, and stop counting extensions as apps

**Date:** 2026-08-23
**Status:** approved, not yet implemented
**Touches:** `skills/launch/scripts/run-ios.sh`, `skills/launch/SKILL.md`

---

## Why

Asked for `/dev:launch ios iphone` and `/dev:launch ios ipad`. Neither works today, and the
reason splits into two defects that were found by trying it on a real repo (SonicPlayer, an
iPhone+iPad app — `TARGETED_DEVICE_FAMILY = "1,2"`).

### Defect 1 — there is no way to say "iPad"

`run-ios.sh` picks a device in one of two modes and neither accepts a *class*:

```python
if want:
    matches = [c for c in candidates if c["udid"] == want] or \
              [c for c in candidates if c["name"] == want]
else:
    phones = [c for c in candidates if c["name"].startswith("iPhone")] or candidates
```

- With no argument it hardcodes `startswith("iPhone")`. iPhone is the default and cannot be named.
- With an argument it matches a **whole name, case-sensitively**. So `ipad` fails, `iPad` fails,
  `iphone 17 pro` fails, and only `iPad Pro 13-inch (M5)` — the exact string, parentheses and all —
  succeeds. Getting an iPad today means pasting a device name out of `simctl list`.

`SKILL.md` Phase 1 has no `iphone`/`ipad` token either; its table sends any unrecognised word
through to this matcher as a device name.

### Defect 2 — an app extension is counted as an app scheme, so the script refuses to run

Measured on SonicPlayer, 2026-08-23:

```
$ run-ios.sh --root /Users/hasan/Developer/SonicPlayer
run-ios.sh: more than one app scheme — pass --scheme NAME.
  candidates: SonicPlayer, SonicPlayerShare
```

`SonicPlayerShare` is a share extension — `productType = "com.apple.product-type.app-extension"`,
`WRAPPER_EXTENSION = appex`. It survives because the filter is a **name blocklist**
(`Tests`, `UITests`, `Widget`, `Screenshot`, `Watch`, `Extension`, `Clip`) and nothing in
`SonicPlayerShare` matches it. An extension named for what it does rather than for what it is
defeats the list — which is most of them.

This is Step 2.0's own rule 3 unapplied: the project **declares** each target's product type, and
the script guesses from the name instead. And the failure is the expensive shape — the script
stops, so the developer goes back to hand-typing `xcodebuild … && simctl install && simctl launch`,
which is the four-command pipeline `run-ios.sh` exists to replace.

The two defects are independent, but the second one means `/dev:launch ios iphone` would still not
run on this repo after the first is fixed. Both ship together.

---

## What ships

Two tokens, orthogonal to the `sim` / `device` tokens that already choose simulator vs hardware:

| Command | Result |
|---|---|
| `/dev:launch ios iphone` | newest booted iPhone simulator, else the newest available one |
| `/dev:launch ios ipad` | the same ladder over iPads |
| `/dev:launch ios ipad device` | a connected physical iPad |
| `/dev:launch ios "ipad air"` | case-insensitive, substring — matches `iPad Air 13-inch (M4)` |
| `/dev:launch ios` | unchanged: iPhone, because that is the default it already had |

---

## Design 1 — a class is a substring match, not a special case

The temptation is `if want in ("iphone", "ipad"): <class branch>`. Rejected: it adds a third
matching mode next to the two that already disagree with each other, and it answers `ipad` while
still failing `iPad` and `ipad air`.

Instead **one** matcher, applied to whatever the user typed:

1. UDID, exact.
2. Name, exact, case-insensitive.
3. Name, prefix, case-insensitive.
4. Name, substring, case-insensitive.

Stop at the first rung that matches anything; rank whatever it returns. `iphone` and `ipad` then
need no code of their own — they are rung 4 against every device of that family. `ipad air` is
rung 4 against two. `iPhone 17 Pro` is rung 2 against one per runtime.

Ranking is unchanged in spirit and generalised across families:

```
(booted, runtime_version, tier, inches, name)
```

- **booted first** — unchanged, and the reason is unchanged: booting a third simulator to run on it
  is slower and leaves the developer with three.
- **tier** — `Pro Max` 3 › `Pro` 2 › `Air` 1 › everything else 0. Reads correctly for both
  families: iPhone Pro Max › iPhone Pro › iPhone Air › iPhone 17e, and iPad Pro › iPad Air ›
  iPad mini › iPad.
- **inches** — the integer in `13-inch` / `11-inch`, else 0. Only iPads carry one; it breaks the
  Pro tie, larger wins, matching the existing Pro Max preference for phones.

The no-argument default becomes `want = "iphone"` fed through the same ladder, deleting the
`startswith` branch. Same behaviour, one code path.

**Absence gets its search path.** Today an unmatched name says only
`no available simulator named or identified by 'ipad'`. Under Step 2.0 rule 2 that is a claim
without evidence, and it is the exact shape the rule exists to catch: the message reads as *"your
machine has no iPad"* when the truth was *"I compared case-sensitively"*. The new message lists the
available device names.

## Design 2 — an app scheme is one whose target declares `com.apple.product-type.application`

Build `target → productType` from every `project.pbxproj` under `$PROJECT_ROOT`, excluding
`Pods/`, `Carthage/`, `.build/`, `DerivedData/`. Resolve each scheme to its target — the
`BlueprintName` in a shared `.xcscheme` if there is one, otherwise the scheme's own name, which is
what Xcode's autocreated schemes use — and keep only schemes whose target's product type is
**exactly** `com.apple.product-type.application`.

Exactly, because `com.apple.product-type.application.watchapp2` starts with the same string and is
not the app to launch on an iPhone.

Ordering of the ladder, and why the obvious option is not first:

1. **pbxproj `productType`.** A declaration, read from files, no `xcodebuild` invocation. On
   SonicPlayer it maps `SonicPlayer → application`, `SonicPlayerShare → app-extension`,
   `SonicPlayerTests → bundle.unit-test` and resolves the refusal to one scheme.
2. **The existing name blocklist**, if step 1 read nothing — an unparseable or absent pbxproj, or
   a scheme whose target is not found.
3. **Refuse, as today**, if 2+ genuine application schemes survive. That case is ambiguous in fact
   and is worth the question; `SonicPlayerShare` never was.

`xcodebuild -showBuildSettings` is **not** in the ladder despite being the most direct read.
Measured at **1.9 s per scheme**, and it prints the settings of *every* target the scheme builds —
for `SonicPlayerShare` it emitted `PRODUCT_TYPE = app-extension` *and*
`PRODUCT_TYPE = application`, because the scheme builds the host app too. A `grep | head -1`
against that output is a coin toss. Against 2.3.2's measured 1130-scheme project it is also
over half an hour.

This changes `SKILL.md` 2.3.2 Path B as well, which carries the same blocklist in prose: the
declaration goes in front of it there too, so the script and the prose fallback agree.

## Design 3 — the class token reaches physical devices

`iphone` / `ipad` filter `xcrun devicectl list devices` by name in Phase 3B exactly as they filter
the simulator list, then the existing rule applies unchanged: first device with
State = `connected`. Prose only — 3B has no script. Without this the token would silently mean
nothing when combined with `device`, which is a token that lies rather than one that is absent.

---

## Files

| File | Change |
|---|---|
| `skills/launch/scripts/run-ios.sh` | the match ladder, the generalised rank, the pbxproj scheme resolver, the listing error message, the header help |
| `skills/launch/SKILL.md` Phase 1 | `iphone` / `ipad` row; note that `phone` is an alias of `device`, not a device class |
| `skills/launch/SKILL.md` 3A.1 | selection priority rewritten as the class ladder |
| `skills/launch/SKILL.md` 3B.1 | class filter over `devicectl list devices` |
| `skills/launch/SKILL.md` 2.3.2 Path B | product-type declaration ahead of the name blocklist |
| `skills/launch/SKILL.md` recovery table | the "more than one app scheme" row now describes when it can still fire |

## Verification

Not "it should work" — each row is a command whose output goes in the PR.

| Check | Command | Expected |
|---|---|---|
| iPhone class | `run-ios.sh --root <SonicPlayer> iphone` | builds, installs, launches on an iPhone 17 Pro sim |
| iPad class | `run-ios.sh --root <SonicPlayer> ipad` | same, on an iPad — proving the scheme fix too, since neither ran before |
| Substring | `run-ios.sh "ipad air"` | resolves to an iPad Air, not an error |
| Case | `run-ios.sh "iphone 17 pro"` | resolves; fails today |
| Exact name still wins | `run-ios.sh "iPhone 17 Pro"` | one device, newest runtime |
| Scheme by declaration | the two runs above | no `more than one app scheme`, and the summary prints `Scheme: SonicPlayer` |
| No false negative | `run-ios.sh "iPhone 99"` | error **lists the available names** |
| No regression | `run-ios.sh --root <SonicPlayer>` | unchanged: an iPhone |

## Out of scope

- Android. `run-android.sh` has its own device selection and its own defects if any; not touched.
- `dev:shots` and `dev:launch-kill`, which read this skill's discovery but not its device argument.
- Making `phone` stop meaning "physical device". It is confusing next to `iphone`, but renaming a
  token that already ships breaks invocations for a cosmetic gain. The Phase 1 table says plainly
  which is which instead.
