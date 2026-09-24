#!/bin/bash
# "Return to Gaming Mode" desktop shortcut and the sudoers rule it needs.
# Sourced by steamify.sh; not meant to be run on its own.

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

    # On SDDM, steamos-session-select logging out is enough: Relogin=true
    # logs straight back in to the newly selected session, like SteamOS.
    # plasma-login-manager needs the sync bridge run and a restart, which
    # the shortcut can't sudo for interactively (Terminal=false), so it gets
    # a password-less rule scoped to exactly those two commands.
    local exec_line="steamos-session-select gamescope"
    if [[ "$LOGIN_MANAGER" == "plasmalogin" ]]; then
        exec_line="sh -c 'steamos-session-select gamescope && sudo -n /usr/bin/systemctl start sync-steamos-session.service && sudo -n /usr/bin/systemctl restart plasmalogin'"
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
    else
        sudo rm -f /etc/sudoers.d/gamescope-session-switch
    fi

    # SteamOS itself uses Valve's "gaming-return" icon (Steam logo with a
    # return arrow; the Deck-style arrow is only used on Steam Deck
    # hardware). The theme installs it (lib/steamos-extras.sh) and updates
    # the shortcut via set_shortcut_icon; without it, use Steam's icon.
    local shortcut_icon="steam"
    [[ -f /usr/local/share/icons/hicolor/scalable/actions/gaming-return.svg ]] &&
        shortcut_icon="gaming-return"

    # 2. Generate the .desktop shortcut with instant session switcher strings
    local shortcut_path="$desktop_dir/Return to Gaming Mode.desktop"
    info "Creating 'Return to Gaming Mode' desktop shortcut at: $shortcut_path"

    cat << EOF > "$shortcut_path"
[Desktop Entry]
Name=Return to Gaming Mode
Comment=Switch session back to Gamescope
Exec=$exec_line
Icon=$shortcut_icon
Terminal=false
Type=Application
Categories=System;
EOF

    # Fix permissions for the target user and KDE Plasma desktop ecosystem
    chmod +x "$shortcut_path"

    ok "Desktop shortcut created successfully."
}

set_shortcut_icon() {
    # set_shortcut_icon <icon>: update an existing shortcut, if any.
    local shortcut
    shortcut="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")/Return to Gaming Mode.desktop"
    [[ -f "$shortcut" ]] && sed -i "s/^Icon=.*/Icon=$1/" "$shortcut"
    return 0
}

remove_desktop_shortcut() {
    local desktop_dir
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    rm -f "$desktop_dir/Return to Gaming Mode.desktop"
    sudo rm -f /etc/sudoers.d/gamescope-session-switch
}
