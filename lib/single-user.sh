#!/bin/bash
# Single user, no password, like SteamOS: no lock screen, user switching or
# log out, since typing a password with a controller is miserable. Goes
# together with SDDM (see lib/login-manager.sh). All changes are journaled
# per user (lib/state.sh), so turning it off restores KDE's previous state.
# Sourced by steamify.sh; not meant to be run on its own.

single_status() {
    [[ "$(kreadconfig6 --file kdeglobals --group "KDE Action Restrictions" --key action/lock_screen)" == false ]]
}

WALLET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kwalletd"
# The user's own wallet while single user mode is on, and ours after.
WALLET_BACKUP=".bak-steamify"
WALLET_OURS=".steamify-single-user"

stop_kwallet() {
    # The wallet daemon keeps the file open and would write it back.
    local d
    for d in kwalletd6 ksecretd; do
        pkill -u "$USER" -x "$d" 2>/dev/null && sleep 1
    done
    return 0
}

single_wallet_enable() {
    # Like SteamOS: an empty, password-less wallet (Valve's own file), so
    # nothing asks for a wallet password (e.g. Brave at start): with
    # autologin nobody typed the login password that unlocks the usual one.
    # The user's wallet is moved aside and comes back when this is off. The
    # wallet from an earlier time in single user mode is reused, with
    # whatever was saved in it then.
    local tmp f
    if [[ -f "$WALLET_DIR/kdewallet.kwl$WALLET_OURS" ]]; then
        stop_kwallet
        for f in kdewallet.kwl kdewallet.salt; do
            [[ -f "$WALLET_DIR/$f" && ! -e "$WALLET_DIR/$f$WALLET_BACKUP" ]] &&
                mv "$WALLET_DIR/$f" "$WALLET_DIR/$f$WALLET_BACKUP"
            [[ -f "$WALLET_DIR/$f$WALLET_OURS" ]] && mv -f "$WALLET_DIR/$f$WALLET_OURS" "$WALLET_DIR/$f"
        done
        kset single kwalletrc Wallet "First Use" false
        ok "Single user mode's wallet (no password) is back; your own is kept as kdewallet.kwl$WALLET_BACKUP."
        return 0
    fi
    tmp="$(mktemp -d)"
    if ! fetch_valve_presets "$tmp"; then
        rm -rf "$tmp"
        warn "Couldn't get Valve's empty wallet; apps may still ask for the wallet password."
        return 0
    fi
    if [[ -f "$WALLET_DIR/kdewallet.kwl" ]] &&
        cmp -s "$WALLET_DIR/kdewallet.kwl" "$tmp/usr/share/kwalletd/kdewallet.kwl"; then
        rm -rf "$tmp"
        return 0
    fi
    stop_kwallet
    mkdir -p "$WALLET_DIR"
    for f in kdewallet.kwl kdewallet.salt; do
        # Never overwrite an earlier backup: that one is the user's.
        [[ -f "$WALLET_DIR/$f" && ! -e "$WALLET_DIR/$f$WALLET_BACKUP" ]] &&
            mv "$WALLET_DIR/$f" "$WALLET_DIR/$f$WALLET_BACKUP"
        install -m 600 "$tmp/usr/share/kwalletd/$f" "$WALLET_DIR/$f"
    done
    rm -rf "$tmp"
    kset single kwalletrc Wallet "First Use" false
    [[ -f "$WALLET_DIR/kdewallet.kwl$WALLET_BACKUP" ]] &&
        info "Your wallet is kept as $WALLET_DIR/kdewallet.kwl$WALLET_BACKUP and comes back when single user mode is off."
    ok "Empty wallet without a password: apps no longer ask for the wallet password."
}

single_wallet_disable() {
    # The user's wallet back; ours (maybe with passwords saved since) is
    # kept next to it.
    [[ -f "$WALLET_DIR/kdewallet.kwl$WALLET_BACKUP" ]] || return 0
    stop_kwallet
    local f
    for f in kdewallet.kwl kdewallet.salt; do
        [[ -f "$WALLET_DIR/$f" ]] && mv -f "$WALLET_DIR/$f" "$WALLET_DIR/$f$WALLET_OURS"
        [[ -f "$WALLET_DIR/$f$WALLET_BACKUP" ]] && mv "$WALLET_DIR/$f$WALLET_BACKUP" "$WALLET_DIR/$f"
    done
    ok "Your own wallet is back (the empty one is kept as kdewallet.kwl$WALLET_OURS)."
}

single_launcher() {
    # Launcher: only Sleep / Restart / Shut Down, no Session dropdown (where
    # Log Out lives). Restricting action/logout instead would also hide
    # Restart and Shut Down. Separate so the theme can re-apply it after
    # replacing the Plasma layout. Edit only while plasmashell is stopped.
    local applet grp
    for applet in $(plasma_applets org.kde.plasma.kickoff); do
        grp="Containments|${applet%%:*}|Applets|${applet#*:}|Configuration|General"
        kset single plasma-org.kde.plasma.desktop-appletsrc "$grp" primaryActions 3
        kset single plasma-org.kde.plasma.desktop-appletsrc "$grp" systemFavorites 'suspend,reboot,shutdown'
    done
}

single_enable() {
    info "Turning off the lock screen, user switching and logging out..."
    stop_plasmashell_for_edit

    # Hides Lock / Switch User in menus.
    local action
    for action in lock_screen switch_user start_new_session; do
        kset single kdeglobals "KDE Action Restrictions" "action/$action" false
    done
    # Never lock on idle or resume.
    kset single kscreenlockerrc Daemon Autolock false
    kset single kscreenlockerrc Daemon LockOnResume false
    kset single kscreenlockerrc Daemon Timeout 0
    # The restrictions don't cover the shortcuts: unbind Meta+L and the
    # Ctrl+Alt+Del logout screen (format: current,default,description).
    kset single kglobalshortcutsrc ksmserver "Lock Session" $'none,Screensaver\tMeta+L,Lock Session'
    kset single kglobalshortcutsrc ksmserver "Log Out" 'none,Ctrl+Alt+Del,Show Logout Screen'
    single_launcher

    restart_plasmashell_if_stopped
    single_wallet_enable
    ok "Single user: no lock screen, user switching or log out."
}

single_disable() {
    info "Restoring the lock screen, user switching and logging out..."
    stop_plasmashell_for_edit
    if has_journal single; then
        krevert single
    else
        # Set up by a version of this script without the undo journal:
        # fall back to KDE's defaults for everything it changes.
        local action applet key
        for action in lock_screen switch_user start_new_session; do
            kwriteconfig6 --file kdeglobals --group "KDE Action Restrictions" --key "action/$action" --delete
        done
        for key in Autolock LockOnResume Timeout; do
            kwriteconfig6 --file kscreenlockerrc --group Daemon --key "$key" --delete
        done
        kwriteconfig6 --file kglobalshortcutsrc --group ksmserver --key "Lock Session" $'Screensaver\tMeta+L,Screensaver\tMeta+L,Lock Session'
        kwriteconfig6 --file kglobalshortcutsrc --group ksmserver --key "Log Out" 'Ctrl+Alt+Del,Ctrl+Alt+Del,Show Logout Screen'
        for applet in $(plasma_applets org.kde.plasma.kickoff); do
            kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group "${applet%%:*}" \
                --group Applets --group "${applet#*:}" --group Configuration --group General --key primaryActions --delete
            kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group "${applet%%:*}" \
                --group Applets --group "${applet#*:}" --group Configuration --group General --key systemFavorites --delete
        done
    fi
    restart_plasmashell_if_stopped
    single_wallet_disable
    ok "KDE's normal lock screen and user switching are back."
}
