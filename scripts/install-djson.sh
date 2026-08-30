#!/usr/bin/env bash
# Install DJSON (v1.0) into the D7 workstation. RTL-only single unit — no palette
# package, nothing to register but the dcu dir on the search path.
#
#   install-djson.sh <djson-vendor-dir> <out-root>
#     <djson-vendor-dir>  vendor/djson  (needs lib-d7/)
#     <out-root>          gets dcu/  (DJson.dcu + the DJsonD7 package artefacts)
#
# Uses the vendored prebuilt D7 dcu. To rebuild instead: dcc32 src/DJson.pas
# (one self-contained unit, stock RTL deps only) into $OUT/dcu.
set -euo pipefail

SRC=${1:?usage: install-djson.sh <djson-vendor-dir> <out-root>}
OUT=${2:?usage: install-djson.sh <djson-vendor-dir> <out-root>}
LIBKEY='HKLM\Software\Borland\Delphi\7.0\Library'

echo ">>> djson dcus -> $OUT/dcu"
install -d "$OUT/dcu"
cp -f "$SRC/lib-d7/DJson.dcu" "$SRC/lib-d7/DJsonD7.dcu" "$SRC/lib-d7/DJsonD7.dcp" "$OUT/dcu/"

echo ">>> registry: djson dcu on the IDE library path"
old=$(wine reg query "$LIBKEY" /v 'Search Path' | sed -n 's/.*Search Path[[:space:]]*REG_SZ[[:space:]]*//p' | tr -d '\r')
case ";$old;" in
  *';C:\opt\djson\dcu;'*) ;;                                    # idempotent re-run
  *) wine reg add "$LIBKEY" /v 'Search Path' /d "C:\\opt\\djson\\dcu;$old" /f ;;
esac

wineserver -w
echo ">>> djson installed"
