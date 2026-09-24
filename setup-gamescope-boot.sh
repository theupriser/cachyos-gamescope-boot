#!/bin/bash
#
# setup-gamescope-boot.sh
#
# Wizard that makes a CachyOS (KDE Plasma) install behave like SteamOS:
# boot into a Steam Deck-style gamescope session, switch to the Plasma
# desktop and back, and reset to gamescope on the next boot/logout.
#
# It opens with a menu that detects which components are on and turns
# them on or off to match what the user picks; turning one off restores
# what was there before (system files from .bak-gamescope-wizard backups,
# KDE settings from the undo journal in lib/state.sh). Components live in
# lib/, see README.md. Safe to re-run.

set -uo pipefail

# Release version, see CHANGELOG.md.
VERSION=0.7.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for lib in common state packages login-manager single-user steam-desktop steam-machine vapor-theme steamos-extras bios desktop-shortcut menu; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/$lib.sh"
done

require_root_helper

echo -e "${c_bold}CachyOS Steam Deck-style Gamescope Boot Wizard${c_reset} v$VERSION"
echo "Turn the SteamOS-style parts on or off. The menu shows what is on now;"
echo "anything you turn off is put back the way it was."

if ! command -v pacman >/dev/null 2>&1; then
    err "This doesn't look like an Arch/CachyOS system (no pacman found). Aborting."
    exit 1
fi

# Everything per-user (autologin user, Steam, theme, shortcut) is for the
# user running the script.
TARGET_USER="$(id -un)"

detect_components
run_menu || { info "Nothing changed."; exit 0; }
plan_changes

if [[ ${#TO_DISABLE[@]} -eq 0 && ${#TO_ENABLE[@]} -eq 0 ]]; then
    ok "Everything is already the way you want it."
    exit 0
fi

echo
echo -e "${c_bold}This will:${c_reset}"
for c in "${TO_DISABLE[@]}"; do echo "  - turn off: ${LABEL[$c]}"; done
for c in "${TO_ENABLE[@]}"; do
    if is_action "$c"; then echo "  - run:      ${LABEL[$c]%%:*} (checks, then asks twice more)"
    elif [[ "${CURRENT[$c]}" == 1 ]]; then echo "  - re-apply: ${LABEL[$c]}"; else echo "  - turn on:  ${LABEL[$c]}"; fi
done
ask_yn "Go ahead?" y || { info "Nothing changed."; exit 0; }

# Ask for the sudo password once and keep it fresh, instead of prompting at
# random points during the run.
sudo -n true 2>/dev/null || sudo -v || exit 1
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

apply_changes

echo
detect_components
echo -e "${c_bold}Done. Current state:${c_reset}"
for c in "${COMPONENTS[@]}"; do
    component_available "$c" && ! is_action "$c" || continue
    if [[ "${CURRENT[$c]}" == 1 ]]; then echo -e "  ${c_green}on ${c_reset} ${LABEL[$c]}"; else echo "  off  ${LABEL[$c]}"; fi
done
if [[ ${#FAILED[@]} -gt 0 ]]; then
    warn "These had problems (see above): ${FAILED[*]}"
fi
echo

# A staged BIOS update is written during the restart.
if [[ -n "${BIOS_NEEDS_RESTART:-}" ]]; then
    warn "The BIOS update is written during the next restart. Keep the power on and"
    warn "don't touch the machine until it has fully started again, even if the screen stays black."
    if ask_yn "Restart now to install the BIOS update?" n; then
        sudo reboot
    else
        info "The BIOS update installs at your next restart."
    fi
    exit 0
fi

# Login manager changes only take effect after a restart.
if [[ " ${TO_DISABLE[*]} ${TO_ENABLE[*]} " == *" gaming "* || " ${TO_DISABLE[*]} ${TO_ENABLE[*]} " == *" single "* ]]; then
    if ask_yn "Restart now so the changes take effect?" n; then
        sudo reboot
    else
        info "Restart whenever you're ready."
    fi
fi
