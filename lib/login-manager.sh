#!/bin/bash
# plasma-login-manager autologin into gamescope, and the session sync bridge.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

BASE_CONF="/etc/plasmalogin.conf"

check_display_manager() {
    # Step 1: warn when the login manager is not plasma-login-manager.
    local DM
    DM="$(systemctl show -p Id --value display-manager 2>/dev/null | sed 's/\.service$//')"
    info "Detected display manager: ${DM:-none}"

    if [[ "$DM" != "plasmalogin" ]]; then
        warn "This wizard was built and tested against plasma-login-manager (plasmalogin)."
        warn "Detected display manager is '${DM:-unknown}'. SDDM setups don't need"
        warn "most of these workarounds (SDDM's own Autologin works out of the box);"
        warn "this script will still try, but review the output carefully."
        ask_yn "Continue anyway?" n || exit 0
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
