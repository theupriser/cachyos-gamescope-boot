#!/bin/bash
# SteamOS Vapor desktop theme, from CachyOS's cachyos-vapor package.
# Sourced by steamify.sh; not meant to be run on its own.

VAPOR_LOOKANDFEEL=com.valve.vapor.desktop
VAPOR_DEFAULTS=/usr/share/plasma/look-and-feel/$VAPOR_LOOKANDFEEL/contents/defaults
# Files the "Desktop and window layout" part replaces wholesale (panels,
# widgets, wallpaper); backed up as-is rather than journaled key by key.
THEME_LAYOUT_FILES=(plasma-org.kde.plasma.desktop-appletsrc plasmashellrc kdedefaults)

current_colorscheme() {
    # CachyOS ships its dark Breeze colors inline in kdeglobals without a
    # ColorScheme name, so fall back to the scheme matching ColorSchemeHash.
    local name hash f
    name="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)"
    if [[ -z "$name" ]]; then
        hash="$(kreadconfig6 --file kdeglobals --group General --key ColorSchemeHash)"
        for f in ~/.local/share/color-schemes/*.colors /usr/share/color-schemes/*.colors; do
            [[ -f "$f" && -n "$hash" ]] || continue
            [[ "$(sha1sum < "$f")" == "$hash "* ]] && { name="$(basename "$f" .colors)"; break; }
        done
    fi
    echo "${name:-BreezeLight}"
}

journal_vapor_defaults() {
    # Write every setting from Vapor's defaults file ("[file][group]" +
    # key=value) through the undo journal, so disable restores the user's
    # icons, cursor, splash, window decoration etc. The color scheme is
    # left to plasma-apply-colorscheme.
    local line file groups key rest
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\[([^]]+)\](.*)$ ]]; then
            file="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"; groups=""
            while [[ "$rest" =~ ^\[([^]]*)\](.*)$ ]]; do
                groups+="${groups:+|}${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
            done
        elif [[ "$line" == *=* && -n "$groups" ]]; then
            key="${line%%=*}"
            [[ "$key" == ColorScheme ]] && continue
            kset theme "$file" "$groups" "$key" "${line#*=}"
        fi
    done < "$VAPOR_DEFAULTS"
}

theme_status() {
    [[ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" == "$VAPOR_LOOKANDFEEL" ]]
}

theme_enable() {
    if ! pacman -Q cachyos-vapor >/dev/null 2>&1; then
        info "Installing cachyos-vapor..."
        sudo pacman -S --needed --noconfirm cachyos-vapor || { err "Installing cachyos-vapor failed."; return 1; }
        # Only remove it again on disable if we were the ones installing it.
        state_set theme installed_pkg 1
    fi
    if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
        err "Run this from the Plasma desktop: applying the Vapor layout needs a running Plasma session."
        return 1
    fi

    # Only the first time, so a re-apply doesn't overwrite the originals.
    local backup="$STATE_DIR/theme-layout" f
    if [[ ! -d "$backup" ]]; then
        mkdir -p "$backup"
        for f in "${THEME_LAYOUT_FILES[@]}"; do
            [[ -e ~/.config/"$f" ]] && cp -a ~/.config/"$f" "$backup/"
        done
    fi
    # Applying a color scheme or cursor rewrites more than the journal
    # covers (inline colors, GTK settings): remember what to re-apply.
    [[ -n "$(state_get theme colorscheme)" ]] || state_set theme colorscheme "$(current_colorscheme)"
    [[ -n "$(state_get theme cursor)" ]] ||
        state_set theme cursor "$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme --default breeze_cursors)"
    for f in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
        [[ -f "$f" ]] && kset theme "$f" Settings gtk-cursor-theme-name \
            "$(kreadconfig6 --file "$f" --group Settings --key gtk-cursor-theme-name)"
    done

    kset theme kdeglobals KDE LookAndFeelPackage "$VAPOR_LOOKANDFEEL"
    # Vapor is a dark theme: register it as the dark one, or Plasma's Dark
    # Mode toggle shows "off" and offers to switch to Breeze Dark.
    kset theme kdeglobals KDE DefaultDarkLookAndFeel "$VAPOR_LOOKANDFEEL"
    journal_vapor_defaults
    # Journal the key, then clear it: plasma-apply-colorscheme skips a
    # scheme that is already named in the config, without writing its colors.
    kset theme kdeglobals General ColorScheme --delete
    plasma-apply-colorscheme Vapor >/dev/null 2>&1 || true

    info "Applying the Vapor theme with its desktop and window layout..."
    # --resetLayout is "Desktop and window layout" in System Settings: the
    # SteamOS panel, launcher icon and wallpaper. It needs plasmashell up.
    lookandfeeltool -a "$VAPOR_LOOKANDFEEL" --resetLayout >/dev/null 2>&1 ||
        { err "lookandfeeltool failed."; return 1; }
    # The new layout has a new launcher, without single user's settings.
    if single_status; then
        sleep 3
        stop_plasmashell_for_edit
        single_launcher
        restart_plasmashell_if_stopped
    fi
    extras_enable || warn "SteamOS desktop extras not installed (see above); the theme itself is on."
    ok "Vapor theme active."
}

theme_disable() {
    extras_disable
    info "Restoring the previous desktop look and layout..."
    plasma-apply-colorscheme "$(state_get theme colorscheme BreezeLight)" >/dev/null 2>&1 || true
    plasma-apply-cursortheme "$(state_get theme cursor breeze_cursors)" >/dev/null 2>&1 || true

    local backup="$STATE_DIR/theme-layout" f
    stop_plasmashell_for_edit
    if [[ -d "$backup" ]]; then
        for f in "${THEME_LAYOUT_FILES[@]}"; do
            rm -rf ~/.config/"$f"
            [[ -e "$backup/$f" ]] && cp -a "$backup/$f" ~/.config/
        done
        rm -rf "$backup"
    fi
    # After the tools above, so keys that weren't set before are removed again.
    krevert theme
    single_status && single_launcher
    restart_plasmashell_if_stopped
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true

    if [[ -n "$(state_get theme installed_pkg)" ]]; then
        # Fails, and stays installed, when another package (e.g.
        # cachyos-handheld) depends on it.
        sudo pacman -R --noconfirm cachyos-vapor >/dev/null 2>&1 ||
            info "Keeping cachyos-vapor installed (another package needs it)."
    fi
    state_clear theme
    ok "Previous desktop look restored."
}
