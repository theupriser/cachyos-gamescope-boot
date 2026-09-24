#!/bin/bash
# "Boot into: gamescope / desktop" menu item, on top of the SteamOS
# conversion. Gamescope is the default (the conversion's autologin, and
# CachyOS's cachyos-gamescope-autologin resetting to it after a desktop
# session). Desktop: a unit that sets the autologin session to Plasma at
# every boot, before the login manager starts. Switching between the two in
# a running system (Return to Gaming Mode, Steam's Switch to Desktop) works
# the same either way.
# Sourced by steamify.sh; not meant to be run on its own.

BOOT_UNIT_NAME="steamify-boot-desktop.service"
BOOT_UNIT="/etc/systemd/system/$BOOT_UNIT_NAME"
SESSION_SYNC="/usr/local/bin/sync-steamos-session.sh"

boot_status() {
    # On = boots into the desktop.
    [[ -f "$BOOT_UNIT" ]] && systemctl is-enabled -q "$BOOT_UNIT_NAME" 2>/dev/null
}

boot_enable() {
    info "Setting the PC to boot into the desktop..."
    # The sync bridge (plasma-login-manager only; not there with SDDM) copies
    # the session into the base config; run it right away rather than rely
    # on its path unit, which could still be pending when the login manager
    # starts.
    sudo tee "$BOOT_UNIT" > /dev/null << EOF
[Unit]
Description=Steamify CachyOS: boot into the desktop instead of gaming mode
Before=display-manager.service sddm.service plasmalogin.service

[Service]
Type=oneshot
ExecStart=/usr/lib/steamos/steam-set-session plasma.desktop
ExecStart=/bin/sh -c '[ -x $SESSION_SYNC ] && exec $SESSION_SYNC || true'

[Install]
WantedBy=graphical.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$BOOT_UNIT_NAME" || { err "Enabling $BOOT_UNIT_NAME failed."; return 1; }
    ok "Boots into the desktop from the next boot on (Return to Gaming Mode still works)."
}

boot_disable() {
    info "Setting the PC to boot into gaming mode again..."
    sudo systemctl disable "$BOOT_UNIT_NAME" 2>/dev/null
    sudo rm -f "$BOOT_UNIT"
    sudo systemctl daemon-reload
    # Next boot into gamescope, as the conversion sets it up.
    sudo /usr/lib/steamos/steam-set-session gamescope-session.desktop
    [[ -x "$SESSION_SYNC" ]] && sudo "$SESSION_SYNC"
    ok "Boots into gaming mode from the next boot on."
}

boot_choice() {
    # The menu row: the chosen option in brackets.
    if [[ "$1" == 1 ]]; then
        echo "Boot into:  gamescope  [desktop]"
    else
        echo "Boot into: [gamescope]  desktop"
    fi
}
