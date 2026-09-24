#!/bin/bash
# "Update BIOS" menu item, only on a Steam Machine and always opt-in: flashes
# the newest Steam Machine BIOS from Valve's fremont-hw-support package with
# fwupd. It's an action, not an on/off component: never preselected, never
# re-applied, and there is nothing to turn off afterwards.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

BIOS_REPO_PREFIX=holo

bios_available() { detect_valve_fremont; }

bios_status() { return 1; }

bios_disable() { return 0; }

bios_current() {
    cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unknown
}

bios_lookup_newest() {
    # Sets BIOS_REPO, BIOS_PKG, BIOS_SHA256 and BIOS_NEWEST (e.g. F7F0108)
    # from the newest holo-X.Y repository on Valve's mirror: its .files
    # database names the firmware file, its .db gives the package checksum.
    # Only once per run, and with short timeouts so an offline machine
    # doesn't hold up the menu.
    [[ -n "${BIOS_LOOKED_UP:-}" ]] && return 0
    BIOS_LOOKED_UP=1; BIOS_NEWEST=""
    local tmp desc
    BIOS_REPO="$(curl -fsL --max-time 10 "$VALVE_MIRROR/" | grep -oE "$BIOS_REPO_PREFIX-[0-9]+\.[0-9]+/" | tr -d / | sort -uV | tail -n 1)"
    [[ -n "$BIOS_REPO" ]] || return 1
    tmp="$(mktemp -d)"
    if curl -fsL --max-time 30 "$VALVE_MIRROR/$BIOS_REPO/os/x86_64/$BIOS_REPO.files" -o "$tmp/files" &&
        curl -fsL --max-time 30 "$VALVE_MIRROR/$BIOS_REPO/os/x86_64/$BIOS_REPO.db" -o "$tmp/db"; then
        desc="$(tar -tf "$tmp/files" 2>/dev/null | grep -E '^fremont-hw-support-[0-9][^/]*/files$' | head -n 1)"
        [[ -n "$desc" ]] && BIOS_CAB="$(tar -xOf "$tmp/files" "$desc" | grep -E '^usr/share/fwupd/.*\.cab$' | head -n 1)"
        desc="${desc%/files}/desc"
        BIOS_PKG="$(tar -xOf "$tmp/db" "$desc" 2>/dev/null | awk '/^%FILENAME%$/ { getline; print }')"
        BIOS_SHA256="$(tar -xOf "$tmp/db" "$desc" 2>/dev/null | awk '/^%SHA256SUM%$/ { getline; print }')"
        [[ -n "${BIOS_CAB:-}" && -n "$BIOS_PKG" && -n "$BIOS_SHA256" ]] && BIOS_NEWEST="$(basename "$BIOS_CAB" .cab)"
    fi
    rm -rf "$tmp"
    [[ -n "$BIOS_NEWEST" ]]
}

bios_label() {
    # Menu label with the current and the newest version.
    local newest="newest unknown (offline?)"
    bios_lookup_newest && newest="newest $BIOS_NEWEST"
    [[ "$BIOS_NEWEST" == "$(bios_current)" ]] && newest="up to date"
    echo "Update BIOS (at your own risk): now $(bios_current), $newest"
}

bios_disclaimer() {
    local r="$c_red$c_bold" n="$c_reset"
    echo
    echo -e "${r}  ###################################################################${n}"
    echo -e "${r}  ##                                                               ##${n}"
    echo -e "${r}  ##    WARNING: BIOS UPDATE - ENTIRELY AT YOUR OWN RISK           ##${n}"
    echo -e "${r}  ##                                                               ##${n}"
    echo -e "${r}  ###################################################################${n}"
    echo -e "${r}  ##${n}  $1"
    echo -e "${r}  ##${n}"
    echo -e "${r}  ##${n}  - A failed or interrupted BIOS update can leave the machine"
    echo -e "${r}  ##${n}    unable to start (bricked). This wizard, CachyOS and Valve"
    echo -e "${r}  ##${n}    take no responsibility for that."
    echo -e "${r}  ##${n}  - ${c_bold}NEVER turn off the power, unplug the machine or press the${n}"
    echo -e "${r}  ##${n}    ${c_bold}power button while the update runs${n}, including during the"
    echo -e "${r}  ##${n}    restart(s) afterwards, when the firmware is actually written."
    echo -e "${r}  ##${n}  - The screen can stay black for several minutes. Wait."
    echo -e "${r}  ##${n}  - Use this only on a Valve Steam Machine, on mains power, and"
    echo -e "${r}  ##${n}    close all other programs first."
    echo -e "${r}  ###################################################################${n}"
    echo
}

bios_enable() {
    if ! bios_lookup_newest; then
        err "Couldn't find the newest Steam Machine BIOS on Valve's mirror ($VALVE_MIRROR)."
        return 1
    fi
    local current
    current="$(bios_current)"
    if [[ "$current" == "$BIOS_NEWEST" ]]; then
        ok "The BIOS is already the newest version ($current); nothing to do."
        return 0
    fi

    bios_disclaimer "Current BIOS: ${c_bold}$current${c_reset}   ->   new BIOS: ${c_bold}$BIOS_NEWEST${c_reset} ($BIOS_PKG)"
    ask_yn "Do you understand the risks and want to continue?" n ||
        { info "BIOS update cancelled; nothing was changed."; return 0; }
    bios_disclaimer "LAST CHANCE: this flashes BIOS $BIOS_NEWEST onto this machine."
    local reply
    read -rp "$(echo -e "${c_red}${c_bold}Type UPDATE (in capitals) to flash the BIOS, anything else cancels:${c_reset} ")" reply
    [[ "$reply" == UPDATE ]] || { info "BIOS update cancelled; nothing was changed."; return 0; }

    pacman -Q fwupd >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm fwupd ||
        { err "Installing fwupd failed."; return 1; }
    local tmp
    tmp="$(mktemp -d)"
    info "Downloading $BIOS_PKG ($BIOS_REPO)..."
    if ! curl -fL "$VALVE_MIRROR/$BIOS_REPO/os/x86_64/$BIOS_PKG" -o "$tmp/pkg.tar.zst" ||
        ! echo "$BIOS_SHA256  $tmp/pkg.tar.zst" | sha256sum -c --quiet - ||
        ! tar -I unzstd -xf "$tmp/pkg.tar.zst" -C "$tmp" "$BIOS_CAB"; then
        err "Downloading or verifying $BIOS_PKG failed; the BIOS was not touched."
        rm -rf "$tmp"
        return 1
    fi

    info "Handing BIOS $BIOS_NEWEST to fwupd. Do NOT turn off the power from now on."
    # -y: we already asked twice; --no-reboot-check: the wizard's own
    # restart question comes at the end.
    if ! sudo fwupdmgr install -y --no-reboot-check "$tmp/$BIOS_CAB"; then
        err "fwupd could not install the BIOS update (see above); the BIOS was not changed."
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    BIOS_NEEDS_RESTART=1
    ok "BIOS $BIOS_NEWEST is staged. It is written during the next restart:"
    warn "keep the power on and don't touch the machine until it has fully started again."
}
