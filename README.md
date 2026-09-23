# CachyOS Gamescope Boot Wizard

Turn a CachyOS desktop PC into a SteamOS-style console: it boots straight
into Steam's Big Picture (gamescope), and you can switch to the KDE Plasma
desktop and back whenever you like - just like on a Steam Deck or Valve's
Steam Machine.

Out of the box, CachyOS doesn't quite manage this: the switch to the desktop
can hang, and the PC doesn't reliably boot back into gaming mode. This
script fixes that and sets everything up for you.

## What you get

The wizard is a menu: pick what you want, and it turns each part on or off.
Everything you turn off is put back the way it was.

1. **SteamOS conversion** - boots straight into gaming mode, **Switch to
   Desktop** in Steam works and so does going back (the **Return to Gaming
   Mode** icon on the desktop), you're back in gaming mode after a restart,
   and Steam's on-screen keyboard (Steam + X) also works on the desktop.
2. **SteamOS theme** - Valve's own Vapor look for the desktop: wallpaper,
   dark mode and the SteamOS taskbar.
3. **Steam Deck/Machine icons** - Steam Deck button icons in gaming mode.
4. **Single user mode** - like SteamOS: never a login or lock screen, no
   user switching or logging out. Typing a password with a controller is no
   fun. (Needs 1.)
5. **Steam Machine support** - only shown on a Valve Steam Machine: the
   driver for the front LED bar, and the hardware settings in Steam (fan,
   TV control over HDMI-CEC).

## Requirements

- CachyOS with the KDE Plasma desktop (the default CachyOS Desktop edition)
- Your normal user account, with permission to use `sudo`

## Installation

Open **Konsole** on your Plasma desktop and run:

```bash
curl -fsSL https://github.com/theupriser/cachyos-gamescope-boot/releases/download/latest/setup-gamescope-boot.sh | bash
```

That downloads and runs the latest single-file version, and works in any
shell, including fish (CachyOS's default). Prefer to keep a copy, or to look
at the script first? Clone the repository instead:

```bash
git clone https://github.com/theupriser/cachyos-gamescope-boot.git
cd cachyos-gamescope-boot
./setup-gamescope-boot.sh
```

Run it as yourself, not as root. You'll see a checklist:

```
   [x] SteamOS conversion: boot into gaming mode, Steam on the desktop  (now: off)
 > [x] Install SteamOS theme: Vapor look, dark mode, SteamOS taskbar  (now: off)
   [x] Install Steam Deck/Machine icons: Deck button icons in gaming mode  (now: off)
   [x] Single user mode: no password, lock screen or log out (SDDM)  (now: off)

  Up/Down move   Space select   Enter run   a run + re-apply what's on   q quit
```

Move with the **arrow keys**, tick or untick with **Space**, and press
**Enter** to run. "now:" shows what's on at the moment. The wizard then
shows what it will change, asks your password once, and at the end offers
to restart (needed for changes to how the PC starts).

Run it again whenever you like - to change your choices, to turn things off
again, or after a CachyOS update (press `a` in the menu to re-apply
everything that's on).

If you cloned the repository, keep the whole folder: the script needs the
files in `lib/` next to it.

## Using it

- **To the desktop:** in gaming mode, open the Steam menu and choose
  **Power > Switch to Desktop**.
- **Back to gaming mode:** double-click **Return to Gaming Mode** on the
  desktop (or log out, if you're not using single user mode).
- After a restart you always start in gaming mode.

Prefer to decide yourself where your PC starts? Run one of these in Konsole:

```bash
steamos-session-select persistent  # start where you left off last time
steamos-session-select oneshot     # always start in gaming mode (default)
```

## If something goes wrong

**Gaming mode shows a black screen or keeps restarting.** Press
**Ctrl+Alt+F3**, log in with your username and password, and run:

```bash
sudo /usr/lib/steamos/steam-set-session plasma.desktop && sudo systemctl restart display-manager
```

That takes you back to the desktop.

**The LED bar on the Steam Machine stays dark.** Restart the PC once more; a
freshly installed driver often needs a reboot. Still dark? See
[Front LED bar](#front-led-bar-steam-machine) under technical details.

**Undo something:** run the wizard again and untick it.

---

## Technical details

### How turning things on and off works

At startup every component checks whether it is on (`*_status` in `lib/`).
You choose; the wizard then turns off what you unticked (in reverse order)
and turns on what you ticked. To be able to undo:

- **System files** are backed up once, next to the original, with a
  `.bak-gamescope-wizard` suffix, and restored when you turn the component
  off.
- **KDE settings** in your home directory are recorded with their previous
  value the first time the wizard changes them, in an undo journal under
  `~/.local/state/cachyos-gamescope-boot/`. Turning the component off writes
  the old values back (or removes keys that didn't exist before). Setups
  made by older versions of the script, without a journal, fall back to
  KDE's defaults.
- **Packages** installed for the conversion (Steam, gamescope-session, ...)
  are kept when you turn it off; Steam Machine support removes its own.

### Single user mode: SDDM, no locking

Turning it on switches to **SDDM** and turns off everything that asks for a
password or another user, per user: `action/lock_screen`, `switch_user` and
`start_new_session` restrictions in `kdeglobals`, no automatic locking
(`kscreenlockerrc`), Meta+L and Ctrl+Alt+Del unbound, and the launcher shows
only Sleep / Restart / Shut Down (kickoff `primaryActions=3`), which hides
the Session dropdown with Log Out. (Restricting `action/logout` would also
hide Restart and Shut Down.) Turning it off restores all of that and moves
the conversion back to plasma-login-manager.

**SDDM** is what SteamOS uses, and CachyOS's `steam-set-session` supports it
directly: it writes `/etc/sddm.conf.d/zz-steamos-autologin.conf`, which SDDM
honours. The script installs and enables `sddm` (active from the next boot),
writes `User=`, `Session=` and `Relogin=true` to
`/etc/sddm.conf.d/10-gamescope-autologin.conf`, and removes any
`[Autologin]` from `/etc/sddm.conf` (read last, so it would override both).
No sync bridge or sudoers rule is needed; the shortcut just runs
`steamos-session-select gamescope`, which logs out, and `Relogin=true` logs
straight back in to gamescope.

Without single user mode, the conversion uses **plasma-login-manager**
(CachyOS's default since March 2026), which needs the workarounds below.

### Why this is needed (plasma-login-manager)

CachyOS's `gamescope-session-cachyos` package ships `steamos-session-select`,
which is meant to work exactly like it does on real SteamOS. Since the March
2026 release, CachyOS uses `plasma-login-manager` instead of SDDM, and three
things get in the way:

1. **No `User=` written to the autologin config.**
   `steam-set-session` (called by `steamos-session-select`) only writes a
   `Session=` key. `plasma-login-manager` needs both `Session=` and `User=`
   to autologin at all; without `User=` it shows the greeter every boot.

2. **Missing `/etc/plasmalogin.conf.d` directory.**
   Without it, `steam-set-session` fails, and Steam's "Switch to Desktop"
   hangs forever. *(Fixed upstream in `gamescope-session-cachyos` 1.1.6; the
   script still creates the directory for older versions.)*

3. **The base `/etc/plasmalogin.conf` wins over conf.d, and CachyOS ships it
   with `Session=plasma`.**
   Every tool that changes sessions (`steamos-session-select`, Steam's power
   menu, and `cachyos-gamescope-autologin.service`, which resets you to
   gamescope after a desktop session) only writes
   `/etc/plasmalogin.conf.d/zz-steamos-autologin.conf`. The base file takes
   priority, so none of those switches stick.

The script sets `Session=`, `User=` and `Relogin=true` in the base config,
and installs a small systemd path watcher that copies whatever CachyOS's
tools write to the conf.d fragment into the base config.

### What each component changes

**SteamOS conversion** (`lib/login-manager.sh`, `lib/steam-desktop.sh`,
`lib/desktop-shortcut.sh`):

- installs missing packages: `gamescope-session-cachyos`, `steam`,
  `mangohud`, `xterm`, `ttf-liberation`, `wqy-zenhei`, `plasma-keyboard`;
- *SDDM (single user mode):* installs/enables SDDM and writes its autologin
  config;
- *plasma-login-manager:* creates `/etc/plasmalogin.conf.d`, backs up and
  rewrites the `[Autologin]` section of `/etc/plasmalogin.conf`, removes
  stray `zzz-steamos-autologin*.conf` files from manual troubleshooting
  (never `zz-steamos-autologin.conf`, which CachyOS's tools own), and
  installs `/usr/local/bin/sync-steamos-session.sh` plus
  `sync-steamos-session.path`/`.service`;
- `KWIN_IM_SHOW_ALWAYS=1` for the virtual keyboard and a
  `steam-desktop-autostart` systemd user service that starts Steam silently
  in Plasma only;
- the **Return to Gaming Mode** shortcut; on plasma-login-manager with a
  narrow sudoers rule (`/etc/sudoers.d/gamescope-session-switch`) so it can
  restart the login manager without a password prompt.

Turning it off restores `/etc/plasmalogin.conf` from its backup, removes the
SDDM autologin, sync bridge, shortcut, sudoers rule and Steam autostart, and
switches back to plasma-login-manager.

**Steam Deck/Machine icons:** `STEAM_GAMEPADUI_ARGS="-gamepadui -steamos3"`
in `~/.config/environment.d/` (and gamescope-session's own environment
file), which makes Steam show Steam Deck button glyphs in gaming mode.

### SteamOS desktop look

Downloads Valve's official `steamdeck-kde-presets` package from Valve's
SteamOS mirror and installs it into `~/.local/share` - nothing system-wide:

- the Vapor global theme, color scheme, Plasma style, wallpapers and icons;
- the Vapor GTK theme, Konsole profile and user avatars;
- Valve's SteamOS desktop defaults, merged into your own config: Noto Sans
  fonts, no Xwayland input-permission prompt for Steam Input, the window
  rule that keeps the Steam keyboard on top and out of the taskbar, no
  welcome screen, light file indexing;
- the SteamOS panel: solid (not floating), full width, 44 px high, tray icons
  scaled to fit, date below the time, and the SteamOS launcher icon;
- dark mode for GTK, libadwaita and portal-aware apps (Firefox, Flatpaks).

Run inside a Plasma session, it applies everything live; otherwise it takes
effect at the next desktop login.

**Package version.** The script always takes the newest
`steamdeck-kde-presets` from the highest-numbered SteamOS release repository
on the mirror (`jupiter-3.9`, `jupiter-3.10`, ...). That repository's pacman
database gives the exact file name and SHA-256 checksum, which is verified
after downloading. If the lookup fails, it falls back to the known-good
3.9.4 (see `install_vapor_theme()` in `lib/vapor-theme.sh`). To check the
current version yourself:

```bash
m=https://steamdeck-packages.steamos.cloud/archlinux-mirror
r=$(curl -fsL $m/ | grep -oE 'jupiter-[0-9]+\.[0-9]+/' | tr -d / | sort -V | tail -n 1)
curl -fsL $m/$r/os/x86_64/$r.db | bsdtar -tf - | grep -o '^steamdeck-kde-presets-[^/]*' | sort -u
```

### Front LED bar (Steam Machine)

The **Steam Machine support** component, only shown on Fremont hardware
(DMI `Valve`/`Fremont`, or `OEM`/`F7F` on early units):

- installs an AUR helper (`yay`) if neither `yay` nor `paru` is present;
- installs the kernel headers for every installed kernel;
- installs `leds-valve-dkms-git` from the AUR - Valve's own driver from the
  SteamOS kernel - builds it for the running kernel, and loads it at every
  boot (`/etc/modules-load.d/leds-valve.conf`);
- adds a udev rule (`/etc/udev/rules.d/70-valve-leds-user.rules`) that gives
  your user the LED files, so Steam, which runs as you, can drive the bar;
- installs and enables `steamos-manager`, the service Steam in gaming mode
  uses for hardware settings (fan, HDMI-CEC, performance); it recognises the
  Steam Machine from its DMI data.

Turning it off removes all of that again (the AUR helper is kept).

The LEDs appear as `/sys/class/leds/valve-leds*`. The driver's Makefile
builds against the running kernel, so after a kernel update, boot the new
kernel and re-apply (`a` in the menu) or run
`sudo dkms install leds-valve-dkms/0.1 -k "$(uname -r)"`.

Troubleshooting:

```bash
dkms status
ls -l /sys/class/leds/valve-leds*/
sudo dmesg | grep -i valve
cat /var/lib/dkms/leds-valve-dkms/0.1/build/make.log
journalctl --user -b | grep -i led
```

**BIOS updates** are not part of the wizard. Valve ships the Steam Machine
BIOS as `F7F0108.cab` in its `fremont-hw-support` package for fwupd. To
install it by hand (keep the machine on mains power and don't interrupt it):

```bash
sudo dmidecode -s bios-version     # current version
sudo pacman -S fwupd
curl -LO https://steamdeck-packages.steamos.cloud/archlinux-mirror/holo-3.9/os/x86_64/fremont-hw-support-20260807.1-1-any.pkg.tar.zst
mkdir fhw && tar -I zstd -xf fremont-hw-support-*.pkg.tar.zst -C fhw
sudo fwupdmgr install fhw/usr/share/fwupd/remotes.d/fremont/firmware/F7F0108.cab
```

### Manual session control

```bash
steamos-session-select gamescope   # switch to gamescope right now
steamos-session-select plasma      # switch to desktop right now
steamos-session-select persistent  # remember the last-used session across reboots
steamos-session-select oneshot     # always start in gamescope (default, like a Deck)
```

With `Relogin=true`, a gamescope session that fails to start is restarted
immediately, which can turn into a loop - hence the Ctrl+Alt+F3 escape above.

### Removing everything

Run the wizard and untick everything. Afterwards the PC boots to the normal
CachyOS login screen again; packages installed for the conversion (Steam,
gamescope-session, ...) stay installed.

### Project layout

| File | Responsibility |
|---|---|
| `setup-gamescope-boot.sh` | Entry point: checks, menu, apply, summary, restart |
| `lib/menu.sh` | The menu: detect, toggle, plan and apply changes |
| `lib/state.sh` | Undo journal for KDE settings (`kset`/`krevert`) |
| `lib/common.sh` | Output helpers, prompts, backups, plasmashell handling |
| `lib/packages.sh` | Required packages, AUR helper (yay/paru) |
| `lib/login-manager.sh` | SteamOS conversion: SDDM or plasmalogin autologin, sync bridge |
| `lib/steam-desktop.sh` | Steam in the Plasma session; Steam Deck/Machine icons |
| `lib/desktop-shortcut.sh` | Return to Gaming Mode shortcut and its sudoers rule |
| `lib/vapor-theme.sh` | SteamOS theme: Vapor, Valve's defaults, panel, dark mode |
| `lib/single-user.sh` | Single user mode: no lock screen, user switching or log out |
| `lib/steam-machine.sh` | Steam Machine support: LED driver, LED access, steamos-manager |
| `tools/bundle.sh` | Builds the single-file version (`dist/setup-gamescope-boot.sh`) |
| `.github/workflows/bundle.yml` | Builds and checks it on every push; publishes it on `main` |

The single-file version is generated: on every push to `main`, GitHub
Actions runs `tools/bundle.sh`, checks the result with `bash -n` and
shellcheck, and uploads it to the rolling `latest` release. It inlines
`lib/*.sh` and wraps the entry point in `main()`, so bash has read the whole
file before anything runs; when stdin is a pipe (`curl | bash`) it reattaches
the terminal for the menu (set `WIZARD_KEEP_STDIN=1` to keep piped input).

Notes for contributors and AI coding agents are in [`AGENTS.md`](AGENTS.md).

### Caveats

- This works around CachyOS/`plasma-login-manager` behavior as of September
  2026. If CachyOS fixes `steam-set-session` upstream, parts of this script
  become unnecessary - please open an issue or PR if you notice that.
- Tested on a Valve Steam Machine running CachyOS Desktop edition. It should
  work on any CachyOS desktop install using `plasma-login-manager`, but
  hasn't been tested on Steam Deck/Legion Go hardware.

### Related upstream reports

- [CachyOS/gamescope-session#9](https://github.com/CachyOS/gamescope-session/issues/9) - "Switch to Desktop" hang due to missing `/etc/plasmalogin.conf.d`

## License

MIT - do whatever you want with it.
