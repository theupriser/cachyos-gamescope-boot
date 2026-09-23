#!/bin/bash
# Interactive menu: detects which components are on, lets the user pick what
# they want, then turns components on or off to match.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

# Menu order. Components are turned on in this order and off in reverse;
# gaming must come first (single user builds on it).
COMPONENTS=(gaming theme glyphs single machine)

declare -A LABEL=(
    [gaming]="SteamOS conversion: boot into gaming mode, Steam on the desktop"
    [theme]="Install SteamOS theme: Vapor look, dark mode, SteamOS taskbar"
    [glyphs]="Install Steam Deck/Machine icons: Deck button icons in gaming mode"
    [single]="Single user mode: no password, lock screen or log out (SDDM)"
    [machine]="Steam Machine support: LED bar driver, hardware settings in Steam"
)
declare -A CURRENT WANTED

component_available() {
    [[ "$1" != machine ]] || machine_available
}

detect_components() {
    local c any=false
    for c in "${COMPONENTS[@]}"; do
        component_available "$c" || continue
        if "${c}_status"; then CURRENT[$c]=1; any=true; else CURRENT[$c]=0; fi
        WANTED[$c]=${CURRENT[$c]}
    done
    # First run: preselect the full SteamOS experience.
    if [[ "$any" == false ]]; then
        for c in "${COMPONENTS[@]}"; do
            component_available "$c" && WANTED[$c]=1
        done
    fi
}

toggle_component() {
    local c="$1"
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
        now="off"; [[ "${CURRENT[$c]}" == 1 ]] && now="${c_green}on${c_reset} "
        want="[ ]"; [[ "${WANTED[$c]}" == 1 ]] && want="[x]"
        printf "  %-3s %-6b %-6s %s\n" "$i" "$now  " "$want" "${LABEL[$c]}"
    done
    echo
}

run_menu() {
    # Sets REAPPLY. Returns 1 if the user quit.
    REAPPLY=false
    local reply
    while true; do
        show_menu
        read -rp "$(echo -e "${c_bold}Type a number to toggle, Enter to continue, a = also re-apply what's on, q = quit:${c_reset} ")" reply
        case "$reply" in
            "") return 0 ;;
            a|A) REAPPLY=true; return 0 ;;
            q|Q) return 1 ;;
            *)
                if [[ "$reply" =~ ^[0-9]+$ && -n "${MENU_ITEMS[$reply]:-}" ]]; then
                    toggle_component "${MENU_ITEMS[$reply]}"
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
        echo; echo -e "${c_bold}Turning on: ${LABEL[$c]}${c_reset}"
        "${c}_enable" || failed+=("$c")
    done
    FAILED=("${failed[@]}")
}
