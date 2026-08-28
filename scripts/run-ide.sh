#!/usr/bin/env bash
# PLAN.md Phase 5: run the Delphi 7 IDE from d7-dev on the host X display.
#
# Wayland/XWayland host: needs `xhost +local:` once per session so the container
# can reach /tmp/.X11-unix (revert with `xhost -local:`). label=disable is for
# that socket; the real sandbox is --network=none --cap-drop=ALL --userns.
# --ipc=host is required — Wine's MIT-SHM path fatals across an IPC namespace.
set -euo pipefail

WORK=${1:?usage: run-ide.sh <project-dir>   # bind-mounted at /work (W:)}
DISPLAY=${DISPLAY:-:0}

xhost +local: >/dev/null

exec podman run --rm --name d7ide \
  --userns=keep-id --security-opt label=disable \
  --security-opt no-new-privileges --cap-drop=ALL --network=none --ipc=host \
  -e DISPLAY="$DISPLAY" \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$WORK:/work" \
  d7-dev \
  wine explorer /desktop=Delphi7,1600x1000 'C:\Program Files\Borland\Delphi7\Bin\delphi32.exe'
