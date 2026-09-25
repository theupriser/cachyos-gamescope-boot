#!/bin/bash
# "HDMI-CEC" menu item, on any PC: Valve's CEC daemon (cecd), TV/receiver
# volume control (cec-audio-control) and the units that attach USB CEC
# adapters (Pulse-Eight, RainShadow) with inputattach. They're only in
# Valve's SteamOS (holo) repository, not in CachyOS or the AUR. Works with
# any /dev/cec*: a GPU with CEC (e.g. the Steam Machine) or a USB adapter.
# On a Steam Machine, steamos-manager configures cecd from Steam's settings.
# Sourced by steamify.sh; not meant to be run on its own.

CEC_PKGS=(cecd cec-audio-control inputattach-cec-units)

cec_status() { pacman -Q "${CEC_PKGS[@]}" >/dev/null 2>&1; }

fetch_holo_pkg() {
    # fetch_holo_pkg <dir> <package>: download the newest <package> from
    # Valve's newest holo repository into <dir> and print its path. The
    # SHA-256 comes from Valve's package index and is verified.
    local dir="$1" name="$2" repo desc file_name sha256
    repo="$(curl -fsL "$VALVE_MIRROR/" | grep -oE 'holo-[0-9]+\.[0-9]+/' | tr -d / | sort -V | tail -n 1)"
    if [[ ! -f "$dir/holo.db" ]]; then
        [[ -n "$repo" ]] && curl -fsL "$VALVE_MIRROR/$repo/os/x86_64/$repo.db" -o "$dir/holo.db" ||
            { err "Couldn't read Valve's SteamOS package index ($VALVE_MIRROR)."; return 1; }
    fi
    desc="$(tar -tf "$dir/holo.db" 2>/dev/null | grep -E "^$name-[0-9][^/]*/desc$" | head -n 1)"
    [[ -n "$desc" ]] || { err "No $name in Valve's $repo repository."; return 1; }
    file_name="$(tar -xOf "$dir/holo.db" "$desc" | awk '/^%FILENAME%$/ { getline; print }')"
    sha256="$(tar -xOf "$dir/holo.db" "$desc" | awk '/^%SHA256SUM%$/ { getline; print }')"
    info "Downloading $file_name ($repo)..." >&2
    curl -fsL "$VALVE_MIRROR/$repo/os/x86_64/$file_name" -o "$dir/$file_name" ||
        { err "Downloading $file_name failed."; return 1; }
    echo "$sha256  $dir/$file_name" | sha256sum -c --quiet - >&2 ||
        { err "Checksum mismatch for $file_name; not using it."; return 1; }
    echo "$dir/$file_name"
}

cec_enable() {
    local tmp p f files=()
    # inputattach, needed by inputattach-cec-units.
    if ! pacman -Q linuxconsole >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm linuxconsole || { err "Installing linuxconsole failed."; return 1; }
        state_set cec installed_linuxconsole 1
    fi
    tmp="$(mktemp -d)"
    for p in "${CEC_PKGS[@]}"; do
        f="$(fetch_holo_pkg "$tmp" "$p")" || { rm -rf "$tmp"; return 1; }
        files+=("$f")
    done
    info "Installing Valve's CEC daemon..."
    if ! sudo pacman -U --needed --noconfirm "${files[@]}"; then
        rm -rf "$tmp"
        err "Installing ${CEC_PKGS[*]} failed."
        return 1
    fi
    rm -rf "$tmp"
    # Its udev rule gives the user /dev/cec*; cecd starts with the graphical
    # session, after steamos-manager wrote its config from Steam's settings.
    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=cec --action=add
    systemctl --user daemon-reload
    systemctl --user enable steamos-manager-configure-cecd.service 2>/dev/null
    if compgen -G "/dev/cec*" >/dev/null; then
        systemctl --user restart cecd.service 2>/dev/null
        ok "HDMI-CEC on ($(cd /dev && echo cec*)). Turn on CEC on your TV too (e.g. Sony: BRAVIA Sync, Samsung: Anynet+, LG: SimpLink)."
    else
        warn "No CEC device (/dev/cec*) found: your GPU may not support CEC. A USB CEC adapter"
        warn "(e.g. Pulse-Eight) works too. Check again after a restart with: ls /dev/cec*"
    fi
}

cec_disable() {
    info "Removing HDMI-CEC..."
    systemctl --user disable --now cecd.service cec-audio-control.socket cec-audio-control.service 2>/dev/null
    systemctl --user disable steamos-manager-configure-cecd.service 2>/dev/null
    sudo pacman -Rns --noconfirm "${CEC_PKGS[@]}" 2>/dev/null
    if [[ -n "$(state_get cec installed_linuxconsole)" ]]; then
        sudo pacman -Rns --noconfirm linuxconsole 2>/dev/null
        state_clear cec
    fi
    sudo udevadm control --reload
    ok "HDMI-CEC removed."
}

cec_overview() {
    # For the menu's kernel overview.
    local dev="none"
    compgen -G "/dev/cec*" >/dev/null && dev="$(cd /dev && echo cec*)"
    echo "CEC devices: $dev  cecd: $(systemctl --user is-active cecd 2>/dev/null)"
}
