# CachyOS Gamescope Boot Wizard

Turn a CachyOS desktop PC into a SteamOS-style console: it boots straight
into Steam's Big Picture (gamescope), and you can switch to the KDE Plasma
desktop and back whenever you like - just like on a Steam Deck or Valve's
Steam Machine.

Out of the box, CachyOS doesn't quite manage this: the switch to the desktop
can hang, and the PC doesn't reliably boot back into gaming mode. This
script fixes that and sets everything up for you.

## What you get

- **Boots into gaming mode** automatically, without a login screen.
- **Switch to Desktop** from Steam's power menu works, and so does going
  back: use the **Return to Gaming Mode** icon on the desktop, or just log
  out.
- **Back to gaming mode after a restart**, like SteamOS.
- **Steam's on-screen keyboard** (Steam + X) also works on the desktop.
- *Optional:* the **SteamOS desktop look** - Valve's own Vapor theme,
  wallpaper, dark mode and taskbar.
- *Optional, Steam Machine only:* a driver for the **front LED bar**.

## Requirements

- CachyOS with the KDE Plasma desktop (the default CachyOS Desktop edition)
- Your normal user account, with permission to use `sudo`

## Installation

Open **Konsole** on your Plasma desktop and run:

```bash
git clone <this-repo-url>
cd <this-repo>
./setup-gamescope-boot.sh
```

Run it as yourself, not as root. It asks for your password once, then asks a
few yes/no questions (whether to install missing packages, the SteamOS look,
and the LED driver on a Steam Machine). At the end it offers to restart.

Keep the whole folder: the script needs the files in `lib/` next to it.

It's safe to run again later, for example after a CachyOS update.

## Using it

- **To the desktop:** in gaming mode, open the Steam menu and choose
  **Power > Switch to Desktop**.
- **Back to gaming mode:** double-click **Return to Gaming Mode** on the
  desktop, or log out.
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
steamos-session-select plasma && sudo systemctl restart plasmalogin
```

That takes you back to the desktop.

**The LED bar on the Steam Machine stays dark.** Restart the PC once more; a
freshly installed driver often needs a reboot. Still dark? See
[Front LED bar](#front-led-bar-steam-machine) under technical details.

**Undo the SteamOS look:** pick another theme under **System Settings >
Colors & Themes > Global Theme**.

To remove everything the script set up, see
[Removing everything](#removing-everything).

---

## Technical details

### Why this is needed

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

### What the script changes

In order:

1. Checks the display manager (warns if it isn't `plasma-login-manager`) and
   that it runs as the user that should autologin.
2. Installs missing packages: `gamescope-session-cachyos`, `steam`,
   `mangohud`, `xterm`, `ttf-liberation`, `wqy-zenhei`, `plasma-keyboard`.
3. Creates `/etc/plasmalogin.conf.d`, backs up and rewrites the
   `[Autologin]` section of `/etc/plasmalogin.conf`, and removes stray
   `zzz-steamos-autologin*.conf` files from manual troubleshooting (never
   `zz-steamos-autologin.conf`, which CachyOS's tools own).
4. Installs `/usr/local/bin/sync-steamos-session.sh` plus
   `sync-steamos-session.path`/`.service`, which keep the base config in sync
   with session switches.
5. Sets up Steam for the desktop: `STEAM_GAMEPADUI_ARGS="-gamepadui -steamos3"`
   (gamepad UI with Steam Deck glyphs), `KWIN_IM_SHOW_ALWAYS=1` for the
   virtual keyboard, and a `steam-desktop-autostart` systemd user service
   that starts Steam silently in Plasma only.
6. *(Steam Machine, optional)* the LED driver - see below.
7. *(Optional)* the SteamOS desktop look - see below.
8. Creates the **Return to Gaming Mode** shortcut, with a narrow sudoers rule
   (`/etc/sudoers.d/gamescope-session-switch`) so it can restart the login
   manager without a password prompt.

Re-running doesn't duplicate any settings. Every system file it modifies is
backed up once, next to the original, with a `.bak-gamescope-wizard` suffix.

### SteamOS desktop look

Downloads Valve's official `steamdeck-kde-presets` package from Valve's
SteamOS mirror and installs it into `~/.local/share` - nothing system-wide:

- the Vapor global theme, color scheme, Plasma style, wallpapers and icons;
- the Vapor GTK theme, Konsole profile and user avatars;
- Valve's SteamOS desktop defaults, merged into your own config: Noto Sans
  fonts, no Xwayland input-permission prompt for Steam Input, the window
  rule that keeps the Steam keyboard on top and out of the taskbar, no
  screen locking, no welcome screen, light file indexing;
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

Standard desktop kernels, including CachyOS's, lack Valve's `leds-valve`
driver, so the Steam Machine's front LED bar goes dark or "breathes". On
Fremont hardware (DMI `Valve`/`Fremont`) the script offers to:

- install an AUR helper (`yay`) if neither `yay` nor `paru` is present;
- install the kernel headers for every installed kernel;
- install `leds-valve-dkms-git` from the AUR, build it for the running
  kernel, and load it at every boot (`/etc/modules-load.d/leds-valve.conf`);
- optionally install the experimental `openrgb-git`, which can drive the bar.

The LEDs appear as `/sys/class/leds/valve-leds*`. Steam itself only drives
the bar (e.g. download progress) in real SteamOS Game Mode.

The driver's Makefile builds against the running kernel, so after a kernel
update, boot the new kernel and re-run the script (or
`sudo dkms install leds-valve-dkms/0.1 -k "$(uname -r)"`).

Troubleshooting:

```bash
dkms status
ls /sys/class/leds | grep valve
sudo dmesg | grep -i valve
cat /var/lib/dkms/leds-valve-dkms/0.1/build/make.log
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

```bash
# restore the original login config
sudo cp /etc/plasmalogin.conf.bak-gamescope-wizard /etc/plasmalogin.conf

# session sync watcher
sudo systemctl disable --now sync-steamos-session.path
sudo rm /etc/systemd/system/sync-steamos-session.path
sudo rm /etc/systemd/system/sync-steamos-session.service
sudo rm /usr/local/bin/sync-steamos-session.sh
sudo systemctl daemon-reload

# shortcut and its sudoers rule
sudo rm /etc/sudoers.d/gamescope-session-switch
rm ~/Desktop/"Return to Gaming Mode.desktop"

# Steam desktop autostart and environment
systemctl --user disable --now steam-desktop-autostart.service
rm ~/.config/systemd/user/steam-desktop-autostart.service
rm ~/.config/environment.d/99-gamescope-steam-glyphs.conf \
   ~/.config/environment.d/99-kde-virtual-keyboard.conf

# LED driver (Steam Machine)
sudo rm /etc/modules-load.d/leds-valve.conf
sudo pacman -R leds-valve-dkms-git
```

### Project layout

| File | Responsibility |
|---|---|
| `setup-gamescope-boot.sh` | Entry point: user and sudo checks, step order, summary, reboot |
| `lib/common.sh` | Output helpers, yes/no prompts, backups |
| `lib/packages.sh` | Required packages, AUR helper (yay/paru) |
| `lib/login-manager.sh` | plasmalogin autologin, session sync bridge and its systemd units |
| `lib/steam-desktop.sh` | Steam in the Plasma session: gamepad UI flags, virtual keyboard, autostart |
| `lib/led-driver.sh` | Fremont detection, kernel headers, LED driver, OpenRGB |
| `lib/vapor-theme.sh` | Vapor theme, Valve's SteamOS defaults, panel, dark mode |
| `lib/desktop-shortcut.sh` | Return to Gaming Mode shortcut and its sudoers rule |

Notes for contributors and AI coding agents are in [`AGENTS.md`](AGENTS.md).

### Caveats

- This works around CachyOS/`plasma-login-manager` behavior as of September
  2026. If CachyOS fixes `steam-set-session` upstream, parts of this script
  become unnecessary - please open an issue or PR if you notice that.
- Tested on a Valve Steam Machine running CachyOS Desktop edition. It should
  work on any CachyOS desktop install using `plasma-login-manager`, but
  hasn't been tested on Steam Deck/Legion Go hardware, which typically use
  SDDM. With another display manager the script warns and asks before
  continuing.

### Related upstream reports

- [CachyOS/gamescope-session#9](https://github.com/CachyOS/gamescope-session/issues/9) - "Switch to Desktop" hang due to missing `/etc/plasmalogin.conf.d`

## License

MIT - do whatever you want with it.
