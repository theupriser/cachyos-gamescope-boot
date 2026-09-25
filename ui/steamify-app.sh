#!/bin/bash
# Steamify CachyOS - get and start the app (v2), for `curl | bash`:
#   curl -fsSL https://github.com/theupriser/steamify-cachyos/releases/latest/download/steamify-app.sh | bash
# Downloads the newest release's app package (steamify-app.tar.gz: the app,
# steamify.sh and lib/) to ~/.local/share/steamify/app, installs PySide6 if
# it's missing, adds a launcher entry, and starts the app.
# STEAMIFY_RELEASE=<tag> takes that release instead of the newest (the
# v2-ui-preview build's copy of this script sets it). STEAMIFY_BRANCH=<branch>
# takes that branch's source instead (for testing before a build).
set -euo pipefail

REPO="theupriser/steamify-cachyos"
RELEASE="${STEAMIFY_RELEASE:-latest}"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/steamify/app"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

say() { printf '\033[36m[INFO]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[ERROR] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "Run this as your normal user, not as root."
command -v pacman >/dev/null || die "This is for CachyOS/Arch (no pacman found)."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -n "${STEAMIFY_BRANCH:-}" ]]; then
    say "Downloading Steamify from the $STEAMIFY_BRANCH branch..."
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/$STEAMIFY_BRANCH.tar.gz" -o "$tmp/src.tar.gz" ||
        die "Couldn't download the $STEAMIFY_BRANCH branch."
    mkdir "$tmp/app"
    tar -xzf "$tmp/src.tar.gz" -C "$tmp/app" --strip-components=1
else
    if [[ "$RELEASE" == latest ]]; then
        url="https://github.com/$REPO/releases/latest/download/steamify-app.tar.gz"
        say "Downloading the newest Steamify app..."
    else
        url="https://github.com/$REPO/releases/download/$RELEASE/steamify-app.tar.gz"
        say "Downloading the Steamify app ($RELEASE)..."
    fi
    curl -fsSL "$url" -o "$tmp/app.tar.gz" ||
        die "Couldn't download the app (is there a release with steamify-app.tar.gz yet?)."
    mkdir "$tmp/app"
    tar -xzf "$tmp/app.tar.gz" -C "$tmp/app"
fi
[[ -x "$tmp/app/ui/steamify-ui" && -f "$tmp/app/steamify.sh" ]] || die "The download doesn't contain the app."

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST.new"; mv "$tmp/app" "$DEST.new"
rm -rf "$DEST"; mv "$DEST.new" "$DEST"
say "Installed to $DEST ($(grep -m1 -oP '^VERSION=\K.*' "$DEST/steamify.sh"))."

if ! python3 -c 'import PySide6.QtQml' 2>/dev/null; then
    say "The app needs PySide6 (Qt for Python); installing it..."
    # Piped in via curl, stdin isn't the terminal: sudo asks on it anyway.
    sudo pacman -S --needed --noconfirm pyside6 </dev/tty || die "Installing pyside6 failed."
fi

# Launcher entry (its id also names the app to the desktop portal).
mkdir -p "$APPS"
cat > "$APPS/steamify-ui.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Steamify CachyOS
Comment=Turn this PC into a SteamOS-style console
Exec=$DEST/ui/steamify-ui
Icon=$DEST/assets/steam-gaming-settings.svg
Terminal=false
Categories=Game;Settings;
EOF
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true

say "Starting Steamify..."
setsid "$DEST/ui/steamify-ui" >/dev/null 2>&1 < /dev/null &
