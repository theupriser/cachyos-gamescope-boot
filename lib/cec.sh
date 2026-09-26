#!/bin/bash
# "HDMI-CEC" menu item, on any PC: Valve's CEC daemon (cecd), TV/receiver
# volume control (cec-audio-control) and the units that attach USB CEC
# adapters (Pulse-Eight, RainShadow) with inputattach. They're only in
# Valve's SteamOS (holo) repository, not in CachyOS or the AUR. Works with
# any /dev/cec*: a GPU with CEC or a USB adapter. On a Steam Machine it also
# builds Valve's CEC driver (see cec_driver_enable), and steamos-manager
# configures cecd from Steam's settings.
# Sourced by steamify.sh; not meant to be run on its own.

CEC_PKGS=(cecd cec-audio-control inputattach-cec-units)
# steamos-manager checks once, at its start, whether cecd runs; order it
# after cecd so it never misses it at login.
CEC_ORDER_DROPIN=/etc/systemd/user/steamos-manager.service.d/10-steamify-after-cecd.conf
# CachyOS's gaming mode script exports STEAM_ENABLE_CEC=0, which hides
# Steam's HDMI-CEC settings; Steam reads it from the gamescope environment
# file. A later EnvironmentFile= overrides it.
CEC_STEAM_ENV=/etc/steamify/steam-cec.env
CEC_STEAM_DROPIN=/etc/systemd/user/steam-launcher.service.d/10-steamify-cec.conf
# The Steam Machine's CEC runs through its embedded controller (cros_ec_cec).
# Mainline's driver doesn't list Fremont, so there's no /dev/cec0; Valve's
# kernel does. We build Valve's copy with DKMS for every kernel, pinned to a
# reviewed commit.
CEC_DKMS_NAME=steamify-cros-ec-cec
CEC_DKMS_VER=1
CEC_DKMS_SRC="/usr/src/$CEC_DKMS_NAME-$CEC_DKMS_VER"
CEC_DRIVER_URL="https://raw.githubusercontent.com/evlaV/linux-integration/10c8c8800ccd3ae359203b4eefb6479f613b3b8e/drivers/media/cec/platform/cros-ec/cros-ec-cec.c"
CEC_DRIVER_SHA256=e89fd4e87fceb32d713ffc59b64794779b3c2b3c012b0e2f2e9f0c40b42f4373

cec_link_steamos_manager() {
    # On a Steam Machine: steamos-manager writes cecd's config from Steam's
    # CEC settings (its configure-cecd unit, run before cecd), and only
    # offers Steam those settings when cecd was there at its start. Also
    # called by Steam Machine support, which installs steamos-manager after
    # this item ran.
    pacman -Q steamos-manager >/dev/null 2>&1 || return 0
    systemctl --user daemon-reload
    systemctl --user enable steamos-manager-configure-cecd.service 2>/dev/null
    systemctl --user start steamos-manager-configure-cecd.service 2>/dev/null
    systemctl --user restart cecd.service 2>/dev/null
    systemctl --user restart steamos-manager.service 2>/dev/null
    return 0
}

cec_installed() { pacman -Q "${CEC_PKGS[@]}" >/dev/null 2>&1; }
cec_driver_ok() { ! detect_valve_fremont || [[ -d "$CEC_DKMS_SRC" ]]; }
# On = installed, Steam told to show its CEC settings and, on a Steam
# Machine, the driver built. An install from before 1.1.3 (settings) or
# 2.0.3 (driver) lacks one; the menu then ticks it (see cec_repair).
cec_status() { cec_installed && [[ -f "$CEC_STEAM_DROPIN" ]] && cec_driver_ok; }

cec_reload_driver() {
    # cecd keeps /dev/cec0 open, so the old module can't be unloaded under it.
    systemctl --user stop cecd.service 2>/dev/null
    sudo modprobe -r cros_ec_cec 2>/dev/null
    sudo modprobe cros_ec_cec 2>/dev/null
    systemctl --user start cecd.service 2>/dev/null
}

cec_driver_enable() {
    detect_valve_fremont || return 0
    local tmp k
    if ! pacman -Q dkms >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm dkms || { err "Installing dkms failed."; return 1; }
    fi
    install_kernel_headers || return 1
    tmp="$(mktemp -d)"
    info "Downloading Valve's Steam Machine CEC driver..."
    if ! curl -fsL "$CEC_DRIVER_URL" -o "$tmp/cros-ec-cec.c" ||
        ! echo "$CEC_DRIVER_SHA256  $tmp/cros-ec-cec.c" | sha256sum -c --quiet -; then
        rm -rf "$tmp"
        err "Downloading Valve's CEC driver failed (or its checksum didn't match)."
        return 1
    fi
    # amdgpu registers its HDMI notifier without a port name, which only
    # matches the driver's named lookup ("Port C") if the driver loaded
    # first; amdgpu loads from the initramfs, so it never does. With a
    # single CEC port, look it up by device alone.
    sed -i 's/cec_notifier_cec_adap_register(hdmi_dev, conns\[port_num\],/cec_notifier_cec_adap_register(hdmi_dev, conns[1] ? conns[port_num] : NULL,/' \
        "$tmp/cros-ec-cec.c"
    grep -q 'conns\[1\] ? conns\[port_num\] : NULL' "$tmp/cros-ec-cec.c" ||
        { rm -rf "$tmp"; err "Patching Valve's CEC driver failed."; return 1; }
    echo 'obj-m += cros-ec-cec.o' >"$tmp/Makefile"
    printf '%s\n' "# Written by Steamify: Valve's cros_ec_cec, which knows the Steam Machine." \
        "PACKAGE_NAME=\"$CEC_DKMS_NAME\"" "PACKAGE_VERSION=\"$CEC_DKMS_VER\"" \
        'BUILT_MODULE_NAME[0]="cros-ec-cec"' 'DEST_MODULE_LOCATION[0]="/updates/dkms"' \
        'AUTOINSTALL="yes"' >"$tmp/dkms.conf"
    sudo dkms remove "$CEC_DKMS_NAME/$CEC_DKMS_VER" --all >/dev/null 2>&1
    sudo rm -rf "$CEC_DKMS_SRC"
    sudo install -d "$CEC_DKMS_SRC" && sudo install -m644 "$tmp"/{cros-ec-cec.c,Makefile,dkms.conf} "$CEC_DKMS_SRC/"
    rm -rf "$tmp"
    sudo dkms add "$CEC_DKMS_NAME/$CEC_DKMS_VER" >/dev/null || { err "Adding the CEC driver to DKMS failed."; return 1; }
    # Every kernel with headers; one that fails to build only lacks CEC.
    for k in /usr/lib/modules/*/build; do
        k="$(basename "$(dirname "$k")")"
        info "Building the CEC driver for $k..."
        sudo dkms install "$CEC_DKMS_NAME/$CEC_DKMS_VER" -k "$k" >/dev/null ||
            warn "Building the CEC driver for $k failed; that kernel has no HDMI-CEC."
    done
    cec_reload_driver
}

cec_driver_disable() {
    [[ -d "$CEC_DKMS_SRC" ]] || return 0
    sudo dkms remove "$CEC_DKMS_NAME/$CEC_DKMS_VER" --all >/dev/null 2>&1
    sudo rm -rf "$CEC_DKMS_SRC"
    cec_reload_driver
}
cec_repair() { cec_installed && ! cec_status; }

fetch_holo_pkg() {
    # fetch_holo_pkg <dir> <package>: download the newest <package> from
    # Valve's newest holo repository into <dir> and print its path. The
    # SHA-256 comes from Valve's package index and is verified.
    local dir="$1" name="$2" repo desc file_name sha256
    repo="$(curl -fsL "$VALVE_MIRROR/" | grep -oE 'holo-[0-9]+\.[0-9]+/' | tr -d / | sort -V | tail -n 1)"
    if [[ ! -f "$dir/holo.db" ]]; then
        [[ -n "$repo" ]] && curl -fsL "$VALVE_MIRROR/$repo/os/x86_64/$repo.db" -o "$dir/holo.db" ||
            { err "Couldn't read Valve's SteamOS package index ($VALVE_MIRROR)."; return 1; }
    fi
    desc="$(tar -tf "$dir/holo.db" 2>/dev/null | grep -E "^$name-[0-9][^/]*/desc$" | head -n 1)"
    [[ -n "$desc" ]] || { err "No $name in Valve's $repo repository."; return 1; }
    file_name="$(tar -xOf "$dir/holo.db" "$desc" | awk '/^%FILENAME%$/ { getline; print }')"
    sha256="$(tar -xOf "$dir/holo.db" "$desc" | awk '/^%SHA256SUM%$/ { getline; print }')"
    info "Downloading $file_name ($repo)..." >&2
    curl -fsL "$VALVE_MIRROR/$repo/os/x86_64/$file_name" -o "$dir/$file_name" ||
        { err "Downloading $file_name failed."; return 1; }
    echo "$sha256  $dir/$file_name" | sha256sum -c --quiet - >&2 ||
        { err "Checksum mismatch for $file_name; not using it."; return 1; }
    echo "$dir/$file_name"
}

cec_enable() {
    local tmp p f files=()
    # inputattach, needed by inputattach-cec-units.
    if ! pacman -Q linuxconsole >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm linuxconsole || { err "Installing linuxconsole failed."; return 1; }
        state_set cec installed_linuxconsole 1
    fi
    tmp="$(mktemp -d)"
    for p in "${CEC_PKGS[@]}"; do
        f="$(fetch_holo_pkg "$tmp" "$p")" || { rm -rf "$tmp"; return 1; }
        files+=("$f")
    done
    info "Installing Valve's CEC daemon..."
    if ! sudo pacman -U --needed --noconfirm "${files[@]}"; then
        rm -rf "$tmp"
        err "Installing ${CEC_PKGS[*]} failed."
        return 1
    fi
    rm -rf "$tmp"
    cec_driver_enable || return 1
    # Its udev rule gives the user /dev/cec*; cecd starts with the graphical
    # session, after steamos-manager wrote its config from Steam's settings.
    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=cec --action=add
    sudo mkdir -p "$(dirname "$CEC_ORDER_DROPIN")"
    printf '%s\n' "# Written by Steamify: steamos-manager only sees cecd if it runs at its start." \
        '[Unit]' 'After=cecd.service' | sudo tee "$CEC_ORDER_DROPIN" >/dev/null
    sudo mkdir -p "$(dirname "$CEC_STEAM_ENV")" "$(dirname "$CEC_STEAM_DROPIN")"
    printf '%s\n' "# Written by Steamify: Steam's HDMI-CEC settings in gaming mode." 'STEAM_ENABLE_CEC=1' |
        sudo tee "$CEC_STEAM_ENV" >/dev/null
    printf '%s\n' "# Written by Steamify: overrides STEAM_ENABLE_CEC=0 from the gaming mode script." \
        '[Service]' "EnvironmentFile=-$CEC_STEAM_ENV" | sudo tee "$CEC_STEAM_DROPIN" >/dev/null
    systemctl --user daemon-reload
    cec_link_steamos_manager
    if compgen -G "/dev/cec*" >/dev/null; then
        systemctl --user restart cecd.service 2>/dev/null
        ok "HDMI-CEC on ($(cd /dev && echo cec*)); Steam shows its settings from the next gaming mode start."
        info "Turn on CEC on your TV too (e.g. Sony: BRAVIA Sync, Samsung: Anynet+, LG: SimpLink)."
    else
        warn "No CEC device (/dev/cec*) found: your GPU may not support CEC. A USB CEC adapter"
        warn "(e.g. Pulse-Eight) works too. Check again after a restart with: ls /dev/cec*"
    fi
}

cec_disable() {
    info "Removing HDMI-CEC..."
    systemctl --user disable --now cecd.service cec-audio-control.socket cec-audio-control.service 2>/dev/null
    systemctl --user disable steamos-manager-configure-cecd.service 2>/dev/null
    sudo pacman -Rns --noconfirm "${CEC_PKGS[@]}" 2>/dev/null
    cec_driver_disable
    sudo rm -f "$CEC_ORDER_DROPIN" "$CEC_STEAM_DROPIN" "$CEC_STEAM_ENV"
    sudo rmdir "$(dirname "$CEC_ORDER_DROPIN")" "$(dirname "$CEC_STEAM_DROPIN")" "$(dirname "$CEC_STEAM_ENV")" 2>/dev/null
    systemctl --user daemon-reload
    if [[ -n "$(state_get cec installed_linuxconsole)" ]]; then
        sudo pacman -Rns --noconfirm linuxconsole 2>/dev/null
        state_clear cec
    fi
    sudo udevadm control --reload
    systemctl --user is-active -q steamos-manager.service 2>/dev/null &&
        systemctl --user restart steamos-manager.service
    ok "HDMI-CEC removed."
}

cec_overview() {
    # For the menu's kernel overview.
    local dev="none"
    compgen -G "/dev/cec*" >/dev/null && dev="$(cd /dev && echo cec*)"
    echo "CEC devices: $dev  cecd: $(systemctl --user is-active cecd 2>/dev/null)"
}
