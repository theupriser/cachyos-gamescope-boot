#!/bin/bash
# Output helpers, prompts and small shared utilities.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

c_reset="\033[0m"; c_bold="\033[1m"; c_green="\033[32m"; c_yellow="\033[33m"; c_red="\033[31m"; c_cyan="\033[36m"

info()  { echo -e "${c_cyan}[INFO]${c_reset} $*"; }
ok()    { echo -e "${c_green}[OK]${c_reset} $*"; }
warn()  { echo -e "${c_yellow}[WARN]${c_reset} $*"; }
err()   { echo -e "${c_red}[ERROR] $*${c_reset}" >&2; }
ask_yn() {
    local prompt="$1" default="${2:-y}" reply
    local hint="[Y/n]"; [[ "$default" == "n" ]] && hint="[y/N]"
    read -rp "$(echo -e "${c_bold}${prompt}${c_reset} ${hint} ")" reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

require_root_helper() {
    # Re-exec any privileged step through sudo rather than requiring the
    # whole script to run as root, so $HOME/whoami stay correct for the
    # target user detection below.
    if [[ $EUID -eq 0 && -z "${SUDO_USER:-}" ]]; then
        err "Please run this script as your normal user (it will call sudo itself), not directly as root."
        exit 1
    fi
}

plasma_applets() {
    # Print "containment:applet" for every applet of plugin $1 in the
    # user's Plasma layout, for kwriteconfig6 --group paths.
    local conf="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    [[ -f "$conf" ]] || return 0
    awk -v plugin="$1" '
        /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { split($0, p, /[][]+/); sect = p[3] ":" p[5] }
        /^\[/ && !/\]\[Applets\]\[[0-9]+\]$/ { sect = "" }
        $0 == "plugin=" plugin && sect != "" { print sect }
    ' "$conf"
}

backup_file() {
    local f="$1"
    if [[ -f "$f" && ! -f "${f}.bak-gamescope-wizard" ]]; then
        sudo cp -a "$f" "${f}.bak-gamescope-wizard"
        info "Backed up $f -> ${f}.bak-gamescope-wizard"
    fi
}

# plasmashell keeps its config in memory and writes it back on exit, so
# edits to its files (panels, applets, wallpaper) must be made while it is
# stopped. It is restarted through systemd so it keeps the session's
# environment (platform theme etc.); a plain --replace from this shell
# may not, which gives a light-themed desktop.
stop_plasmashell_for_edit() {
    PLASMASHELL_WAS_RUNNING=false
    if pgrep -u "$USER" -x plasmashell >/dev/null; then
        PLASMASHELL_WAS_RUNNING=true
        systemctl --user stop plasma-plasmashell.service 2>/dev/null
        pkill -u "$USER" -x plasmashell && sleep 2
    fi
}

restart_plasmashell_if_stopped() {
    if [[ "${PLASMASHELL_WAS_RUNNING:-false}" == true ]]; then
        rm -rf ~/.cache/plasmashell* ~/.cache/org.kde.dirmodel-qml.kcache
        systemctl --user start plasma-plasmashell.service 2>/dev/null ||
            { setsid plasmashell >/dev/null 2>&1 & }
    fi
}
