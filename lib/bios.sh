#!/bin/bash
# "Update BIOS" menu item, only on a Steam Machine and always opt-in: flashes
# the newest Steam Machine BIOS from Valve's fremont-hw-support package with
# fwupd. It's an action, not an on/off component: never preselected, never
# re-applied, and there is nothing to turn off afterwards.
# Sourced by steamify.sh; not meant to be run on its own.

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
    # Menu label with the current and the newest version; kept short so the
    # row (with "(not available)" when greyed out) fits 80 columns.
    local current
    current="$(bios_current)"
    if [[ -n "${BIOS_NEEDS_RESTART:-}" ]]; then
        echo "Update BIOS: $BIOS_NEWEST waits for a restart"
    elif [[ -z "${BIOS_NEWEST:-}" ]]; then
        echo "Update BIOS: now $current, newest unknown (offline?)"
    elif [[ "$BIOS_NEWEST" == "$current" ]]; then
        echo "Update BIOS: $current is up to date"
    else
        echo "Update BIOS: now $current, newest $BIOS_NEWEST (own risk)"
    fi
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

# The checked firmware waits here between bios_prepare and bios_flash, so the
# app can show its warnings in between (and the terminal flow uses it too).
BIOS_STAGE_DIR="${XDG_RUNTIME_DIR:-/tmp}/steamify-bios"

bios_prepare() {
    # Downloads Valve's package, checks its SHA-256 and extracts the .cab to
    # $BIOS_STAGE_DIR, then asks fwupd whether it fits this machine. Sets
    # BIOS_COMPATIBLE (yes|dry-run). 0 = ready to flash, 2 = nothing to do
    # (already the newest), 1 = error (nothing was touched).
    if ! bios_lookup_newest; then
        err "Couldn't find the newest Steam Machine BIOS on Valve's mirror ($VALVE_MIRROR)."
        return 1
    fi
    [[ -n "$BIOS_DRY_RUN" ]] && warn "DRY RUN (WIZARD_BIOS_DRY_RUN): nothing will be flashed."
    if [[ "$(bios_current)" == "$BIOS_NEWEST" ]]; then
        ok "The BIOS is already the newest version ($BIOS_NEWEST); nothing to do."
        return 2
    fi
    pacman -Q fwupd >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm fwupd ||
        { err "Installing fwupd failed."; return 1; }
    rm -rf "$BIOS_STAGE_DIR"; mkdir -p "$BIOS_STAGE_DIR"; chmod 700 "$BIOS_STAGE_DIR"
    info "Downloading $BIOS_PKG ($BIOS_REPO)..."
    if ! curl -fsSL "$VALVE_MIRROR/$BIOS_REPO/os/x86_64/$BIOS_PKG" -o "$BIOS_STAGE_DIR/pkg.tar.zst" ||
        ! echo "$BIOS_SHA256  $BIOS_STAGE_DIR/pkg.tar.zst" | sha256sum -c --quiet - ||
        ! tar -I unzstd -xf "$BIOS_STAGE_DIR/pkg.tar.zst" -C "$BIOS_STAGE_DIR" "$BIOS_CAB"; then
        err "Downloading or verifying $BIOS_PKG failed; the BIOS was not touched."
        rm -rf "$BIOS_STAGE_DIR"
        return 1
    fi
    ok "Checksum OK: this is Valve's $BIOS_PKG."
    if [[ -n "$BIOS_DRY_RUN" ]]; then
        warn "Dry run: skipping fwupd's check that the firmware fits this machine."
        BIOS_COMPATIBLE=dry-run
    elif bios_fits_device "$BIOS_STAGE_DIR/$BIOS_CAB"; then
        ok "fwupd confirms BIOS $BIOS_NEWEST is firmware for this machine."
        BIOS_COMPATIBLE=yes
    else
        err "fwupd says BIOS $BIOS_NEWEST is not for this machine's hardware; not installing it."
        rm -rf "$BIOS_STAGE_DIR"
        return 1
    fi
    printf '%s\n' "$BIOS_NEWEST" "$BIOS_CAB" > "$BIOS_STAGE_DIR/ready"
}

bios_flash() {
    # Hands the firmware bios_prepare checked to fwupd; it is written during
    # the next restart. Sets BIOS_NEEDS_RESTART.
    local newest cab
    { read -r newest; read -r cab; } < "$BIOS_STAGE_DIR/ready" 2>/dev/null
    if [[ -z "${cab:-}" || ! -f "$BIOS_STAGE_DIR/$cab" ]]; then
        err "No checked BIOS file waiting; nothing was flashed."
        return 1
    fi
    if [[ -n "$BIOS_DRY_RUN" ]]; then
        ok "Dry run: would run: fwupdmgr install -y --no-reboot-check $(basename "$cab")"
        ok "Dry run finished; nothing was flashed."
        # Treated as staged, so the restart choices that follow a real
        # update show up too; restarting only prints (see restart_now).
        BIOS_NEEDS_RESTART=1
        rm -rf "$BIOS_STAGE_DIR"
        return 0
    fi
    info "Handing BIOS $newest to fwupd. Do NOT turn off the power from now on."
    # -y: the user confirmed twice; --no-reboot-check: our own restart
    # question comes at the end.
    if ! sudo fwupdmgr install -y --no-reboot-check "$BIOS_STAGE_DIR/$cab"; then
        err "fwupd could not install the BIOS update (see above); the BIOS was not changed."
        rm -rf "$BIOS_STAGE_DIR"
        return 1
    fi
    rm -rf "$BIOS_STAGE_DIR"
    BIOS_NEEDS_RESTART=1
    ok "BIOS $newest is staged. It is written during the next restart:"
    warn "keep the power on and don't touch the machine until it has fully started again."
}

bios_enable() {
    local rc current compatible
    current="$(bios_current)"
    bios_prepare; rc=$?
    [[ $rc -eq 2 ]] && return 0
    [[ $rc -ne 0 ]] && return 1

    local yes="$c_green$c_bold" b="$c_bold" n="$c_reset"
    if [[ "$BIOS_COMPATIBLE" == dry-run ]]; then
        compatible="${c_yellow}${b}not checked${n} (dry run)"
    else
        compatible="${yes}yes${n} (checked by fwupd)"
    fi
    bios_disclaimer "WARNING: BIOS UPDATE - ENTIRELY AT YOUR OWN RISK" \
        "Current BIOS: ${b}$current${n}" \
        "New BIOS:     ${b}$BIOS_NEWEST${n}" \
        "Checksum:     ${yes}OK${n} (Valve's package)" \
        "Compatible:   $compatible"
    if ! ask_yn "Do you understand the risks and want to continue?" n; then
        info "BIOS update cancelled; nothing was changed."; rm -rf "$BIOS_STAGE_DIR"; return 0
    fi
    bios_disclaimer "LAST CHANCE: THIS FLASHES BIOS $BIOS_NEWEST" \
        "After this, keep the power on until the machine has fully" \
        "started again. Don't touch it, even if the screen is black."
    local reply
    read -rp "$(echo -e "${c_red}${c_bold}Type UPDATE (in capitals) to flash the BIOS, anything else cancels:${c_reset} ")" reply
    if [[ "$reply" != UPDATE ]]; then
        info "BIOS update cancelled; nothing was changed."; rm -rf "$BIOS_STAGE_DIR"; return 0
    fi
    bios_flash
}

# For the app (lib/backend.sh): the flash step alone, after its warnings.
bios_flash_only() { bios_flash; }
