# AGENTS.md

Guidance for AI coding agents working on this repository. See `README.md`
for what the script does from a user's point of view.

## Project overview

A bash wizard that makes CachyOS (KDE Plasma 6 + `plasma-login-manager`)
boot into a SteamOS-style gamescope session, with working switching between
gamescope and the Plasma desktop. Primary target: the Valve Steam Machine
(DMI `Valve`/`Fremont`) running CachyOS Desktop edition.

## Layout

- `setup-gamescope-boot.sh` - the only entry point. Pre-flight checks,
  sources `lib/*.sh`, then calls the steps in order. No step logic here.
- `lib/*.sh` - one file per responsibility, each defining functions only
  (no top-level side effects). See the table in `README.md`. New
  functionality goes in the module it belongs to, or a new module that is
  added to the `source` loop in `setup-gamescope-boot.sh`.

## Conventions

- Bash, `set -uo pipefail` (no `-e`): check exit codes of steps that matter
  explicitly (`|| { err ...; exit 1; }` or `|| return 1`).
- Use the helpers from `lib/common.sh` (`info`, `ok`, `warn`, `err`,
  `ask_yn`, `backup_file`) for all output and prompts.
- Runs as the normal user; use `sudo` per command, never require root.
  Per-user files go in `$HOME` of the invoking user (the script refuses to
  configure another user).
- **Idempotent**: every step must be safe to re-run without duplicating
  lines or settings. Back up system files with `backup_file` before the
  first edit.
- Don't overwrite package-owned files in `/etc/xdg` or `/usr`. KDE settings
  go into the user's config via `kwriteconfig6` (or `merge_kde_config` for
  whole Valve ini files).
- Package installs after a user already confirmed use `--noconfirm`: a
  second pacman prompt consumes the next scripted answer.
- Comments explain *why* (the CachyOS/Plasma quirk being worked around),
  not what the next line does.

## Non-obvious behaviour to preserve

- `steam-set-session` only writes `/etc/plasmalogin.conf.d/zz-steamos-autologin.conf`;
  the base `/etc/plasmalogin.conf` wins, hence the sync bridge. The sync
  service needs `StartLimitIntervalSec=0`, or bursts of session switches
  get it rate-limited and all later switches silently stop working.
- The sync script must only edit `Session=` inside `[Autologin]`.
- The Steam desktop autostart unit is guarded with
  `ExecCondition=... XDG_CURRENT_DESKTOP = KDE`, so it doesn't start a
  second Steam inside gamescope.
- Vapor theme: install Valve's files as shipped. Don't rewrite Valve's
  `metadata.json`; the icon theme is `breeze-dark` (there is no "Vapor"
  icon theme); wallpapers are flat JPGs in `usr/share/wallpapers`.
  `lookandfeeltool` does not switch the color scheme, so
  `plasma-apply-colorscheme Vapor` is applied explicitly.
- Plasma 6 has no separate systemtray containment: tray settings live on
  the systemtray applet itself (Valve's setup script targets Plasma 5).
- Restart plasmashell via `systemctl --user` (`plasma-plasmashell.service`),
  not `plasmashell --replace` from the script's shell: a shell without the
  session environment yields a light-themed desktop (context menus, apps it
  launches).
- Live Plasma changes (`qdbus6 ... evaluateScript`, `lookandfeeltool`) only
  run when `plasmashell` is running; config-file fallbacks cover the rest.
- LED driver: `leds-valve-dkms-git`'s Makefile builds against `uname -r`,
  so the script builds explicitly for the running kernel and installs
  headers for every installed kernel first. The module creates
  `/sys/class/leds/valve-leds*`.
- `Relogin=true` means a gamescope that fails to start is relaunched in a
  tight loop; keep that in mind when changing session handling.

## Checking changes

There is no test suite. At minimum:

```bash
for f in setup-gamescope-boot.sh lib/*.sh; do bash -n "$f"; done
shellcheck -S warning setup-gamescope-boot.sh lib/*.sh   # if available
```

Behaviour is best verified in a CachyOS VM (QEMU/KVM, KDE Plasma install,
`plasma-login-manager`) with SSH access, reset from a disk snapshot between
runs. Notes from doing this:

- Run the script non-interactively by piping answers, e.g.
  `printf "\ny\nn\n" | ./setup-gamescope-boot.sh` (user, theme, reboot).
  The prompt order depends on what's already installed.
- Over SSH, export the session environment before running it so the live
  Plasma steps work:
  `XDG_RUNTIME_DIR=/run/user/$UID WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus`.
- `spectacle -b -n -f -o shot.png` takes a screenshot to check the look.
  Apps you launch over SSH lack the session's Qt platform theme and look
  light; launch them with `systemd-run --user` to judge colors correctly.
- Gamescope usually won't render in a VM (no suitable Vulkan), so test the
  session logic with `plasma.desktop` as the autologin session. The
  gamescope boot itself and the LED driver can only be verified on real
  hardware.
