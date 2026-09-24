#!/bin/bash
# Required packages and AUR helper handling.
# Sourced by steamify.sh; not meant to be run on its own.

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

find_aur_helper() {
    if command -v yay >/dev/null 2>&1; then
        echo yay
    elif command -v paru >/dev/null 2>&1; then
        echo paru
    fi
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

install_required_packages() {
    # Step 2: gamescope/Steam and the desktop helpers the rest of the setup uses.
    local -a MISSING
    info "Checking required packages: gamescope-session-cachyos, steam, mangohud, xterm, ttf-liberation, wqy-zenhei, plasma-keyboard"
    mapfile -t MISSING < <(pacman -T gamescope-session-cachyos steam mangohud xterm ttf-liberation wqy-zenhei plasma-keyboard)

    if [[ ${#MISSING[@]} -gt 0 ]]; then
        info "Installing missing packages: ${MISSING[*]}"
        sudo pacman -S --needed --noconfirm "${MISSING[@]}" || { err "Package installation failed."; return 1; }
    else
        ok "All required packages already installed."
    fi
}

ensure_aur_helper() {
    # yay or paru, bootstrapping yay from the AUR when neither is installed.
    if [[ -n "$(find_aur_helper)" ]]; then
        ok "AUR helper already present."
    else
        info "No AUR helper (yay/paru) found. Installing yay..."
        bootstrap_yay
    fi
}
