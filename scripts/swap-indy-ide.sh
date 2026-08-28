#!/usr/bin/env bash
# Replace D7's bundled Indy 9 with the Indy 10 built by build-indy10.sh, for the
# IDE (delphi32). Headless — all registry edits via `wine reg`.
#
#   swap-indy-ide.sh <indy10-out-root>     # dir with bpl/ and dcu/ from build-indy10.sh
#
# D7 keeps two Indy-loaded runtime packages (Indy70, Intraweb_50_70) from ever
# coexisting with Indy 10's IndySystem70/IndyCore70/IndyProtocols70 — they
# contain the same units, so the IDE refuses to load both. So: physically remove
# the Indy 9 DCUs/BPLs, drop dclindy70 AND dclIntraweb_50_70 from the palette
# (this project uses neither IntraWeb nor Indy 9), install Indy 10's two design
# packages, and put Indy 10 first on the IDE library path.
set -euo pipefail

OUT=${1:?usage: swap-indy-ide.sh <indy10-out-root>}
D="/home/dev/d7/drive_c/Program Files/Borland/Delphi7"
K='HKLM\Software\Borland\Delphi\7.0\Known Packages'
LIBKEY='HKLM\Software\Borland\Delphi\7.0\Library'

echo ">>> removing bundled Indy 9"
rm -f "$D/Lib"/Id*.dcu "$D/Lib/Debug"/Id*.dcu "$D/Lib"/Indy*.dcp
rm -f "$D/Bin"/indy70.bpl "$D/Bin"/indy70.map "$D/Bin"/dclindy70.bpl "$D/Bin"/dclindy70.map
rm -rf "$D/Source/Indy"

echo ">>> installing Indy 10 bpls into Bin (on the Windows PATH for package load)"
cp -f "$OUT/bpl"/*.bpl "$D/Bin/"

echo ">>> registry: palette packages"
wine reg delete "$K" /v '$(DELPHI)\Bin\dclindy70.bpl'            /f
wine reg delete "$K" /v '$(DELPHI)\Bin\dclIntraweb_50_70.bpl'    /f
wine reg add    "$K" /v '$(DELPHI)\Bin\dclIndyCore70.bpl'        /d 'Indy 10 Core Design Time'      /f
wine reg add    "$K" /v '$(DELPHI)\Bin\dclIndyProtocols70.bpl'   /d 'Indy 10 Protocols Design Time' /f

echo ">>> registry: Indy 10 first on the IDE library path"
old=$(wine reg query "$LIBKEY" /v 'Search Path' | sed -n 's/.*Search Path[[:space:]]*REG_SZ[[:space:]]*//p' | tr -d '\r')
case "$old" in
  'C:\opt\indy10\dcu;'*) ;;                                   # already done (idempotent re-run)
  *) wine reg add "$LIBKEY" /v 'Search Path' /d "C:\\opt\\indy10\\dcu;$old" /f ;;
esac

wineserver -w
echo ">>> done"
