#!/usr/bin/env bash
# Install the MWA Software JPEG Component Library (v1.10.0) into the D7 workstation
# the way a dev would install it once through the IDE: register its design package
# on the palette, put its runtime bpl where package-load can find it, and drop its
# dcus on the compile + IDE library search path. Headless — registry via `wine reg`.
#
#   install-mwajpeg.sh <mwajpeg-vendor-dir> <out-root>
#     <mwajpeg-vendor-dir>  vendor/mwajpeg  (needs bpl-d7/ and dcu-d7/)
#     <out-root>            gets dcu/  (.dcu + .dcp for -U / library-path consumers)
#
# Uses the vendored 2007-era D7 .dcu/.bpl (a genuine D7 build — they load). If a
# future D7 rebuild ever rejects them, rebuild from dpk/mwajpg.dpk: once plain for
# the runtime bpl, once with -dDESIGNTIME for dclmwajpgd7.bpl.
set -euo pipefail

SRC=${1:?usage: install-mwajpeg.sh <mwajpeg-vendor-dir> <out-root>}
OUT=${2:?usage: install-mwajpeg.sh <mwajpeg-vendor-dir> <out-root>}
D="/home/dev/d7/drive_c/Program Files/Borland/Delphi7"
K='HKLM\Software\Borland\Delphi\7.0\Known Packages'
LIBKEY='HKLM\Software\Borland\Delphi\7.0\Library'

echo ">>> mwajpeg dcus -> $OUT/dcu"
install -d "$OUT/dcu"
cp -f "$SRC/dcu-d7/"*.dcu "$SRC/dcu-d7/"*.dcp "$OUT/dcu/"

# The design package links the runtime one; both must be on the Windows PATH
# (Bin is) for LoadPackage to resolve it.
echo ">>> mwajpeg bpls -> Bin"
cp -f "$SRC/bpl-d7/mwajpgd7.bpl" "$SRC/bpl-d7/dclmwajpgd7.bpl" "$D/Bin/"

echo ">>> registry: palette package"
wine reg add "$K" /v '$(DELPHI)\Bin\dclmwajpgd7.bpl' /d 'MWA JPEG Component Library' /f

echo ">>> registry: mwajpeg dcus on the IDE library path"
old=$(wine reg query "$LIBKEY" /v 'Search Path' | sed -n 's/.*Search Path[[:space:]]*REG_SZ[[:space:]]*//p' | tr -d '\r')
case ";$old;" in
  *';C:\opt\mwajpeg\dcu;'*) ;;                                  # idempotent re-run
  *) wine reg add "$LIBKEY" /v 'Search Path' /d "C:\\opt\\mwajpeg\\dcu;$old" /f ;;
esac

wineserver -w
echo ">>> mwajpeg installed"
