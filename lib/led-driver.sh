#!/bin/bash
# Valve Fremont (Steam Machine) front LED bar driver.
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

    if ! pacman -Qi leds-valve-dkms-git >/dev/null 2>&1; then
        info "Installing leds-valve-dkms-git from the AUR via $aur_helper (non-interactive)..."
        if ! "$aur_helper" -S "${flags[@]}" leds-valve-dkms-git; then
            err "Installing leds-valve-dkms-git failed."
            return 1
        fi
    else
        ok "leds-valve-dkms-git already installed."
    fi

    # Build for the running kernel explicitly. The upstream Makefile uses
    # `uname -r` rather than DKMS's target kernel, so building for the
    # running kernel is the one case that reliably works.
    local kver
    kver="$(uname -r)"
    if ! dkms status -k "$kver" leds-valve-dkms 2>/dev/null | grep -q installed; then
        info "Building leds-valve for running kernel $kver..."
        if ! sudo dkms install leds-valve-dkms/0.1 -k "$kver"; then
            err "DKMS build failed. See the build log:"
            err "  /var/lib/dkms/leds-valve-dkms/0.1/build/make.log"
            return 1
        fi
    fi

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

    echo
    info "Steam only pushes download progress to the LED bar in real SteamOS Game Mode."
    if ask_yn "Also install the experimental OpenRGB build (openrgb-git), which can drive the LED bar?" n; then
        "$aur_helper" -S "${flags[@]}" openrgb-git &&
            ok "openrgb-git installed. Launch OpenRGB to detect and configure the front panel."
    fi
}

setup_led_driver() {
    # Step 8c: only on Fremont hardware, and only if the user wants it.
    if detect_valve_fremont; then
        info "Detected Valve Fremont hardware (Steam Machine)."
        if ask_yn "Set up the front-panel LED bar driver (leds-valve) so it isn't stuck dark/breathing?" y; then
            ensure_aur_helper || warn "Couldn't set up an AUR helper automatically. You can install one yourself later and run: yay -S leds-valve-dkms-git"
            install_valve_led_driver || warn "LED driver setup ran into a problem - see errors above. Your gamescope boot setup above is unaffected."
        fi
        echo
    fi
}
