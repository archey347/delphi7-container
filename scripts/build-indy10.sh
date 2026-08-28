#!/usr/bin/env bash
# Build the Indy 10 packages for Delphi 7.
#
#   build-indy10.sh <indy10-root> <out-root>
#     <indy10-root>  dir containing Lib/{System,Core,Protocols}/*70.dpk
#                    (compiled in place, so pass a disposable copy)
#     <out-root>     gets dcu/ (.dcu + .dcp, for compile consumers) and
#                    bpl/ (.bpl, for the IDE component palette)
#
# Mirrors Indy's own Lib/Fulld_7.bat: the packaging-safe switch set, dcus to a
# shared dir via -N, but .dcp/.bpl left to land in each package's source dir
# (NOT forced with -LN/-LE — that produced a .dcp that failed the packaged-unit
# format check when the design packages read it back). Order is load-bearing:
# each package requires the previous, and IdCompressionIntercept must be a
# standalone unpackaged unit (-Z) before IndyProtocols70.
set -euo pipefail

SRC=${1:?usage: build-indy10.sh <indy10-root> <out-root>}
OUT=${2:?usage: build-indy10.sh <indy10-root> <out-root>}

# Self-sufficient for manual runs against a live d7-dev container; the path is
# fixed by the Delphi 7 install and already hardcoded in the Containerfile.
export PATH="/home/dev/d7/drive_c/Program Files/Borland/Delphi7/Bin:$PATH"

WORK="$OUT/build"
DCU="$OUT/dcu"
BPL="$OUT/bpl"
rm -rf "$WORK"
mkdir -p "$WORK" "$DCU" "$BPL"

D7LIB='C:\Program Files\Borland\Delphi7\Lib'
wWORK=$(winepath -w "$WORK")
OPT='-$d-l-n+p+r-s-t-w-'

# Compile in <dir>; dcus to $WORK; then publish any .dcp it produced to $WORK so
# the next package's `requires` resolves it.
dcc() {
  local dir="$SRC/Lib/$1"; shift
  ( cd "$dir" && wine dcc32.exe "$OPT" -M -Q -H -W -N"$wWORK" -U"$wWORK;$D7LIB" -I. "$@" )
  cp -f "$dir"/*70.dcp "$WORK"/ 2>/dev/null || true
}

echo ">>> IndySystem70"
dcc System IndySystem70.dpk
echo ">>> IndyCore70 + dclIndyCore70"
dcc Core IndyCore70.dpk
dcc Core dclIndyCore70.dpk
echo ">>> IdCompressionIntercept (standalone, unpackaged)"
dcc Protocols -Z IdCompressionIntercept.pas
echo ">>> IndyProtocols70 + dclIndyProtocols70"
dcc Protocols IndyProtocols70.dpk
dcc Protocols dclIndyProtocols70.dpk

find "$SRC/Lib" -maxdepth 2 -name '*70.bpl' -exec cp -f {} "$BPL"/ \;
cp -f "$WORK"/*.dcu "$WORK"/*.dcp "$DCU"/
rm -rf "$WORK"

echo ">>> built $(ls "$DCU"/*.dcu | wc -l) dcu, $(ls "$DCU"/*.dcp | wc -l) dcp, $(ls "$BPL"/*.bpl | wc -l) bpl into $OUT"
ls "$BPL"
