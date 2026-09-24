# AGENTS.md

Guidance for AI coding agents working on this repository. See `README.md`
for what the script does from a user's point of view.

## Project overview

**Steamify CachyOS**: a bash wizard that makes CachyOS (KDE Plasma 6 + `plasma-login-manager`)
boot into a SteamOS-style gamescope session, with working switching between
gamescope and the Plasma desktop. Primary target: the Valve Steam Machine
(DMI `Valve`/`Fremont`) running CachyOS Desktop edition.

## Layout

- `steamify.sh` - the only entry point. Pre-flight checks,
  sources `lib/*.sh`, runs the menu and applies the plan. No component
  logic here.
- `lib/*.sh` - one file per responsibility, each defining functions only
  (no top-level side effects besides constants). See the table in
  `README.md`.
- **Components.** Every menu item `<id>` (listed in `COMPONENTS` and `LABEL`
  in `lib/menu.sh`) provides `<id>_status` (return 0 if on, detected from
  the system, no state file needed), `<id>_enable` and `<id>_disable`, all
  idempotent. `<id>_enable` is also used to re-apply. Optional
  `<id>_available` is checked via `component_available` (e.g. `machine`
  only on Fremont). Turn-on order is `COMPONENTS` order, turn-off reverse;
  `gaming` must stay first. Dependencies live in `toggle_component`.
- **Reversibility.** Every per-user KDE setting a component changes goes
  through `kset <component> <file> <group|group> <key> <value>`
  (`lib/state.sh`), which records the old value once; `<id>_disable` calls
  `krevert <component>`. Never call `kwriteconfig6` directly for settings a
  component owns. System files are backed up with `backup_file` and restored
  on disable.
- **Single-file build.** `.github/tools/bundle.sh` inlines `lib/*.sh` in the order of
  the entry point's `for lib in ...; do` source loop and wraps everything
  after that loop in `main()`. Keep that loop on one line, keep all logic in
  functions, and don't rely on `SCRIPT_DIR` for anything but sourcing.
  CI (`.github/workflows/bundle.yml`) publishes the bundle as release
  `v$VERSION` on pushes to `main`; an existing version is never overwritten,
  so bump `VERSION` for every release.

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

- **Versioning and releases.** SemVer in `VERSION` (`steamify.sh`,
  shown in the menu header and the bundle header).
  - Every commit gets an entry in `CHANGELOG.md` under its version (short hash
    + subject; a commit can't contain its own hash, so fill it in with the
    next commit). The section heading must be `## <VERSION> - <date>`: CI
    cuts the release notes out of the changelog by that heading.
  - Every PR that should be released bumps `VERSION` and adds its section.
    A push to `main` publishes release `v$VERSION` (tag + bundle + that
    changelog section) and marks it latest. An existing version is never
    overwritten: without a bump nothing is released, and pull requests show
    a warning.
  - Users install through `releases/latest/download/steamify.sh`
    (GitHub's newest release). The `latest` tag and release follow the newest
    version tag too (moved, asset replaced, when a new version is released),
    so the older URL `releases/download/latest/...` keeps working.

## Non-obvious behaviour to preserve

- `apply_changes` sets `$LOGIN_MANAGER` from the menu: `sddm` when single
  user mode is wanted, else `plasmalogin`. Toggling single user re-applies
  `gaming` so it moves to the other login manager. Single user mode hides
  the launcher's Session dropdown via kickoff `primaryActions=3` (restricting
  `action/logout` also hides Restart/Shut Down). Two login-manager paths:
  **sddm** (like SteamOS: `steam-set-session` writes
  `/etc/sddm.conf.d/zz-steamos-autologin.conf`, which SDDM honours; we add
  `User=`/`Relogin=` in `10-gamescope-autologin.conf`, and `/etc/sddm.conf`
  must not contain `[Autologin]` since it's read last) and **plasmalogin**
  (needs the sync bridge and the shortcut's sudoers rule). Both must keep
  working.

- `steam-set-session` only writes `/etc/plasmalogin.conf.d/zz-steamos-autologin.conf`;
  the base `/etc/plasmalogin.conf` wins, hence the sync bridge. The sync
  service needs `StartLimitIntervalSec=0`, or bursts of session switches
  get it rate-limited and all later switches silently stop working.
- The sync script must only edit `Session=` inside `[Autologin]`.
- The Steam desktop autostart unit is guarded with
  `ExecCondition=... XDG_CURRENT_DESKTOP = KDE`, so it doesn't start a
  second Steam inside gamescope.
- Vapor theme: comes from the `cachyos-vapor` package (system-wide, in
  `/usr/share`); only remove it on disable if we installed it. It is applied
  with `lookandfeeltool --resetLayout` ("Desktop and window layout"), which
  replaces the panel/desktop layout: the layout files are backed up to
  `$STATE_DIR/theme-layout` and restored, and every key from Vapor's
  `contents/defaults` goes through `kset` first. `plasma-apply-colorscheme`
  runs with the `ColorScheme` key cleared, since it skips a scheme already
  named there. The layout reset drops single user's launcher settings, so
  `single_launcher` is re-applied.
- SteamOS extras (`lib/steamos-extras.sh`, part of the theme): downloaded from
  Valve's newest `steamdeck-kde-presets` (repo db gives name + SHA-256) into
  `/usr/local`, never `/usr`. `gaming-return.svg` is a symlink in the package:
  install `steam-gaming-return.svg` under that name. The shortcut's icon is
  switched with `set_shortcut_icon`, since the conversion is created before
  the theme. An existing KWallet is never replaced or removed.
- Plasma 6 has no separate systemtray containment: tray settings live on
  the systemtray applet itself (Valve's setup script targets Plasma 5).
- Restart plasmashell via `systemctl --user` (`plasma-plasmashell.service`),
  not `plasmashell --replace` from the script's shell: a shell without the
  session environment yields a light-themed desktop (context menus, apps it
  launches).
- Live Plasma changes (`qdbus6 ... evaluateScript`, `lookandfeeltool`) only
  run when `plasmashell` is running; config-file fallbacks cover the rest.
- plasmashell writes its in-memory config back on exit: edit panel/applet/
  wallpaper files only between `stop_plasmashell_for_edit` and
  `restart_plasmashell_if_stopped` (`lib/common.sh`).
- LED driver: `leds-valve-dkms-git`'s Makefile builds against `uname -r`,
  not DKMS's target kernel: `/etc/dkms/leds-valve-dkms.conf` sets
  `MAKE[0]="make KVERSION=${kernelver}"` (written before the AUR install).
  Without it, other kernels build against the running kernel's tree and
  fail (CachyOS kernels are clang-built; DKMS adds `LLVM=1` only for the
  target's tree). Headers for every installed kernel are installed first,
  and `ensure-kernel-headers.service` installs missing ones at boot (a
  pacman hook can't run pacman), which triggers DKMS's install hook. The module creates
  `/sys/class/leds/valve-leds*`.
- `bios` is an *action* (`ACTIONS` in `lib/menu.sh`), not an on/off
  component: never preselected (not even on a first run), never re-applied
  by `a`, not listed in the state overview, and `bios_status` is always off.
  Only selectable when Valve's version differs from the installed one
  (`component_selectable`, greyed out otherwise). Download, SHA-256 and the
  fwupd device check (`get-details --json`: no `UpdateError`) come before the
  warnings. The warning box uses `█` for its frame: Konsole draws a long
  coloured row of `#` narrower, so the right edge wouldn't line up.
  Keep both confirmations (y/N, then typing `UPDATE`) and the warnings; the
  firmware comes from the newest `holo-X.Y` repo (`.files` db names the
  `.cab`, `.db` gives the SHA-256), and fwupd itself refuses non-Fremont
  hardware. In the VM, test it with `WIZARD_BIOS_DRY_RUN=1` (skips only the
  device check, never flashes) and a faked version (dev-env
  `BIOS_VERSION=F7F0107 ./run.sh --fremont`).
- The entry point loops: menu, run, "back to the menu" (or `[m]`/`[r]` when a
  restart is needed), until `q`; the restart question is asked once at the
  end. Scripted input that runs out ends the loop like `q`.
- Steamify shortcut (`launcher`): the icon runs `curl | bash` of
  `releases/latest/download/steamify.sh` in Konsole, so it's
  always the newest release. Its icon, `assets/steam-gaming-settings.svg`
  (Valve's GPL-2.0 return icon with a gear), is a release asset too, and is
  downloaded from there (Steam's icon if that fails). Desktop files are
  written with their mode already set (`install_executable`): Plasma opens a
  desktop icon it first saw non-executable in an editor.
- `Relogin=true` means a gamescope that fails to start is relaunched in a
  tight loop; keep that in mind when changing session handling.

## Checking changes

The bundle puts every module in one file, so shellcheck sees all their
`local` variables together: don't reuse a name another module uses as an
array (e.g. `g` in `lib/state.sh`), or CI's shellcheck on the bundle fails.


There is no test suite. At minimum:

```bash
for f in steamify.sh lib/*.sh; do bash -n "$f"; done
shellcheck -S warning steamify.sh lib/*.sh   # if available
```

Behaviour is verified in a CachyOS QEMU/KVM test VM. The VM scripts and a
Claude Code skill describing the whole test workflow (snapshots, SSH, running
the wizard with scripted menu input such as `printf '2\n\ny\nn\n'`, the
per-component checks; when stdin is not a terminal the menu falls back to a
numbered prompt, which is what scripted runs use, reboot checks, the full test matrix, `--fremont` to
fake Steam Machine hardware) live in
[steamify-cachyos-dev](https://github.com/theupriser/steamify-cachyos-dev).
Gamescope itself and the real LED bar can only be verified on hardware.
