#!/bin/bash
# Valve's SteamOS Vapor desktop theme and SteamOS desktop defaults.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

merge_kde_config() {
    # Merge a KDE-style ini file (e.g. one of Valve's /etc/xdg defaults) into
    # the user's own config (journaled, see lib/state.sh), so SteamOS defaults win over
    # the distro's without touching package-owned files in /etc/xdg.
    # Nested groups ("[A][B]") are supported; immutable "[$i]" groups and
    # comments are skipped.
    local src="$1" target="$2" line key value
    local groups=""
    local skip=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" == \[* ]]; then
            skip=0; groups=""
            [[ "$line" == *'[$'* ]] && { skip=1; continue; }
            local rest="$line"
            while [[ "$rest" =~ ^\[([^]]*)\](.*)$ ]]; do
                groups+="${groups:+|}${BASH_REMATCH[1]}"
                rest="${BASH_REMATCH[2]}"
            done
            continue
        fi
        (( skip )) && continue
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"; value="${line#*=}"
        kset theme "$target" "$groups" "$key" "$value"
    done < "$src"
}

install_vapor_theme() {
    # Installs Valve's official SteamOS "Vapor" Plasma theme (color scheme,
    # Plasma look-and-feel package, wallpapers, icons) straight from Valve's
    # own SteamOS package mirror, into the current user's ~/.local/share.
    # This only touches the invoking user's home directory, never system
    # files, so it's independent from everything else this script does.
    local mirror="https://steamdeck-packages.steamos.cloud/archlinux-mirror"
    local repo file_name sha256 tmp_dir
    tmp_dir="$(mktemp -d)"

    # Take the package from the newest SteamOS release repo (jupiter-3.9,
    # jupiter-3.10, ...), read from its pacman database: that gives the
    # exact file name and checksum. Fall back to a known-good version.
    info "Looking up the current SteamOS Vapor presets..."
    repo="$(curl -fsL "$mirror/" | grep -oE 'jupiter-[0-9]+\.[0-9]+/' | tr -d / | sort -V | tail -n 1)"
    if [[ -n "$repo" ]] && curl -fsL "$mirror/$repo/os/x86_64/$repo.db" -o "$tmp_dir/repo.db"; then
        local desc
        desc="$(tar -tf "$tmp_dir/repo.db" 2>/dev/null | grep -E '^steamdeck-kde-presets-[0-9][^/]*/desc$' | head -n 1)"
        if [[ -n "$desc" ]]; then
            file_name="$(tar -xOf "$tmp_dir/repo.db" "$desc" | awk '/^%FILENAME%$/ { getline; print }')"
            sha256="$(tar -xOf "$tmp_dir/repo.db" "$desc" | awk '/^%SHA256SUM%$/ { getline; print }')"
        fi
    fi
    if [[ -z "${file_name:-}" ]]; then
        warn "Couldn't read Valve's package index; using the known-good version."
        repo="jupiter-3.9"
        file_name="steamdeck-kde-presets-3.9.4-2-any.pkg.tar.zst"
        sha256=""
    fi

    info "Downloading $file_name ($repo)..."
    if ! curl -fL "$mirror/$repo/os/x86_64/$file_name" -o "${tmp_dir}/presets.tar.zst"; then
        err "Download failed. Valve may have moved/renamed this package;"
        err "check $mirror for the current version."
        rm -rf "$tmp_dir"
        return 1
    fi
    if [[ -n "$sha256" ]] && ! echo "$sha256  ${tmp_dir}/presets.tar.zst" | sha256sum -c --quiet -; then
        err "Checksum mismatch for $file_name; not installing it."
        rm -rf "$tmp_dir"
        return 1
    fi

    info "Extracting package contents..."
    if ! tar -I unzstd -xf "${tmp_dir}/presets.tar.zst" -C "$tmp_dir"; then
        err "Extraction failed (is 'zstd' installed? try: sudo pacman -S --needed zstd)"
        rm -rf "$tmp_dir"
        return 1
    fi

    info "Creating local configuration directories..."
    mkdir -p ~/.local/share/color-schemes \
             ~/.local/share/plasma/desktoptheme \
             ~/.local/share/plasma/look-and-feel \
             ~/.local/share/wallpapers \
             ~/.local/share/icons/hicolor

    info "Installing Steam Deck theme assets..."
    [[ -d "${tmp_dir}/usr/share/color-schemes" ]] && cp -r "${tmp_dir}/usr/share/color-schemes/"* ~/.local/share/color-schemes/
    [[ -d "${tmp_dir}/usr/share/plasma/desktoptheme/Vapor" ]] && cp -r "${tmp_dir}/usr/share/plasma/desktoptheme/Vapor" ~/.local/share/plasma/desktoptheme/
    [[ -d "${tmp_dir}/usr/share/plasma/look-and-feel/com.valve.vapor.desktop" ]] && cp -r "${tmp_dir}/usr/share/plasma/look-and-feel/com.valve.vapor.desktop" ~/.local/share/plasma/look-and-feel/
    [[ -d "${tmp_dir}/usr/share/wallpapers" ]] && cp -r "${tmp_dir}/usr/share/wallpapers/"* ~/.local/share/wallpapers/
    [[ -d "${tmp_dir}/usr/share/icons/hicolor" ]] && cp -r "${tmp_dir}/usr/share/icons/hicolor/"* ~/.local/share/icons/hicolor/

    # The rest of what SteamOS ships: GTK theme (Steam, Firefox, ...), Konsole
    # profile and user avatars -- the same files the AUR package installs.
    mkdir -p ~/.local/share/themes ~/.local/share/konsole ~/.local/share/plasma/avatars
    [[ -d "${tmp_dir}/usr/share/themes/Vapor" ]] && cp -r "${tmp_dir}/usr/share/themes/Vapor" ~/.local/share/themes/
    [[ -d "${tmp_dir}/usr/share/konsole" ]] && cp -r "${tmp_dir}/usr/share/konsole/"* ~/.local/share/konsole/
    [[ -d "${tmp_dir}/usr/share/plasma/avatars" ]] && cp -r "${tmp_dir}/usr/share/plasma/avatars/"* ~/.local/share/plasma/avatars/

    # Valve's SteamOS desktop defaults (fonts, Steam keyboard window rule,
    # no welcome screen, light file indexing, GTK theme).
    # Left out on purpose: autostart entries (Steam is started by our user
    # unit), sddm/profile.d, and files hardcoding /home/deck or SteamOS tools.
    info "Applying SteamOS desktop defaults..."
    local f
    # kscreenlockerrc is left to the single-user question.
    for f in kdeglobals kwinrc kwinrulesrc kded5rc baloofilerc kcminputrc; do
        [[ -f "${tmp_dir}/etc/xdg/$f" ]] && merge_kde_config "${tmp_dir}/etc/xdg/$f" "$f"
    done
    [[ -f "${tmp_dir}/etc/xdg/kded5rc" ]] && merge_kde_config "${tmp_dir}/etc/xdg/kded5rc" kded6rc
    kset theme konsolerc "Desktop Entry" DefaultProfile Vapor.profile
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    kset theme ~/.config/gtk-3.0/settings.ini Settings gtk-theme-name Vapor
    kset theme ~/.config/gtk-4.0/settings.ini Settings gtk-theme-name Vapor
    # Vapor is a dark theme: tell GTK, libadwaita and portal-aware apps
    # (Firefox, Steam's web views, Flatpaks) to use their dark variants too.
    kset theme ~/.config/gtk-3.0/settings.ini Settings gtk-application-prefer-dark-theme true
    kset theme ~/.config/gtk-4.0/settings.ini Settings gtk-application-prefer-dark-theme true
    if command -v gsettings >/dev/null 2>&1; then
        [[ -n "$(state_get theme gsettings_scheme)" ]] ||
            state_set theme gsettings_scheme "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
        [[ -n "$(state_get theme gsettings_gtk)" ]] ||
            state_set theme gsettings_gtk "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)"
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme Vapor 2>/dev/null || true
    fi
    [[ -f "${tmp_dir}/etc/xdg/gtk-2.0/gtkrc" ]] && cp "${tmp_dir}/etc/xdg/gtk-2.0/gtkrc" ~/.gtkrc-2.0

    info "Cleaning up temporary files..."
    rm -rf "$tmp_dir"

    # Remember what to go back to when the theme is turned off again.
    [[ -n "$(state_get theme lookandfeel)" ]] ||
        state_set theme lookandfeel "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage \
            --default "$(kreadconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage --default org.kde.breeze.desktop)")"
    [[ -n "$(state_get theme colorscheme)" ]] ||
        state_set theme colorscheme "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme --default BreezeLight)"

    local appletsrc="plasma-org.kde.plasma.desktop-appletsrc" applet

    # Same launcher icon SteamOS sets (Vapor Deck plasmoid setup script).
    for applet in $(plasma_applets org.kde.plasma.kickoff); do
        kset theme "$appletsrc" "Containments|${applet%%:*}|Applets|${applet#*:}|Configuration|General" icon distributor-logo-steamdeck
    done
    # SteamOS scales tray icons to the panel height. Valve's setup script
    # targets Plasma 5's separate tray containment; in Plasma 6 the setting
    # lives on the systemtray applet itself.
    for applet in $(plasma_applets org.kde.plasma.systemtray); do
        kset theme "$appletsrc" "Containments|${applet%%:*}|Applets|${applet#*:}|General" scaleIconsToFit true
    done
    # SteamOS shows the date below the time.
    for applet in $(plasma_applets org.kde.plasma.digitalclock); do
        kset theme "$appletsrc" "Containments|${applet%%:*}|Applets|${applet#*:}|Configuration|Appearance" dateDisplayFormat BelowTime
    done

    # Wallpaper: Valve ships them as flat JPGs in usr/share/wallpapers.
    local wallpaper="$HOME/.local/share/wallpapers/Steam Deck Logo Default.jpg" containment
    if [[ -f "$wallpaper" ]]; then
        for containment in $(grep -oP '^\[Containments\]\[\K[0-9]+(?=\]$)' ~/.config/"$appletsrc" 2>/dev/null); do
            grep -q "^\[Containments\]\[$containment\]\[Wallpaper\]" ~/.config/"$appletsrc" || continue
            kset theme "$appletsrc" "Containments|$containment|Wallpaper|org.kde.image|General" Image "file://$wallpaper"
        done
    fi

    # Vapor color scheme and Plasma style; the theme's own defaults use
    # breeze-dark icons (there is no "Vapor" icon theme).
    kset theme kdeglobals KDE LookAndFeelPackage com.valve.vapor.desktop
    kset theme kdeglobals Icons Theme breeze-dark
    kset theme kdeglobals General ColorScheme Vapor
    kset theme plasmarc Theme name Vapor

    # SteamOS uses a solid, full-width bottom panel at Plasma's stock 44px
    # height (CachyOS ships a floating 30px one).
    local panel
    for panel in $(grep -oP '^\[PlasmaViews\]\[Panel \K[0-9]+(?=\]$)' ~/.config/plasmashellrc 2>/dev/null); do
        kset theme plasmashellrc "PlasmaViews|Panel $panel" floating 0
        kset theme plasmashellrc "PlasmaViews|Panel $panel|Defaults" thickness 44
    done

    gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true
    kbuildsycoca6 --noincremental 2>/dev/null || true

    # Live changes need a running Plasma session; otherwise they are picked
    # up from the config files above at the next Plasma login.
    if [[ "${PLASMASHELL_WAS_RUNNING:-false}" == true ]]; then
        info "Applying the theme to the running Plasma session..."
        lookandfeeltool -a com.valve.vapor.desktop >/dev/null 2>&1 || true
        # lookandfeeltool leaves the distro's color scheme active; apply it explicitly.
        plasma-apply-colorscheme Vapor >/dev/null 2>&1 || true
        qdbus6 org.kde.kded6 /modules/gtkconfig org.kde.gtkconfig.setGtkTheme Vapor >/dev/null 2>&1 || true
        qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
    else
        info "No running Plasma session; the theme applies at your next desktop login."
    fi
    ok "SteamOS desktop look installed."
}

theme_status() {
    [[ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" == com.valve.vapor.desktop ]]
}

theme_enable() {
    command -v curl >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm curl
    command -v unzstd >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm zstd
    # Stop plasmashell first: the panel and wallpaper edits go to files it
    # would otherwise overwrite with its in-memory config on exit.
    stop_plasmashell_for_edit
    install_vapor_theme
    local rc=$?
    restart_plasmashell_if_stopped
    (( rc == 0 )) || warn "Vapor theme install ran into a problem - see errors above."
    return $rc
}

theme_disable() {
    info "Restoring the previous desktop look..."
    local lookandfeel colorscheme
    lookandfeel="$(state_get theme lookandfeel org.kde.breeze.desktop)"
    colorscheme="$(state_get theme colorscheme BreezeLight)"

    stop_plasmashell_for_edit
    if has_journal theme; then
        krevert theme
    else
        # Installed by a version of this script without the undo journal:
        # undo the main settings it made.
        kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage --delete
        kwriteconfig6 --file kdeglobals --group General --key ColorScheme --delete
        kwriteconfig6 --file kdeglobals --group Icons --key Theme --delete
        kwriteconfig6 --file plasmarc --group Theme --key name --delete
        local f
        for f in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
            [[ -f "$f" ]] || continue
            kwriteconfig6 --file "$f" --group Settings --key gtk-theme-name --delete
            kwriteconfig6 --file "$f" --group Settings --key gtk-application-prefer-dark-theme --delete
        done
        kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile --delete
    fi
    if command -v gsettings >/dev/null 2>&1; then
        local v
        v="$(state_get theme gsettings_scheme)"
        if [[ -n "$v" ]]; then gsettings set org.gnome.desktop.interface color-scheme "$v" 2>/dev/null
        else gsettings reset org.gnome.desktop.interface color-scheme 2>/dev/null; fi
        v="$(state_get theme gsettings_gtk)"
        if [[ -n "$v" ]]; then gsettings set org.gnome.desktop.interface gtk-theme "$v" 2>/dev/null
        else gsettings reset org.gnome.desktop.interface gtk-theme 2>/dev/null; fi
    fi
    rm -rf ~/.local/share/plasma/look-and-feel/com.valve.vapor.desktop \
        ~/.local/share/plasma/desktoptheme/Vapor \
        ~/.local/share/themes/Vapor \
        ~/.local/share/color-schemes/Vapor.colors ~/.local/share/color-schemes/VGUI.colors \
        ~/.local/share/konsole/Vapor.profile ~/.local/share/konsole/Vapor.colorscheme \
        ~/.local/share/wallpapers/Steam\ Deck\ Logo*.jpg ~/.local/share/wallpapers/Troll.jpg
    rm -f ~/.gtkrc-2.0
    kbuildsycoca6 --noincremental 2>/dev/null || true

    if [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
        lookandfeeltool -a "$lookandfeel" >/dev/null 2>&1 || true
        plasma-apply-colorscheme "$colorscheme" >/dev/null 2>&1 || true
    fi
    restart_plasmashell_if_stopped
    state_clear theme
    ok "Previous desktop look restored."
}
