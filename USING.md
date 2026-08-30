# Building your own Delphi 7 project with this image

`d7-dev` (see `PLAN.md`) is **one shared Delphi 7 workstation image** — Wine + a
baked D7 prefix (IDE, `dcc32`, BDE engine, QuickReport, Rave) with a curated set
of third-party components already installed, the way a team's dev machines would
be. All projects use the same image; you do not build one per project (the D7
install itself needs a human, so that would not be sensible).

## What's already in the workstation

The `default` profile (`profiles/default.conf`) installs:

| Component | Where | Notes |
| --- | --- | --- |
| **Indy 10.6.3.12** | `C:\opt\indy10\dcu` + palette | swapped in for the bundled Indy 9 |
| **mwajpeg** 1.10.0 | `C:\opt\mwajpeg\dcu` + palette | `TDBJPEGImage` design package registered |
| **djson** 1.0 | `C:\opt\djson\dcu` | RTL-only unit, no palette entry |

`C:\opt` is a symlink to `/opt` in the prefix, so both `C:\opt\<name>\dcu` and the
Unix `/opt/<name>/dcu` work on `dcc32 -U`; the IDE library path needs the
`C:\opt\…` form.

**To add another component to the workstation** (it belongs to the *IDE setup*,
not to one project's dependency list): drop `vendor/<name>/`, add
`scripts/install-<name>.sh` and a `Containerfile.d/NN-<name>.part` fragment
(model them on `20-mwajpeg.part` / `install-mwajpeg.sh`), list `<name>` in
`profiles/default.conf`, and rerun `scripts/build-image.sh`. `--with <name>` /
`--without <name>` build one-off variants without editing the profile.

## Wiring a project in

Everything below lives in *your project's* repo, not this one. The project layer
is deliberately thin: a `dcc32.cfg`, optionally an overlay image for source
patches, a BDE alias at container start, and a run wrapper.

---

## 1. Overlay image — `FROM d7-dev`

Keep it in the project repo (e.g. `docker/Containerfile`):

Often you need no overlay at all — just mount the source and a `dcc32.cfg`
(§2, §6). Add an overlay only for things that must be baked: source patches, or a
project-only unit that isn't worth making a workstation component.

```dockerfile
FROM d7-dev

COPY --chown=dev:dev docker/dcc32.cfg "/home/dev/d7/drive_c/Program Files/Borland/Delphi7/Bin/dcc32.cfg"

# A unit used only by this project (not a shared workstation component). Anything
# reusable across projects belongs in a Containerfile.d/ fragment instead — see
# "What's already in the workstation" above.
COPY --chown=dev:dev vendor/proj-only/ /opt/proj-only/

# BDE alias the app expects but never creates itself (see §5) — do it at
# container start, not build time, so it can point at the run's data mount.
COPY --chown=dev:dev docker/entrypoint.sh /usr/local/bin/proj-entrypoint
ENTRYPOINT ["proj-entrypoint"]
```

`d7-dev` already puts `Delphi7\Bin` on `PATH` and sets `WINEPREFIX`, so `wine
dcc32.exe` and `wine delphi32.exe` work as-is.

---

## 2. `dcc32.cfg` — from the project's `.dof`

A headless `dcc32` reads none of the IDE's `.dof`/`.dproj`. Translate the parts
that matter into a `dcc32.cfg` next to the `.dpr` (or baked in, as above):

- `-U` — unit search path. **Order matters** (see §3, §4).
- `-I` — include path, `-R` — resource path, `-O` — object path.
- `-D` — conditional defines from the `.dof` `[Directories] Conditionals=`.
- `-E` — exe output dir, `-N` — dcu output dir.
- `-$…` switches (range checking, overflow, etc.) from `[Compiler]`.

Many Delphi repos `.gitignore` `*.cfg`; committing this one needs `git add -f`
(or name it `dcc32.cfg.in` and copy it into place in the overlay build).

---

## 3. Third-party units — mostly already installed

D7 has no package manager, so each third-party dependency is vendored under
`vendor/<name>/` (README recording version, licence, upstream, how obtained) and
installed into the workstation image by `scripts/install-<name>.sh` from a
`Containerfile.d/` fragment. The `default` profile already covers Indy 10,
mwajpeg and djson (table at the top).

**Project side, all you do is reference them on `-U`** in `dcc32.cfg`:

```
-U"C:\opt\indy10\dcu;C:\opt\mwajpeg\dcu;C:\opt\djson\dcu;C:\Program Files\Borland\Delphi7\Lib"
```

Order matters — put `C:\opt\indy10\dcu` before `Delphi7\Lib` so Indy 10 shadows
the bundled Indy 9 dcus (§4). The IDE side (palette + library path) is already
set by the install scripts.

### Adding one that isn't there yet

Two shapes, both handled the same way — a fragment + `install-` script:

- **RTL-only unit** (no components, e.g. djson): copy the `.dcu` (or rebuild the
  `.pas` against this D7 — DCU format is compiler-build-locked) to
  `/opt/<name>/dcu` and add that to the IDE *Library* → *Search Path*. No palette
  entry. Model: `install-djson.sh`.
- **Needs a design-time package** (a component streamed off a `.dfm`, e.g.
  mwajpeg's `TDBJPEGImage`): also copy the runtime + design `.bpl` into
  `Delphi7\Bin` and register the design `.bpl` under
  `HKLM\Software\Borland\Delphi\7.0\Known Packages` (`wine reg add`, value name =
  Windows path to the `.bpl`, data = a description). Model: `install-mwajpeg.sh`.
  Headless `dcc32` still only needs the `.dcu` on `-U` — design packages are
  irrelevant to it.

---

## 4. Indy 10 — the one component that also *removes* things

`d7-dev` builds Indy 10 at `$INDY10` (`/opt/indy10/{dcu,bpl}`) and
`swap-indy-ide.sh` swaps it in for the bundled Indy 9 IDE-side — Known Packages +
Library path rewritten, the bundled `Lib\Id*.dcu` / `Bin\*indy70.bpl` stripped,
IntraWeb's Indy-9-linked design package dropped. (mwajpeg and djson are purely
additive; Indy is the one that deletes bundled files, which is why it has to be a
workstation component and can't be an overlay.)

Project side:

- **Headless build:** put `C:\opt\indy10\dcu` **first** on `-U` in `dcc32.cfg`,
  before `Delphi7\Lib`, so Indy 10 units shadow any bundled Indy 9 `.dcu`s.
- **Indy-9 leakage:** `swap-indy-ide.sh` already deletes the bundled
  `Lib\Id*.dcu`, so a missing `Id*` unit now fails loudly rather than silently
  linking Indy 9. If that happens, the unit isn't `contain`ed in any Indy 10
  package — add its source dir to `-U`, or the `.dpk` list in `build-indy10.sh`.
- **Runtime:** `IdSSLOpenSSL` needs `libeay32.dll` + `ssleay32.dll` (OpenSSL
  1.0.x) beside the exe or on the Windows `PATH`.
- **IDE:** if you use IntraWeb, re-register its design package *after* Indy 10
  and test for a load clash.

---

## 5. BDE / Paradox

The image has the BDE engine but no aliases and stock `IDAPI32.CNF`.

### The alias

If the app does `TTable.DatabaseName = 'SomeAlias'` with no `TDatabase`
component and no `Session.AddAlias` call, the alias must be in the BDE config
before the app starts. Create it at **container start** (entrypoint), so it can
point at that run's data mount:

- Compile a one-shot `mkalias.pas` (`dcc32`) that does
  `Session.AddStandardAlias('SomeAlias', 'X:\', 'PARADOX'); Session.SaveConfigFile;`
  and run it in the entrypoint; **or**
- `bdeadmin` it once in an X container and re-snapshot the prefix (heavier).

Point the alias at a **drive letter** (`X:`), not a Unix path — map the letter
with `ln -s /data /home/dev/d7/dosdevices/x:` in the entrypoint or overlay.

### `IDAPI32.CNF` settings for the Paradox driver

- `NET DIR` — a writable dir that always exists in the container; this is where
  `PDOXUSRS.NET` is created. Keep it with the data (`X:\`).
- `LOCAL SHARE = TRUE`.
- `LANGDRIVER` — **must match the tables**. A mismatch gives *"table is in a
  non-standard format"* or silently wrong sort/index order. Check the tables'
  actual language driver; don't assume.

### Test data

- **Never** on a FUSE (`fuseblk` NTFS/exFAT) mount — Paradox locking on FUSE is
  unreliable and will corrupt. rsync to a local-fs dir first; a re-runnable
  script that resets a gitignored `testdata/` is the usual pattern.
- Bind-mount that dir **read-write**; drive letter `X:` → it.
- **Never bake table data into an image.** Treat any real dataset as PII:
  gitignored + bind-mounted only, never copied off the machine.
- Mixed-case table filenames vs varied case in `.dfm`s: Wine resolves
  case-insensitively, so normally fine — flag only if one table won't open.

---

## 6. Running

### Headless compile

```
podman run --rm --userns=keep-id \
  -v /path/to/project:/work -w /work \
  <overlay-image> \
  sh -lc "wine dcc32.exe -B YourProject.dpr | tee build.log; \
          ! grep -E 'Error:|Fatal:' build.log"
```

`/work` is `W:` in the prefix. Add `-v /path/to/testdata:/data` and the `X:`
symlink if the build (or a run) touches the BDE. `--network=none` is usually
fine.

### IDE

Use this repo's `scripts/run-ide.sh <project-dir>` (it sets `xhost +local:`,
`--ipc=host`, the X socket mount and the sandbox flags), pointing at your
project and your overlay image.

---

## 7. Recurring source fixes

- **Malformed `uses` clause** — a stray `;` before the last few units in the
  `.dpr` leaves them out of the build. Grep the `.dpr`'s `uses` for a `;` that
  isn't the final one.
- **`.dof`-only search paths** — see §2.
- Units that `use` something display-related pulling `dcc32` into needing an X
  server — wrap the build in `xvfb-run` if so.

---

## 8. Private inputs you supply locally

None of these can be committed (this repo or yours) — reproduce or fetch each:

| Input | How |
| --- | --- |
| `d7prefix.tar` (~1.1 GB) | `PLAN.md` phases 2–3, or fetch a shared copy |
| `images/delphi7/` (ISO + slip) | your own D7 Enterprise media |
| `d7-license.env` | your D7 serial / key |
| `vendor/<name>/` | per each vendored lib's README |
| `testdata/` | rsync from the real dataset |
