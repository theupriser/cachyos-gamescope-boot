#!/bin/bash
# Machine-readable mode for the graphical app (steamify-ui): the same
# components and plan as the menu, as JSON on stdout.
#   steamify.sh --backend status
#       one JSON object: version, machine, and every menu item with its
#       current state and what a run would pick by default.
#   steamify.sh --backend apply [--reapply] [--boot gamescope|desktop] <id>...
#       turns on the listed components and off the others (like ticking them
#       in the menu), then streams one JSON object per line: plan, start,
#       log, done, finished. sudo asks through $SUDO_ASKPASS (no terminal).
#   steamify.sh --backend apply ... --hdmi <output>=<w>x<h>:<rate>,... hdmi
#       HDMI refresh boost with the rates the app confirmed.
#   steamify.sh --backend hdmi-options
#       hdmi-options event: every HDMI output, its mode and rates to offer.
#   steamify.sh --backend hdmi-try <connector> <w> <h> <hz> [<rate>...]
#   steamify.sh --backend hdmi-reset <connector> <w> <h> <hz>
#       switch to a rate live (hdmi-tried event), or back to the display's
#       own EDID (hdmi-reset event); the app asks in between.
#   steamify.sh --backend bios-prepare | bios-flash
#       the BIOS update in two steps, so the app shows both warnings between
#       them (bios-ready event: current, newest, checksum, compatible).
# Sourced by steamify.sh; not meant to be run on its own.

json_str() {
    # json_str <text>: <text> as a JSON string (quotes, backslashes and
    # control characters escaped; colour codes dropped).
    local s="$1"
    s="$(printf '%s' "$s" | sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g')"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"; s="${s//$'\r'/}"; s="${s//$'\n'/\\n}"
    s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
    printf '"%s"' "$s"
}

json_list() {
    # json_list <item>...: a JSON array of strings.
    local out="" x
    for x in "$@"; do out+="${out:+,}$(json_str "$x")"; done
    printf '[%s]' "$out"
}

backend_event() {
    # backend_event <event> [<json fields without braces>]
    printf '{"event":%s%s}\n' "$(json_str "$1")" "${2:+,$2}"
}

backend_status() {
    local c first_run=true items="" kind parent now
    detect_components
    for c in "${COMPONENTS[@]}"; do
        component_available "$c" && ! is_action "$c" && [[ "${CURRENT[$c]}" == 1 ]] && first_run=false
    done
    for c in "${COMPONENTS[@]}"; do
        component_available "$c" || continue
        kind=toggle; is_action "$c" && kind=action; [[ "$c" == boot ]] && kind=choice
        parent="${PARENT[$c]:-}"
        now="${CURRENT[$c]:-0}"
        items+="${items:+,}{\"id\":$(json_str "$c"),\"label\":$(json_str "${LABEL[$c]%%:*}")"
        items+=",\"hint\":$(json_str "$( [[ "${LABEL[$c]}" == *:* ]] && echo "${LABEL[$c]#*: }")")"
        items+=",\"kind\":\"$kind\",\"parent\":$(json_str "$parent")"
        items+=",\"on\":$( [[ "$now" == 1 ]] && echo true || echo false)"
        items+=",\"wanted\":$( [[ "${WANTED[$c]:-0}" == 1 ]] && echo true || echo false)"
        items+=",\"selectable\":$(component_selectable "$c" && echo true || echo false)}"
    done
    local cec="" f
    for f in /dev/cec*; do [[ -e "$f" ]] && cec+="${cec:+ }$(basename "$f")"; done
    local bios='null'
    if bios_available; then
        bios="{\"current\":$(json_str "$(bios_current)"),\"newest\":$(json_str "${BIOS_NEWEST:-}"),\"selectable\":$(bios_selectable && echo true || echo false),\"dryRun\":$([[ -n "$BIOS_DRY_RUN" ]] && echo true || echo false)}"
    fi
    printf '{"version":%s,"firstRun":%s,"steamMachine":%s,"kernel":%s,"pinnedKernel":%s,"cecDevices":%s,"leds":%s,"bios":%s,"items":[%s]}\n' \
        "$(json_str "$VERSION")" "$first_run" \
        "$(detect_valve_fremont && echo true || echo false)" \
        "$(json_str "$(uname -r)")" "$(json_str "${PINNED_KERNEL_VER:-}")" \
        "$(json_str "$cec")" \
        "$(compgen -G '/sys/class/leds/valve-leds*' | wc -l)" \
        "$bios" "$items"
}

backend_run_component() {
    # backend_run_component <id> <enable|disable>: runs it in this shell
    # (its variables, e.g. RESTART_FOR_LOGIN, must survive), each output line
    # as a log event.
    local c="$1" what="$2" rc
    backend_event start "\"id\":$(json_str "$c"),\"action\":\"$what\",\"label\":$(json_str "${LABEL[$c]%%:*}")"
    "${c}_${what}" > >(while IFS= read -r line; do backend_event log "\"id\":$(json_str "$c"),\"line\":$(json_str "$line")"; done) 2>&1
    rc=$?
    # Let the log reader finish before the next event.
    wait $! 2>/dev/null
    backend_event "done" "\"id\":$(json_str "$c"),\"ok\":$([[ $rc -eq 0 ]] && echo true || echo false)"
    return $rc
}

backend_sudo() {
    # sudo from the app has no terminal: ask through its helper, and keep the
    # credentials fresh as the menu does.
    if [[ -z "${SUDO_ASKPASS:-}" ]] && ! sudo -n true 2>/dev/null; then
        backend_event finished '"failed":[],"restart":false,"error":"no-sudo"'
        return 1
    fi
    sudo() { command sudo ${SUDO_ASKPASS:+-A} "$@"; }
    if ! sudo -n true 2>/dev/null && ! sudo true 2>/dev/null; then
        backend_event finished '"failed":[],"restart":false,"error":"wrong-password"'
        return 1
    fi
    while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
}

backend_bios_prepare() {
    # Download, checksum and fwupd's device check; the app then shows its
    # two warnings and calls bios-flash.
    local rc
    backend_sudo || return 1
    backend_event start '"id":"bios","action":"prepare","label":"Update BIOS"'
    bios_prepare > >(while IFS= read -r line; do backend_event log "\"id\":\"bios\",\"line\":$(json_str "$line")"; done) 2>&1
    rc=$?; wait $! 2>/dev/null
    case $rc in
        0) backend_event bios-ready "\"current\":$(json_str "$(bios_current)"),\"newest\":$(json_str "$BIOS_NEWEST"),\"checksum\":true,\"compatible\":$(json_str "$BIOS_COMPATIBLE")" ;;
        2) backend_event finished '"failed":[],"restart":false,"nothing":true' ;;
        *) backend_event finished '"failed":["bios"],"restart":false' ;;
    esac
}

backend_bios_flash() {
    backend_sudo || return 1
    local rc
    backend_run_component bios flash_only; rc=$?
    backend_event finished "\"failed\":$([[ $rc -eq 0 ]] && echo '[]' || echo '["bios"]'),\"restart\":$(restart_needed && echo true || echo false),\"bios\":true"
}

backend_apply() {
    local reapply=false boot="" id c
    local -a want=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reapply) reapply=true ;;
            --boot) boot="$2"; shift ;;
            --hdmi) HDMI_CHOICE+=("$2"); shift ;;
            *) want+=("$1") ;;
        esac
        shift
    done
    detect_components
    # What the app ticked: exactly these on, every other component off.
    for c in "${COMPONENTS[@]}"; do
        component_available "$c" || continue
        is_action "$c" && { WANTED[$c]=0; continue; }
        WANTED[$c]=0
        for id in "${want[@]}"; do [[ "$id" == "$c" ]] && WANTED[$c]=1; done
    done
    # The same rules as the menu's toggles.
    [[ "${WANTED[single]:-0}" == 1 ]] && WANTED[gaming]=1
    [[ "${WANTED[gaming]:-0}" == 0 ]] && { WANTED[single]=0; WANTED[boot]=0; }
    [[ "${WANTED[kpin]:-0}" == 1 ]] && WANTED[machine]=1
    [[ "${WANTED[machine]:-0}" == 0 ]] && WANTED[kpin]=0
    [[ "${WANTED[hdmi]:-0}" == 1 ]] && { WANTED[machine]=1; WANTED[kpin]=1; }
    [[ "${WANTED[kpin]:-0}" == 0 ]] && WANTED[hdmi]=0
    case "$boot" in desktop) WANTED[boot]=1; WANTED[gaming]=1 ;; gamescope) WANTED[boot]=0 ;; esac

    REAPPLY=$reapply
    plan_changes
    backend_event plan "\"disable\":$(json_list "${TO_DISABLE[@]}"),\"enable\":$(json_list "${TO_ENABLE[@]}")"
    if [[ ${#TO_DISABLE[@]} -eq 0 && ${#TO_ENABLE[@]} -eq 0 ]]; then
        backend_event finished '"failed":[],"restart":false,"nothing":true'
        return 0
    fi

    backend_sudo || return 1

    LOGIN_MANAGER=plasmalogin
    [[ "${WANTED[single]}" == 1 ]] && LOGIN_MANAGER=sddm
    local -a failed=()
    for c in "${TO_DISABLE[@]}"; do backend_run_component "$c" disable || failed+=("$c"); done
    for c in "${TO_ENABLE[@]}"; do backend_run_component "$c" enable || failed+=("$c"); done
    [[ " ${TO_DISABLE[*]} ${TO_ENABLE[*]} " =~ \ (gaming|single|boot|kpin)\  ]] && RESTART_FOR_LOGIN=true
    backend_event finished "\"failed\":$(json_list "${failed[@]}"),\"restart\":$(restart_needed && echo true || echo false)"
}

backend_hdmi() {
    # backend_hdmi options|try|reset [args]: the app's HDMI screen. Events
    # only (no "finished"): the app goes on from its own screen.
    local what="$1" rc
    shift
    backend_sudo || return 1
    case "$what" in
        options)
            sudo pacman -S --needed --noconfirm i2c-tools python >/dev/null 2>&1
            backend_event hdmi-options "\"outputs\":$(hdmi_options 2>/dev/null)" ;;
        try)
            hdmi_try "$@" >/dev/null 2>&1; rc=$?
            backend_event hdmi-tried "\"hz\":$4,\"ok\":$([[ $rc -eq 0 ]] && echo true || echo false)" ;;
        reset)
            hdmi_reset "$@" >/dev/null 2>&1
            backend_event hdmi-reset ;;
    esac
}

backend_main() {
    case "${1:-}" in
        status) backend_status ;;
        apply) shift; backend_apply "$@" ;;
        bios-prepare) backend_bios_prepare ;;
        bios-flash) backend_bios_flash ;;
        hdmi-options) backend_hdmi options ;;
        hdmi-try) shift; backend_hdmi try "$@" ;;
        hdmi-reset) shift; backend_hdmi reset "$@" ;;
        *) err "Usage: steamify.sh --backend status | apply [--reapply] [--boot gamescope|desktop] <id>..."; return 2 ;;
    esac
}
