#!/bin/bash
# Interactive menu: detects which components are on, lets the user pick what
# they want, then turns components on or off to match.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

# Menu order. Components are turned on in this order and off in reverse;
# gaming must come first (single user builds on it).
COMPONENTS=(gaming theme glyphs single launcher machine bios)
# One-off actions rather than on/off components: never preselected, never
# re-applied, not listed as on or off.
ACTIONS=(bios)

declare -A LABEL=(
    [gaming]="SteamOS conversion: boot into gaming mode, Steam on the desktop"
    [theme]="Install SteamOS theme: Vapor look (cachyos-vapor)"
    [glyphs]="Install Steam Deck/Machine icons: Deck button icons in gaming mode"
    [single]="Single user mode: no password, lock screen or log out (SDDM)"
    [launcher]="Wizard shortcut: desktop icon to run this wizard again"
    [machine]="Steam Machine support: LED bar driver, hardware settings in Steam"
    [bios]="Update BIOS"
)
declare -A CURRENT WANTED

component_available() {
    case "$1" in
        machine) machine_available ;;
        bios) bios_available ;;
    esac
}

is_action() { [[ " ${ACTIONS[*]} " == *" $1 "* ]]; }

component_selectable() {
    # Greyed out and not tickable when it has nothing to do.
    case "$1" in
        bios) bios_selectable ;;
    esac
}

detect_components() {
    local c any=false
    for c in "${COMPONENTS[@]}"; do
        component_available "$c" || continue
        if "${c}_status"; then CURRENT[$c]=1; any=true; else CURRENT[$c]=0; fi
        WANTED[$c]=${CURRENT[$c]}
    done
    # Shows the current and newest BIOS version.
    bios_available && { bios_lookup_newest; LABEL[bios]="$(bios_label)"; }
    # First run: preselect the full SteamOS experience (never an action).
    if [[ "$any" == false ]]; then
        for c in "${COMPONENTS[@]}"; do
            component_available "$c" && ! is_action "$c" && WANTED[$c]=1
        done
    fi
}

toggle_component() {
    local c="$1"
    component_selectable "$c" || return 1
    WANTED[$c]=$(( 1 - WANTED[$c] ))
    # Single user mode only makes sense on top of the SteamOS conversion.
    if [[ "$c" == single && "${WANTED[single]}" == 1 ]]; then WANTED[gaming]=1; fi
    if [[ "$c" == gaming && "${WANTED[gaming]}" == 0 ]]; then WANTED[single]=0; fi
}

show_menu() {
    local i=0 c now want
    echo
    printf "  ${c_bold}%-3s %-6s %-6s %s${c_reset}\n" "#" "Now" "Want" "Component"
    MENU_ITEMS=()
    for c in "${COMPONENTS[@]}"; do
        component_available "$c" || continue
        i=$((i + 1)); MENU_ITEMS[$i]=$c
        # Pad the plain word, then colour it: colour codes would count as width.
        now="off"; [[ "${CURRENT[$c]}" == 1 ]] && now="on"
        is_action "$c" && now="-"
        now="$(printf '%-6s' "$now")"
        [[ "${CURRENT[$c]}" == 1 ]] && now="${now/on/${c_green}on${c_reset}}"
        want="[ ]"; [[ "${WANTED[$c]}" == 1 ]] && want="[x]"
        if component_selectable "$c"; then
            printf "  %-3s %b %-6s %s\n" "$i" "$now" "$want" "${LABEL[$c]}"
        else
            printf "  %b%-3s %-6s %-6s %s (not available)%b\n" "$c_dim" "$i" "$now" "$want" "${LABEL[$c]}" "$c_reset"
        fi
    done
    echo
    echo -e "$KERNEL_OVERVIEW"
    echo
}

run_menu() {
    # Sets REAPPLY. Returns 1 if the user quit. A checkbox list on a
    # terminal; a plain numbered prompt when input is piped (scripted runs).
    REAPPLY=false
    # Built once: the TUI redraws on every key press.
    KERNEL_OVERVIEW="$(kernel_overview)"
    if [[ -t 0 && -t 1 ]]; then
        run_menu_tui
    else
        run_menu_lines
    fi
}

draw_menu_tui() {
    local cursor="$1" i=0 c box state line
    printf '\033[H\033[2J'
    echo -e "${c_bold}CachyOS Steam Deck-style Gamescope Boot Wizard${c_reset} v$VERSION"
    echo "Pick what you want. Anything you untick is put back the way it was."
    echo
    MENU_ITEMS=()
    for c in "${COMPONENTS[@]}"; do
        component_available "$c" || continue
        MENU_ITEMS[$i]=$c
        box="[ ]"; [[ "${WANTED[$c]}" == 1 ]] && box="[${c_green}x${c_reset}]"
        state="  (now: off)"; [[ "${CURRENT[$c]}" == 1 ]] && state="  (now: ${c_green}on${c_reset})"
        is_action "$c" && state="  (opt-in, runs once)"
        line="$box ${LABEL[$c]}"
        if ! component_selectable "$c"; then
            # Greyed out: nothing to do (e.g. BIOS already up to date).
            local mark="   "; (( i == cursor )) && mark=" ${c_cyan}>${c_reset} "
            echo -e "${mark}${c_dim}[ ] ${LABEL[$c]}  (not available)${c_reset}"
        elif (( i == cursor )); then
            # The green x's reset would end the bold too: re-enable it after.
            echo -e " ${c_cyan}>${c_reset} ${c_bold}${line//"$c_reset"/"$c_reset$c_bold"}${c_reset}${state}"
        else
            echo -e "   ${line}${state}"
        fi
        i=$((i + 1))
    done
    echo
    echo -e "$KERNEL_OVERVIEW"
    echo
    echo -e "  ${c_bold}Up/Down${c_reset} move   ${c_bold}Space${c_reset} select   ${c_bold}Enter${c_reset} run   ${c_bold}a${c_reset} run + re-apply what's on   ${c_bold}q${c_reset} quit"
}

run_menu_tui() {
    local cursor=0 key rest count
    tput civis 2>/dev/null
    trap 'tput cnorm 2>/dev/null' EXIT
    while true; do
        draw_menu_tui "$cursor"
        count=${#MENU_ITEMS[@]}
        IFS= read -rsn1 key
        if [[ "$key" == $'\e' ]]; then
            IFS= read -rsn2 -t 0.05 rest
            key+="$rest"
        fi
        case "$key" in
            $'\e[A'|k) (( cursor = (cursor + count - 1) % count )) ;;
            $'\e[B'|j) (( cursor = (cursor + 1) % count )) ;;
            " ") toggle_component "${MENU_ITEMS[$cursor]}" ;;
            "") break ;;
            a|A) REAPPLY=true; break ;;
            q|Q) tput cnorm 2>/dev/null; echo; return 1 ;;
        esac
    done
    tput cnorm 2>/dev/null
    echo
    return 0
}

run_menu_lines() {
    local reply
    while true; do
        show_menu
        read -rp "$(echo -e "${c_bold}Type a number to toggle, Enter to continue, a = also re-apply what's on, q = quit:${c_reset} ")" reply || return 1
        case "$reply" in
            "") return 0 ;;
            a|A) REAPPLY=true; return 0 ;;
            q|Q) return 1 ;;
            *)
                if [[ "$reply" =~ ^[0-9]+$ && -n "${MENU_ITEMS[$reply]:-}" ]]; then
                    toggle_component "${MENU_ITEMS[$reply]}" ||
                        warn "Not available: ${LABEL[${MENU_ITEMS[$reply]}]}"
                else
                    warn "Unknown choice: $reply"
                fi
                ;;
        esac
    done
}

plan_changes() {
    # Fills TO_DISABLE (reverse order) and TO_ENABLE. Switching single user
    # on or off moves gaming mode to the other login manager, so gaming
    # mode is re-applied then too.
    TO_DISABLE=(); TO_ENABLE=()
    local c i
    for (( i = ${#COMPONENTS[@]} - 1; i >= 0; i-- )); do
        c=${COMPONENTS[$i]}
        component_available "$c" || continue
        [[ "${CURRENT[$c]}" == 1 && "${WANTED[$c]}" == 0 ]] && TO_DISABLE+=("$c")
    done
    for c in "${COMPONENTS[@]}"; do
        component_available "$c" || continue
        [[ "${WANTED[$c]}" == 1 ]] || continue
        if is_action "$c"; then TO_ENABLE+=("$c"); continue; fi
        if [[ "${CURRENT[$c]}" == 0 || "$REAPPLY" == true ]] ||
            [[ "$c" == gaming && "${CURRENT[single]}" != "${WANTED[single]}" ]]; then
            TO_ENABLE+=("$c")
        fi
    done
}

apply_changes() {
    local c failed=()
    LOGIN_MANAGER=plasmalogin
    [[ "${WANTED[single]}" == 1 ]] && LOGIN_MANAGER=sddm

    for c in "${TO_DISABLE[@]}"; do
        echo; echo -e "${c_bold}Turning off: ${LABEL[$c]}${c_reset}"
        "${c}_disable" || failed+=("$c")
    done
    for c in "${TO_ENABLE[@]}"; do
        if is_action "$c"; then echo; echo -e "${c_bold}Running: ${LABEL[$c]%%:*}${c_reset}"
        else echo; echo -e "${c_bold}Turning on: ${LABEL[$c]}${c_reset}"; fi
        "${c}_enable" || failed+=("$c")
    done
    FAILED=("${failed[@]}")
}
