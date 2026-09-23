#!/bin/bash
# plasma-login-manager autologin into gamescope, and the session sync bridge.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

BASE_CONF="/etc/plasmalogin.conf"

choose_setup_mode() {
    # Step 1: one question decides both the login manager and locking.
    # "Single user, no password" is SteamOS: SDDM (which CachyOS's session
    # tools support directly, no workarounds) plus no lock screen, user
    # switching or log out. Otherwise keep the current login manager
    # (CachyOS's default plasma-login-manager gets the sync bridge below)
    # and KDE's normal locking. Sets SINGLE_USER and LOGIN_MANAGER.
    local current
    current="$(systemctl show -p Id --value display-manager 2>/dev/null | sed 's/\.service$//')"
    info "Detected display manager: ${current:-none}"

    echo "SteamOS is a single-user console without passwords: no login screen, no"
    echo "lock screen, no user switching or logging out - typing a password with a"
    echo "controller is no fun. It uses the SDDM login manager for that."
    if ask_yn "Single user, no password, like SteamOS? (switches to SDDM)" y; then
        SINGLE_USER=true
        LOGIN_MANAGER="sddm"
        return
    fi

    SINGLE_USER=false
    if [[ "$current" == "sddm" ]]; then
        LOGIN_MANAGER="sddm"
        return
    fi
    LOGIN_MANAGER="plasmalogin"
    if [[ "$current" != "plasmalogin" ]]; then
        warn "The workarounds are built for plasma-login-manager, but '${current:-unknown}' is active."
        ask_yn "Continue anyway?" n || exit 0
    fi
}

setup_login_manager() {
    # Steps 3-8 for whichever login manager was chosen in step 1.
    case "$LOGIN_MANAGER" in
        sddm)
            switch_to_sddm || exit 1
            configure_sddm_autologin
            remove_session_sync
            ;;
        plasmalogin)
            configure_autologin
            install_session_sync
            ;;
    esac
}

switch_to_sddm() {
    # Takes effect at the next boot; the running session is left alone.
    info "Installing and enabling SDDM..."
    sudo pacman -S --needed --noconfirm sddm || { err "Installing sddm failed."; return 1; }
    local current
    current="$(systemctl show -p Id --value display-manager 2>/dev/null)"
    if [[ -n "$current" && "$current" != "sddm.service" ]]; then
        sudo systemctl disable "$current"
    fi
    sudo systemctl enable -f sddm.service || { err "Enabling sddm failed."; return 1; }
    ok "SDDM is the login manager from the next boot on."
    echo
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
