#!/bin/bash
# Valve's SteamOS Vapor desktop theme and SteamOS desktop defaults.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

merge_kde_config() {
    # Merge a KDE-style ini file (e.g. one of Valve's /etc/xdg defaults) into
    # the user's own config with kwriteconfig6, so SteamOS defaults win over
    # the distro's without touching package-owned files in /etc/xdg.
    # Nested groups ("[A][B]") are supported; immutable "[$i]" groups and
    # comments are skipped.
    local src="$1" target="$2" line key value
    local -a groups=()
    local skip=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" == \[* ]]; then
            skip=0; groups=()
            [[ "$line" == *'[$'* ]] && { skip=1; continue; }
            local rest="$line"
            while [[ "$rest" =~ ^\[([^]]*)\](.*)$ ]]; do
                groups+=("--group" "${BASH_REMATCH[1]}")
                rest="${BASH_REMATCH[2]}"
            done
            continue
        fi
        (( skip )) && continue
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"; value="${line#*=}"
        kwriteconfig6 --file "$target" "${groups[@]}" --key "$key" "$value"
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
    # no screen locking, no welcome screen, light file indexing, GTK theme).
    # Left out on purpose: autostart entries (Steam is started by our user
    # unit), sddm/profile.d, and files hardcoding /home/deck or SteamOS tools.
    info "Applying SteamOS desktop defaults..."
    local f
    for f in kdeglobals kwinrc kwinrulesrc kscreenlockerrc kded5rc baloofilerc kcminputrc; do
        [[ -f "${tmp_dir}/etc/xdg/$f" ]] && merge_kde_config "${tmp_dir}/etc/xdg/$f" "$f"
    done
    [[ -f "${tmp_dir}/etc/xdg/kded5rc" ]] && merge_kde_config "${tmp_dir}/etc/xdg/kded5rc" kded6rc
    kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile Vapor.profile
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    kwriteconfig6 --file ~/.config/gtk-3.0/settings.ini --group Settings --key gtk-theme-name Vapor
    kwriteconfig6 --file ~/.config/gtk-4.0/settings.ini --group Settings --key gtk-theme-name Vapor
    # Vapor is a dark theme: tell GTK, libadwaita and portal-aware apps
    # (Firefox, Steam's web views, Flatpaks) to use their dark variants too.
    kwriteconfig6 --file ~/.config/gtk-3.0/settings.ini --group Settings --key gtk-application-prefer-dark-theme true
    kwriteconfig6 --file ~/.config/gtk-4.0/settings.ini --group Settings --key gtk-application-prefer-dark-theme true
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme Vapor 2>/dev/null || true
    fi
    [[ -f "${tmp_dir}/etc/xdg/gtk-2.0/gtkrc" ]] && cp "${tmp_dir}/etc/xdg/gtk-2.0/gtkrc" ~/.gtkrc-2.0

    info "Cleaning up temporary files..."
    rm -rf "$tmp_dir"

    # Launcher icon
    # Same launcher icon SteamOS sets (Vapor Deck plasmoid setup script).
    local icon_name="distributor-logo-steamdeck"
    local conf_file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    if ! find ~/.local/share/icons /usr/share/icons -iname "${icon_name}.*" 2>/dev/null | grep -q .; then
        warn "Could not find '${icon_name}' installed anywhere under ~/.local/share/icons or /usr/share/icons."
        warn "The launcher icon will be set anyway, but it may show as a broken icon until the file is installed."
    fi

    if [[ -f "$conf_file" ]]; then
        info "Looking for the Application Launcher applet (Kickoff/Kicker) to set the custom icon..."
        local matches=()
        local current_section=""
        local current_containment=""
        local current_applet=""

        while IFS= read -r line; do
            if [[ "$line" =~ ^\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]$ ]]; then
                current_containment="${BASH_REMATCH[1]}"
                current_applet="${BASH_REMATCH[2]}"
                current_section="applet_root"
                continue
            fi
            if [[ "$line" =~ ^\[ ]]; then
                current_section=""
                continue
            fi
            if [[ "$current_section" == "applet_root" && "$line" =~ ^plugin=(org\.kde\.plasma\.(kickoff|kicker|simplemenu|homerun|application-menu))$ ]]; then
                matches+=( "${current_containment}:${current_applet}:${BASH_REMATCH[1]}" )
                current_section=""
            fi
        done < "$conf_file"

        if [[ ${#matches[@]} -gt 0 ]]; then
            for m in "${matches[@]}"; do
                IFS=':' read -r containment applet plugin <<< "$m"
                info "Setting launcher icon on Containment $containment / Applet $applet ($plugin)..."
                kwriteconfig6 \
                    --file "$conf_file" \
                    --group Containments --group "$containment" \
                    --group Applets --group "$applet" \
                    --group Configuration --group General \
                    --key icon "$icon_name"
                ok "Icon set to '$icon_name'."
            done
        else
            warn "No compatible Application Launcher applet found in panel config. Skipping icon assignment."
        fi
    else
        warn "$conf_file not found. Skipping menu icon configuration."
    fi

    # SteamOS scales system tray icons to the panel height. Valve's setup
    # script targets Plasma 5's separate tray containment; in Plasma 6 the
    # setting lives on the systemtray applet itself.
    if [[ -f "$conf_file" ]]; then
        local tray
        for tray in $(awk '
            /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { split($0, p, /[][]+/); sect = p[3] ":" p[5] }
            /^\[/ && !/\]\[Applets\]\[[0-9]+\]$/ { sect = "" }
            /^plugin=org\.kde\.plasma\.systemtray$/ && sect != "" { print sect }
        ' "$conf_file"); do
            kwriteconfig6 --file "$conf_file" --group Containments --group "${tray%%:*}" \
                --group Applets --group "${tray#*:}" --group General \
                --key scaleIconsToFit true
        done
    fi

    # SteamOS shows the date below the time in the panel clock.
    if [[ -f "$conf_file" ]]; then
        local clock
        for clock in $(awk '
            /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { split($0, p, /[][]+/); sect = p[3] ":" p[5] }
            /^\[/ && !/\]\[Applets\]\[[0-9]+\]$/ { sect = "" }
            /^plugin=org\.kde\.plasma\.digitalclock$/ && sect != "" { print sect }
        ' "$conf_file"); do
            kwriteconfig6 --file "$conf_file" --group Containments --group "${clock%%:*}" \
                --group Applets --group "${clock#*:}" --group Configuration --group Appearance \
                --key dateDisplayFormat BelowTime
        done
    fi

    # Wallpaper
    # Valve ships the wallpapers as flat JPGs in usr/share/wallpapers.
    local wallpaper_path="$HOME/.local/share/wallpapers/Steam Deck Logo Default.jpg"

    if [[ -f "$wallpaper_path" ]]; then
        info "Applying official Steam Deck Vapor wallpaper via D-Bus script..."
        local dbus_cmd="
            var allDesktops = desktops();
            for (var i = 0; i < allDesktops.length; i++) {
                var d = allDesktops[i];
                d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
                d.writeConfig('Image', 'file://${wallpaper_path}');
            }
        "
        if ! pgrep -u "$USER" -x plasmashell >/dev/null; then
            :
        elif command -v qdbus6 >/dev/null 2>&1; then
            qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$dbus_cmd" >/dev/null 2>&1 || true
        else
            qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$dbus_cmd" >/dev/null 2>&1 || true
        fi

        if [[ -f "$conf_file" ]]; then
            local desktop_sections=$(grep -E '^\[Containments\]\[[0-9]+\]$' "$conf_file" || true)
            while read -r section; do
                if [[ -n "$section" ]]; then
                    local clean_sec=$(echo "$section" | tr -d '[]')
                    kwriteconfig6 --file "$conf_file" --group "$clean_sec" --group Wallpaper --group org.kde.image --group General --key Image "file://${wallpaper_path}"
                fi
            done <<< "$desktop_sections"
        fi
        ok "Wallpaper path pushed to session config."
    else
        warn "Could not find extracted Vapor wallpaper file. Skipping."
    fi

    # Activate the Vapor global theme and color scheme, then restart
    # plasmashell once so it picks everything up (restarting first races
    # with the settings being written). The theme's own defaults use
    # breeze-dark icons; there is no "Vapor" icon theme.
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "breeze-dark"
    kwriteconfig6 --file kdeglobals --group General --key ColorScheme "Vapor"
    kwriteconfig6 --file plasmarc --group Theme --key name "Vapor"

    # Same panel change for the next login, in case Plasma isn't running now.
    local panel
    for panel in $(grep -oP '^\[PlasmaViews\]\[Panel \K[0-9]+(?=\]$)' ~/.config/plasmashellrc 2>/dev/null); do
        kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $panel" --key floating 0
        kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $panel" --group Defaults --key thickness 44
    done

    gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true
    kbuildsycoca6 --noincremental 2>/dev/null || true

    # Live changes need a running Plasma session; otherwise they are picked
    # up from the config files above at the next Plasma login.
    if pgrep -u "$USER" -x plasmashell >/dev/null; then
        info "Applying the theme to the running Plasma session..."
        lookandfeeltool -a com.valve.vapor.desktop >/dev/null 2>&1 || true
        # lookandfeeltool leaves the distro's color scheme active; apply it explicitly.
        plasma-apply-colorscheme Vapor >/dev/null 2>&1 || true
        qdbus6 org.kde.kded6 /modules/gtkconfig org.kde.gtkconfig.setGtkTheme Vapor >/dev/null 2>&1 || true
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            'panels().forEach(function (p) {
                p.widgets("org.kde.plasma.systemtray").forEach(function (w) { w.currentConfigGroup = ["General"]; w.writeConfig("scaleIconsToFit", true); });
                p.widgets("org.kde.plasma.digitalclock").forEach(function (w) { w.currentConfigGroup = ["Appearance"]; w.writeConfig("dateDisplayFormat", "BelowTime"); });
            })' \
            >/dev/null 2>&1 || true
        # SteamOS uses a solid, full-width bottom panel at Plasma's stock
        # 44px height (CachyOS ships a floating 30px one).
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            'panels().forEach(function (p) { p.floating = false; p.lengthMode = "fill"; p.height = 44; })' \
            >/dev/null 2>&1 || true
        sleep 2  # let plasmashell flush the scripted changes before replacing it
        rm -rf ~/.cache/plasmashell* ~/.cache/org.kde.dirmodel-qml.kcache
        qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
        # Restart through systemd so plasmashell keeps the session's environment
        # (platform theme etc.); a plain --replace from this shell may not.
        if systemctl --user cat plasma-plasmashell.service >/dev/null 2>&1; then
            # Also takes over from a stray instance started by an earlier --replace.
            systemctl --user stop plasma-plasmashell.service
            pkill -u "$USER" -x plasmashell && sleep 2
            systemctl --user start plasma-plasmashell.service
        else
            setsid plasmashell --replace >/dev/null 2>&1 &
        fi
    else
        info "No running Plasma session; the theme applies at your next desktop login."
    fi

    ok "Vapor theme assets installed. Apply it under System Settings > Appearance"
    ok "> Global Theme > Vapor (Steam Deck), next time you're in a Plasma session."
}

setup_vapor_theme() {
    # Step 9 (optional): ask, make sure curl/zstd exist, then install.
    echo
    if ask_yn "Also install Valve's official Vapor (Steam Deck) KDE theme for your desktop session?" n; then
        if ! command -v curl >/dev/null 2>&1; then
            warn "curl not found, installing it first..."
            sudo pacman -S --needed --noconfirm curl
        fi
        if ! command -v unzstd >/dev/null 2>&1; then
            warn "zstd not found, installing it first..."
            sudo pacman -S --needed --noconfirm zstd
        fi
        install_vapor_theme || warn "Vapor theme install ran into a problem - see errors above. Your gamescope boot setup above is unaffected."
    fi
}
