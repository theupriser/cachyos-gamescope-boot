# CachyOS Gamescope Boot Wizard

A setup script that makes a CachyOS desktop install (running KDE Plasma +
`plasma-login-manager`) always boot into a **Steam Deck-style gamescope
session** - the same "always boots into Big Picture, switch to desktop and
back on demand" experience SteamOS gives you on a real Deck or the Valve
Steam Machine.

It exists because, as of the CachyOS March 2026 release (which switched the
default login manager from SDDM to `plasma-login-manager`), the stock
`gamescope-session-cachyos` tooling has a few gaps that stop this from
working out of the box. This script patches around them.

## What's actually broken (and what this fixes)

CachyOS's `gamescope-session-cachyos` package ships `steamos-session-select`,
which is meant to work exactly like it does on real SteamOS. On a
`plasma-login-manager` system, three things get in the way:

1. **No `User=` written to the autologin config.**
   `steam-set-session` (the script `steamos-session-select` calls under the
   hood) only ever writes a `Session=` key to the autologin config file. On
   SDDM this is fine, because SDDM's `User=` is set once by the installer and
   never touched again. `plasma-login-manager` needs *both* `Session=` and
   `User=` present to autologin at all - without `User=`, it just falls back
   to showing the greeter every boot.

2. **Missing `/etc/plasmalogin.conf.d` directory.**
   If that directory doesn't exist, `steam-set-session` fails outright when
   it tries to write to it. In practice this shows up as Steam's **"Switch to
   Desktop"** hanging forever on a "Switching to Desktop" message with no way
   back except a hard reset.

3. **The base `/etc/plasmalogin.conf` wins over conf.d, and CachyOS ships it
   hardcoded to `Session=plasma`.**
   Every CachyOS tool that changes sessions (`steamos-session-select`, Steam's
   power menu, and the `cachyos-gamescope-autologin.service` that's supposed
   to reset you back to gamescope after a desktop session) only ever writes
   to `/etc/plasmalogin.conf.d/zz-steamos-autologin.conf`. But the *base*
   `/etc/plasmalogin.conf` file takes priority over that fragment, and it
   ships with `Session=plasma` baked in - so none of those session switches
   ever actually stick, no matter what the fragment says.

This script fixes all three: it ensures the conf.d directory exists, sets the
base config's `Session=`, `User=`, and `Relogin=true` correctly, and installs
a small `systemd` path-watcher that keeps the base config in sync with
whatever CachyOS's own tools write to the conf.d fragment - so switching
sessions from inside Steam or the desktop actually works, in both
directions, and resets to gamescope on the next boot by default (matching
real Deck/SteamOS behavior).

It also optionally offers to install Valve's official **Vapor** KDE Plasma
theme - the same colors, icons, wallpapers, and Plasma look-and-feel package
used on real SteamOS - pulled directly from Valve's own SteamOS package
mirror, so your desktop session matches the gamescope side visually.

## Requirements

- CachyOS (or an Arch-based system) with `pacman`
- KDE Plasma installed
- `plasma-login-manager` as the active display manager
  *(the script will warn and ask for confirmation if it detects SDDM or
  something else instead - most of these workarounds are specific to
  `plasma-login-manager`)*
- A regular user account with `sudo` access

## Usage

```bash
git clone <this-repo-url>
cd <this-repo>
chmod +x setup-gamescope-boot.sh
./setup-gamescope-boot.sh
```

Run it as your normal user, **not** as root - it calls `sudo` internally for
the specific commands that need it.

The script will:

1. Ask which user account should autologin into gamescope (defaults to
   whoever's running the script).
2. Check for and offer to install `gamescope-session-cachyos`, `steam`, and
   `mangohud` if any are missing.
3. Create `/etc/plasmalogin.conf.d` if it doesn't exist.
4. Back up and rewrite `/etc/plasmalogin.conf`'s `[Autologin]` section.
5. Remove any stray manual override files from earlier troubleshooting
   attempts (only files matching `zzz-steamos-autologin*.conf` - it never
   touches `zz-steamos-autologin.conf`, which CachyOS's own tools own).
6. Install a sync script (`/usr/local/bin/sync-steamos-session.sh`) and a
   `systemd` path unit that keeps the base config aligned with session
   switches made through Steam or `steamos-session-select`.
7. Ask whether you'd also like to install Valve's **Vapor** (Steam Deck) KDE
   theme. If you say yes, it downloads the official `steamdeck-kde-presets`
   package straight from Valve's SteamOS mirror and installs the color
   scheme, Plasma look-and-feel package, wallpapers, and icons into your
   user's `~/.local/share`. This step only touches your home directory -
   nothing system-wide - and installing `curl`/`zstd` first if either is
   missing. Apply it afterwards from **System Settings > Appearance >
   Global Theme > Vapor (Steam Deck)** the next time you're in a Plasma
   session.

   If you keep a folder named `icons/` next to the script (e.g. custom Steam
   Deck logo assets), it'll also copy those into the right Plasma icon
   directories automatically. This is entirely optional - the theme installs
   fine without it.
8. Ask whether to reboot immediately to test the gamescope setup.

It's **safe to re-run** - every step checks current state first, and any
file it modifies gets backed up once with a `.bak-gamescope-wizard` suffix
before the first change.

## After running it

Boot straight into gamescope: it should happen automatically. From inside
gamescope, Steam's **Power > Switch to Desktop** should now work. From the
desktop, logging out should drop you back into gamescope automatically
(thanks to CachyOS's own `cachyos-gamescope-autologin.service`, which this
script doesn't replace - it just makes sure the setting it writes actually
takes effect).

You can also switch sessions manually at any time:

```bash
steamos-session-select gamescope   # switch to gamescope right now
steamos-session-select plasma      # switch to desktop right now
steamos-session-select persistent  # remember whichever session you used last, across reboots
steamos-session-select oneshot     # always start in gamescope regardless of what you used last (the default Deck-like behavior)
```

## Restoring the originals

Every file the script modifies is backed up next to itself:

```bash
sudo cp /etc/plasmalogin.conf.bak-gamescope-wizard /etc/plasmalogin.conf
```

To fully remove the sync watcher this script adds:

```bash
sudo systemctl disable --now sync-steamos-session.path
sudo rm /etc/systemd/system/sync-steamos-session.path
sudo rm /etc/systemd/system/sync-steamos-session.service
sudo rm /usr/local/bin/sync-steamos-session.sh
sudo systemctl daemon-reload
```

## Caveats

- This works around current CachyOS/`plasma-login-manager` behavior as of
  September 2026. If CachyOS fixes `steam-set-session` upstream to write
  `User=` and to target whichever base config the login manager actually
  reads, this script becomes unnecessary - check for updates before running
  it on a freshly reinstalled system.
- Tested on a Valve Steam Machine (desktop AMD APU + discrete GPU) running
  CachyOS Desktop edition. Should apply to any CachyOS desktop install using
  `plasma-login-manager`, but hasn't been tested on Steam Deck/Legion Go
  hardware, which typically ship with SDDM instead.
- If you find CachyOS has patched the underlying issue, please open an issue
  or PR here so the script can detect that and skip the workaround.
- The Vapor theme step depends on Valve's `steamdeck-kde-presets` package
  staying available at its current URL and version
  (`steamdeck-kde-presets-0.29-1-any.pkg.tar.zst` on
  `steamdeck-packages.steamos.cloud`). If Valve ships a newer version or
  changes the mirror layout, update `pkg_ver` near the top of
  `install_vapor_theme()` in the script.

## Related upstream reports

- [CachyOS/gamescope-session#9](https://github.com/CachyOS/gamescope-session/issues/9) - "Switch to Desktop" hang due to missing `/etc/plasmalogin.conf.d`

## License

MIT - do whatever you want with it.
