# Technical details

How Steamify CachyOS works under the hood. For using it, see
[README.md](README.md); for problems, [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## How turning things on and off works

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

## Single user mode: SDDM, no locking

Turning it on switches to **SDDM** and turns off everything that asks for a
password or another user, per user: `action/lock_screen`, `switch_user` and
`start_new_session` restrictions in `kdeglobals`, no automatic locking
(`kscreenlockerrc`), Meta+L and Ctrl+Alt+Del unbound, and the launcher shows
only Sleep / Restart / Shut Down (kickoff `primaryActions=3`), which hides
the Session dropdown with Log Out. (Restricting `action/logout` would also
hide Restart and Shut Down.) Turning it off restores all of that and moves
the conversion back to plasma-login-manager.

**KDE wallet.** KDE normally unlocks your wallet with the password you log in
with; with autologin nobody types it, so apps that keep passwords in it (Brave,
for example) ask for the wallet password. Single user mode does what SteamOS
does: it uses Valve's empty wallet without a password (from
`steamdeck-kde-presets`, checksum verified). Your own wallet in
`~/.local/share/kwalletd/` is moved to `kdewallet.kwl.bak-steamify` (and
`.salt`). Turning single user mode off puts it back, unchanged; the single
user wallet, with anything saved in it meanwhile, is kept as
`kdewallet.kwl.steamify-single-user` and used again the next time it's on.
Passwords aren't shared between the two wallets.

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

## Why this is needed (plasma-login-manager)

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

## What each component changes

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

## SteamOS desktop look

Installs CachyOS's `cachyos-vapor` package (the SteamOS Vapor theme the
CachyOS handheld edition uses) from the CachyOS repository and switches your
desktop to its Vapor global theme, including its desktop and window layout
(like ticking "Desktop and window layout" in System Settings): Vapor colors
and Plasma style, the SteamOS panel and launcher icon, and the Steam Deck
wallpaper. Run it from the Plasma desktop: applying the layout needs a
running Plasma session.

It also adds the SteamOS desktop extras that `cachyos-vapor` doesn't ship,
taken from the newest `steamdeck-kde-presets` on Valve's SteamOS mirror
(checksum verified) and installed to `/usr/local`:

- **Add to Steam** in the right-click menu of apps, AppImages and `.exe`
  files, and in the launcher: adds them to Steam as non-Steam games;
- **Nested Desktop**: add it to Steam from the launcher, then start it in
  gaming mode for a Plasma desktop inside gaming mode;
- the SteamOS **Return to Gaming Mode** icon (Steam logo with a return arrow);
- a window rule that keeps the **Steam keyboard** above other windows.

Turning it off restores your previous look and panel layout, and removes `cachyos-vapor` again
if the wizard installed it (and nothing else, like `cachyos-handheld`, needs it).

## Front LED bar (Steam Machine)

The **Steam Machine support** component, only shown on Fremont hardware
(DMI `Valve`/`Fremont`, or `OEM`/`F7F` on early units):

- installs an AUR helper (`yay`) if neither `yay` nor `paru` is present;
- installs the kernel headers for every installed kernel;
- installs `leds-valve-dkms-git` from the AUR - Valve's own driver from the
  SteamOS kernel - builds it for every installed kernel (so the LTS kernel
  works too), and loads it at every boot (`/etc/modules-load.d/leds-valve.conf`);
- adds a udev rule (`/etc/udev/rules.d/70-valve-leds-user.rules`) that gives
  your user the LED files, so Steam, which runs as you, can drive the bar;
- console-like power button: it puts the machine to sleep, and it never
  suspends by itself on mains power (the launcher's Shut Down still shuts down);
- installs and enables `steamos-manager`, the service Steam in gaming mode
  uses for hardware settings (fan, performance, and the HDMI-CEC settings
  when [HDMI-CEC](#hdmi-cec) is on); it recognises the Steam Machine from its
  DMI data.

Turning it off removes all of that again (the AUR helper is kept).

The LEDs appear as `/sys/class/leds/valve-leds*`. The driver's Makefile
builds against the running kernel (`uname -r`) instead of the kernel DKMS
builds for, so the wizard adds a DKMS override
(`/etc/dkms/leds-valve-dkms.conf`) that passes DKMS's target kernel in. With
it, DKMS rebuilds the driver whenever a kernel or its headers are installed
or upgraded. A newly added kernel doesn't come with its headers, so
`ensure-kernel-headers.service` checks at every boot and installs any
missing `-headers` package, which makes DKMS build the driver for it.

## HDMI-CEC

The **HDMI-CEC** item (on every PC; ticked by default only on a Steam
Machine) installs
Valve's CEC stack from its SteamOS `holo` repository, the newest `holo-X.Y`
on `steamdeck-packages.steamos.cloud`, each package checked against the
SHA-256 in Valve's package index:

- `cecd`, Valve's CEC daemon (a user service started with the desktop and
  gaming mode): TV remote keys become normal key presses (arrows, Enter,
  Back), and it turns the TV on and off with the PC;
- `cec-audio-control`: volume of the TV or receiver;
- `inputattach-cec-units` (with `linuxconsole` from CachyOS for
  `inputattach`): attaches USB CEC adapters (Pulse-Eight, RainShadow).

It works with any `/dev/cec*`: a GPU that has CEC on its HDMI port (the
Steam Machine; the CachyOS kernel has DisplayPort CEC built in) or a USB
adapter ([CEC.md](CEC.md) lists which PCs have one). The menu lists the CEC
devices found. Also turn on CEC on the TV
(Sony: BRAVIA Sync, Samsung: Anynet+, LG: SimpLink). On a Steam Machine
`steamos-manager` writes cecd's settings from Steam's (wake the TV, put it to
sleep), in `~/.config/cecd/config.d/`, and Steam shows its HDMI-CEC
settings; the wizard restarts steamos-manager so that happens right away.

It's experimental: on SteamOS itself CEC can wake the Steam Machine right
after it goes to sleep (Samsung TVs,
[SteamOS#2626](https://github.com/ValveSoftware/SteamOS/issues/2626)) and
upset CEC for the TV's other devices
([SteamOS#2817](https://github.com/ValveSoftware/SteamOS/issues/2817)).
Turning it off removes the packages again (`linuxconsole` only if the
wizard installed it).

## Kernel pin (Steam Machine)

With CachyOS kernels newer than 7.1.6 a Steam Machine reboots instead of
shutting down. The **Pin the kernel** sub-option (ticked along with Steam
Machine support) installs `linux-cachyos` and `linux-cachyos-headers`
7.1.6-1 and adds them to `IgnorePkg` in `/etc/pacman.conf`, so updates skip
them. DKMS builds the LED driver for it; restart to boot it.

The packages (and their signatures, which pacman checks) are kept in
`/var/cache/steamify/kernel`, so re-applying needs no download. Missing
files are taken from pacman's cache, else downloaded from this repo's
`kernel-7.1.6-1` release, then `archive.cachyos.org`, then
`mirror.cachyos.org` (which only has the current kernel). Every file must
match the SHA-256 in the script and have a valid CachyOS signature; a bad
one is deleted, so the next run downloads it again. Set `PINNED_KERNEL_URL`
to a directory URL with the files to try another source first, or drop them
into the kernel directory yourself.

Unticking it removes the pin and runs `sudo pacman -Syu`, which brings the
kernel back to CachyOS's current version; the files stay for next time.

## BIOS updates (Steam Machine)

The **Update BIOS** item is only shown on a Steam Machine and is never ticked
by default. It shows the BIOS version you have now and the newest one Valve
ships (the `.cab` file in its `fremont-hw-support` package, looked up on
Valve's SteamOS mirror):

```
 [ ] Update BIOS: now F7F0107, newest F7F0108 (own risk)  (opt-in, runs once)
```

It can only be ticked when Valve has a newer BIOS than yours; when you're up
to date, when the newest version can't be looked up (offline), or when an
update is already waiting for a restart, it's greyed out.

When you run it, the wizard:

1. downloads Valve's package and checks its **SHA-256** against Valve's
   repository, so it's exactly Valve's file;
2. asks **fwupd** whether the firmware is for this very machine (fwupd compares
   the firmware's hardware IDs with the device) and stops if it isn't;
3. shows a large red **warning** with the current and the new version, and asks
   whether you understand the risks (default: no);
4. shows the warning **again** and only continues when you type `UPDATE`;
5. hands the firmware to fwupd, which writes it during the **next restart**:
   choose "restart now" or restart later yourself.

**At your own risk:** a failed or interrupted BIOS update can leave the machine
unable to start. Keep it on mains power, and never turn off the power, unplug
it or press the power button while it updates, including during the restart;
the screen can stay black for several minutes.

To walk through it without flashing anything, run the wizard with
`WIZARD_BIOS_DRY_RUN=1`: it downloads and checks the package and shows both
warnings, skips fwupd's device check, and only prints the install command.

## Manual session control

```bash
steamos-session-select gamescope   # switch to gamescope right now
steamos-session-select plasma      # switch to desktop right now
steamos-session-select persistent  # remember the last-used session across reboots
steamos-session-select oneshot     # always start in gamescope (default, like a Deck)
```

With `Relogin=true`, a gamescope session that fails to start is restarted
immediately, which can turn into a loop - see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) for the way out.

## Project layout

| File | Responsibility |
|---|---|
| `steamify.sh` | Entry point: checks, menu, apply, summary, restart |
| `lib/menu.sh` | The menu: detect, toggle, plan and apply changes |
| `lib/state.sh` | Undo journal for KDE settings (`kset`/`krevert`) |
| `lib/common.sh` | Output helpers, prompts, backups, plasmashell handling |
| `lib/packages.sh` | Required packages, AUR helper (yay/paru) |
| `lib/boot-session.sh` | Boot into gamescope or the desktop (`steamify-boot-desktop.service`) |
| `lib/login-manager.sh` | SteamOS conversion: SDDM or plasmalogin autologin, sync bridge |
| `lib/steam-desktop.sh` | Steam in the Plasma session; Steam Deck/Machine icons |
| `lib/desktop-shortcut.sh` | Return to Gaming Mode shortcut and its sudoers rule |
| `lib/vapor-theme.sh` | SteamOS theme: installs and switches to `cachyos-vapor` |
| `lib/steamos-extras.sh` | SteamOS desktop extras from Valve's package (Add to Steam, Nested Desktop, icon, keyboard rule, KWallet) |
| `lib/single-user.sh` | Single user mode: no lock screen, user switching or log out |
| `lib/wizard-shortcut.sh` | Steamify shortcut: desktop icon and launcher entry that run the newest release |
| `lib/bios.sh` | Update BIOS (Steam Machine, opt-in): current/newest version, double confirmation, fwupd |
| `lib/cec.sh` | HDMI-CEC: Valve's `cecd` and friends from its `holo` repository |
| `lib/steam-machine.sh` | Steam Machine support: LED driver, LED access, steamos-manager; kernel pin |
| `.github/tools/bundle.sh` | Builds the single-file version (`dist/steamify.sh`) |
| `.github/workflows/bundle.yml` | Builds and checks it on every push; publishes it on `main` |

The single-file version is generated: on every push to `main`, GitHub
Actions runs `.github/tools/bundle.sh`, checks the result with `bash -n` and
shellcheck, and publishes it as a release per version (tag `v<VERSION>`,
never overwritten; the newest is marked latest, and the `latest` tag follows
it). It inlines
`lib/*.sh` and wraps the entry point in `main()`, so bash has read the whole
file before anything runs; when stdin is a pipe (`curl | bash`) it reattaches
the terminal for the menu (set `WIZARD_KEEP_STDIN=1` to keep piped input).

Notes for contributors and AI coding agents are in [`AGENTS.md`](AGENTS.md).

## Caveats

- This works around CachyOS/`plasma-login-manager` behavior as of September
  2026. If CachyOS fixes `steam-set-session` upstream, parts of this script
  become unnecessary - please open an issue or PR if you notice that.
- Tested on a Valve Steam Machine running CachyOS Desktop edition. It should
  work on any CachyOS desktop install using `plasma-login-manager`, but
  hasn't been tested on Steam Deck/Legion Go hardware.

## Related upstream reports

- [CachyOS/gamescope-session#9](https://github.com/CachyOS/gamescope-session/issues/9) - "Switch to Desktop" hang due to missing `/etc/plasmalogin.conf.d`
