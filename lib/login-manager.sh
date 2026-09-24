#!/bin/bash
# Booting into gaming mode: autologin into gamescope with SDDM or
# plasma-login-manager (plus the session sync bridge the latter needs).
# Sourced by steamify.sh; not meant to be run on its own.

BASE_CONF="/etc/plasmalogin.conf"

# The "SteamOS conversion" menu item: gaming mode boot, the Return to
# Gaming Mode shortcut and Steam on the desktop (lib/steam-desktop.sh).
gaming_status() {
    # Autologin into gamescope is configured for this user.
    case "$(current_display_manager)" in
        sddm) [[ -f /etc/sddm.conf.d/10-gamescope-autologin.conf ]] ;;
        plasmalogin)
            sed -n '/^\[Autologin\]/,/^\[/p' "$BASE_CONF" 2>/dev/null | grep -qx "User=$USER" &&
                [[ -f /etc/systemd/system/sync-steamos-session.path ]] ;;
        *) return 1 ;;
    esac
}

gaming_enable() {
    # LOGIN_MANAGER (sddm with single user, else plasmalogin) is set by the
    # menu. Re-running with the other value switches over cleanly.
    install_required_packages || return 1
    case "$LOGIN_MANAGER" in
        sddm)
            switch_to_sddm || return 1
            configure_sddm_autologin
            remove_session_sync
            ;;
        plasmalogin)
            remove_sddm_autologin
            switch_to_plasmalogin || return 1
            configure_autologin
            install_session_sync
            ;;
    esac
    create_desktop_shortcut
    steam_enable
}

gaming_disable() {
    # Back to a normal desktop boot with CachyOS's default login manager.
    # Packages (steam, gamescope-session-cachyos, ...) are kept.
    info "Turning off booting into gaming mode..."
    remove_sddm_autologin
    remove_session_sync
    restore_plasmalogin_config
    switch_to_plasmalogin
    remove_desktop_shortcut
    steam_disable
    ok "The PC boots to the normal login screen again (from the next boot)."
}

switch_to_plasmalogin() {
    [[ "$(current_display_manager)" == plasmalogin ]] && return 0
    info "Switching the login manager to plasma-login-manager..."
    sudo pacman -S --needed --noconfirm plasma-login-manager || { err "Installing plasma-login-manager failed."; return 1; }
    local current
    current="$(systemctl show -p Id --value display-manager 2>/dev/null)"
    [[ -n "$current" && "$current" != plasmalogin.service ]] && sudo systemctl disable "$current"
    sudo systemctl enable -f plasmalogin.service || { err "Enabling plasmalogin failed."; return 1; }
    ok "plasma-login-manager is the login manager from the next boot on."
}

remove_sddm_autologin() {
    sudo rm -f /etc/sddm.conf.d/10-gamescope-autologin.conf
}

restore_plasmalogin_config() {
    # Put back the original /etc/plasmalogin.conf from the first run's
    # backup, or at least drop our [Autologin] section.
    if [[ -f "${BASE_CONF}.bak-gamescope-wizard" ]]; then
        sudo cp -a "${BASE_CONF}.bak-gamescope-wizard" "$BASE_CONF"
    elif [[ -f "$BASE_CONF" ]]; then
        sudo awk '/^\[Autologin\]/ { skip=1; next } /^\[/ { skip=0 } !skip { print }' "$BASE_CONF" |
            sudo tee "${BASE_CONF}.tmp" > /dev/null && sudo mv "${BASE_CONF}.tmp" "$BASE_CONF"
    fi
}

switch_to_sddm() {
    # Takes effect at the next boot; the running session is left alone.
    [[ "$(current_display_manager)" == sddm ]] && return 0
    info "Installing and enabling SDDM..."
    sudo pacman -S --needed --noconfirm sddm || { err "Installing sddm failed."; return 1; }
    local current
    current="$(systemctl show -p Id --value display-manager 2>/dev/null)"
    if [[ -n "$current" && "$current" != "sddm.service" ]]; then
        sudo systemctl disable "$current"
    fi
    sudo systemctl enable -f sddm.service || { err "Enabling sddm failed."; return 1; }
    ok "SDDM is the login manager from the next boot on."
}

configure_sddm_autologin() {
    # User= and Relogin= live in our own fragment; steam-set-session keeps
    # Session= up to date in zz-steamos-autologin.conf, which sorts later
    # and so wins. /etc/sddm.conf is read last, so any [Autologin] there
    # would override both and is removed.
    local conf="/etc/sddm.conf.d/10-gamescope-autologin.conf"
    info "Configuring SDDM autologin for $TARGET_USER into gamescope (Relogin=true)"
    sudo mkdir -p /etc/sddm.conf.d
    sudo tee "$conf" > /dev/null << EOF
[Autologin]
User=$TARGET_USER
Session=gamescope-session.desktop
Relogin=true
EOF

    if [[ -f /etc/sddm.conf ]] && grep -q '^\[Autologin\]' /etc/sddm.conf; then
        backup_file /etc/sddm.conf
        sudo awk '
            /^\[Autologin\]/ { skip=1; next }
            /^\[/ { skip=0 }
            !skip { print }
        ' /etc/sddm.conf | sudo tee /etc/sddm.conf.tmp > /dev/null &&
            sudo mv /etc/sddm.conf.tmp /etc/sddm.conf
        info "Removed [Autologin] from /etc/sddm.conf (backup kept)."
    fi

    # Start in gamescope, through CachyOS's own tool so its file is current.
    sudo /usr/lib/steamos/steam-set-session gamescope-session.desktop

    ok "SDDM autologin configured:"
    cat "$conf"
    echo
}

remove_session_sync() {
    # The plasmalogin sync bridge from an earlier run isn't needed on SDDM.
    if [[ -f /etc/systemd/system/sync-steamos-session.path ]]; then
        info "Removing the plasma-login-manager sync bridge (not needed with SDDM)..."
        sudo systemctl disable --now sync-steamos-session.path 2>/dev/null
        sudo rm -f /etc/systemd/system/sync-steamos-session.path \
            /etc/systemd/system/sync-steamos-session.service \
            /usr/local/bin/sync-steamos-session.sh
        sudo systemctl daemon-reload
    fi
}

configure_autologin() {
    # Steps 3-5: plasmalogin.conf.d, the base [Autologin] section, stray fragments.
    # 3. Ensure plasmalogin.conf.d exists (fixes Switch-to-Desktop crash)
    info "Ensuring /etc/plasmalogin.conf.d exists (fixes the 'Switching to Desktop' hang bug)"
    sudo mkdir -p /etc/plasmalogin.conf.d
    ok "Directory present."
    echo

    # 4. Fix the base /etc/plasmalogin.conf
    info "Configuring $BASE_CONF (Session=gamescope-session.desktop, User=$TARGET_USER, Relogin=true)"
    backup_file "$BASE_CONF"

    sudo touch "$BASE_CONF"

    sudo awk '
        BEGIN { in_autologin=0 }
        /^\[Autologin\]/ { in_autologin=1; next }
        /^\[/ { in_autologin=0 }
        !in_autologin { print }
    ' "$BASE_CONF" | sudo tee "${BASE_CONF}.tmp" > /dev/null || { err "Failed to rewrite $BASE_CONF."; exit 1; }

    sudo mv "${BASE_CONF}.tmp" "$BASE_CONF"

    sudo tee -a "$BASE_CONF" > /dev/null << EOF
[Autologin]
Session=gamescope-session.desktop
User=$TARGET_USER
Relogin=true
EOF

    ok "Base autologin config written:"
    sudo sed -n '/^\[Autologin\]/,$p' "$BASE_CONF"
    echo

    # 5. Clean up any stray conf.d autologin fragments from manual attempts
    info "Removing any leftover manual conf.d autologin overrides (base config now handles it)"
    sudo rm -f /etc/plasmalogin.conf.d/zzz-steamos-autologin*.conf
    ok "Cleaned."
    echo
}

install_session_sync() {
    # Steps 6-8: sync bridge conf.d -> base config, its systemd units, first run.
    # 6. Install the sync bridge: conf.d -> base config
    local SYNC_SCRIPT="/usr/local/bin/sync-steamos-session.sh"
    info "Installing session sync bridge at $SYNC_SCRIPT"

    sudo tee "$SYNC_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
SRC="/etc/plasmalogin.conf.d/zz-steamos-autologin.conf"
DEST="/etc/plasmalogin.conf"

[[ -f "$SRC" ]] || exit 0
SESSION=$(grep -oP '^Session=\K.*' "$SRC")
[[ -z "$SESSION" ]] && exit 0

# Only touch Session= inside [Autologin]; other sections may have their own.
if sed -n '/^\[Autologin\]/,/^\[/p' "$DEST" | grep -q '^Session='; then
    sed -i "/^\[Autologin\]/,/^\[/ s|^Session=.*|Session=$SESSION|" "$DEST"
elif grep -q '^\[Autologin\]' "$DEST"; then
    sed -i "/^\[Autologin\]/a Session=$SESSION" "$DEST"
else
    printf '\n[Autologin]\nSession=%s\n' "$SESSION" >> "$DEST"
fi
EOF

    sudo chmod +x "$SYNC_SCRIPT"
    ok "Sync script installed."
    echo

    # 7. systemd path watcher + service
    info "Installing systemd path watcher so session switches take effect immediately"

    sudo tee /etc/systemd/system/sync-steamos-session.path > /dev/null << 'EOF'
[Unit]
Description=Watch for steamos session changes

[Path]
PathModified=/etc/plasmalogin.conf.d/zz-steamos-autologin.conf

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/sync-steamos-session.service > /dev/null << 'EOF'
[Unit]
Description=Sync steamos session selection into plasmalogin.conf
# Session switches can come in bursts (switch + autologin reset); never
# let systemd's start rate limit silently stop the bridge.
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-steamos-session.sh
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now sync-steamos-session.path
    ok "Path watcher enabled."
    echo

    # 8. Run it once now so current state is in sync
    info "Running the sync once now to align current state"
    sudo systemctl start sync-steamos-session.service
    ok "Done. Current base config:"
    sudo cat "$BASE_CONF"
    echo
}
