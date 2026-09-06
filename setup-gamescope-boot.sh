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

set -uo pipefail

# ---------- helpers ----------

c_reset="\033[0m"; c_bold="\033[1m"; c_green="\033[32m"; c_yellow="\033[33m"; c_red="\033[31m"; c_cyan="\033[36m"

info()  { echo -e "${c_cyan}==>${c_reset} $*"; }
ok()    { echo -e "${c_green}✔${c_reset} $*"; }
warn()  { echo -e "${c_yellow}!${c_reset} $*"; }
err()   { echo -e "${c_red}✘ $*${c_reset}" >&2; }
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

backup_file() {
    local f="$1"
    if [[ -f "$f" && ! -f "${f}.bak-gamescope-wizard" ]]; then
        sudo cp -a "$f" "${f}.bak-gamescope-wizard"
        info "Backed up $f -> ${f}.bak-gamescope-wizard"
    fi
}

# ---------- start ----------

require_root_helper

echo -e "${c_bold}CachyOS Steam Deck-style Gamescope Boot Wizard${c_reset}"
echo "This sets your machine up to always boot into gamescope (like SteamOS),"
echo "with working Switch-to-Desktop and switch-back, surviving reboots."
echo

if ! command -v pacman >/dev/null 2>&1; then
    err "This doesn't look like an Arch/CachyOS system (no pacman found). Aborting."
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
read -rp "$(echo -e "${c_bold}Which user should autologin into gamescope?${c_reset} [${TARGET_USER}] ")" input_user
TARGET_USER="${input_user:-$TARGET_USER}"

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    err "User '$TARGET_USER' does not exist on this system."
    exit 1
fi
ok "Using user: $TARGET_USER"
echo

# ---------- 1. Login manager check ----------

DM="$(systemctl show -p Id --value display-manager 2>/dev/null | sed 's/\.service$//')"
info "Detected display manager: ${DM:-none}"

if [[ "$DM" != "plasmalogin" ]]; then
    warn "This wizard was built and tested against plasma-login-manager (plasmalogin)."
    warn "Detected display manager is '${DM:-unknown}'. SDDM setups don't need"
    warn "most of these workarounds (SDDM's own Autologin works out of the box);"
    warn "this script will still try, but review the output carefully."
    ask_yn "Continue anyway?" n || exit 0
fi
echo

# ---------- 2. Install packages ----------

info "Checking required packages: gamescope-session-cachyos, steam, mangohud"
MISSING=()
for pkg in gamescope-session-cachyos steam mangohud; do
    pacman -Qi "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Missing packages: ${MISSING[*]}"
    if ask_yn "Install them now?"; then
        sudo pacman -S --needed "${MISSING[@]}"
    else
        err "Cannot continue without these packages."
        exit 1
    fi
else
    ok "All required packages already installed."
fi
echo

# ---------- 3. Ensure plasmalogin.conf.d exists (fixes Switch-to-Desktop crash) ----------

info "Ensuring /etc/plasmalogin.conf.d exists (fixes the 'Switching to Desktop' hang bug)"
sudo mkdir -p /etc/plasmalogin.conf.d
ok "Directory present."
echo

# ---------- 4. Fix the base /etc/plasmalogin.conf ----------
#
# steam-set-session only ever writes to /etc/plasmalogin.conf.d/*.conf,
# but the base /etc/plasmalogin.conf takes priority and, as shipped by
# CachyOS, hardcodes Session=plasma with no User= and no Relogin=. We
# rewrite the [Autologin] block cleanly here.

BASE_CONF="/etc/plasmalogin.conf"
info "Configuring $BASE_CONF (Session=gamescope-session.desktop, User=$TARGET_USER, Relogin=true)"
backup_file "$BASE_CONF"

sudo touch "$BASE_CONF"

# Strip any existing [Autologin] section (from the first [Autologin] line
# to the next section header or EOF), then append a clean one. This is
# safer than a series of seds for an unknown starting state.
sudo awk '
    BEGIN { in_autologin=0 }
    /^\[Autologin\]/ { in_autologin=1; next }
    /^\[/ { in_autologin=0 }
    !in_autologin { print }
' "$BASE_CONF" | sudo tee "${BASE_CONF}.tmp" > /dev/null

sudo mv "${BASE_CONF}.tmp" "$BASE_CONF"

sudo tee -a "$BASE_CONF" > /dev/null << EOF
[Autologin]
Session=gamescope-session.desktop
User=$TARGET_USER
Relogin=true
EOF

ok "Base autologin config written:"
sudo sed -n '/\[Autologin\]/,/^\[/p' "$BASE_CONF" | head -n -1 2>/dev/null || sudo cat "$BASE_CONF"
echo

# ---------- 5. Clean up any stray conf.d autologin fragments from manual attempts ----------

info "Removing any leftover manual conf.d autologin overrides (base config now handles it)"
sudo rm -f /etc/plasmalogin.conf.d/zzz-steamos-autologin*.conf
ok "Cleaned."
echo

# ---------- 6. Install the sync bridge: conf.d -> base config ----------
#
# CachyOS's own tools (steamos-session-select, Steam's "Switch to
# Desktop", and cachyos-gamescope-autologin.service) only ever write the
# session choice to /etc/plasmalogin.conf.d/zz-steamos-autologin.conf.
# Since the base config wins, we need a watcher that copies that value
# into the base file whenever it changes.

SYNC_SCRIPT="/usr/local/bin/sync-steamos-session.sh"
info "Installing session sync bridge at $SYNC_SCRIPT"

sudo tee "$SYNC_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
# Copies the Session= value CachyOS's steamos tools write into
# /etc/plasmalogin.conf.d/zz-steamos-autologin.conf back into the base
# /etc/plasmalogin.conf, which plasma-login-manager actually obeys.
SRC="/etc/plasmalogin.conf.d/zz-steamos-autologin.conf"
DEST="/etc/plasmalogin.conf"

[[ -f "$SRC" ]] || exit 0
SESSION=$(grep -oP '^Session=\K.*' "$SRC")
[[ -z "$SESSION" ]] && exit 0

if grep -q '^Session=' "$DEST"; then
    sed -i "s|^Session=.*|Session=$SESSION|" "$DEST"
else
    echo "Session=$SESSION" >> "$DEST"
fi
EOF

sudo chmod +x "$SYNC_SCRIPT"
ok "Sync script installed."
echo

# ---------- 7. systemd path watcher + service ----------

info "Installing systemd path watcher so session switches take effect immediately"

sudo tee /etc/systemd/system/sync-steamos-session.path > /dev/null << 'EOF'
[Unit]
Description=Watch for steamos session changes

[Path]
PathModified=/etc/plasmalogin.conf.d/zz-steamos-autologin.conf

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/sync-steamos-session.service > /dev/null << 'EOF'
[Unit]
Description=Sync steamos session selection into plasmalogin.conf

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-steamos-session.sh
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now sync-steamos-session.path
ok "Path watcher enabled."
echo

# ---------- 8. Run it once now so current state is in sync ----------

info "Running the sync once now to align current state"
sudo systemctl start sync-steamos-session.service
ok "Done. Current base config:"
sudo cat "$BASE_CONF"
echo

# ---------- 9. Summary + reboot ----------

echo -e "${c_bold}Setup complete.${c_reset}"
echo "What this did:"
echo "  - Installed gamescope-session-cachyos, steam, mangohud (if missing)"
echo "  - Created /etc/plasmalogin.conf.d (fixes Switch-to-Desktop crash)"
echo "  - Set $BASE_CONF to autologin '$TARGET_USER' into gamescope, with Relogin=true"
echo "  - Installed a sync bridge + systemd watcher so Steam's Switch-to-Desktop"
echo "    (and cachyos-gamescope-autologin.service resetting back to gamescope"
echo "    on logout) both actually take effect"
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
