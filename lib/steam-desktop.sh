#!/bin/bash
# Steam in the Plasma desktop session: gamepad UI args, virtual keyboard,
# autostart. Part of the SteamOS conversion (gaming_enable/gaming_disable).
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

steam_enable() {
    info "Applying non-optional SteamOS environment & keyboard fixes..."
    local steam_env_dir systemd_user_dir
    steam_env_dir="$HOME/.config/environment.d"
    mkdir -p "$steam_env_dir"

    # 2. Prevent KDE Wayland from blocking the virtual keyboard overlay
    echo "KWIN_IM_SHOW_ALWAYS=1" > "$steam_env_dir/99-kde-virtual-keyboard.conf"

    # 3. Setup robust background systemd service for Steam autostart on Desktop Mode
    systemd_user_dir="$HOME/.config/systemd/user"
    mkdir -p "$systemd_user_dir"

    cat << 'EOF' > "$systemd_user_dir/steam-desktop-autostart.service"
[Unit]
Description=Steam Background Autostart for Virtual Keyboard
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
# Only in the Plasma desktop session; gamescope-session starts its own Steam.
ExecCondition=/bin/sh -c '[ "$XDG_CURRENT_DESKTOP" = KDE ]'
ExecStart=/usr/bin/steam -silent
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

    # Clean out old .desktop shortcut so they don't fight
    rm -f "$HOME/.config/autostart/steam.desktop"

    # Reload user systemd context and activate the background loop
    systemctl --user daemon-reload
    systemctl --user enable --now steam-desktop-autostart.service

    ok "Steam UI parameters and keyboard autostart deployed successfully."
}

steam_disable() {
    info "Removing Steam desktop autostart..."
    systemctl --user disable --now steam-desktop-autostart.service 2>/dev/null
    rm -f "$HOME/.config/systemd/user/steam-desktop-autostart.service" \
        "$HOME/.config/environment.d/99-kde-virtual-keyboard.conf"
    systemctl --user daemon-reload
    ok "Steam desktop settings removed (takes full effect at next login)."
}

# "Steam Deck/Machine icons" menu item: Steam's gamepad UI in SteamOS 3
# mode, which shows Steam Deck button glyphs in gaming mode.
glyphs_status() {
    [[ -f "$HOME/.config/environment.d/99-gamescope-steam-glyphs.conf" ]]
}

glyphs_enable() {
    local gs_env="$HOME/.config/gamescope-session/environment"
    mkdir -p "$HOME/.config/environment.d"
    echo 'STEAM_GAMEPADUI_ARGS="-gamepadui -steamos3"' > "$HOME/.config/environment.d/99-gamescope-steam-glyphs.conf"
    if [[ -d "$HOME/.config/gamescope-session" ]]; then
        touch "$gs_env"
        sed -i '/^STEAM_GAMEPADUI_ARGS=/d' "$gs_env"
        echo 'STEAM_GAMEPADUI_ARGS="-gamepadui -steamos3"' >> "$gs_env"
    fi
    ok "Steam Deck/Machine icons on (from the next gaming mode start)."
}

glyphs_disable() {
    rm -f "$HOME/.config/environment.d/99-gamescope-steam-glyphs.conf"
    [[ -f "$HOME/.config/gamescope-session/environment" ]] &&
        sed -i '/^STEAM_GAMEPADUI_ARGS=/d' "$HOME/.config/gamescope-session/environment"
    ok "Steam's default button icons are back (from the next gaming mode start)."
}
