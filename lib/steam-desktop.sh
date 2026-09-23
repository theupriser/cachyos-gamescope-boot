#!/bin/bash
# Steam in the Plasma desktop session: gamepad UI args, virtual keyboard,
# autostart, and no screen locking (like SteamOS).
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

setup_steam_desktop() {
    # Step 8b: always runs.
    info "Applying non-optional SteamOS environment & keyboard fixes..."
    local steam_env_dir gs_env systemd_user_dir
    steam_env_dir="$HOME/.config/environment.d"
    mkdir -p "$steam_env_dir"

    # 1. Force Gamescope Steam to boot into Deck mode and load Deck glyphs
    echo "STEAM_GAMEPADUI_ARGS=\"-gamepadui -steamos3\"" > "$steam_env_dir/99-gamescope-steam-glyphs.conf"
    gs_env="$HOME/.config/gamescope-session/environment"
    if [[ -d "$HOME/.config/gamescope-session" ]]; then
        touch "$gs_env"
        sed -i '/^STEAM_GAMEPADUI_ARGS=/d' "$gs_env"
        echo "STEAM_GAMEPADUI_ARGS=\"-gamepadui -steamos3\"" >> "$gs_env"
    fi

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

setup_single_user() {
    # With SINGLE_USER (chosen in step 1), like SteamOS: one user and no
    # password prompts, since typing a password with a controller is
    # miserable. Hides Lock / Switch User / Log Out
    # everywhere (launcher, Meta+L, Ctrl+Alt+Del) and never locks on idle or
    # resume; "Return to Gaming Mode" is the way out of the desktop. Declining
    # restores KDE's defaults.
    local action allow=true
    [[ "$SINGLE_USER" == true ]] && allow=false
    for action in lock_screen switch_user start_new_session; do
        kwriteconfig6 --file kdeglobals --group "KDE Action Restrictions" --key "action/$action" "$allow"
    done
    if [[ "$allow" == false ]]; then
        kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
        kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false
        kwriteconfig6 --file kscreenlockerrc --group Daemon --key Timeout 0
        # The action restriction hides Lock in menus but not the Meta+L
        # shortcut; unbind it (format: current,default,description).
        kwriteconfig6 --file kglobalshortcutsrc --group ksmserver --key "Lock Session" \
            $'none,Screensaver\tMeta+L,Lock Session'
        kwriteconfig6 --file kglobalshortcutsrc --group ksmserver --key "Log Out" \
            'none,Ctrl+Alt+Del,Show Logout Screen'
        set_launcher_leave_buttons single
        ok "Screen locking, user switching and logging out disabled."
    else
        kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock --delete
        kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume --delete
        kwriteconfig6 --file kscreenlockerrc --group Daemon --key Timeout --delete
        kwriteconfig6 --file kglobalshortcutsrc --group ksmserver --key "Lock Session" \
            $'Screensaver\tMeta+L,Screensaver\tMeta+L,Lock Session'
        kwriteconfig6 --file kglobalshortcutsrc --group ksmserver --key "Log Out" \
            'Ctrl+Alt+Del,Ctrl+Alt+Del,Show Logout Screen'
        set_launcher_leave_buttons default
        ok "Keeping KDE's normal screen locking and user switching."
    fi
}

set_launcher_leave_buttons() {
    # "single": only Sleep / Restart / Shut Down buttons in the launcher, no
    # Session dropdown (that's where Log Out lives). Restricting the
    # "logout" action instead would also hide Restart and Shut Down.
    # "default": Plasma's own buttons.
    local mode="$1" applet
    for applet in $(plasma_applets org.kde.plasma.kickoff); do
        local -a grp=(--file plasma-org.kde.plasma.desktop-appletsrc --group Containments
            --group "${applet%%:*}" --group Applets --group "${applet#*:}"
            --group Configuration --group General)
        if [[ "$mode" == single ]]; then
            kwriteconfig6 "${grp[@]}" --key primaryActions 3
            kwriteconfig6 "${grp[@]}" --key systemFavorites 'suspend,reboot,shutdown'
        else
            kwriteconfig6 "${grp[@]}" --key primaryActions --delete
            kwriteconfig6 "${grp[@]}" --key systemFavorites --delete
        fi
    done
    if pgrep -u "$USER" -x plasmashell >/dev/null; then
        local js
        if [[ "$mode" == single ]]; then
            js="w.writeConfig('primaryActions', 3); w.writeConfig('systemFavorites', 'suspend,reboot,shutdown');"
        else
            js="w.writeConfig('primaryActions', 0); w.writeConfig('systemFavorites', 'suspend,hibernate,reboot,shutdown');"
        fi
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            "panels().forEach(function (p) { p.widgets('org.kde.plasma.kickoff').forEach(function (w) { w.currentConfigGroup = ['General']; $js w.reloadConfig(); }); })" \
            >/dev/null 2>&1 || true
    fi
}
