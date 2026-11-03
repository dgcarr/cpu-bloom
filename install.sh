#!/usr/bin/env bash
# Builds CPU Bloom with Processing and installs it under a prefix, by default
# ~/.local for the current user only:
#
#   PREFIX/lib/cpu-bloom/            exported app + top-bar indicator script
#   PREFIX/bin/cpu-bloom             command-line launcher
#   PREFIX/share/applications/       desktop launcher (app menu, dock)
#   PREFIX/share/icons/hicolor/      app and top-bar icons
#
# Usage: ./install.sh [--no-build] [--variant=linux-x86_64|linux-aarch64]
#                     [--prefix=DIR] [--destdir=DIR] [--uninstall]
#
# For every account on this computer, build as yourself, then install as root:
#   ./scripts/build-export.sh && pkexec "$PWD/install.sh" --no-build --prefix=/usr/local
# --destdir stages the files under DIR for packaging (see packaging/build.sh).
# Set PROCESSING=/path/to/Processing if it isn't in /opt/processing.

set -euo pipefail
umask 022

REPO="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$HOME/.local"
DESTDIR=""
BUILD_ARGS=()
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --no-build|--variant=*) BUILD_ARGS+=("$arg") ;;
    --prefix=*) PREFIX="$(realpath -m "${arg#--prefix=}")" ;;
    --destdir=*) DESTDIR="$(realpath -m "${arg#--destdir=}")" ;;
    --uninstall) UNINSTALL=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

ROOT="$DESTDIR$PREFIX"
APP_HOME="$ROOT/lib/cpu-bloom"
BIN="$ROOT/bin/cpu-bloom"
DESKTOP="$ROOT/share/applications/cpu-bloom.desktop"
ICONS="$ROOT/share/icons/hicolor/scalable/apps"
# Where 0.1 installed the app for one user; removed so it can't shadow this.
LEGACY_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/cpu-bloom"

stop_running() {
  [[ -z "$DESTDIR" ]] || return 0
  pkill -u "$(id -u)" -f "$PREFIX/lib/cpu-bloom/" 2>/dev/null || true
  pkill -u "$(id -u)" -f "$LEGACY_HOME/" 2>/dev/null || true
}

refresh_caches() {
  [[ -z "$DESTDIR" ]] || return 0
  update-desktop-database -q "$ROOT/share/applications" 2>/dev/null || true
  gtk-update-icon-cache -q -t -f "$ROOT/share/icons/hicolor" 2>/dev/null || true
}

if [[ $UNINSTALL == 1 ]]; then
  stop_running
  rm -rf "$APP_HOME" "$LEGACY_HOME"
  rm -f "$BIN" "$DESKTOP" "$ICONS/cpu-bloom.svg" "$ICONS/cpu-bloom-symbolic.svg"
  # Start at Login is per user; only remove it when uninstalling for this user.
  [[ "$PREFIX" == "$HOME"/* ]] && rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/cpu-bloom.desktop"
  refresh_caches
  echo "CPU Bloom uninstalled from $ROOT."
  exit 0
fi

"$REPO/scripts/build-export.sh" "${BUILD_ARGS[@]}" "$REPO/out"

stop_running
rm -rf "$APP_HOME"
[[ -n "$DESTDIR" || "$PREFIX" != "$HOME"/* ]] || rm -rf "$LEGACY_HOME"
mkdir -p "$APP_HOME" "$(dirname "$BIN")" "$(dirname "$DESKTOP")" "$ICONS"
cp -r "$REPO/out" "$APP_HOME/app"
cp "$REPO/tray/tray.js" "$APP_HOME/tray.js"
cp "$REPO/bin/cpu-bloom" "$BIN"
cp "$REPO/icons/cpu-bloom.svg" "$REPO/icons/cpu-bloom-symbolic.svg" "$ICONS/"
chmod -R u+w,go-w,a+rX "$APP_HOME"
chmod 755 "$BIN"
chmod 644 "$ICONS/cpu-bloom.svg" "$ICONS/cpu-bloom-symbolic.svg"

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=CPU Bloom
GenericName=System Monitor
Comment=Live CPU load drawn as a glowing flower
Exec="$PREFIX/bin/cpu-bloom"
Icon=cpu-bloom
Terminal=false
Categories=System;Monitor;
Keywords=cpu;load;monitor;system;overlay;
StartupWMClass=cpu-bloom
Actions=overlay;quit;

[Desktop Action overlay]
Name=Show Overlay
Exec="$PREFIX/bin/cpu-bloom" --overlay

[Desktop Action quit]
Name=Quit CPU Bloom
Exec="$PREFIX/bin/cpu-bloom" --quit
EOF
chmod 644 "$DESKTOP"

refresh_caches
if [[ -n "$DESTDIR" ]]; then
  echo "Staged in $DESTDIR (prefix $PREFIX)."
else
  echo "Installed in $PREFIX. Launch \"CPU Bloom\" from the app menu, or run: $PREFIX/bin/cpu-bloom [--overlay]"
fi
