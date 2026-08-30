# Delphi 7 in a sandboxed container

A reproducible, sandboxed Delphi 7 Enterprise environment — IDE and headless
`dcc32` — running under rootless Podman + Wine.

## What's included

`d7-dev` is one shared Delphi 7 workstation image — a stock D7 Enterprise install
plus a curated set of components, assembled from `Containerfile.d/*.part`
fragments by `scripts/build-image.sh`. The `default` profile
(`profiles/default.conf`) installs:

- **From the D7 install:** VCL, BDE engine, QuickReport 3, Rave 5.
- **Indy 10.6.3.12** — rebuilt for D7 and swapped in for the bundled Indy 9
  (needed for `TIdSSLIOHandlerSocketOpenSSL`); at `C:\opt\indy10\dcu`, palette
  registered.
- **mwajpeg v1.10.0** — MWA Software JPEG Component Library (`TDBJPEGImage`); at
  `C:\opt\mwajpeg\dcu`, design package registered.
- **djson v1.0** (MIT) — RTL-only JSON unit (D7 has no `System.JSON`); at
  `C:\opt\djson\dcu`.

The three vendored components live under `vendor/` (gitignored — you supply; see
each one's README).

## How to use

- **Build the image:** `d7-base` from `Containerfile.base`, then
  `scripts/build-image.sh` for `d7-dev`. Add components with
  `--with <name>` / a profile; see `PLAN.md`.
- **Run the IDE:** `scripts/run-ide.sh <project-dir>` — starts `delphi32.exe` in
  a virtual desktop on the host X display.
- **Headless compile:** `podman run --rm --userns=keep-id -v <project>:/work -w /work d7-dev wine dcc32.exe -B YourProject.dpr`
- **Wire in your own project** (`dcc32.cfg`, BDE aliases, source patches), and
  **add a workstation component**: see `USING.md`.

Private inputs (D7 install media, licence, the baked prefix, vendored libraries)
are gitignored and supplied locally — see the table at the end of `USING.md`.

## How to install

TODO
