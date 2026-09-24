# Changelog

All notable changes, per version and per commit. Versions follow
[Semantic Versioning](https://semver.org/); the current one is `VERSION` in
`steamify.sh`. Versions before 0.7.0 were numbered afterwards,
one per merged pull request.

## 0.9.0 - 2026-09-24

The wizard is now called **Steamify CachyOS**, and can put a shortcut to
itself on the desktop.

- `f01aa93` **feat: Wizard shortcut on the desktop and in the launcher**
  - New menu item: a desktop icon and app launcher entry
    that open the newest release of the wizard in Konsole (`curl | bash`).
  - Its icon: Valve's Return to Gaming Mode icon with a gear instead of the
    arrow (`assets/steam-gaming-settings.svg`), published with every release
    and downloaded from there.
  - Desktop files are written already executable, so Plasma runs them instead
    of opening them in an editor.
- `be874b8` **feat: Rename to Steamify CachyOS**
  - Menu header, the shortcut ("Steamify CachyOS", menu item "Steamify
    shortcut"), release titles, README and AGENTS.md.
- `1c34a97` **chore: Repository renamed to steamify-cachyos**
  - All URLs point to `github.com/theupriser/steamify-cachyos` (the old ones
    redirect). The script keeps its name, `setup-gamescope-boot.sh`, so the
    old download URL keeps working; internal names such as
    `~/.local/state/cachyos-gamescope-boot` stay, so existing installs can
    still be turned off.
- `69a420b` **feat: The script is now steamify.sh**
  - `setup-gamescope-boot.sh` is renamed to `steamify.sh`; releases publish the
    bundle under both names, so `.../download/setup-gamescope-boot.sh` keeps
    working. The Steamify shortcut runs `steamify.sh`.
- `b0553ae` **docs: Shorter README intro**
- **feat: The shortcut's window closes itself after a countdown**
  - After the wizard ends, a 10-second countdown closes the Konsole window
    (Enter closes it right away); after an error it stays open until Enter.
  - A failed download now counts as an error (`pipefail`) instead of running
    an empty script.

## 0.8.0 - 2026-09-24 (#8)

An opt-in BIOS update for the Steam Machine, and a menu that comes back after
every run.

- `2f9b2a5` **feat: Opt-in BIOS update for the Steam Machine**
  - New menu item (Steam Machine only, never ticked by default) showing the
    current BIOS version and the newest from Valve's `fremont-hw-support`.
  - Two large warnings and two confirmations (y/N, then typing `UPDATE`),
    checksum-verified download, installed with fwupd; the wizard then offers
    the restart that writes it, with a warning to keep the power on.
- `40c9ee6` **fix: BIOS update only when newer, device check first, aligned warnings**
  - The item is greyed out and can't be ticked unless Valve has a newer BIOS.
  - Before any warning: SHA-256 of Valve's package, then fwupd confirms the
    firmware fits this machine's hardware; otherwise it stops.
  - Warning box drawn with a solid red frame whose edges line up, and the
    menu's "Now" column aligned.
- `b70c9d6` **fix: shellcheck in the bundle, and the docs for the BIOS checks**
  - A variable name in `lib/bios.sh` clashed with `lib/state.sh` in the bundle
    (CI's shellcheck would fail); README, AGENTS.md and this changelog updated.
- `54fc9e3` **feat: Menu comes back after each run, BIOS dry run, version 0.8.0**
  - After a run the menu returns with the new state; quit with `q`. When
    something needs a restart, choose between back to the menu (`m`) and
    restart now (`r`); quitting asks once more.
  - A staged BIOS update greys the item out until the restart.
  - `WIZARD_BIOS_DRY_RUN=1` walks through the whole BIOS update (download,
    checksum, both warnings) but only prints the install and never flashes.
  - README: the menu loop and the BIOS update step by step.
- `45a8757` **fix: BIOS dry run also walks through the restart choices**
  - A dry run counts as staged, so `[m]`/`[r]` and the restart question on `q`
    show up; in dry-run mode restarting only prints what it would do.
- `429e840` **fix: Shorter BIOS labels so the menu fits 80 columns**
  - "now F7F0107, newest F7F0108 (own risk)", "F7F0108 waits for a restart",
    "F7F0107 is up to date"; shorter dry-run line.
- `99a95ab` **fix: Kernel legend only mentions the LEDs on a Steam Machine**
- `c0014ee` **docs: Last commit hash in the changelog; 0.7.0 was released on its own (#6, #7)**

## 0.7.0 - 2026-09-24 (#6, #7)

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
- `10b5164` **docs: Version 0.7.0 and CHANGELOG**
  - `VERSION` in the entry point, shown in the menu header and the bundle.
  - README and AGENTS.md updated for the theme, the extras and the LED driver.
- `eb3169e` **ci: Version and changelog in the release notes**
  - The `latest` release's title shows the version, and its notes include this
    version's section of `CHANGELOG.md`.
  - Fix a shellcheck warning in the bundle (a variable name shared with
    `lib/state.sh`), which would have failed the CI check.
- `d7231eb` **chore: Move the bundle tool to .github/tools/bundle.sh**
- `5c00504` **docs: Commit hashes in the changelog**
- `8aab946` **ci: A release per version (tag v0.7.0, ...) instead of overwriting "latest"**
  - Each push to `main` publishes release `v$VERSION` with that version's
    changelog; an already released version is never overwritten (pull requests
    get a warning when `VERSION` wasn't bumped).
  - Install with `.../releases/latest/download/setup-gamescope-boot.sh`, which
    always points to the newest release.
- `1604ed1` **docs: Versioning and release rules in AGENTS.md**
- `6afef78` **ci: The latest tag follows the newest version tag**
  - When a new version is released, the `latest` tag and release move to it
    (bundle replaced), so the older `.../releases/download/latest/...` URL
    also always gives the newest version.

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
