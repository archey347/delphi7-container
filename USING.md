# Building your own Delphi 7 project with this image

`d7-dev` (see `PLAN.md`) is a project-agnostic Delphi 7 Enterprise environment:
Wine + a baked D7 prefix (IDE, `dcc32`, BDE engine, QuickReport, Rave) with Indy
10 built in. It knows nothing about any particular project. This is the checklist
for wiring a project into it — written against a project that has the full set of
awkward D7 dependencies: **vendored third-party units, a BDE/Paradox database,
QuickReport, and Indy 10** (for `TIdSSLIOHandlerSocketOpenSSL`, which the Indy 9
D7 bundles lacks).

Everything below lives in *your project's* repo, not this one. The tie-in is a
thin overlay image plus a run wrapper.

---

## 1. Overlay image — `FROM d7-dev`

Keep it in the project repo (e.g. `docker/Containerfile`):

```dockerfile
FROM d7-dev

# Project-vendored D7 units. Copy the source (or prebuilt .dcu) in and add it to
# the compiler's unit path via a dcc32.cfg you also ship.
COPY --chown=dev:dev vendor/ /opt/proj-vendor/
COPY --chown=dev:dev docker/dcc32.cfg "/home/dev/d7/drive_c/Program Files/Borland/Delphi7/Bin/dcc32.cfg"

# If any vendored lib needs a design-time package in the IDE, install its .bpl
# and put its dir on the Windows PATH (see §3).

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

## 3. Vendored units

D7 has no package manager. Each third-party dependency is copied into the repo
under `vendor/<name>/` with a short README recording version, licence, upstream
URL and how it was obtained. Two shapes:

### RTL-only unit (no components) — e.g. a JSON unit

Nothing to install. Put the directory holding the `.pas` (or a prebuilt `.dcu`)
on `-U` in `dcc32.cfg`, and on the IDE's *Library Path* if you open units that
`use` it. Prefer **rebuilding the `.pas` against this exact D7** over trusting a
`.dcu` built elsewhere — DCU format is locked to the compiler build.

### Needs a design-time package — e.g. a DB-aware image component on a `.dfm`

The IDE can't stream the component off a `.dfm` until its design package is
registered. In the overlay image:

1. Copy the runtime + design `.bpl` into `Delphi7\Bin` (or any dir on the
   Windows `PATH`).
2. Register the design package: add it under
   `HKCU\Software\Borland\Delphi\7.0\Known Packages` with `wine reg add`, value
   name = the full Windows path to the `.bpl`, data = a description string.
3. Add the unit source/`dcu` dir to the *Library Path* the same way
   (`…\7.0\Library` → `Search Path`).

For a **headless** `dcc32` build you only need the `.dcu`/`.pas` on `-U` — design
packages are irrelevant. Rebuild the package from `src/` against this D7 if the
prebuilt `.dcu` is rejected (`Fulld_7.bat` or the `.dpk` directly).

---

## 4. Indy 10

Already built into `d7-dev` at `$INDY10` (`/opt/indy10/{dcu,bpl}`), and the
image's `swap-indy-ide.sh` has already swapped it in for the bundled Indy 9 on
the IDE side (Known Packages + Library path rewritten, IntraWeb's Indy-9-linked
design package dropped).

Project side:

- **Headless build:** put `$INDY10/dcu` (`C:\opt\indy10\dcu`) **first** on `-U`
  in `dcc32.cfg`, before `Delphi7\Lib`, so Indy 10 units shadow the bundled Indy
  9 `.dcu`s that are still in `Lib`.
- **Watch for Indy-9 leakage:** any `Id*` unit your project uses that isn't
  `contain`ed in an Indy 10 package will still resolve from `Delphi7\Lib`
  (Indy 9). A version-mismatch or missing-symbol error at link is the tell —
  the fix is to strip `Delphi7\Lib\Id*.dcu` in the overlay image.
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
