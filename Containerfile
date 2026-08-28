# PLAN.md Phase 4: lean dev/CI image. Bakes the Phase 3 golden snapshot
# (d7prefix.tar) into d7-base — no installer runs at build time.
#
#   podman build -f Containerfile -t d7-dev .
#
# d7prefix.tar is a Wine prefix with Delphi 7 Enterprise already installed
# (BDE, QuickReport, Rave; registered via dent.slip), produced by:
#   podman volume export d7-prefix -o d7prefix.tar
# It is private and gitignored — rebuild it, don't commit it.

FROM d7-base

# Bind-mount the snapshot (no COPY layer for 1.1 GB), swap it in for the empty
# booted prefix from d7-base, and fix ownership so wine's prefix check passes.
# W: -> /work gives the project mount a drive letter (dangling until run -v).
USER root
RUN --mount=type=bind,source=d7prefix.tar,target=/mnt/d7prefix.tar,z \
    set -eux; \
    rm -rf /home/dev/d7; mkdir -p /home/dev/d7; \
    tar xf /mnt/d7prefix.tar -C /home/dev/d7; \
    chown -R dev:dev /home/dev/d7; \
    ln -sf /work /home/dev/d7/dosdevices/w:; \
    chown -h dev:dev /home/dev/d7/dosdevices/w:; \
    install -d -o dev -g dev -m 700 /run/user/1000
USER dev

# dcc32 / delphi32 on PATH for headless compiles; XDG_RUNTIME_DIR silences a
# wine warning on every invocation.
#
# WINEDLLOVERRIDES overrides d7-base's `mscoree,mshtml=`: .NET/Mono stays off (no
# wineboot prompt to worry about here — the prefix is already booted), but mshtml
# goes back to builtin, without which the D7 IDE throws at startup and quits.
ENV PATH="/home/dev/d7/drive_c/Program Files/Borland/Delphi7/Bin:${PATH}" \
    XDG_RUNTIME_DIR=/run/user/1000 \
    WINEDLLOVERRIDES=mscoree=

# Indy 10.6.3.12 built here for D7 into /opt/indy10 (generic, not project-
# specific — baked so CI compiles don't rebuild Indy every run). Then swap it in
# for the bundled Indy 9 IDE-side: the two can't coexist as loaded packages
# (same unit names), so swap-indy-ide.sh strips Indy 9 + the IntraWeb design
# package and registers Indy 10's. Headless `dcc32` uses $INDY10/dcu (put first
# on -U); the IDE gets it via the library path + Bin\*.bpl that the swap sets.
USER root
COPY --chown=dev:dev scripts/build-indy10.sh scripts/swap-indy-ide.sh /usr/local/bin/
RUN --mount=type=bind,source=vendor/indy10,target=/mnt/indy10,z \
    set -eux; \
    install -d -o dev -g dev /opt/indy10; \
    su -p -s /bin/bash dev -c ' \
      cp -a /mnt/indy10 /tmp/indy10 && \
      build-indy10.sh /tmp/indy10 /opt/indy10 && \
      swap-indy-ide.sh /opt/indy10 && \
      rm -rf /tmp/indy10 /opt/indy10/build'
USER dev
ENV INDY10=/opt/indy10

CMD ["wine", "explorer", "/desktop=d7,1600x1000", "C:\\Program Files\\Borland\\Delphi7\\Bin\\delphi32.exe"]
