#!/bin/bash
# Interactive menu: detects which components are on, lets the user pick what
# they want, then turns components on or off to match.
# Sourced by steamify.sh; not meant to be run on its own.

# Menu order. Components are turned on in this order and off in reverse;
# gaming must come first (single user builds on it).
COMPONENTS=(gaming boot theme glyphs single launcher cec machine kpin hdmi bios)
# One-off actions rather than on/off components: never preselected, never
# re-applied, not listed as on or off.
ACTIONS=(bios)
# Sub-options, shown indented under their parent and only while it's ticked.
declare -A PARENT=([boot]=gaming [kpin]=machine)
# Never preselected on a first run: booting into the desktop is a choice,
# gamescope is the default; HDMI-CEC is opt-in (it can wake the machine or
# upset other devices on the TV, even on SteamOS), except on a Steam Machine,
# which has CEC like on SteamOS. HDMI refresh boost needs someone at the
# screen to confirm each step.
NO_PRESELECT=(boot cec hdmi)

declare -A LABEL=(
    [gaming]="SteamOS conversion: boot into gaming mode, Steam on the desktop"
    [boot]="Boot into the desktop instead of gaming mode"
    [theme]="Install SteamOS theme: Vapor look (cachyos-vapor)"
    [glyphs]="Install Steam Deck/Machine icons: Deck button icons in gaming mode"
    [single]="Single user mode: no password, lock screen or log out (SDDM)"
    [launcher]="Steamify shortcut: desktop icon to run this again"
    [cec]="HDMI-CEC: use Steam with the TV remote, TV on/off with the PC (experimental)"
    [machine]="Steam Machine support: LED bar driver, hardware settings in Steam"
    [kpin]="Pin the kernel to $PINNED_KERNEL_VER (fixes rebooting after shutdown)"
    [hdmi]="HDMI refresh boost: highest refresh your HDMI display runs"
    [bios]="Update BIOS"
)
declare -A CURRENT WANTED

component_available() {
    case "$1" in
        machine|kpin) machine_available ;;
        hdmi) hdmi_available ;;
        bios) bios_available ;;
    esac
}

is_action() { [[ " ${ACTIONS[*]} " == *" $1 "* ]]; }

boot_mode() {
    # boot_mode 0|1: the "Boot into" choice as a word, for messages; "turn
    # off boot into the desktop" reads as the opposite of what was chosen.
    if [[ "$1" == 1 ]]; then echo desktop; else echo gamescope; fi
}

menu_visible() {
    # Shown in the menu. A sub-option ("Boot into", the kernel pin) only
    # while its parent is ticked.
    component_available "$1" || return 1
    [[ -z "${PARENT[$1]:-}" || "${WANTED[${PARENT[$1]}]:-0}" == 1 ]]
}

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
    # HDMI-CEC set up by an older version: tick it, so a normal run fixes it.
    component_available cec && cec_repair && WANTED[cec]=1
    # Shows the current and newest BIOS version.
    bios_available && { bios_lookup_newest; LABEL[bios]="$(bios_label)"; }
    # First run: preselect the full SteamOS experience (never an action).
    if [[ "$any" == false ]]; then
        for c in "${COMPONENTS[@]}"; do
            component_available "$c" && ! is_action "$c" &&
                [[ " ${NO_PRESELECT[*]} " != *" $c "* ]] && WANTED[$c]=1
        done
        machine_available && WANTED[cec]=1
    fi
}

toggle_component() {
    local c="$1"
    component_selectable "$c" || return 1
    WANTED[$c]=$(( 1 - WANTED[$c] ))
    # Single user mode only makes sense on top of the SteamOS conversion.
    if [[ "$c" == single && "${WANTED[single]}" == 1 ]]; then WANTED[gaming]=1; fi
    if [[ "$c" == gaming && "${WANTED[gaming]}" == 0 ]]; then WANTED[single]=0; WANTED[boot]=0; fi
    # Where to boot to is part of the conversion, too.
    if [[ "$c" == boot && "${WANTED[boot]}" == 1 ]]; then WANTED[gaming]=1; fi
    # The kernel pin is opt-out: ticked along with Steam Machine support.
    if [[ "$c" == machine ]]; then WANTED[kpin]=${WANTED[machine]}; fi
    if [[ "$c" == kpin && "${WANTED[kpin]}" == 1 ]]; then WANTED[machine]=1; fi
}

show_menu() {
    local i=0 c now want
    echo
    printf "  ${c_bold}%-3s %-6s %-6s %s${c_reset}\n" "#" "Now" "Want" "Component"
    MENU_ITEMS=()
    for c in "${COMPONENTS[@]}"; do
        menu_visible "$c" || continue
        i=$((i + 1)); MENU_ITEMS[$i]=$c
        # Pad the plain word, then colour it: colour codes would count as width.
        now="off"; [[ "${CURRENT[$c]}" == 1 ]] && now="on"
        is_action "$c" && now="-"
        now="$(printf '%-6s' "$now")"
        [[ "${CURRENT[$c]}" == 1 ]] && now="${now/on/${c_green}on${c_reset}}"
        want="[ ]"; [[ "${WANTED[$c]}" == 1 ]] && want="[x]"
        if [[ "$c" == boot ]]; then
            # A choice rather than a checkbox: Now/Want show the mode.
            now="gaming"; [[ "${CURRENT[boot]}" == 1 ]] && now="desk"
            [[ "${CURRENT[gaming]}" == 1 ]] || now="-"
            want="gaming"; [[ "${WANTED[boot]}" == 1 ]] && want="desk"
            printf "  %-3s %-6s %-6s   └ %s\n" "$i" "$now" "$want" "$(boot_choice "${WANTED[boot]}")"
        elif [[ -n "${PARENT[$c]:-}" ]]; then
            printf "  %-3s %b %-6s   └ %s\n" "$i" "$now" "$want" "${LABEL[$c]}"
        elif component_selectable "$c"; then
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
    echo -e "${c_bold}Steamify CachyOS${c_reset} v$VERSION"
    echo "Pick what you want. Anything you untick is put back the way it was."
    echo
    MENU_ITEMS=()
    for c in "${COMPONENTS[@]}"; do
        menu_visible "$c" || continue
        MENU_ITEMS[$i]=$c
        box="[ ]"; [[ "${WANTED[$c]}" == 1 ]] && box="[${c_green}x${c_reset}]"
        state="  (now: off)"; [[ "${CURRENT[$c]}" == 1 ]] && state="  (now: ${c_green}on${c_reset})"
        is_action "$c" && state="  (opt-in, runs once)"
        line="$box ${LABEL[$c]}"
        if [[ "$c" == boot ]]; then
            # A choice rather than a checkbox; Space switches it.
            # Indented under the conversion, whose sub-option it is.
            line="$(boot_choice "${WANTED[boot]}")"
            line="    └ ${line/\[/[${c_green}}"; line="${line/\]/${c_reset}]}"
            local mode=gamescope; [[ "${CURRENT[boot]}" == 1 ]] && mode=desktop
            state="  (${c_bold}←/→${c_reset} choose)"
            [[ "${CURRENT[gaming]}" == 1 ]] && state="  (now: $mode; ${c_bold}←/→${c_reset} choose)"
        elif [[ -n "${PARENT[$c]:-}" ]]; then
            line="    └ $line"
        fi
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
    echo -e "  ${c_bold}Up/Down${c_reset} move   ${c_bold}Space${c_reset} select   ${c_bold}Left/Right${c_reset} choose   ${c_bold}Enter${c_reset} run"
    echo -e "  ${c_bold}a${c_reset} run + re-apply what's on   ${c_bold}q${c_reset} quit"
}

run_menu_tui() {
    local cursor=0 key rest count
    tput civis 2>/dev/null
    trap 'tput cnorm 2>/dev/null' EXIT
    while true; do
        draw_menu_tui "$cursor"
        count=${#MENU_ITEMS[@]}
        # The list shrinks when the conversion (and its sub-option) is unticked.
        if (( cursor >= count )); then cursor=$(( count - 1 )); draw_menu_tui "$cursor"; fi
        IFS= read -rsn1 key
        if [[ "$key" == $'\e' ]]; then
            IFS= read -rsn2 -t 0.05 rest
            key+="$rest"
        fi
        case "$key" in
            $'\e[A'|k) (( cursor = (cursor + count - 1) % count )) ;;
            $'\e[B'|j) (( cursor = (cursor + 1) % count )) ;;
            " ") toggle_component "${MENU_ITEMS[$cursor]}" ;;
            # On the "Boot into" row: left = gamescope, right = desktop.
            $'\e[D'|h) [[ "${MENU_ITEMS[$cursor]}" == boot && "${WANTED[boot]}" == 1 ]] && toggle_component boot ;;
            $'\e[C'|l) [[ "${MENU_ITEMS[$cursor]}" == boot && "${WANTED[boot]}" == 0 ]] && toggle_component boot ;;
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
        if [[ "$c" == boot ]]; then echo; echo -e "${c_bold}Boot into: gamescope${c_reset}"
        else echo; echo -e "${c_bold}Turning off: ${LABEL[$c]}${c_reset}"; fi
        "${c}_disable" || failed+=("$c")
    done
    for c in "${TO_ENABLE[@]}"; do
        if [[ "$c" == boot ]]; then echo; echo -e "${c_bold}Boot into: desktop${c_reset}"
        elif is_action "$c"; then echo; echo -e "${c_bold}Running: ${LABEL[$c]%%:*}${c_reset}"
        else echo; echo -e "${c_bold}Turning on: ${LABEL[$c]}${c_reset}"; fi
        "${c}_enable" || failed+=("$c")
    done
    FAILED=("${failed[@]}")
}
