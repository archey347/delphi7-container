# Delphi 7 in a sandboxed container — plan

Goal: reproducible, sandboxed Delphi 7 environment via rootless Podman on a Fedora 43 /
Hyprland (Wayland) host. Same image serves:

1. interactive IDE development (GUI over the host X socket), and
2. headless `dcc32` compiles (basis for a self-hosted CI runner later).

The D7 install itself is done **inside a container**, not on the host.

The environment is project-agnostic. It is exercised against a representative
Delphi 7 Enterprise app that uses BDE/Paradox tables, QuickReport 3, **Indy 10**
(for `TIdSSLIOHandlerSocketOpenSSL` — the Indy 9 that D7 bundles has no OpenSSL
IO handler), and a couple of vendored third-party units. Wiring a project of your
own into the image is covered in `USING.md`.

---

## Status (2026-08-30)

| Phase | State |
| --- | --- |
| 0 · decisions | ✅ settled — see below |
| 1 · `d7-base` (`Containerfile.base`) | ✅ built, 4.19 GB |
| 2 · interactive install → `d7-prefix` volume | ✅ done (MSI, GUI over host X socket) |
| 3 · snapshot → `d7prefix.tar` | ✅ 1.1 GB + `.sha256` |
| 4 · `d7-dev` — templated from `Containerfile.d/*.part` via `scripts/build-image.sh` | ✅ `default` profile = prefix + indy10 + mwajpeg + djson |
| 5 · run the IDE (`scripts/run-ide.sh`) | ✅ IDE runs; built + ran a test app in it |
| 5b · database access (runtime) | ☐ designed, not built — see below |
| 6 · headless `dcc32` | ⏳ compiler verified; Indy 10 builds + links in the image (test exe → `10.6.3.12`); target project not built yet |
| 7 · source fixes for a green build | ☐ not started |
| 8 · CI | ☐ out of scope for now |
| 9 · fold into a project repo | ☐ end goal — see below |

Images / artifacts (all **private**, gitignored): `d7-base`, `d7-dev`,
`d7prefix.tar`, `images/`, `d7-license.env`. The `d7-prefix` podman volume
still exists (only needed for re-running the interactive install).

---

## TODO / open items

- [ ] **Phase 7 (project side): translate the project's `.dof` → a committed
      `dcc32.cfg`.** Conditional defines, unit/lib paths and output settings
      normally live only in the IDE's `.dof`; a headless build needs them in a
      `dcc32.cfg` next to the `.dpr`.
- [x] **`DJSON` acquired + installed** — DJSON v1.0 (Carlos Renan Silveira, MIT),
      vendored at `vendor/djson/`. Representative "RTL-only vendored unit" case —
      no `System.JSON` on D7. Installed as a workstation component by
      `scripts/install-djson.sh` (fragment `Containerfile.d/30-djson.part`,
      `default` profile) → `C:\opt\djson\dcu`. Verified: a console program
      `uses`ing `DJson` compiles + runs from the baked image.
- [x] **mwajpeg acquired + installed** — MWA Software JPEG Component Library
      v1.10.0, vendored at `vendor/mwajpeg/`. Representative "needs a design-time
      package" case (`TDBJPEGImage` on a `.dfm`). Installed as a workstation
      component by `scripts/install-mwajpeg.sh` (fragment
      `Containerfile.d/20-mwajpeg.part`, `default` profile): `dclmwajpgd7.bpl`
      registered in *Known Packages*, `mwajpgd7.bpl` + dcus at `C:\opt\mwajpeg\dcu`
      on the library path. Verified headless: a program `uses`ing `jpeglib` +
      `mwajpeg` + `mwadbjpg` compiles + runs from the baked image. Still untried:
      opening a `.dfm` that drops `TDBJPEGImage` in the IDE to confirm the
      component streams at design time.
- [x] **Indy 10.6.3.12 acquired** — vendored at `vendor/indy10/` (`Lib/{System,
      Core,Protocols,...}` sources + D7 `*70.dpk` packages + `Indy70.bpg`; original
      tarballs, incl. an unused `Indy9.tar.gz`, in `orig/`). QuickReport 3
      confirmed in the D7 install (`Lib/QR*.dcu`); Rave 5 also installed.
- [x] **Phase 6: build Indy 10 into the image (headless).** `scripts/build-indy10.sh`
      does `dcc32 -B` on `IndySystem70` → `IndyCore70` → `IndyProtocols70`; the
      `Containerfile` runs it at build time into `/opt/indy10/{dcu,bpl}` (env
      `$INDY10`). All three compile clean (warnings only). Verified: a console
      program `uses`ing `IdHTTP` + `IdSSLOpenSSL` with `$INDY10/dcu` first on `-U`
      builds and runs → `gsIdVersion` = `10.6.3.12` (vs bundled Indy 9). **Low-effort
      clash route confirmed working** — nothing removed from `Delphi7\Lib`; the
      dcu-dir-first `-U` ordering is enough for the CI build. The vendored tree
      also ships prebuilt Dec-2025 D7 `.bpl/.dcp/.dcu`; we rebuild for
      reproducibility.
- [ ] **Phase 7: wire `$INDY10/dcu` into the project build** — first entry in the
      committed `dcc32.cfg` `-U` (before `Delphi7\Lib`). Watch for Indy-9 leakage:
      any `Id*` unit the project uses that Indy 10's packages don't `contain` would
      resolve to the bundled Indy 9 dcu — if the target build shows a version-
      mismatch or a missing `Id*` symbol, fall back to the clean-env strip below.
- [x] **Phase 6: Indy 9 → 10 swap folded into the image (IDE side).**
      `scripts/swap-indy-ide.sh` runs after `build-indy10.sh` in the `Containerfile`:
      strips bundled Indy 9 (`Lib\Id*.dcu`, `Lib\Debug\Id*.dcu`, `Bin\indy70.bpl` +
      `dclindy70.bpl`, `Source\Indy\`), copies the 5 Indy 10 bpls into `Bin\`,
      and via `wine reg` on `HKLM\...\7.0`: drops `dclindy70.bpl` **and**
      `dclIntraweb_50_70.bpl` from *Known Packages* (IntraWeb's design pkg links
      Indy 9 and would clash — add it back only if a project uses IntraWeb), adds
      `dclIndyCore70.bpl` + `dclIndyProtocols70.bpl`, and prepends
      `C:\opt\indy10\dcu` to the *Library* Search Path. `build-indy10.sh` also
      builds the 2 design packages (needs Indy's `Fulld_7.bat` flag set
      `-$d-l-n+p+r-s-t-w-` and `.dcp`/`.bpl` left in the source dir, **not** forced
      with `-LN/-LE` — that yields a `.dcp` that fails the packaged-unit check).
      Verified headless: `LoadPackage('dclIndyProtocols70.bpl')` (the whole
      System→Core→Protocols→designide chain) loads + unloads clean in the baked
      image — no duplicate-unit clash. Verified live (`run-ide.sh` on the host X
      display): IDE starts with no package-load error; palette has the Indy 10
      tabs (incl. *Indy I/O Handlers* / *Indy Intercepts*, which Indy 9 on D7
      lacked); *Project → Options → Packages* lists both *Indy 10 …Design Time*
      packages checked, no Borland-Indy or IntraWeb entries. Still untried:
      opening a `.dfm` that streams `TIdSSLIOHandlerSocketOpenSSL` to confirm the
      Indy 10 component resolves at design time.
- [ ] Runtime needs `libeay32.dll`/`ssleay32.dll` (OpenSSL 1.0.x) beside the exe
      or on the Windows PATH for any build that uses `IdSSLOpenSSL`.
- [ ] Fix the IDE `WINEDLLOVERRIDES` gotcha properly if Gecko is ever wanted (see
      Phase 5). Currently fine without it.
- [ ] `scripts/`: still need `build.sh` (Phase 6) and `export-prefix.sh` (Phase 3
      was run by hand).
- [ ] Housekeeping: `xhost -local:` reverts the X access opened for run-ide;
      prune dangling build images.
- [ ] Confirm the Indy 10 design-time component and `TDBJPEGImage` both resolve
      when a `.dfm` using them is opened in the IDE — the `C:\opt\…\dcu` library
      paths only became reachable in-IDE once `drive_c/opt -> /opt` was added to
      `00-base.part` (headless `dcc32` had been using the Unix paths).

### Phase 5b — BDE / Paradox database access (generic notes, not built)

Only relevant to a project that uses the BDE. The image ships the BDE *engine*
(installed with D7) but no aliases and no tuned `IDAPI32.CNF`. Project-specific
wiring — alias name, data location, drive-letter mounts — lives in `USING.md`.
Generic points that hold for any BDE/Paradox project:

- **An alias that the app references but never creates at runtime must exist in
  the BDE config before the app starts.** Two ways to put it there: (a) a tiny
  `mkalias.pas` compiled with `dcc32` that calls `Session.AddStandardAlias(name,
  path, 'PARADOX')` + `Session.SaveConfigFile`, run at image-build or container
  start; (b) add it once with `bdeadmin` in an X container and re-snapshot the
  prefix. Point aliases at a **drive letter**, not a host path.
- Paradox driver settings that matter: `NET DIR` = a writable dir that always
  exists in the container (this is where `PDOXUSRS.NET` lands — keep it beside the
  data); `LOCAL SHARE = TRUE`; `LANGDRIVER` **matching the tables** (a mismatch
  gives "table is in a non-standard format" or silently wrong sort/index order —
  verify the tables' actual language driver, don't guess).
- **Do not mount table data off a FUSE (`fuseblk` NTFS/exFAT) mount** — Paradox
  locking on FUSE is unreliable. Copy to a local filesystem first (a re-runnable
  rsync script that resets a gitignored `testdata/` is the usual pattern) and
  bind-mount that read-write.
- **Never bake table data into an image**, and treat any real dataset as PII —
  gitignored + bind-mounted only, never copied off the machine.
- Mixed-case table filenames vs varied case in `.dfm`s: Wine resolves
  case-insensitively by scanning the directory, so this is normally fine — flag
  it only if a specific table fails to open.

### Architecture — generic env vs project layer

Everything here (Wine prefix, D7 install, BDE engine, Indy 10, Containerfiles,
scripts) is generic "Delphi 7 in a container". A real project adds only a thin
layer on top:

- **Generic layer (this repo → `d7-base` / `d7-dev`):** the two Containerfiles,
  the baked prefix, Indy 10 built in, `run-ide.sh` and build helpers. Knows
  nothing about any project's tables, aliases or unit layout.
- **Project layer (in the project's own repo):** a thin `Containerfile` `FROM
  d7-dev` adding that project's vendored units and its `dcc32.cfg`; a BDE alias
  created at container start from a mount/env by a small entrypoint hook; a run
  wrapper that mounts the source tree (and a data dir if BDE is used); any
  source fixes the project needs. This is what `USING.md` documents.

Tie-in mechanism: a project overlay `Containerfile` `FROM d7-dev`, plus a small
entrypoint for the BDE alias only. (A devcontainer + postCreate hook is an
equivalent alternative.)

Open: where does the golden `d7prefix.tar` live so several project repos / CI can
fetch it?

### Phase 9 — fold into a project repo (end goal, not yet)

- [ ] Keep the **generic** parts here (own repo or a `d7-env/` subtree); put the
      **project** parts in that project's repo (e.g. a `docker/` dir) so a dev can
      clone the project and run one script to get a working build/run env. See
      `USING.md`.
- [ ] The private inputs cannot be committed anywhere — each dev/CI regenerates
      or supplies them locally: `d7prefix.tar` (~1.1 GB), `images/` (the ISO + its
      extract), `d7-license.env`, `vendor/`, and any `testdata/`. Document the
      steps to reproduce each.
- [ ] Watch the target repo's own `.gitignore` — a committed `dcc32.cfg` often
      needs `git add -f` (many Delphi repos ignore `*.cfg`).

## Assets on hand

- Install media: `images/delphi7/Delphi7.iso` (473 MiB ISO **file**, not a
  directory). Extracted to `images/delphi7/extracted/` with `7z`; `media` is a
  symlink to it. It is an **MSI** package (`Borland Delphi 7.msi` + an
  InstallShield `setup.exe` bootstrapper), *not* a script-driven InstallShield
  install.
- Licence: `dent.slip` sits next to the ISO (Delphi ENTerprise slip). The serial
  (`PRODUCT_ID`) and key (`AUTH_KEY`) are in `d7-license.env` (gitignored).

---

## Phase 0 — decisions (settled)

- Base image: `debian:bookworm-slim` + **WineHQ `stable`** repo (`winehq-stable`,
  wine-11.0), 32-bit (`dpkg --add-architecture i386`). Not Debian's own `wine32`.
  Override to staging with `--build-arg WINE_BRANCH=staging` if ever needed.
- `winetricks`: pinned from GitHub raw. Only the **`corefonts`** verb is used
  (small). `riched20` (pulls a 135 MB Win2000 SP4), `gdiplus`, `mfc42` are **not**
  installed — Wine builtins are fine; add back individually if something needs them.
- **Mono/Gecko disabled** in `d7-base` via `WINEDLLOVERRIDES=mscoree,mshtml=`,
  otherwise `wineboot --init` blocks forever on the wine-mono auto-install dialog
  under headless Xvfb. `d7-dev` narrows this to `mscoree=` (see Phase 5).
- Prefix handling: **bake the snapshot.** Interactive install writes to the named
  volume `d7-prefix`; Phase 3 exports it to `d7prefix.tar`; Phase 4 bakes that
  tarball into `d7-dev`. (The "runtime volume" alternative was dropped.)
- Display transport: **bind-mount the host X socket** (`/tmp/.X11-unix`). Xephyr
  is not installed on the host. Needs `xhost +local:` once per session and
  `--security-opt label=disable` on the container (SELinux blocks the socket
  otherwise); the real sandboxing is `--network=none --cap-drop=ALL --userns`.
- All images / tarballs / media stay **private** — never pushed to a public
  registry (D7 licence).

## Phase 1 — base image  (`Containerfile.base` → `d7-base`)  ✅

Built. Contents:

- `dpkg --add-architecture i386`; `apt-get install` `ca-certificates wget gnupg
  xz-utils p7zip-full cabextract xvfb xauth winbind fonts-liberation`.
- WineHQ repo key + `winehq-bookworm.sources`; `apt-get install --install-recommends
  winehq-stable`. `winetricks` pinned from GitHub raw.
- non-root `dev` user, uid 1000 (matches `--userns=keep-id`).
- `ENV WINEARCH=win32 WINEPREFIX=/home/dev/d7 WINEDEBUG=-all
  WINEDLLOVERRIDES=mscoree,mshtml=`.
- One layer under a throwaway Xvfb: `wineboot --init` → `winetricks -q corefonts`
  → `winetricks -q winxp` (WinXP mode), each followed by `wineserver -w`.

## Phase 2 — interactive install  ✅

Done manually. What worked:

```
podman volume create d7-prefix
# seed the volume from the image's booted prefix, SAME userns as the install run:
podman run --rm --userns=keep-id -v d7-prefix:/seed d7-base \
  sh -c 'cp -a /home/dev/d7/. /seed/'

xhost +local:
podman run --rm --name d7install --userns=keep-id --security-opt label=disable \
  -e DISPLAY=:0 -e WINEDEBUG=-all \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$PWD/images/delphi7/extracted:/media/d7:ro" \
  -v d7-prefix:/home/dev/d7 \
  d7-base \
  wine msiexec /i 'Z:\media\d7\Borland Delphi 7.msi' \
       /l*v 'Z:\home\dev\d7\msi-install.log'
```

Click-through: enter the serial / key from `d7-license.env`; "install
for anyone"; accept licence; **default path** `C:\Program Files\Borland\Delphi7`;
keep BDE + QuickReport; the "AeDebug JIT debugger is set to another application"
prompt → **No** (it is just Wine's `winedbg`, harmless). Result verified: `INSTALL
return value 1`, `dcc32.exe`/`delphi32.exe` in `Bin`, BDE + QR + Rave present,
`dent.slip` copied into the install dir.

Notes / traps hit:
- Volume must be seeded with the **same `--userns`** as the install run, or wine
  says `'/home/dev/d7' is not owned by you`.
- Headless silent install is not worth it: the package has human-gated custom
  actions (AeDebug prompt etc.) that ignore `/qb` and block under Xvfb. If ever
  needed, the MSI properties are `PRODUCT_ID=<serial>` and `AUTH_KEY=<key>`.

## Phase 3 — snapshot the prefix  ✅

```
podman volume export d7-prefix -o d7prefix.tar
sha256sum d7prefix.tar | tee d7prefix.tar.sha256   # d92a85bd...4b065
```

1.1 GB. This is the golden private artifact (gitignored). TODO: wrap in
`scripts/export-prefix.sh`.

## Phase 4 — the workstation image  (`Containerfile.d/*.part` → `d7-dev`)  ✅

`d7-dev` is **one shared image** — a Delphi 7 workstation set up the way the
team's machines are, not a per-project image (the Phase 2 install needs a human,
so regenerating per project is not sensible). It is assembled from fragments:

- `Containerfile.d/NN-<name>.part` — one Dockerfile snippet per *component*
  (`00-base` always, then `indy10`, `mwajpeg`, `djson`, …). The `NN` prefix fixes
  install order. Each component fragment carries its own `--mount` for its
  `vendor/<name>` dir and `COPY`s its own `scripts/install-<name>.sh`.
- `profiles/<name>.conf` — the list of components to install (`default` =
  `indy10 mwajpeg djson`; `minimal` = none).
- `scripts/build-image.sh [--profile NAME] [--with C] [--without C] [--print |
  --check]` — resolves the component set, concatenates fragments, writes
  `./Containerfile` (committed as the default-profile render), runs `podman build
  -t d7-dev`. `--check` fails if the committed `Containerfile` is stale.

A dev extends the workstation by adding a fragment + `install-` script + a
profile line and rebuilding — the human install step is untouched.

`00-base` = `FROM d7-base`, then as root in one layer:

- bind-mount `d7prefix.tar` (`--mount=type=bind,...,z` — the `,z` is needed for
  SELinux; alternatively `podman build --security-opt label=disable`),
- `rm -rf /home/dev/d7`, extract the tar into it, `chown -R dev:dev`,
- `ln -s /work /home/dev/d7/dosdevices/w:` (W: → project mount, dangling until run),
- `ln -sfn /opt /home/dev/d7/drive_c/opt` — component installers write dcus under
  `/opt/<name>`; this makes the same tree reachable as `C:\opt\<name>`, which is
  the form the IDE library path and `dcc32 -U` want (a Unix `/opt/...` path works
  headless but the IDE can't resolve it),
- `install -d -o dev -g dev -m 700 /run/user/1000`.

Then `USER dev` and `ENV`:

- `PATH=…/Borland/Delphi7/Bin:$PATH`
- `XDG_RUNTIME_DIR=/run/user/1000` (silences a wine warning)
- `WINEDLLOVERRIDES=mscoree=` — narrows the base's `mscoree,mshtml=`: .NET/Mono
  stays off, but **mshtml goes back to builtin**. Without builtin mshtml the D7
  IDE throws at startup and quits (it hosts a WebBrowser control on the Welcome
  page). The prefix is already booted so there is no wineboot Gecko prompt to
  fear here.

Component fragments then layer on (each `USER root` … `USER dev`):

- **`indy10`** — `build-indy10.sh` → `/opt/indy10/{dcu,bpl}` (`ENV
  INDY10=/opt/indy10`): `dcc32` the 5 `.dpk`s in order (System → Core + dclCore →
  Protocols + dclProtocols, `IdCompressionIntercept` precompiled `-Z` first),
  Fulld_7.bat flag set, `.dcu` via `-N` to a shared dir but `.dcp`/`.bpl` left in
  the source dir. Then `swap-indy-ide.sh /opt/indy10` strips bundled Indy 9, copies
  the bpls to `Bin\`, and `wine reg`s *Known Packages* / *Library* so the IDE
  loads Indy 10 not Indy 9 (+ IntraWeb design pkg dropped — it links Indy 9).
- **`mwajpeg`** — `install-mwajpeg.sh` registers `dclmwajpgd7.bpl` in *Known
  Packages*, drops `mwajpgd7.bpl` in `Bin\` and the dcus at `/opt/mwajpeg/dcu`
  (`C:\opt\mwajpeg\dcu`) on the library path.
- **`djson`** — `install-djson.sh` drops the prebuilt dcu at `/opt/djson/dcu`
  (`C:\opt\djson\dcu`) on the library path; no palette package.

Headless `dcc32` builds put `/opt/indy10/dcu;/opt/mwajpeg/dcu;/opt/djson/dcu`
first on `-U` (Unix or `C:\opt\…` form; both resolve).

Build: `scripts/build-image.sh` (wraps `podman build -f Containerfile -t d7-dev
--security-opt label=disable .`).

Key paths inside the prefix:
- Delphi root `C:\Program Files\Borland\Delphi7` = `…/drive_c/Program Files/Borland/Delphi7`
- `…/Delphi7/Bin` — `DCC32.EXE`, `delphi32.exe`, `dcc70.dll`, `brcc32.exe`, `rlink32.dll`
- `…/Delphi7/Lib` — VCL + QuickReport (`QR*.dcu`)
- `…/Delphi7/Source`, `…/Delphi7/Rave5`
- BDE `C:\Program Files\Common Files\Borland Shared\BDE`

## Phase 5 — run the IDE  (`scripts/run-ide.sh`)  ✅

```
xhost +local:
podman run --rm --name d7ide \
  --userns=keep-id --security-opt label=disable \
  --security-opt no-new-privileges --cap-drop=ALL --network=none --ipc=host \
  -e DISPLAY=:0 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v /path/to/your/project:/work \
  d7-dev \
  wine explorer /desktop=Delphi7,1600x1000 'C:\Program Files\Borland\Delphi7\Bin\delphi32.exe'
```

Verified: IDE starts, a form with a button was built, compiled and run inside the
container. Virtual-desktop mode → one XWayland window for Hyprland to manage.

Traps hit:
- **`--ipc=host` is required.** Without it Wine's MIT-SHM `X_ShmPutImage` fatals
  (`BadValue`) and the process dies with no window. (Alternative: set
  `UseXShm=N` in the prefix registry — not done.)
- **Do not disable `mshtml`** (see Phase 4) or the IDE quits ~1 min after the
  splash with a clean exit code and no window.
- `--security-opt label=disable` + `xhost +local:` are what let the container
  reach the host X socket on this SELinux + Wayland host.
- `--network=none` is fine — the IDE runs without it.
- HiDPI (if needed): host `xwayland { force_zero_scaling = true }` + bump Wine DPI
  (~120).

## Phase 6 — headless compile  (`scripts/build.sh`)  ⏳

`dcc32` itself works:

```
podman run --rm --userns=keep-id d7-dev wine dcc32.exe
# -> Borland Delphi Version 15.0 / Copyright (c) 1983,2002 ...
```

Still to do — a real build of a project. Shape of it:

```
podman run --rm --userns=keep-id \
  -v /path/to/your/project:/work -w /work d7-dev \
  sh -lc "wine dcc32.exe -B -Q -E. \
    -U'C:\Program Files\Borland\Delphi7\Lib;W:\vendor\...;<QR/Indy paths>' \
    YourProject.dpr | tee build.log; ! grep -E 'Error:|Fatal:' build.log"
```

Needs (project side, see `USING.md`): a committed `dcc32.cfg` derived from the
project's `.dof`, its vendored units on the unit path, and whatever source fixes
it needs to compile. Headless `dcc32` should not need an X server; add `xvfb-run`
only if a unit pulls in something that touches the display.

## Phase 7 — source fixes to get a green build (project side)

Project-specific; belongs in the project repo, not here. `USING.md` covers the
recurring cases: a malformed `uses` clause in the `.dpr`, and referencing the
pre-installed components (`C:\opt\{indy10,mwajpeg,djson}\dcu` — `indy10` first so
it shadows D7's bundled Indy 9) on the `dcc32.cfg` `-U`.

## Phase 8 — CI (later, out of scope now)

- Self-hosted runner on the build box calling `scripts/build.sh`.
- If the project repo is public: restrict the runner to `push` on own branches
  (fork-PR RCE risk on self-hosted runners).

---

## Directory layout

```
scrapbook/d7/
  PLAN.md
  Containerfile.base        # -> d7-base
  Containerfile             # -> d7-dev  (GENERATED from Containerfile.d/ by build-image.sh)
  Containerfile.d/          # workstation image fragments, one per component
    00-base.part            #   always: bake d7prefix.tar, PATH/DLL env, C:\opt symlink
    10-indy10.part          #   component: indy10
    20-mwajpeg.part         #   component: mwajpeg
    30-djson.part           #   component: djson
    99-footer.part          #   always: CMD
  profiles/
    default.conf            # indy10 + mwajpeg + djson (the team's workstation)
    minimal.conf            # no components — base for --with experiments
  scripts/
    build-image.sh          # assemble Containerfile.d/ -> Containerfile -> podman build
    run-ide.sh              # Phase 5 (done)
    build-indy10.sh         # builds Indy 10 at image-build time (used by 10-indy10.part)
    swap-indy-ide.sh        # swaps Indy 9 -> 10 for the IDE (used by 10-indy10.part)
    install-mwajpeg.sh      # installs mwajpeg component (used by 20-mwajpeg.part)
    install-djson.sh        # installs djson component (used by 30-djson.part)
    build.sh               # Phase 6 (todo — the headless project compile)
    export-prefix.sh        # Phase 3 (todo — was run by hand)
  USING.md                  # how to build your own D7 project with this image
  vendor/                   # third-party D7 source we build against (private, gitignored)
    mwajpeg/                # MWA JPEG Component Library v1.10.0
    indy10/                 # Indy 10.6.3.12 sources + D7 packages
    djson/                 # DJSON v1.0
  images/                   # disc/prefix images (all private, gitignored)
    delphi7/
      Delphi7.iso           # original install ISO + dent.slip + provenance
      extracted/            # ISO unpacked with 7z
  media -> images/delphi7/extracted             # symlink (compat)
  d7prefix.tar  d7prefix.tar.sha256              # golden artifact (private)
  d7-license.env            # PRODUCT_ID / AUTH_KEY  (private, gitignored)
  .gitignore
```

## Risks / known issues

- Wine **Mono/Gecko auto-install dialog** hangs any headless `wineboot` — must
  disable via `WINEDLLOVERRIDES` (mind the mshtml nuance for the IDE).
- Rootless Podman + X socket on SELinux/Wayland — `--userns=keep-id`,
  `--security-opt label=disable`, `xhost +local:`, `--ipc=host`.
- SELinux blocks build-time bind mounts — `,z` on the mount or
  `--security-opt label=disable` on `podman build`.
- Debian dropping 32-bit later — pinned to bookworm; migrate to Wine new-WoW64 if
  it comes to that.
- Big images (`d7-dev` ~4.7 GB) — the prefix is duplicated across the extract
  layer; could squash or bake into `d7-base` later.
- Paradox tables are lock-sensitive: don't run the app against the FUSE copy or a
  network path; use a local-fs working copy with a writable `NET DIR` and
  `LOCAL SHARE=TRUE`. A wrong `LANGDRIVER` corrupts sort order / rejects tables.
