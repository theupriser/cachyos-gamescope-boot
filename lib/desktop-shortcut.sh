#!/bin/bash
# "Return to Gaming Mode" desktop shortcut and the sudoers rule it needs.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

create_desktop_shortcut() {
    # Determine the home directory of the target user
    local user_home
    user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    # Locate the correct Desktop directory
    local desktop_dir
    if [[ -f "$user_home/.config/user-dirs.dirs" ]]; then
        desktop_dir=$(grep '^XDG_DESKTOP_DIR=' "$user_home/.config/user-dirs.dirs" | cut -d '"' -f 2)
        desktop_dir="${desktop_dir/\$HOME/$user_home}"
    fi
    desktop_dir="${desktop_dir:-$user_home/Desktop}"

    mkdir -p "$desktop_dir"

    # Let the shortcut restart the login manager without a password prompt
    # (it runs with Terminal=false, so sudo can't ask). Scoped to exactly
    # the two commands the shortcut needs, for this user only.
    local sudoers_tmp
    sudoers_tmp="$(mktemp)"
    cat > "$sudoers_tmp" << EOF
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start sync-steamos-session.service, /usr/bin/systemctl restart plasmalogin
EOF
    if sudo visudo -cf "$sudoers_tmp" >/dev/null; then
        sudo install -m 0440 -o root -g root "$sudoers_tmp" /etc/sudoers.d/gamescope-session-switch
        ok "Installed /etc/sudoers.d/gamescope-session-switch for the shortcut."
    else
        warn "Generated sudoers rule failed validation; the shortcut will not be able to restart plasmalogin."
    fi
    rm -f "$sudoers_tmp"

    # SteamOS itself uses Valve's "gaming-return" icon (Steam logo with a
    # return arrow; the Deck-style arrow is only used on Steam Deck
    # hardware). It comes with the Vapor theme; without it, use Steam's icon.
    local shortcut_icon="steam"
    [[ -f "$user_home/.local/share/icons/hicolor/scalable/actions/gaming-return.svg" ]] &&
        shortcut_icon="gaming-return"

    # 2. Generate the .desktop shortcut with instant session switcher strings
    local shortcut_path="$desktop_dir/Return to Gaming Mode.desktop"
    info "Creating 'Return to Gaming Mode' desktop shortcut at: $shortcut_path"

    cat << EOF > "$shortcut_path"
[Desktop Entry]
Name=Return to Gaming Mode
Comment=Switch session back to Gamescope
Exec=sh -c 'steamos-session-select gamescope && sudo -n /usr/bin/systemctl start sync-steamos-session.service && sudo -n /usr/bin/systemctl restart plasmalogin'
Icon=$shortcut_icon
Terminal=false
Type=Application
Categories=System;
EOF

    # Fix permissions for the target user and KDE Plasma desktop ecosystem
    chmod +x "$shortcut_path"

    ok "Desktop shortcut created successfully."
}
