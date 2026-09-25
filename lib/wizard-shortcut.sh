#!/bin/bash
# "Steamify shortcut" menu item: "Steamify CachyOS" on the desktop and in the
# app launcher opens the newest release of the app (curl | bash of
# steamify-app.sh, like the install command in the README), so it's never out
# of date; "Steamify Terminal" in the launcher opens the terminal menu in
# Konsole the same way.
# Sourced by steamify.sh; not meant to be run on its own.

WIZARD_RELEASE="https://github.com/theupriser/steamify-cachyos/releases/latest/download"
WIZARD_URL="$WIZARD_RELEASE/steamify.sh"
WIZARD_APP_URL="$WIZARD_RELEASE/steamify-app.sh"
# Steam logo with a gear (assets/ in the repo, published with every release).
WIZARD_ICON="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/cachyos-gamescope-boot-wizard.svg"
WIZARD_LAUNCHER="${XDG_DATA_HOME:-$HOME/.local/share}/cachyos-gamescope-boot/run-wizard"
WIZARD_APP_LAUNCHER="${XDG_DATA_HOME:-$HOME/.local/share}/cachyos-gamescope-boot/run-app"
WIZARD_APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
# steamify-ui: the id the app gives itself, so its window belongs to this
# entry. steamify-app.sh leaves an entry with X-Steamify-Shortcut alone.
WIZARD_DESKTOP_NAME="steamify-ui.desktop"
WIZARD_APP_ENTRY="$WIZARD_APPS/$WIZARD_DESKTOP_NAME"
WIZARD_TERMINAL_ENTRY="$WIZARD_APPS/steamify-terminal.desktop"
# Before 2.0.1 the shortcut opened the terminal menu under this name.
WIZARD_OLD_NAME="cachyos-gamescope-boot-wizard.desktop"

wizard_desktop_dir() {
    xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop"
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
    [[ -x "$WIZARD_APP_LAUNCHER" && -x "$WIZARD_LAUNCHER" && -f "$WIZARD_APP_ENTRY" && -f "$WIZARD_TERMINAL_ENTRY" ]]
}

# A shortcut from before 2.0.1 (terminal only): the menu ticks the item, so a
# normal run replaces it.
launcher_repair() { [[ -f "$WIZARD_APPS/$WIZARD_OLD_NAME" ]] && ! launcher_status; }

launcher_enable() {
    info "Adding the Steamify shortcut (the app on the desktop and in the launcher, Steamify Terminal in the launcher)..."
    install_executable "$WIZARD_LAUNCHER" 755 << EOF
#!/bin/bash
# Installed by Steamify CachyOS: run its newest release.
# pipefail: a failed download must count as a failure, not an empty script.
set -o pipefail
if ! curl -fsSL --max-time 30 "$WIZARD_URL" | bash; then
    echo
    echo "Couldn't download or run the wizard. Are you connected to the internet?"
    echo
    read -rp "Press Enter to close this window... " _
    exit 1
fi
# Done: close the window after a countdown (Enter closes it right away).
echo
for (( i = 10; i > 0; i-- )); do
    printf '\rClosing this window in %2d seconds (Enter to close now)... ' "\$i"
    read -rs -t 1 _ && break
done
echo
EOF

    # The app, without a terminal. Only the first time, when PySide6 still
    # has to be installed, it runs in Konsole: sudo asks for the password there.
    install_executable "$WIZARD_APP_LAUNCHER" 755 << EOF
#!/bin/bash
# Installed by Steamify CachyOS: start the newest release of its app.
set -o pipefail
if [[ "\${1:-}" != --in-terminal ]] && ! python3 -c 'import PySide6.QtQml' 2>/dev/null; then
    exec konsole -e "\$0" --in-terminal
fi
if ! curl -fsSL --max-time 30 "$WIZARD_APP_URL" | bash; then
    msg="Couldn't download or start Steamify. Are you connected to the internet?"
    if [[ "\${1:-}" == --in-terminal ]]; then echo; echo "\$msg"; read -rp "Press Enter to close this window... " _
    else kdialog --title Steamify --sorry "\$msg" 2>/dev/null; fi
    exit 1
fi
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
Exec=$WIZARD_APP_LAUNCHER
Icon=$icon
Terminal=false
Categories=Game;System;Settings;
X-Steamify-Shortcut=true"
    printf '%s\n' "$entry" | install_executable "$WIZARD_APP_ENTRY" 644
    printf '%s\n' "$entry" | install_executable "$(wizard_desktop_dir)/$WIZARD_DESKTOP_NAME" 755
    printf '%s\n' "[Desktop Entry]
Type=Application
Name=Steamify Terminal
Comment=Steamify CachyOS's menu in a terminal
Exec=konsole -e $WIZARD_LAUNCHER
Icon=$icon
Terminal=false
Categories=Game;System;Settings;" | install_executable "$WIZARD_TERMINAL_ENTRY" 644
    # The terminal-only shortcut from before 2.0.1.
    rm -f "$(wizard_desktop_dir)/$WIZARD_OLD_NAME" "$WIZARD_APPS/$WIZARD_OLD_NAME"
    kbuildsycoca6 >/dev/null 2>&1 || true
    ok "Steamify shortcut added: \"Steamify CachyOS\" (the app) on the desktop and in the launcher, \"Steamify Terminal\" in the launcher."
}

launcher_disable() {
    # The launcher entry only if it's ours: steamify-app.sh writes its own
    # under the same name when there's no shortcut.
    grep -q '^X-Steamify-Shortcut=true' "$WIZARD_APP_ENTRY" 2>/dev/null && rm -f "$WIZARD_APP_ENTRY"
    rm -f "$(wizard_desktop_dir)/$WIZARD_DESKTOP_NAME" "$WIZARD_TERMINAL_ENTRY" \
        "$(wizard_desktop_dir)/$WIZARD_OLD_NAME" "$WIZARD_APPS/$WIZARD_OLD_NAME" \
        "$WIZARD_LAUNCHER" "$WIZARD_APP_LAUNCHER" "$WIZARD_ICON"
    rmdir "$(dirname "$WIZARD_LAUNCHER")" 2>/dev/null || true
    kbuildsycoca6 >/dev/null 2>&1 || true
    ok "Steamify shortcut removed."
}
