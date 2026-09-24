#!/bin/bash
# "Steam Machine support" menu item, only on Valve Fremont hardware: the
# front LED bar driver, LED access for Steam, and steamos-manager.
# Sourced by setup-gamescope-boot.sh; not meant to be run on its own.

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

install_kernel_headers() {
    # DKMS can only build leds-valve against kernels whose headers are
    # installed. CachyOS ships several kernels (linux-cachyos, -lts, -bore,
    # ...); install the matching -headers package for every one present.
    local -a kernels headers=()
    mapfile -t kernels < <(pacman -Qqo /usr/lib/modules/*/pkgbase 2>/dev/null | sort -u)
    local k
    for k in "${kernels[@]}"; do
        pacman -Si "${k}-headers" >/dev/null 2>&1 && headers+=("${k}-headers")
    done
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
    printf '%s\n' "# Written by cachyos-gamescope-boot: build for DKMS's target kernel." \
        'MAKE[0]="make KVERSION=${kernelver}"' | sudo tee "$LED_DKMS_OVERRIDE" >/dev/null

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
    echo -e "  ${c_bold}Kernels${c_reset} (> = running; controller = Steam controller driver, LEDs = LED bar driver built)"
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
