# Changelog

All notable changes, per version and per commit. Versions follow
[Semantic Versioning](https://semver.org/); the current one is `VERSION` in
`setup-gamescope-boot.sh`. Versions before 0.7.0 were numbered afterwards,
one per merged pull request.

## 0.7.0 - 2026-09-24

The SteamOS theme comes from CachyOS's `cachyos-vapor` package, applied with
Vapor's own desktop layout, and gains the SteamOS desktop extras. The Steam
Machine LED driver works on every installed kernel and survives kernel updates.

- `978f5a1` **feat: SteamOS theme from cachyos-vapor with its desktop layout, plus SteamOS desktop extras**
  - Installs `cachyos-vapor` instead of extracting Valve's `steamdeck-kde-presets`
    into `~/.local/share`; removes it on disable if the wizard installed it.
  - Applies the Vapor global theme with "Desktop and window layout": Steam Deck
    wallpaper, SteamOS panel and launcher icon. Layout files are backed up and
    restored; every key from Vapor's defaults goes through the undo journal.
  - Restores the real previous color scheme on disable (CachyOS's BreezeDark
    colors have no scheme name), instead of falling back to light Breeze.
  - Registers Vapor as the dark theme, so Plasma's Dark Mode toggle shows on.
  - Drops the extra SteamOS desktop defaults (GTK, Konsole, gsettings, panel tweaks).
  - New SteamOS desktop extras, downloaded from Valve's newest
    `steamdeck-kde-presets` (checksum verified) into `/usr/local`: Add to Steam,
    Nested Desktop, the SteamOS Return to Gaming Mode icon, the Steam Keyboard
    window rule and an empty KWallet (only when there is no wallet yet).
  - Single user mode's launcher settings are re-applied after the layout reset.
- `7802d90` **fix: LED driver for every kernel, kernel headers at boot, console power button, kernel overview**
  - DKMS override (`/etc/dkms/leds-valve-dkms.conf`) so the LED driver builds
    for every installed kernel (the LTS kernel failed) and on kernel updates.
  - `ensure-kernel-headers.service` installs missing kernel headers at boot, so
    a newly added kernel gets the LED driver too.
  - Power button sleeps and no automatic suspend on mains power (Steam Machine).
  - Menu shows every kernel with its headers, Steam controller driver and LED
    driver, plus whether the LEDs are loaded.
  - The selected menu row is highlighted in full.
- **docs: Version 0.7.0 and CHANGELOG** (this release's docs)
  - `VERSION` in the entry point, shown in the menu header and the bundle.
  - README and AGENTS.md updated for the theme, the extras and the LED driver.
- **ci: Version and changelog in the release notes**
  - The `latest` release's title shows the version, and its notes include this
    version's section of `CHANGELOG.md`.
  - Fix a shellcheck warning in the bundle (a variable name shared with
    `lib/state.sh`), which would have failed the CI check.
- **chore: Move the bundle tool to .github/tools/bundle.sh**

## 0.6.2 - 2026-09-23

- `a501df2` **Update steam-machine.sh**: install and enable `inputplumber`
  next to `steamos-manager`.

## 0.6.1 - 2026-09-23 (#5)

- `c0bd16e` **fix: Use curl | bash in the docs**: `bash <(...)` doesn't work in fish.

## 0.6.0 - 2026-09-23 (#4)

- `d654d44` **fix: Single-file build for curl, published by GitHub Actions**:
  `tools/bundle.sh` inlines `lib/*.sh`; CI publishes it to the `latest` release.

## 0.5.0 - 2026-09-23 (#3)

- `b91fa4b` **fix: Replace the question flow with a menu that turns components on and off**
- `3d7f376` **fix: Interactive checkbox menu**: arrow keys to move, Space to select, Enter to run.

## 0.4.0 - 2026-09-23 (#2)

- `a0bc385` **fix: Add single user no password option with SDDM, fetch newest Vapor presets**

## 0.3.0 - 2026-09-23 (#1)

- `4ad6c2c` **fix: Fix setup bugs, add SteamOS desktop look and LED driver, split into modules**

## 0.2.0 - 2026-09-07

- `151a3bf` **add steam keyboard to desktop**
- `1999b6e` **Automatically change theme**

## 0.1.0 - 2026-09-06

First version of the script.

- `16a7739`, `97ee6f3`, `6be1051` **commit the script**
- `e1aee45`, `25bc8c0` **change return to gaming mode logo to original logo**
