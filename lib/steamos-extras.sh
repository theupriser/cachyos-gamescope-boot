#!/bin/bash
# SteamOS desktop extras that cachyos-vapor doesn't ship, taken from the
# newest Valve steamdeck-kde-presets package: "Add to Steam" (file
# right-click menu and launcher), Nested Desktop (Plasma as a game inside
# gaming mode), the "Return to Gaming Mode" icon, the Steam Keyboard window
# rule and an empty KWallet. Part of the SteamOS theme component
# (lib/vapor-theme.sh). System files go to /usr/local (nothing
# package-owned); per-user settings go through the undo journal.
# Sourced by steamify.sh; not meant to be run on its own.

VALVE_MIRROR="https://steamdeck-packages.steamos.cloud/archlinux-mirror"
NESTED_DIR=/usr/local/share/applications/steam/holo-nested-desktop
EXTRAS_FILES=(
    /usr/local/bin/holo-add-to-steam
    /usr/local/bin/holo-nested-desktop
    /usr/local/share/kio/servicemenus/steam.desktop
    /usr/local/share/plasma/kickeractions/steam.desktop
    /usr/local/share/icons/hicolor/scalable/actions/gaming-return.svg
    "$NESTED_DIR"
)
# Group name for our rule in kwinrulesrc; KWin accepts any unique id.
STEAM_KEYBOARD_RULE=cachyos-gamescope-boot-steam-keyboard

fetch_valve_presets() {
    # fetch_valve_presets <dir>: download and extract the newest
    # steamdeck-kde-presets into <dir>. The newest SteamOS release repo
    # (jupiter-3.9, jupiter-3.10, ...) is found on the mirror; its pacman
    # database gives the exact file name and SHA-256, which is verified.
    local dir="$1" repo desc file_name sha256
    repo="$(curl -fsL "$VALVE_MIRROR/" | grep -oE 'jupiter-[0-9]+\.[0-9]+/' | tr -d / | sort -V | tail -n 1)"
    [[ -n "$repo" ]] && curl -fsL "$VALVE_MIRROR/$repo/os/x86_64/$repo.db" -o "$dir/repo.db" ||
        { err "Couldn't read Valve's SteamOS package index ($VALVE_MIRROR)."; return 1; }
    desc="$(tar -tf "$dir/repo.db" 2>/dev/null | grep -E '^steamdeck-kde-presets-[0-9][^/]*/desc$' | head -n 1)"
    [[ -n "$desc" ]] || { err "No steamdeck-kde-presets in Valve's $repo repository."; return 1; }
    file_name="$(tar -xOf "$dir/repo.db" "$desc" | awk '/^%FILENAME%$/ { getline; print }')"
    sha256="$(tar -xOf "$dir/repo.db" "$desc" | awk '/^%SHA256SUM%$/ { getline; print }')"

    info "Downloading $file_name ($repo)..."
    curl -fsL "$VALVE_MIRROR/$repo/os/x86_64/$file_name" -o "$dir/presets.pkg.tar.zst" ||
        { err "Downloading $file_name failed."; return 1; }
    echo "$sha256  $dir/presets.pkg.tar.zst" | sha256sum -c --quiet - ||
        { err "Checksum mismatch for $file_name; not using it."; return 1; }
    tar -I unzstd -xf "$dir/presets.pkg.tar.zst" -C "$dir" usr/bin usr/share ||
        { err "Extracting $file_name failed."; return 1; }
}

extras_enable() {
    info "Installing SteamOS desktop extras (Add to Steam, Nested Desktop, icons)..."
    local pkg
    for pkg in curl zstd kdialog; do
        # holo-add-to-steam and holo-nested-desktop show errors with kdialog.
        pacman -Q "$pkg" >/dev/null 2>&1 && continue
        sudo pacman -S --needed --noconfirm "$pkg" && state_set theme "installed_$pkg" 1
    done

    local tmp_dir src
    tmp_dir="$(mktemp -d)"
    if ! fetch_valve_presets "$tmp_dir"; then
        rm -rf "$tmp_dir"
        return 1
    fi
    src="$tmp_dir/usr"
    sudo install -D -m 755 "$src/bin/holo-add-to-steam" /usr/local/bin/holo-add-to-steam
    sudo install -D -m 755 "$src/bin/holo-nested-desktop" /usr/local/bin/holo-nested-desktop
    sudo install -D -m 644 "$src/share/kio/servicemenus/steam.desktop" /usr/local/share/kio/servicemenus/steam.desktop
    sudo install -D -m 644 "$src/share/plasma/kickeractions/steam.desktop" /usr/local/share/plasma/kickeractions/steam.desktop
    # gaming-return.svg is a symlink in the package; SteamOS uses it for the
    # Return to Gaming Mode shortcut on non-Deck hardware.
    sudo install -D -m 644 "$src/share/icons/hicolor/scalable/actions/steam-gaming-return.svg" \
        /usr/local/share/icons/hicolor/scalable/actions/gaming-return.svg
    # Nested Desktop with its Steam library art; the entry points at the
    # art under /usr/share, which is where Valve puts it.
    sudo rm -rf "$NESTED_DIR"
    sudo mkdir -p "$(dirname "$NESTED_DIR")"
    sudo cp -r "$src/share/applications/steam/holo-nested-desktop" "$NESTED_DIR"
    sudo sed -i "s|/usr/share/applications/steam/holo-nested-desktop|$NESTED_DIR|" "$NESTED_DIR/holo-nested-desktop.desktop"

    # An empty, password-less wallet (Valve's), so nothing asks for a wallet
    # password: with autologin nobody typed one to unlock it. Only when the
    # user has no wallet yet; an existing one is never touched.
    local wallet="${XDG_DATA_HOME:-$HOME/.local/share}/kwalletd"
    if [[ ! -f "$wallet/kdewallet.kwl" ]]; then
        mkdir -p "$wallet"
        install -m 600 "$src/share/kwalletd/kdewallet.kwl" "$src/share/kwalletd/kdewallet.salt" "$wallet/"
        kset theme kwalletrc Wallet "First Use" false
    fi
    rm -rf "$tmp_dir"

    sudo gtk-update-icon-cache -q -f -t /usr/local/share/icons/hicolor 2>/dev/null || true
    kbuildsycoca6 >/dev/null 2>&1 || true
    set_shortcut_icon gaming-return

    # Keep Steam's on-screen keyboard (Steam + X) above other windows and out
    # of the taskbar, like SteamOS's kwinrulesrc.
    local rules rule="$STEAM_KEYBOARD_RULE"
    rules="$(kreadconfig6 --file kwinrulesrc --group General --key rules)"
    if [[ ",$rules," != *",$rule,"* ]]; then
        kset theme kwinrulesrc "$rule" Description "Window settings for Steam Keyboard"
        kset theme kwinrulesrc "$rule" above true
        kset theme kwinrulesrc "$rule" aboverule 2
        kset theme kwinrulesrc "$rule" skiptaskbar true
        kset theme kwinrulesrc "$rule" skiptaskbarrule 2
        kset theme kwinrulesrc "$rule" title "Steam Keyboard"
        kset theme kwinrulesrc "$rule" titlematch 2
        kset theme kwinrulesrc "$rule" type 16
        kset theme kwinrulesrc "$rule" typerule 2
        kset theme kwinrulesrc "$rule" wmclass steam
        kset theme kwinrulesrc "$rule" wmclasscomplete true
        kset theme kwinrulesrc "$rule" wmclassmatch 2
        kset theme kwinrulesrc General rules "${rules:+$rules,}$rule"
        kset theme kwinrulesrc General count "$(( $(kreadconfig6 --file kwinrulesrc --group General --key count --default 0) + 1 ))"
        qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
    fi
}

extras_disable() {
    sudo rm -rf "${EXTRAS_FILES[@]}"
    sudo gtk-update-icon-cache -q -f -t /usr/local/share/icons/hicolor 2>/dev/null || true
    kbuildsycoca6 >/dev/null 2>&1 || true
    set_shortcut_icon steam
    local pkg
    for pkg in kdialog zstd curl; do
        [[ -n "$(state_get theme "installed_$pkg")" ]] && sudo pacman -R --noconfirm "$pkg" >/dev/null 2>&1
    done
    # The keyboard rule and kwalletrc are reverted by the theme's journal.
    # The wallet itself stays: secrets may have been saved in it since.
    return 0
}
