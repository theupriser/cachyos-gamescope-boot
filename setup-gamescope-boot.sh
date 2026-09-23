#!/bin/bash
#
# setup-gamescope-boot.sh
#
# Wizard to configure a CachyOS (KDE Plasma + plasma-login-manager) install
# to always boot into a Steam Deck-style gamescope session, with the
# ability to switch to Plasma desktop and back, Deck-style, and have it
# reset to gamescope on the next boot/logout.
#
# Covers three real bugs found on CachyOS as of Sep 2026:
#   1. steam-set-session never writes User= to plasmalogin's autologin
#      config, so plasma-login-manager never actually autologs in.
#   2. steam-set-session fails outright if /etc/plasmalogin.conf.d is
#      missing, breaking "Switch to Desktop" from inside gamescope.
#   3. /etc/plasmalogin.conf (the base config) hardcodes Session=plasma
#      and takes priority over anything written to
#      /etc/plasmalogin.conf.d/*.conf, so session switches never stick
#      without a bridge that copies the conf.d value back into the base
#      file, plus Relogin=true so ending a session re-triggers autologin
#      instead of dropping to the greeter.
#
# Safe to re-run: it is idempotent and backs up files before editing.
#
# Automatically configures a permanent background systemd autostart for Steam
# and Wayland overrides so the Steam Controller virtual keyboard (Steam+X)
# always works in desktop mode.
#
# Optionally also offers to install the official Valve "Vapor" KDE Plasma
# theme (colors, icons, wallpapers, Plasma look-and-feel package) used on
# real SteamOS, pulled directly from Valve's own package mirror, so the
# desktop side matches the gamescope side visually.
#
# On Valve Fremont hardware (DMI sys_vendor=Valve, product_name=Fremont --
# i.e. the Steam Machine), also offers to install the
# leds-valve DKMS driver from the AUR so the front LED bar is exposed under
# /sys/class/leds instead of sitting dark or "breathing" under a standard
# desktop kernel, plus the option to pull in an experimental OpenRGB build
# that has native support for driving it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for lib in common packages login-manager steam-desktop led-driver vapor-theme desktop-shortcut; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/$lib.sh"
done

require_root_helper

echo -e "${c_bold}CachyOS Steam Deck-style Gamescope Boot Wizard${c_reset}"
echo "This sets your machine up to always boot into gamescope (like SteamOS),"
echo "with working Switch-to-Desktop and switch-back, surviving reboots."
echo

if ! command -v pacman >/dev/null 2>&1; then
    err "This doesn't look like an Arch/CachyOS system (no pacman found). Aborting."
    exit 1
fi

# Ask for the sudo password once up front and keep it fresh, instead of
# prompting at random points during the run.
sudo -n true 2>/dev/null || sudo -v || exit 1
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

TARGET_USER="${SUDO_USER:-$USER}"
read -rp "$(echo -e "${c_bold}Which user should autologin into gamescope?${c_reset} [${TARGET_USER}] ")" input_user
TARGET_USER="${input_user:-$TARGET_USER}"

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    err "User '$TARGET_USER' does not exist on this system."
    exit 1
fi
if [[ "$TARGET_USER" != "$(id -un)" ]]; then
    # Environment, systemd user units, theme and shortcut are all written
    # into the invoking user's home and user session.
    err "Run this script as '$TARGET_USER' itself so per-user settings land in the right home."
    exit 1
fi
ok "Using user: $TARGET_USER"
echo

check_display_manager
echo

install_required_packages
echo

configure_autologin
install_session_sync

setup_steam_desktop
echo

setup_led_driver

setup_vapor_theme
echo

create_desktop_shortcut
echo

# ---------- 11. Summary + reboot ----------

echo -e "${c_bold}Setup complete.${c_reset}"
echo "What this did:"
echo "  - Installed gamescope-session-cachyos, steam, mangohud and friends (if missing)"
echo "  - Created /etc/plasmalogin.conf.d (fixes Switch-to-Desktop crash)"
echo "  - Set $BASE_CONF to autologin '$TARGET_USER' into gamescope, with Relogin=true"
echo "  - Installed a sync bridge + systemd watcher so Steam's Switch-to-Desktop"
echo "    (and cachyos-gamescope-autologin.service resetting back to gamescope"
echo "    on logout) both actually take effect"
echo "  - Configured permanent silent Steam autostart so Steam+X works everywhere"
echo "  - Injected -steamos3 flag to force original Steam Deck overlay glyphs"
echo "  - Optionally installed Valve's Vapor (Steam Deck) KDE theme, if you chose to"
echo "  - On Valve Fremont hardware, optionally set up the leds-valve front LED bar driver"
echo "  - Added /etc/sudoers.d/gamescope-session-switch so the desktop shortcut works"
echo
echo "Backups of any files this script modified were saved with a"
echo ".bak-gamescope-wizard suffix next to the original."
echo
echo "To manually flip sessions any time:"
echo "  steamos-session-select gamescope   # boot straight into gamescope now"
echo "  steamos-session-select plasma      # boot straight into desktop now"
echo "  steamos-session-select persistent  # remember last-used session across reboots"
echo "  steamos-session-select oneshot     # always start in gamescope regardless (default Deck behavior)"
echo

if ask_yn "Reboot now to test it?" n; then
    sudo reboot
else
    info "Skipping reboot. Run 'sudo reboot' whenever you're ready to test."
fi
