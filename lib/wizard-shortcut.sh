#!/bin/bash
# "Steamify shortcut" menu item: a desktop icon and an app launcher entry that
# open the newest release of Steamify CachyOS in Konsole (curl | bash, like the
# install command in the README), so it's never out of date.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

WIZARD_RELEASE="https://github.com/theupriser/cachyos-gamescope-boot/releases/latest/download"
WIZARD_URL="$WIZARD_RELEASE/setup-gamescope-boot.sh"
# Steam logo with a gear (assets/ in the repo, published with every release).
WIZARD_ICON="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/cachyos-gamescope-boot-wizard.svg"
WIZARD_LAUNCHER="${XDG_DATA_HOME:-$HOME/.local/share}/cachyos-gamescope-boot/run-wizard"
WIZARD_DESKTOP_NAME="cachyos-gamescope-boot-wizard.desktop"
WIZARD_APP_ENTRY="${XDG_DATA_HOME:-$HOME/.local/share}/applications/$WIZARD_DESKTOP_NAME"

wizard_desktop_file() {
    echo "$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")/$WIZARD_DESKTOP_NAME"
}

install_executable() {
    # install_executable <dest> <mode>: stdin to <dest>, with its mode set
    # before it appears. Plasma treats a desktop icon it saw while it wasn't
    # executable yet as untrusted and opens it in an editor.
    local dest="$1" tmp
    mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp "$(dirname "$dest")/.tmp.XXXXXX")"
    cat > "$tmp"
    chmod "$2" "$tmp"
    mv -f "$tmp" "$dest"
}

launcher_status() {
    [[ -x "$WIZARD_LAUNCHER" && -f "$WIZARD_APP_ENTRY" ]]
}

launcher_enable() {
    info "Adding the Steamify shortcut (desktop icon and app launcher entry)..."
    install_executable "$WIZARD_LAUNCHER" 755 << EOF
#!/bin/bash
# Installed by Steamify CachyOS: run its newest release.
if ! curl -fsSL --max-time 30 "$WIZARD_URL" | bash; then
    echo
    echo "Couldn't download or run the wizard. Are you connected to the internet?"
fi
echo
read -rp "Press Enter to close this window... " _
EOF

    # The icon comes with the release; without it, Steam's own icon.
    local icon=steam tmp
    tmp="$(mktemp)"
    if curl -fsSL --max-time 20 "$WIZARD_RELEASE/steam-gaming-settings.svg" -o "$tmp" && grep -q '<svg' "$tmp"; then
        install -D -m 644 "$tmp" "$WIZARD_ICON"
        icon=cachyos-gamescope-boot-wizard
        gtk-update-icon-cache -q -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true
    else
        warn "Couldn't download the shortcut's icon; using Steam's icon instead."
    fi
    rm -f "$tmp"

    local entry
    entry="[Desktop Entry]
Type=Application
Name=Steamify CachyOS
Comment=Turn the SteamOS-style parts of this PC on or off
Exec=konsole -e $WIZARD_LAUNCHER
Icon=$icon
Terminal=false
Categories=Game;System;Settings;"
    printf '%s\n' "$entry" | install_executable "$WIZARD_APP_ENTRY" 644
    printf '%s\n' "$entry" | install_executable "$(wizard_desktop_file)" 755
    kbuildsycoca6 >/dev/null 2>&1 || true
    ok "Steamify shortcut added: \"Steamify CachyOS\" on the desktop and in the launcher."
}

launcher_disable() {
    rm -f "$(wizard_desktop_file)" "$WIZARD_APP_ENTRY" "$WIZARD_LAUNCHER" "$WIZARD_ICON"
    rmdir "$(dirname "$WIZARD_LAUNCHER")" 2>/dev/null || true
    kbuildsycoca6 >/dev/null 2>&1 || true
    ok "Steamify shortcut removed."
}
