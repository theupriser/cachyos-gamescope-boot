#!/bin/bash
# Single user, no password, like SteamOS: no lock screen, user switching or
# log out, since typing a password with a controller is miserable. Goes
# together with SDDM (see lib/login-manager.sh). All changes are journaled
# per user (lib/state.sh), so turning it off restores KDE's previous state.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

single_status() {
    [[ "$(kreadconfig6 --file kdeglobals --group "KDE Action Restrictions" --key action/lock_screen)" == false ]]
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
    ok "KDE's normal lock screen and user switching are back."
}
