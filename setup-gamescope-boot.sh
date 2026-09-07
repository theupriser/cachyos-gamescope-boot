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
# i.e. Steam Machine / BC-250-class boards), also offers to install the
# leds-valve DKMS driver from the AUR so the front LED bar is exposed under
# /sys/class/leds instead of sitting dark or "breathing" under a standard
# desktop kernel, plus the option to pull in an experimental OpenRGB build
# that has native support for driving it.

set -uo pipefail

# ---------- helpers ----------

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

backup_file() {
    local f="$1"
    if [[ -f "$f" && ! -f "${f}.bak-gamescope-wizard" ]]; then
        sudo cp -a "$f" "${f}.bak-gamescope-wizard"
        info "Backed up $f -> ${f}.bak-gamescope-wizard"
    fi
}

create_desktop_shortcut() {
    # Determine the home directory of the target user
    local user_home
    user_home=$(eval echo "~$TARGET_USER")

    # Locate the correct Desktop directory
    local desktop_dir
    if [[ -f "$user_home/.config/user-dirs.dirs" ]]; then
        desktop_dir=$(grep '^XDG_DESKTOP_DIR=' "$user_home/.config/user-dirs.dirs" | cut -d '"' -f 2)
        desktop_dir="${desktop_dir/\$HOME/$user_home}"
    fi
    desktop_dir="${desktop_dir:-$user_home/Desktop}"

    # Ensure secure icon path and desktop directories exist
    local secure_icon_dir="$user_home/.local/share/icons/hicolor/scalable/apps"
    mkdir -p "$secure_icon_dir"
    mkdir -p "$desktop_dir"

    # 1. Safely copy the icon to the user's permanent theme directory
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"

    if [[ -f "$script_dir/icons/steamdeck-gaming-return.svg" ]]; then
        info "Copying icon asset to permanent system theme path..."
        cp "$script_dir/icons/steamdeck-gaming-return.svg" "$secure_icon_dir/steamdeck-gaming-return.svg"
        chown "$TARGET_USER:$TARGET_USER" "$secure_icon_dir/steamdeck-gaming-return.svg"
    else
        warn "Icon asset not found at $script_dir/icons/steamdeck-gaming-return.svg - Shortcut will use fallback fallback."
    fi

    # 2. Generate the .desktop shortcut with instant session switcher strings
    local shortcut_path="$desktop_dir/Return to Gaming Mode.desktop"
    info "Creating 'Return to Gaming Mode' desktop shortcut at: $shortcut_path"

    cat << EOF > "$shortcut_path"
[Desktop Entry]
Name=Return to Gaming Mode
Comment=Switch session back to Gamescope
Exec=steamos-session-select gamescope && sudo systemctl start sync-steamos-session.service && sudo systemctl restart plasmalogin
Icon=steamdeck-gaming-return
Terminal=false
Type=Application
Categories=System;
EOF

    # Fix permissions for the target user and KDE Plasma desktop ecosystem
    chmod +x "$shortcut_path"
    chown "$TARGET_USER:$TARGET_USER" "$shortcut_path"

    # Refresh the system icon cache so Plasma detects the standalone asset immediately
    gtk-update-icon-cache -f -t "$user_home/.local/share/icons/hicolor" 2>/dev/null || true

    ok "Desktop shortcut created successfully."
}

install_vapor_theme() {
    # Installs Valve's official SteamOS "Vapor" Plasma theme (color scheme,
    # Plasma look-and-feel package, wallpapers, icons) straight from Valve's
    # own SteamOS package mirror, into the current user's ~/.local/share.
    # This only touches the invoking user's home directory, never system
    # files, so it's independent from everything else this script does.
    local pkg_ver="0.29"
    local domain="https://steamdeck-packages.steamos.cloud"
    local path_dir="archlinux-mirror/jupiter-main/os/x86_64"
    local file_name="steamdeck-kde-presets-${pkg_ver}-1-any.pkg.tar.zst"
    local url="${domain}/${path_dir}/${file_name}"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    info "Downloading official SteamOS Vapor presets (v${pkg_ver})..."
    if ! curl -fL "$url" -o "${tmp_dir}/presets.tar.zst"; then
        err "Download failed. Valve may have moved/renamed this package;"
        err "check ${domain} for the current version and update pkg_ver in the script."
        rm -rf "$tmp_dir"
        return 1
    fi

    info "Extracting package contents..."
    if ! tar -I unzstd -xf "${tmp_dir}/presets.tar.zst" -C "$tmp_dir"; then
        err "Extraction failed (is 'zstd' installed? try: sudo pacman -S --needed zstd)"
        rm -rf "$tmp_dir"
        return 1
    fi

    info "Creating local configuration directories..."
    mkdir -p ~/.local/share/color-schemes              ~/.local/share/plasma/desktoptheme              ~/.local/share/plasma/look-and-feel              ~/.local/share/wallpapers              ~/.local/share/icons/hicolor/scalable/apps              ~/.local/share/icons/hicolor/48x48/apps

    info "Installing Steam Deck theme assets..."
    [[ -d "${tmp_dir}/usr/share/color-schemes" ]] && cp -r "${tmp_dir}/usr/share/color-schemes/"* ~/.local/share/color-schemes/
    [[ -d "${tmp_dir}/usr/share/plasma/desktoptheme/Vapor" ]] && cp -r "${tmp_dir}/usr/share/plasma/desktoptheme/Vapor" ~/.local/share/plasma/desktoptheme/
    [[ -d "${tmp_dir}/usr/share/plasma/look-and-feel/com.valve.vapor.desktop" ]] && cp -r "${tmp_dir}/usr/share/plasma/look-and-feel/com.valve.vapor.desktop" ~/.local/share/look-and-feel/
    [[ -d "${tmp_dir}/usr/share/wallpapers" ]] && cp -r "${tmp_dir}/usr/share/wallpapers/"* ~/.local/share/wallpapers/
    [[ -d "${tmp_dir}/usr/share/icons/hicolor" ]] && cp -r "${tmp_dir}/usr/share/icons/hicolor/"* ~/.local/share/icons/hicolor/

    if [[ -d "./icons" ]]; then
        info "Copying local Steam Deck logo assets from ./icons into structured icon paths..."
        cp -r ./icons/* ~/.local/share/icons/hicolor/scalable/apps/ 2>/dev/null || true
        cp -r ./icons/* ~/.local/share/icons/hicolor/48x48/apps/ 2>/dev/null || true
    fi

    local metadata_dir="$HOME/.local/share/plasma/look-and-feel/com.valve.vapor.desktop"
    if [[ -d "$metadata_dir" ]]; then
        info "Patching look-and-feel metadata for Plasma 6 compatibility..."
        mkdir -p "$metadata_dir/contents"
        echo '{"KPlugin": {"Id": "com.valve.vapor.desktop", "Name": "Vapor (Steam Deck)", "ServiceTypes": ["Plasma/LookAndFeel"]}}' > "$metadata_dir/metadata.json"
    fi

    info "Cleaning up temporary files..."
    rm -rf "$tmp_dir"

    # Installs Valve's official SteamOS "Vapor" Plasma theme automatically
    # from the AUR without requiring user interactions or prompts.
    info "Installing official SteamOS Vapor theme via yay (non-interactive)..."

    if ! yay -S --noconfirm --needed --answerclean None --answerdiff None --answeredit None plasma6-themes-vapor-steamos; then
        err "Failed to install plasma6-themes-vapor-steamos package from the AUR."
        return 1
    fi

    # ---------- Integrated: Update Launcher Icon ----------
    local icon_name="steamdeck-gaming-return"
    local conf_file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    if ! find ~/.local/share/icons /usr/share/icons -iname "${icon_name}.*" 2>/dev/null | grep -q .; then
        warn "Could not find '${icon_name}' installed anywhere under ~/.local/share/icons or /usr/share/icons."
        warn "The launcher icon will be set anyway, but it may show as a broken icon until the file is installed."
    fi

    if [[ -f "$conf_file" ]]; then
        info "Looking for the Application Launcher applet (Kickoff/Kicker) to set the custom icon..."
        local matches=()
        local current_section=""
        local current_containment=""
        local current_applet=""

        while IFS= read -r line; do
            if [[ "$line" =~ ^\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]$ ]]; then
                current_containment="${BASH_REMATCH[1]}"
                current_applet="${BASH_REMATCH[2]}"
                current_section="applet_root"
                continue
            fi
            if [[ "$line" =~ ^\[ ]]; then
                current_section=""
                continue
            fi
            if [[ "$current_section" == "applet_root" && "$line" =~ ^plugin=(org\.kde\.plasma\.(kickoff|kicker|simplemenu|homerun|application-menu))$ ]]; then
                matches+=( "${current_containment}:${current_applet}:${BASH_REMATCH[1]}" )
                current_section=""
            fi
        done < "$conf_file"

        if [[ ${#matches[@]} -gt 0 ]]; then
            for m in "${matches[@]}"; do
                IFS=':' read -r containment applet plugin <<< "$m"
                info "Setting launcher icon on Containment $containment / Applet $applet ($plugin)..."
                kwriteconfig6 \
                    --file "$conf_file" \
                    --group Containments --group "$containment" \
                    --group Applets --group "$applet" \
                    --group Configuration --group General \
                    --key icon "$icon_name"
                ok "Icon set to '$icon_name'."
            done
        else
            warn "No compatible Application Launcher applet found in panel config. Skipping icon assignment."
        fi
    else
        warn "$conf_file not found. Skipping menu icon configuration."
    fi

    # ---------- Integrated: Set Default Vapor Wallpaper (Fixed for Plasma 6) ----------
    local wallpaper_path="$HOME/.local/share/wallpapers/Vapor/contents/images/2560x1600.png"

    if [[ ! -f "$wallpaper_path" ]]; then
        wallpaper_path=$(find "$HOME/.local/share/wallpapers/Vapor/contents/images" -type f \( -name "*.png" -o -name "*.jpg" \) | head -n 1)
    fi

    if [[ -f "$wallpaper_path" ]]; then
        info "Applying official Steam Deck Vapor wallpaper via D-Bus script..."
        local dbus_cmd="
            var allDesktops = desktops();
            for (var i = 0; i < allDesktops.length; i++) {
                var d = allDesktops[i];
                d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
                d.writeConfig('Image', 'file://${wallpaper_path}');
            }
        "
        if command -v qdbus6 >/dev/null 2>&1; then
            qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$dbus_cmd" >/dev/null 2>&1 || true
        else
            qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$dbus_cmd" >/dev/null 2>&1 || true
        fi

        if [[ -f "$conf_file" ]]; then
            local desktop_sections=$(grep -E '^\[Containments\]\[[0-9]+\]$' "$conf_file" || true)
            while read -r section; do
                if [[ -n "$section" ]]; then
                    local clean_sec=$(echo "$section" | tr -d '[]')
                    kwriteconfig6 --file "$conf_file" --group "$clean_sec" --group Wallpaper --group org.kde.image --group General --key Image "file://${wallpaper_path}"
                fi
            done <<< "$desktop_sections"
        fi
        ok "Wallpaper path pushed to session config."
    else
        warn "Could not find extracted Vapor wallpaper file. Skipping."
    fi

    info "Refreshing Plasma environment and icon caches..."
    gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true
    kbuildsycoca6 --noincremental 2>/dev/null || true
    rm -rf ~/.cache/plasmashell* ~/.cache/org.kde.dirmodel-qml.kcache
    setsid plasmashell --replace >/dev/null 2>&1 &

     # ---------- Automatisch het Vapor thema activeren ----------
    # info "Vapor-thema direct toepassen op de huidige desktop..."

    # Activeer het globale Plasma look-and-feel thema
    if command -v lookandfeeltool >/dev/null 2>&1; then
        lookandfeeltool -a com.valve.vapor.desktop || true
    fi

    # Zorg dat de iconen en kleurschema's expliciet naar Vapor overschakelen
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "Vapor"
    kwriteconfig6 --file kdeglobals --group General --key ColorScheme "Vapor"

    # Forceer Plasma om de nieuwe instellingen direct in te laden
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true

    ok "Vapor theme assets installed. Apply it under System Settings > Appearance"
    ok "> Global Theme > Vapor (Steam Deck), next time you're in a Plasma session."
}


detect_valve_fremont() {
    # Valve Steam Machine / BC-250-class boards report these DMI strings.
    # Standard desktop kernels (including CachyOS's) lack the leds-valve
    # driver, so the front LED bar just goes dark or breathes on idle.
    local vendor product
    vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    [[ "$vendor" == "Valve" && "$product" == "Fremont" ]]
}

aur_noninteractive_flags() {
    # Fully non-interactive install flags for the given AUR helper: no
    # PKGBUILD diff/edit/cleanbuild prompts, no provider-selection prompts
    # (e.g. picking kernel headers for DKMS), and makepkg itself silenced.
    case "$1" in
        yay)
            echo --needed --noconfirm --answerclean None --answerdiff None \
                 --answeredit None --mflags "--noconfirm"
            ;;
        paru)
            echo --needed --noconfirm --skipreview --mflags "--noconfirm"
            ;;
    esac
}

bootstrap_yay() {
    # Builds and installs yay from the AUR using only makepkg + base-devel
    # (both from the official repos), so we have an AUR helper available
    # without assuming the user already set one up.
    info "Installing base-devel and git (needed to build an AUR helper)..."
    sudo pacman -S --needed --noconfirm base-devel git || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    info "Cloning yay-bin from the AUR..."
    if ! git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp_dir/yay-bin"; then
        err "Failed to clone yay-bin from the AUR."
        rm -rf "$tmp_dir"
        return 1
    fi

    info "Building and installing yay (this runs makepkg as your user, not root)..."
    if (cd "$tmp_dir/yay-bin" && makepkg -si --noconfirm); then
        ok "yay installed."
        rm -rf "$tmp_dir"
        return 0
    else
        err "Building yay failed. See errors above."
        rm -rf "$tmp_dir"
        return 1
    fi
}

install_valve_led_driver() {
    # Installs the leds-valve DKMS driver from the AUR so the front LED
    # bar is exposed under /sys/class/leds, then offers the two known
    # ways to get Steam to actually drive it (gamepadui, which this
    # script already forces via STEAM_GAMEPADUI_ARGS, or OpenRGB's
    # experimental build which has native support for the panel).
    # Assumes an AUR helper was already ensured back in step 2.
    local aur_helper=""
    if command -v yay >/dev/null 2>&1; then
        aur_helper="yay"
    elif command -v paru >/dev/null 2>&1; then
        aur_helper="paru"
    fi

    if [[ -z "$aur_helper" ]]; then
        warn "No AUR helper available - can't install leds-valve-dkms-git."
        warn "Install one yourself, then run: yay -S leds-valve-dkms-git"
        return 1
    fi

    if ! pacman -Qi leds-valve-dkms-git >/dev/null 2>&1; then
        info "Installing leds-valve-dkms-git from the AUR via $aur_helper (non-interactive)..."
        local -a flags
        read -ra flags <<< "$(aur_noninteractive_flags "$aur_helper")"
        "$aur_helper" -S "${flags[@]}" leds-valve-dkms-git
    else
        ok "leds-valve-dkms-git already installed."
    fi

    info "Loading the leds-valve kernel module..."
    if sudo modprobe leds-valve 2>/dev/null; then
        ok "Module loaded."
    else
        warn "modprobe leds-valve failed - a reboot is often needed to pick up a freshly built DKMS module."
    fi

    if ls /sys/class/leds/ 2>/dev/null | grep -qi valve; then
        ok "LED bar nodes detected: $(ls /sys/class/leds/ | grep -i valve | tr '\n' ' ')"
    else
        warn "No valve-led nodes under /sys/class/leds/ yet. Reboot, then check with:"
        warn "  ls /sys/class/leds/ | grep -i valve"
    fi

    echo
    info "Steam only pushes download progress to the LED bar in real SteamOS Game Mode."
    # info "On a desktop install you have two options:"
    # info "  1) Launch Steam's Big Picture UI (this script's -gamepadui -steamos3 flag already covers this)"
    # info "  2) Install an experimental/git OpenRGB build from the AUR, which natively detects this panel"
    # if ask_yn "Also install the experimental OpenRGB build from the AUR now?" n; then
        local -a flags
        read -ra flags <<< "$(aur_noninteractive_flags "$aur_helper")"
        "$aur_helper" -S "${flags[@]}" openrgb-git
        # ok "openrgb-git installed. Launch OpenRGB to detect and configure the front panel."
    # fi
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

# ---------- 2. Install packages (Always Runs) ----------

info "Checking required packages: gamescope-session-cachyos, steam, mangohud, xterm, ttf-liberation, wqy-zenhei, plasma-keyboard"
MISSING=()
for pkg in gamescope-session-cachyos steam mangohud xterm ttf-liberation wqy-zenhei plasma-keyboard; do
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

if detect_valve_fremont; then
    info "Detected Valve Fremont hardware - checking for an AUR helper (needed for leds-valve-dkms-git)"
    if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
        ok "AUR helper already present."
    else
        info "No AUR helper (yay/paru) found. Installing yay..."
        bootstrap_yay || warn "Couldn't set up an AUR helper automatically. You can install one yourself later and run: yay -S leds-valve-dkms-git"
    fi
    echo
fi

# ---------- 3. Ensure plasmalogin.conf.d exists (fixes Switch-to-Desktop crash) ----------

info "Ensuring /etc/plasmalogin.conf.d exists (fixes the 'Switching to Desktop' hang bug)"
sudo mkdir -p /etc/plasmalogin.conf.d
ok "Directory present."
echo

# ---------- 4. Fix the base /etc/plasmalogin.conf ----------

BASE_CONF="/etc/plasmalogin.conf"
info "Configuring $BASE_CONF (Session=gamescope-session.desktop, User=$TARGET_USER, Relogin=true)"
backup_file "$BASE_CONF"

sudo touch "$BASE_CONF"

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

SYNC_SCRIPT="/usr/local/bin/sync-steamos-session.sh"
info "Installing session sync bridge at $SYNC_SCRIPT"

sudo tee "$SYNC_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
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


# ---------- 8b. Core SteamOS Keyboard & Glyphs Fix (Always runs) ----------

info "Applying non-optional SteamOS environment & keyboard fixes..."
steam_env_dir="$HOME/.config/environment.d"
mkdir -p "$steam_env_dir"

# 1. Force Gamescope Steam to boot into Deck mode and load Deck glyphs
echo "STEAM_GAMEPADUI_ARGS=\"-gamepadui -steamos3\"" > "$steam_env_dir/99-gamescope-steam-glyphs.conf"
if [[ -d "$HOME/.config/gamescope-session" ]]; then
    echo "STEAM_GAMEPADUI_ARGS=\"-gamepadui -steamos3\"" >> "$HOME/.config/gamescope-session/environment"
fi

# 2. Prevent KDE Wayland from blocking the virtual keyboard overlay
echo "KWIN_IM_SHOW_ALWAYS=1" > "$steam_env_dir/99-kde-virtual-keyboard.conf"

# 3. Setup robust background systemd service for Steam autostart on Desktop Mode
systemd_user_dir="$HOME/.config/systemd/user"
mkdir -p "$systemd_user_dir"

cat << 'EOF' > "$systemd_user_dir/steam-desktop-autostart.service"
[Unit]
Description=Steam Background Autostart for Virtual Keyboard
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/steam -silent
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

# Clean out old .desktop shortcut so they don't fight
rm -f "$HOME/.config/autostart/steam.desktop"

# Reload user systemd context and activate the background loop
systemctl --user daemon-reload
systemctl --user enable steam-desktop-autostart.service
systemctl --user start steam-desktop-autostart.service

ok "Steam UI parameters and keyboard autostart deployed successfully."
echo


# ---------- 8c. Valve Fremont hardware: front LED bar driver ----------

# if detect_valve_fremont; then
#     echo
#     info "Detected Valve Fremont hardware (Steam Machine / BC-250-class board)."
#     if ask_yn "Set up the front-panel LED bar driver (leds-valve) so it isn't stuck dark/breathing?" y; then
#         install_valve_led_driver || warn "LED driver setup ran into a problem - see errors above. Your gamescope boot setup above is unaffected."
#     fi
#     echo
# fi


# ---------- 9. Optional: Vapor (Steam Deck) KDE theme ----------

echo
if ask_yn "Also install Valve's official Vapor (Steam Deck) KDE theme for your desktop session?" n; then
    if ! command -v curl >/dev/null 2>&1; then
        warn "curl not found, installing it first..."
        sudo pacman -S --needed curl
    fi
    if ! command -v unzstd >/dev/null 2>&1; then
        warn "zstd not found, installing it first..."
        sudo pacman -S --needed zstd
    fi
    install_vapor_theme || warn "Vapor theme install ran into a problem - see errors above. Your gamescope boot setup above is unaffected."
fi
echo


# ---------- 10. Create Return to Gaming Mode Desktop Shortcut ----------

create_desktop_shortcut
echo


# ---------- 11. Summary + reboot ----------

echo -e "${c_bold}Setup complete.${c_reset}"
echo "What this did:"
echo "  - Installed gamescope-session-cachyos, steam, mangohud (if missing)"
echo "  - Created /etc/plasmalogin.conf.d (fixes Switch-to-Desktop crash)"
echo "  - Set $BASE_CONF to autologin '$TARGET_USER' into gamescope, with Relogin=true"
echo "  - Installed a sync bridge + systemd watcher so Steam's Switch-to-Desktop"
echo "    (and cachyos-gamescope-autologin.service resetting back to gamescope"
echo "    on logout) both actually take effect"
echo "  - Configured permanent silent Steam autostart so Steam+X works everywhere"
echo "  - Injected -steamos3 flag to force original Steam Deck overlay glyphs"
echo "  - Optionally installed Valve's Vapor (Steam Deck) KDE theme, if you chose to"
echo "  - On Valve Fremont hardware, optionally set up the leds-valve front LED bar driver"
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
