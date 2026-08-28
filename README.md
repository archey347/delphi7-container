# Delphi 7 in a sandboxed container

A reproducible, sandboxed Delphi 7 Enterprise environment — IDE and headless
`dcc32` — running under rootless Podman + Wine.

## What's included

`d7-dev` on top of a stock Delphi 7 Enterprise install:

- **From the D7 install:** VCL, BDE engine, QuickReport 3, Rave 5.
- **Indy 10.6.3.12** — rebuilt for D7 and swapped in for the bundled Indy 9
  (needed for `TIdSSLIOHandlerSocketOpenSSL`); runtime + design packages, IDE
  palette registered.

Vendored under `vendor/` (gitignored — you supply; see `USING.md`), exercised but
not shipped in the image:

- **DJSON v1.0** (MIT) — RTL-only JSON unit; D7 has no `System.JSON`.
- **mwajpeg v1.10.0** — MWA Software JPEG Component Library (`TDBJPEGImage`).

## How to use

- **Build the images:** `d7-base` from `Containerfile.base`, then `d7-dev` from
  `Containerfile` (bakes a Delphi 7 prefix + Indy 10). See `PLAN.md`.
- **Run the IDE:** `scripts/run-ide.sh <project-dir>` — starts `delphi32.exe` in
  a virtual desktop on the host X display.
- **Headless compile:** `podman run --rm --userns=keep-id -v <project>:/work -w /work d7-dev wine dcc32.exe -B YourProject.dpr`
- **Wire in your own project** (vendored units, BDE aliases, `dcc32.cfg`, Indy
  10): see `USING.md`.

Private inputs (D7 install media, licence, the baked prefix, vendored libraries)
are gitignored and supplied locally — see the table at the end of `USING.md`.

## How to install

TODO
