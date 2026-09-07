# Prod Secrets — Apple acquisition steps

Read from `shared/prod-secrets.md` §3 (Phase 16, step 2) and **only when a missing secret matches a
name below**. A lookup table, not a phase: it adds no step, gates nothing, and Phase 16 stays
stack-agnostic without it. A missing name that matches nothing here is still reported by name.

## Gate on the REPO first, then the name

`CERT`, `CERTIFICATE`, `P12`, `PRIVATE_KEY`, `PROFILE` and `API_KEY` are not Apple words. Consult
this table only when the repo is an Apple build — `*.xcodeproj`, `*.xcworkspace`, `Package.swift`,
`project.yml`, or a `fastlane/` directory. Handing App Store Connect instructions to someone whose
missing `API_KEY` is a payment provider's is worse than saying nothing, because it reads as
authoritative.

## Match on SUBSTRING, never on the exact name

No two repos name these the same — `ASC_API_KEY`, `APP_STORE_CONNECT_PRIVATE_KEY` and
`AUTH_KEY_P8` are one credential under three names. Match the **fragments** in the table's left
column, case-insensitively, and prefer the most specific hit: `ASC_KEY_ID` is the Key ID, not the
key. An exact-name table would miss most repos and report a credential it could have explained.

**Each comma-separated fragment in the first column is a LITERAL SUBSTRING, never a regex** — test
the fragments one at a time, not the cell as a whole. A parenthetical like *(not `_PASSWORD`)* is an
exclusion for the reader, not a fragment to search for. `FASTLANE_.*PASSWORD` sat here until
2026-09-07 and matched nothing: no real secret name contains the characters `.*`.

| Name contains | What it is | Where it comes from |
|---|---|---|
| `ISSUER` | App Store Connect Issuer ID (one per team) | Integrations page header — §1 |
| `KEY_ID`, `API_KEY_ID` | App Store Connect Key ID (one per key) | the key's row — §1 |
| `API_KEY`, `PRIVATE_KEY`, `AUTH_KEY`, `_P8` | the `.p8` private key itself | downloaded once — §1 |
| `CERTIFICATE`, `CERT`, `P12` (not `_PASSWORD`) | Apple Distribution certificate, as `.p12` | Developer portal — §2 |
| `P12_PASSWORD`, `CERT_PASSWORD` | the password you chose exporting that `.p12` | you invent it — §2 |
| `PROFILE`, `MOBILEPROVISION` | App Store provisioning profile | Developer portal — §3 |
| `KEYCHAIN_PASSWORD` | temp keychain the runner creates | **you invent it** — any string; not from Apple |
| `TEAM_ID` | 10-character team identifier | developer.apple.com → Membership details |
| `MATCH_PASSWORD` | fastlane match repo passphrase | set when `match init` ran; not re-issuable — §4 |
| `APPLICATION_SPECIFIC`, `APP_SPECIFIC` | app-specific password for an Apple ID | appleid.apple.com → Sign-In and Security → App-Specific Passwords |

---

## §1 — App Store Connect API key (Issuer ID · Key ID · `.p8`)

One visit produces all three. App Store Connect → **Users and Access → Integrations → App Store
Connect API**, Team Keys.

1. **Issuer ID** is printed at the top of that page. It is account-wide — the same value for every
   key, so a rotated key never changes it.
2. **Generate API Key** → name it, give it a role. **App Manager** is the least privilege that can
   upload a build; Developer cannot.
3. The new row shows its **Key ID**. Copy it.
4. **Download the `.p8`.** It is named `AuthKey_<KEYID>.p8`.

> **The `.p8` downloads exactly once.** There is no second chance and no re-download — Apple stores
> only the public half. Lose it and the only recovery is to revoke the key and generate a new one,
> which changes the Key ID (and so the secret) but not the Issuer ID.

Set it as the **base64 of the file's contents**:

Set `ASC_API_KEY` (or whatever this repo calls it) against **`prod-secrets.md` §3's requirements** —
every row, especially the round-trip. Three earlier versions of that block shipped a fixed one-liner
and all three were wrong, which is the failure this file's closing section describes. Download the
`.p8` to `$(mktemp -d)`, never into the repo.

## §2 — Distribution certificate (`.p12`)

developer.apple.com → **Certificates, Identifiers & Profiles → Certificates → +**.

1. Choose **Apple Distribution**. It needs a **CSR**: Keychain Access → Certificate Assistant →
   *Request a Certificate From a Certificate Authority*, saved to disk.
2. Upload the CSR, download the resulting `.cer`, open it (it lands in the login keychain).
3. In Keychain Access, select the certificate **together with its private key**, right-click →
   Export → `.p12`, and choose a password. That password is the `P12_PASSWORD` secret.
4. The base64 of the `.p12` is the certificate secret's value. Set `BUILD_CERTIFICATE_BASE64` from
   it against **`prod-secrets.md` §3's requirements** — source path and secret name are yours to
   supply, and the round-trip check is what proves the encoding survived.

`P12_PASSWORD` is a value only the developer knows, so **they** run this in their own terminal —
`gh secret set P12_PASSWORD --repo <owner>/<repo>` prompts and does not echo. An agent must not run
it: gh prompts only on a TTY and otherwise reads stdin, so from a non-interactive shell it stores an
**empty** password and exits 0.

A `.p12` exported *without* the private key installs fine and fails at signing — if the disclosure
triangle beside the certificate shows no key, the export is the wrong one.

## §3 — Provisioning profile

Same portal → **Profiles → +** → **App Store Connect** distribution → pick the App ID and the
certificate from §2 → download the `.mobileprovision` to `$(mktemp -d)`, then set
`BUILD_PROVISION_PROFILE_BASE64` against `prod-secrets.md` §3's requirements.

A profile is bound to the certificate it was created against: replacing the certificate in §2
invalidates it, and the profile must be regenerated. This is the pair that most often drifts.

## §4 — fastlane match

`MATCH_PASSWORD` decrypts the match repository. It is not issued by Apple and cannot be recovered —
if it is lost, `fastlane match nuke` and re-init is the only path, which revokes the team's
certificates. Ask before treating it as a value to regenerate.

---

## The trap that makes all of these fail quietly

Every value above is stored as **base64 of the file's contents** — never a path to the file.

A copy-pasted path looks correct in the secrets UI and decodes to garbage. Worse, `base64 --decode`
of an **unset** secret writes an empty file and exits **0**, so the step consuming it reports
success and the failure surfaces somewhere unrelated:

```
xcodebuild: error: Invalid authentication key credential specified
(CryptoKit.CryptoKitASN1Error.invalidPEMDocument).
```

That error names neither the secret, nor the step, nor the empty file. **Phase 16 step 2 cannot
catch this** — the secret exists, so it passes; it is merely wrong. The workflow-side assertion is
what catches it, and it is one line next to each decode:

```bash
[ -s "$RUNNER_TEMP/AuthKey.p8" ] || { echo "::error::AuthKey.p8 is empty — check ASC_API_KEY"; exit 1; }
```

Recommending that line is in scope for this file. **Editing someone's workflow to add it is not** —
say it belongs there and let the developer put it in.
