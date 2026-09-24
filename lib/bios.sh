#!/bin/bash
# "Update BIOS" menu item, only on a Steam Machine and always opt-in: flashes
# the newest Steam Machine BIOS from Valve's fremont-hw-support package with
# fwupd. It's an action, not an on/off component: never preselected, never
# re-applied, and there is nothing to turn off afterwards.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

BIOS_REPO_PREFIX=holo
# WIZARD_BIOS_DRY_RUN=1 walks through the whole BIOS update (download,
# checksum, both warnings) but never flashes: fwupd's device check is
# skipped and the install is only printed. For testing, e.g. in a VM.
BIOS_DRY_RUN="${WIZARD_BIOS_DRY_RUN:-}"

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

bios_selectable() {
    # Only when Valve has a newer BIOS than the one installed; the menu
    # greys the item out otherwise (up to date, or newest unknown/offline).
    [[ -z "${BIOS_NEEDS_RESTART:-}" && -n "${BIOS_NEWEST:-}" && "$BIOS_NEWEST" != "$(bios_current)" ]]
}

bios_label() {
    # Menu label with the current and the newest version.
    local newest="newest unknown (offline?)"
    [[ -n "${BIOS_NEWEST:-}" ]] && newest="newest $BIOS_NEWEST"
    [[ "${BIOS_NEWEST:-}" == "$(bios_current)" ]] && newest="up to date"
    [[ -n "${BIOS_NEEDS_RESTART:-}" ]] && newest="$BIOS_NEWEST staged, restart to install"
    echo "Update BIOS (at your own risk): now $(bios_current), $newest"
}

BIOS_BOX_WIDTH=68

bios_box_line() {
    # bios_box_line [text]: one line of the warning box, padded to the same
    # visible width (colour codes don't count) so the right edge lines up.
    local text="${1:-}" plain pad
    plain="$(printf '%b' "$text" | sed 's/\x1b\[[0-9;]*m//g')"
    pad=$(( BIOS_BOX_WIDTH - 6 - ${#plain} ))
    (( pad < 0 )) && pad=0
    printf '  %b██%b  %b%*s%b██%b\n' "$c_red" "$c_reset" "$text" "$pad" "" "$c_red" "$c_reset"
}

bios_box_border() {
    # Block characters: Konsole draws a long coloured row of # narrower
    # than the box's other lines, so its right edge wouldn't line up.
    printf '  %b%s%b\n' "$c_red" "$(printf '█%.0s' $(seq "$BIOS_BOX_WIDTH"))" "$c_reset"
}

bios_disclaimer() {
    # bios_disclaimer <title> [line...]: the warning box; extra lines are
    # shown above the fixed risks.
    local title="$1" line b="$c_bold" n="$c_reset"
    shift
    echo
    bios_box_border
    bios_box_line
    bios_box_line "$c_red$b$title$n"
    bios_box_line
    bios_box_border
    for line in "$@"; do bios_box_line "$line"; done
    bios_box_line
    bios_box_line "- A failed or interrupted BIOS update can leave the machine"
    bios_box_line "  unable to start (bricked). This wizard, CachyOS and Valve"
    bios_box_line "  take no responsibility for that."
    bios_box_line "- ${b}NEVER turn off the power, unplug the machine or press${n}"
    bios_box_line "  ${b}the power button while the update runs${n}, including the"
    bios_box_line "  restart(s) afterwards, when the firmware is written."
    bios_box_line "- The screen can stay black for several minutes. Wait."
    bios_box_line "- Only on mains power, with all other programs closed."
    bios_box_line
    bios_box_border
    echo
}

bios_fits_device() {
    # bios_fits_device <cab>: does fwupd match this firmware to a device in
    # this machine? It compares the file's hardware IDs (GUIDs) with the
    # hardware; for a file that doesn't fit it reports an UpdateError.
    local details
    details="$(sudo fwupdmgr get-details --json "$1" 2>/dev/null)" || return 1
    grep -q '"Guid"' <<< "$details" && ! grep -q '"UpdateError"' <<< "$details"
}

bios_enable() {
    if ! bios_lookup_newest; then
        err "Couldn't find the newest Steam Machine BIOS on Valve's mirror ($VALVE_MIRROR)."
        return 1
    fi
    local current tmp compatible
    current="$(bios_current)"
    [[ -n "$BIOS_DRY_RUN" ]] && warn "DRY RUN (WIZARD_BIOS_DRY_RUN): nothing will be flashed."
    if [[ "$current" == "$BIOS_NEWEST" ]]; then
        ok "The BIOS is already the newest version ($current); nothing to do."
        return 0
    fi

    # Download and check everything before asking: the warnings only come
    # when the file is Valve's (SHA-256 from Valve's repo database) and fwupd
    # confirms it's firmware for this very machine.
    pacman -Q fwupd >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm fwupd ||
        { err "Installing fwupd failed."; return 1; }
    tmp="$(mktemp -d)"
    info "Downloading $BIOS_PKG ($BIOS_REPO)..."
    if ! curl -fsSL "$VALVE_MIRROR/$BIOS_REPO/os/x86_64/$BIOS_PKG" -o "$tmp/pkg.tar.zst" ||
        ! echo "$BIOS_SHA256  $tmp/pkg.tar.zst" | sha256sum -c --quiet - ||
        ! tar -I unzstd -xf "$tmp/pkg.tar.zst" -C "$tmp" "$BIOS_CAB"; then
        err "Downloading or verifying $BIOS_PKG failed; the BIOS was not touched."
        rm -rf "$tmp"
        return 1
    fi
    ok "Checksum OK: this is Valve's $BIOS_PKG."
    local yes="$c_green$c_bold" b="$c_bold" n="$c_reset"
    if [[ -n "$BIOS_DRY_RUN" ]]; then
        warn "Dry run: skipping fwupd's check that the firmware fits this machine."
        compatible="${c_yellow}${b}not checked${n} (dry run)"
    elif bios_fits_device "$tmp/$BIOS_CAB"; then
        ok "fwupd confirms BIOS $BIOS_NEWEST is firmware for this machine."
        compatible="${yes}yes${n} (checked by fwupd)"
    else
        err "fwupd says BIOS $BIOS_NEWEST is not for this machine's hardware; not installing it."
        rm -rf "$tmp"
        return 1
    fi

    bios_disclaimer "WARNING: BIOS UPDATE - ENTIRELY AT YOUR OWN RISK" \
        "Current BIOS: ${b}$current${n}" \
        "New BIOS:     ${b}$BIOS_NEWEST${n}" \
        "Checksum:     ${yes}OK${n} (Valve's package)" \
        "Compatible:   $compatible"
    if ! ask_yn "Do you understand the risks and want to continue?" n; then
        info "BIOS update cancelled; nothing was changed."; rm -rf "$tmp"; return 0
    fi
    bios_disclaimer "LAST CHANCE: THIS FLASHES BIOS $BIOS_NEWEST" \
        "After this, keep the power on until the machine has fully" \
        "started again. Don't touch it, even if the screen is black."
    local reply
    read -rp "$(echo -e "${c_red}${c_bold}Type UPDATE (in capitals) to flash the BIOS, anything else cancels:${c_reset} ")" reply
    if [[ "$reply" != UPDATE ]]; then
        info "BIOS update cancelled; nothing was changed."; rm -rf "$tmp"; return 0
    fi

    if [[ -n "$BIOS_DRY_RUN" ]]; then
        ok "Dry run: would now run: sudo fwupdmgr install -y --no-reboot-check $BIOS_CAB"
        ok "Dry run finished; nothing was flashed."
        # Treated as staged, so the restart choices that follow a real
        # update show up too; restarting only prints (see restart_now).
        BIOS_NEEDS_RESTART=1
        rm -rf "$tmp"
        return 0
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
