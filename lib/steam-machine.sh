#!/bin/bash
# "Steam Machine support" menu item, only on Valve Fremont hardware: the
# front LED bar driver, LED access for Steam, and steamos-manager.
# Sourced by steamify.sh; not meant to be run on its own.

detect_valve_fremont() {
    # Valve Steam Machine (Fremont) boards. The leds-valve driver's own DMI
    # table also matches the OEM/F7F strings some early units report, so
    # accept both -- otherwise we'd skip hardware the driver supports.
    local vendor product
    vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    [[ "$vendor" == "Valve" && "$product" == "Fremont" ]] ||
        [[ "$vendor" == "OEM" && "$product" == "F7F" ]]
}

# Kernel pinned on a Steam Machine: with newer linux-cachyos releases it
# reboots instead of shutting down. The packages are kept in
# PINNED_KERNEL_DIR, so re-applying (or reinstalling after an update slipped
# through) needs no download.
PINNED_KERNEL_VER="7.1.6-1"
PINNED_KERNEL_KVER="7.1.6-1-cachyos"
PINNED_KERNEL_PKGS=(linux-cachyos linux-cachyos-headers)
PINNED_KERNEL_DIR="${PINNED_KERNEL_DIR:-/var/cache/steamify/kernel}"
# SHA-256 of each package, so a file from any source is the one reviewed
# here; its CachyOS signature is checked as well.
declare -A PINNED_KERNEL_SHA256=(
    [linux-cachyos]=417fcd07102192b86e78e92ed7171d5a49378e9f57faea3fa2c7c541e9f68d08
    [linux-cachyos-headers]=d069866a11d9092746e1d5133cefd8924f027da2c9bf5af38d30b3aed6ded9bf
)
# Tried in order, after the kernel dir and pacman's cache. Our own release
# always has these files; the archive keeps every release; the mirror only
# the current one. PINNED_KERNEL_URL puts another source (a directory
# holding the files) in front.
PINNED_KERNEL_SOURCES=(
    ${PINNED_KERNEL_URL:+"$PINNED_KERNEL_URL"}
    "https://github.com/theupriser/steamify-cachyos/releases/download/kernel-$PINNED_KERNEL_VER"
    "https://archive.cachyos.org/archive/cachyos"
    "https://mirror.cachyos.org/repo/x86_64/cachyos"
)

pinned_kernel_installed() {
    local p
    for p in "${PINNED_KERNEL_PKGS[@]}"; do
        [[ "$(pacman -Q "$p" 2>/dev/null)" == "$p $PINNED_KERNEL_VER" ]] || return 1
    done
}

fetch_pinned_kernel_file() {
    # $1 = file name. Local kernel dir first, then pacman's cache, then the
    # download sources. Downloads go to a .part file so a broken one is never
    # mistaken for a finished one.
    local f="$1" dest="$PINNED_KERNEL_DIR/$1" src
    [[ -s "$dest" ]] && return 0
    if [[ -s "/var/cache/pacman/pkg/$f" ]]; then
        sudo cp "/var/cache/pacman/pkg/$f" "$dest" && return 0
    fi
    for src in "${PINNED_KERNEL_SOURCES[@]}"; do
        if sudo curl -fL --retry 2 --connect-timeout 15 -o "$dest.part" "$src/$f" 2>/dev/null; then
            sudo mv "$dest.part" "$dest"
            return 0
        fi
        warn "Couldn't get $f from $src, trying the next source..."
    done
    sudo rm -f "$dest.part"
    return 1
}

verify_pinned_kernel_pkg() {
    # $1 = package name, $2 = file. Both checks must pass: the SHA-256 from
    # this script, and the CachyOS signature (pacman on its own installs a
    # local file without a .sig: LocalFileSigLevel = Optional).
    local sum
    sum="$(sha256sum "$2" | cut -d' ' -f1)"
    if [[ "$sum" != "${PINNED_KERNEL_SHA256[$1]}" ]]; then
        err "$(basename "$2") doesn't match its expected checksum."
        return 1
    fi
    if ! sudo pacman-key --verify "$2.sig" "$2" >/dev/null 2>&1; then
        err "$(basename "$2") doesn't have a valid CachyOS signature."
        return 1
    fi
}

pin_kernel_in_pacman_conf() {
    # Adds our packages to IgnorePkg in [options], keeping what's there.
    local p
    for p in "${PINNED_KERNEL_PKGS[@]}"; do
        grep -Eq "^IgnorePkg\s*=.*(\s|=)$p(\s|$)" /etc/pacman.conf && continue
        if grep -Eq '^IgnorePkg\s*=' /etc/pacman.conf; then
            sudo sed -i -E "0,/^IgnorePkg\s*=/s/^(IgnorePkg\s*=.*)$/\1 $p/" /etc/pacman.conf
        else
            sudo sed -i -E "0,/^\[options\]/s//[options]\nIgnorePkg = $p/" /etc/pacman.conf
        fi
    done
}

unpin_kernel_in_pacman_conf() {
    local p
    for p in "${PINNED_KERNEL_PKGS[@]}"; do
        sudo sed -i -E "/^IgnorePkg\s*=/s/\s$p(\s|$)/\1/" /etc/pacman.conf
    done
    # Drop the line if nothing is left on it.
    sudo sed -i -E '/^IgnorePkg\s*=\s*$/d' /etc/pacman.conf
}

install_pinned_kernel() {
    sudo mkdir -p "$PINNED_KERNEL_DIR"
    pin_kernel_in_pacman_conf
    if pinned_kernel_installed; then
        ok "Kernel $PINNED_KERNEL_VER already installed and pinned."
        return 0
    fi

    local p f files=()
    info "Getting kernel $PINNED_KERNEL_VER (kept in $PINNED_KERNEL_DIR)..."
    for p in "${PINNED_KERNEL_PKGS[@]}"; do
        f="$p-$PINNED_KERNEL_VER-x86_64.pkg.tar.zst"
        fetch_pinned_kernel_file "$f" && fetch_pinned_kernel_file "$f.sig" ||
            { err "Couldn't download $f from any source."; return 1; }
        if ! verify_pinned_kernel_pkg "$p" "$PINNED_KERNEL_DIR/$f"; then
            # Removed, so the next run fetches it again.
            sudo rm -f "$PINNED_KERNEL_DIR/$f" "$PINNED_KERNEL_DIR/$f.sig"
            err "Removed it; run the wizard again to download it once more."
            return 1
        fi
        files+=("$PINNED_KERNEL_DIR/$f")
    done

    # pacman checks each package against the .sig next to it.
    info "Installing kernel $PINNED_KERNEL_VER..."
    if ! sudo pacman -U --noconfirm "${files[@]}"; then
        err "Installing kernel $PINNED_KERNEL_VER failed."
        return 1
    fi
    [[ "$(uname -r)" != "$PINNED_KERNEL_KVER" ]] && RESTART_FOR_LOGIN=true
    ok "Kernel $PINNED_KERNEL_VER installed and pinned (restart to use it)."
}

remove_kernel_pin() {
    # Back to CachyOS's current kernel. The packages stay in
    # PINNED_KERNEL_DIR, so turning support on again doesn't download.
    unpin_kernel_in_pacman_conf
    pinned_kernel_installed || return 0
    info "Updating the kernel back to CachyOS's current version..."
    sudo pacman -Syu --noconfirm ||
        { warn "Updating the kernel failed; run: sudo pacman -Syu"; return 0; }
    RESTART_FOR_LOGIN=true
}

# "Pin the kernel" menu item, a sub-option of Steam Machine support.
kpin_status() {
    pinned_kernel_installed && grep -Eq '^IgnorePkg\s*=.*\slinux-cachyos(\s|$)' /etc/pacman.conf
}

kpin_enable() {
    install_pinned_kernel || return 1
    # The DKMS pacman hook built leds-valve for the new headers; make sure.
    if pacman -Qi leds-valve-dkms-git >/dev/null 2>&1 &&
        ! dkms status -k "$PINNED_KERNEL_KVER" leds-valve-dkms 2>/dev/null | grep -q installed; then
        sudo dkms install leds-valve-dkms/0.1 -k "$PINNED_KERNEL_KVER" ||
            warn "Building the LED driver for $PINNED_KERNEL_KVER failed."
    fi
}

kpin_disable() { remove_kernel_pin; }

install_kernel_headers() {
    # DKMS can only build leds-valve against kernels whose headers are
    # installed. CachyOS ships several kernels (linux-cachyos, -lts, -bore,
    # ...); install the matching -headers package for every one present.
    local -a kernels headers=()
    local k
    mapfile -t kernels < <(pacman -Qqo /usr/lib/modules/*/pkgbase 2>/dev/null | sort -u)
    # Installed headers are left alone: -S would update them past a pinned
    # kernel (linux-cachyos-headers on a Steam Machine).
    local have=0
    for k in "${kernels[@]}"; do
        pacman -Q "${k}-headers" >/dev/null 2>&1 && { have=$((have + 1)); continue; }
        pacman -Si "${k}-headers" >/dev/null 2>&1 && headers+=("${k}-headers")
    done
    if [[ ${#headers[@]} -eq 0 && $have -gt 0 ]]; then
        ok "Kernel headers already installed."
        return 0
    fi
    if [[ ${#headers[@]} -eq 0 ]]; then
        warn "Couldn't work out which kernel headers package you need."
        warn "Install the -headers package for your kernel (e.g. linux-cachyos-headers) yourself."
        return 1
    fi
    info "Making sure kernel headers are installed: ${headers[*]}"
    sudo pacman -S --needed --noconfirm "${headers[@]}"
}

install_valve_led_driver() {
    # Installs the leds-valve DKMS driver from the AUR so the front LED
    # bar is exposed under /sys/class/leds/valve-leds[N].
    local aur_helper
    aur_helper="$(find_aur_helper)"
    if [[ -z "$aur_helper" ]]; then
        warn "No AUR helper available - can't install leds-valve-dkms-git."
        warn "Install one yourself, then run: yay -S leds-valve-dkms-git"
        return 1
    fi

    local -a flags
    read -ra flags <<< "$(aur_noninteractive_flags "$aur_helper")"

    # Headers first: without them the package installs fine but DKMS
    # silently builds nothing, so modprobe later finds no module.
    install_kernel_headers || return 1

    # The upstream Makefile builds against `uname -r` instead of the kernel
    # DKMS targets, so every other installed kernel (e.g. linux-cachyos-lts)
    # got the running kernel's tree and failed (wrong kernel, and gcc against
    # a clang-built tree). DKMS reads this override after the package's
    # dkms.conf; written before the install so its own build works too.
    # On a fresh system dkms isn't installed yet, so /etc/dkms doesn't exist.
    sudo mkdir -p "$(dirname "$LED_DKMS_OVERRIDE")"
    if ! printf '%s\n' "# Written by cachyos-gamescope-boot: build for DKMS's target kernel." \
        'MAKE[0]="make KVERSION=${kernelver}"' | sudo tee "$LED_DKMS_OVERRIDE" >/dev/null; then
        err "Couldn't write $LED_DKMS_OVERRIDE; without it the LED driver only builds for the running kernel."
        return 1
    fi

    if ! pacman -Qi leds-valve-dkms-git >/dev/null 2>&1; then
        info "Installing leds-valve-dkms-git from the AUR via $aur_helper (non-interactive)..."
        if ! "$aur_helper" -S "${flags[@]}" leds-valve-dkms-git; then
            err "Installing leds-valve-dkms-git failed."
            return 1
        fi
    else
        ok "leds-valve-dkms-git already installed."
    fi

    # Build for every installed kernel that has headers, so booting another
    # one (e.g. the LTS kernel) still has the driver.
    local kdir kver
    for kdir in /usr/lib/modules/*/build; do
        [[ -d "$kdir" ]] || continue
        kver="$(basename "$(dirname "$kdir")")"
        dkms status -k "$kver" leds-valve-dkms 2>/dev/null | grep -q installed && continue
        info "Building leds-valve for kernel $kver..."
        if ! sudo dkms install leds-valve-dkms/0.1 -k "$kver"; then
            err "DKMS build for $kver failed. See the build log:"
            err "  /var/lib/dkms/leds-valve-dkms/0.1/build/make.log"
            return 1
        fi
    done

    # Load now, and on every boot.
    echo leds-valve | sudo tee /etc/modules-load.d/leds-valve.conf >/dev/null

    # The running kernel was just replaced (the kernel pin): its modules are
    # gone, so the driver can only load after the restart.
    if [[ ! -d "/usr/lib/modules/$(uname -r)/kernel" ]]; then
        ok "The LED driver loads after the restart (into the new kernel)."
        return 0
    fi

    info "Loading the leds-valve kernel module..."
    if sudo modprobe leds-valve; then
        ok "Module loaded."
    else
        warn "modprobe leds-valve failed. Kernel messages:"
        sudo dmesg | grep -i 'valve' | tail -n 10
    fi

    if compgen -G "/sys/class/leds/valve-leds*" >/dev/null; then
        ok "LED bar nodes detected: $(cd /sys/class/leds && echo valve-leds*)"
    else
        warn "No valve-leds nodes under /sys/class/leds/ yet. Reboot, then check with:"
        warn "  ls /sys/class/leds/ | grep valve ; sudo dmesg | grep -i valve"
    fi

}

LED_UDEV_RULE="/etc/udev/rules.d/70-valve-leds-user.rules"
LED_DKMS_OVERRIDE="/etc/dkms/leds-valve-dkms.conf"
HEADERS_SCRIPT="/usr/local/lib/cachyos-gamescope-boot/ensure-kernel-headers"
HEADERS_UNIT="/etc/systemd/system/ensure-kernel-headers.service"

install_headers_boot_check() {
    # DKMS's pacman hook rebuilds leds-valve for every kernel whose headers
    # get installed, but a newly added kernel (e.g. linux-cachyos-bore)
    # comes without them, and a pacman hook can't install packages itself.
    # So check at every boot and install missing headers, which triggers
    # that hook and builds the driver for the new kernel.
    sudo mkdir -p "$(dirname "$HEADERS_SCRIPT")"
    sudo tee "$HEADERS_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
# Installed by cachyos-gamescope-boot: install missing -headers for every
# installed kernel, so DKMS builds leds-valve for it.
set -u
missing=()
for k in $(pacman -Qqo /usr/lib/modules/*/pkgbase 2>/dev/null | sort -u); do
    pacman -Q "${k}-headers" >/dev/null 2>&1 && continue
    pacman -Si "${k}-headers" >/dev/null 2>&1 && missing+=("${k}-headers")
done
[[ ${#missing[@]} -eq 0 ]] && exit 0
# Another pacman is running (e.g. an update): try again next boot.
[[ -e /var/lib/pacman/db.lck ]] && { echo "pacman is busy, skipping"; exit 0; }
echo "Installing missing kernel headers: ${missing[*]}"
exec pacman -S --needed --noconfirm "${missing[@]}"
EOF
    sudo chmod 755 "$HEADERS_SCRIPT"
    sudo tee "$HEADERS_UNIT" > /dev/null << EOF
[Unit]
Description=Install missing kernel headers so DKMS builds leds-valve for every kernel
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$HEADERS_SCRIPT

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable ensure-kernel-headers.service
}

reload_powerdevil() {
    qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement \
        org.kde.Solid.PowerManagement.refreshStatus >/dev/null 2>&1 || true
}

kernel_overview() {
    # Per installed kernel: headers (needed to build DKMS modules), the
    # in-kernel Steam controller driver, and, on a Steam Machine, whether the
    # LED driver is built for it. Printed in the menu so it's easy to verify
    # a kernel update or a newly added kernel got everything.
    local mark="${c_green}yes${c_reset}" miss="${c_red}no ${c_reset}" leds=false
    detect_valve_fremont && command -v dkms >/dev/null 2>&1 && leds=true
    local kdir k pkg headers hid led running line
    local legend="> = running; controller = Steam controller driver"
    [[ "$leds" == true ]] && legend+=", LEDs = LED bar driver built"
    echo -e "  ${c_bold}Kernels${c_reset} ($legend)"
    for kdir in /usr/lib/modules/*/; do
        k="$(basename "$kdir")"
        [[ -f "$kdir/pkgbase" ]] || continue
        pkg="$(< "$kdir/pkgbase")"
        headers="$miss"; [[ -d "$kdir/build" ]] && headers="$mark"
        hid="$miss"; compgen -G "$kdir/kernel/drivers/hid/hid-steam.ko*" >/dev/null && hid="$mark"
        running="  "; [[ "$k" == "$(uname -r)" ]] && running="${c_cyan}>${c_reset} "
        line="$(printf '%-23s %-18s headers %b  controller %b' "$k" "$pkg" "$headers" "$hid")"
        if [[ "$leds" == true ]]; then
            led="$miss"; dkms status -k "$k" leds-valve-dkms 2>/dev/null | grep -q installed && led="$mark"
            line+="$(printf '  LEDs %b' "$led")"
        fi
        echo -e "  ${running}${line}"
    done
    cec_status && { echo; echo -e "    $(cec_overview)"; }
    if [[ "$leds" == true ]]; then
        local loaded="$miss" nodes
        lsmod | grep -q '^leds_valve' && loaded="$mark"
        nodes="$(compgen -G '/sys/class/leds/valve-leds*' | wc -l)"
        echo
        echo -e "    LED driver loaded: ${loaded}  LED nodes: ${nodes}  steamos-manager: $(systemctl is-active steamos-manager 2>/dev/null)"
    fi
}

machine_available() { detect_valve_fremont; }

machine_status() {
    pacman -Qi leds-valve-dkms-git >/dev/null 2>&1 && pacman -Qi steamos-manager >/dev/null 2>&1
}

machine_enable() {
    # The pinned kernel first when it's wanted too, so DKMS builds the LED
    # driver for it once, instead of for the current kernel and then again.
    if [[ "${WANTED[kpin]:-0}" == 1 ]]; then
        install_pinned_kernel || { err "Couldn't set up kernel $PINNED_KERNEL_VER."; return 1; }
    fi
    ensure_aur_helper || { warn "Couldn't set up an AUR helper automatically. Install yay or paru, then run the wizard again."; return 1; }
    install_valve_led_driver || { warn "LED driver setup ran into a problem - see errors above."; return 1; }
    install_headers_boot_check

    # The LED files are root-only. Steam runs as the user; let it write them
    # in case it drives the bar directly (Valve's own privileged-write helper
    # doesn't cover the Steam Machine's LED bar).
    info "Letting $TARGET_USER control the LED bar..."
    sudo tee "$LED_UDEV_RULE" > /dev/null << EOF
# Let the console user (and Steam) control the Steam Machine's front LED bar.
SUBSYSTEM=="leds", KERNEL=="valve-leds*", RUN+="/usr/bin/find /sys%p -maxdepth 1 -type f -exec /usr/bin/chown $TARGET_USER {} +"
EOF
    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=leds --action=add

    # steamos-manager and inputplumber are what Steam in gaming mode talks to
    # for hardware and controller settings; it knows the Steam Machine from its DMI data.
    info "Installing hardware manager packages (steamos-manager & inputplumber)..."
    sudo pacman -S --needed --noconfirm steamos-manager inputplumber || { err "Installing hardware manager packages failed."; return 1; }
    sudo systemctl enable --now inputplumber.service
    sudo systemctl enable --now steamos-manager.service
    systemctl --user enable steamos-manager.service 2>/dev/null

    # Console-like power handling, as SteamOS's powerdevilrc (mains-power
    # part; there is no battery): the power button sleeps instead of showing
    # the logout screen, and the machine never suspends on its own (e.g.
    # during a long download). The launcher's Shut Down still shuts down.
    kset machine powerdevilrc "AC|SuspendAndShutdown" PowerButtonAction 1
    kset machine powerdevilrc "AC|SuspendAndShutdown" AutoSuspendAction 0
    kset machine powerdevilrc "AC|Display" LockBeforeTurnOffDisplay false
    reload_powerdevil
    ok "Steam Machine support on."
}

machine_disable() {
    info "Removing Steam Machine support..."
    systemctl --user disable --now steamos-manager.service 2>/dev/null
    sudo systemctl disable --now steamos-manager.service 2>/dev/null
    sudo systemctl disable --now inputplumber.service 2>/dev/null
    sudo pacman -Rns --noconfirm steamos-manager inputplumber 2>/dev/null
    sudo rm -f "$LED_UDEV_RULE" /etc/modules-load.d/leds-valve.conf
    sudo udevadm control --reload
    sudo modprobe -r leds-valve 2>/dev/null
    sudo pacman -Rns --noconfirm leds-valve-dkms-git 2>/dev/null
    krevert machine
    reload_powerdevil
    sudo systemctl disable ensure-kernel-headers.service 2>/dev/null
    sudo rm -f "$LED_DKMS_OVERRIDE" "$HEADERS_UNIT" "$HEADERS_SCRIPT"
    sudo rmdir "$(dirname "$HEADERS_SCRIPT")" 2>/dev/null
    sudo systemctl daemon-reload
    ok "Steam Machine support removed (the AUR helper, if installed, is kept)."
}
