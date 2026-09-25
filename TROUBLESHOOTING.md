# Troubleshooting

See [TECHNICAL.md](TECHNICAL.md) for how each part works.

## Gaming mode shows a black screen or keeps restarting

Press **Ctrl+Alt+F3**, log in with your username and password, and run:

```bash
sudo /usr/lib/steamos/steam-set-session plasma.desktop && sudo systemctl restart display-manager
```

That takes you back to the desktop. Gamescope sessions that fail to start are
restarted right away (`Relogin=true`), which is why it can loop.

## Something is set up wrong

Run the wizard again and press `a` in the menu to re-apply everything that's
on (also useful after a CachyOS update). To undo a part, untick it.

## The LED bar on the Steam Machine stays dark

Restart once more; a freshly installed driver often needs a reboot. The menu
shows per kernel whether the LED driver is built, and whether it's loaded.
Still dark:

```bash
dkms status
ls -l /sys/class/leds/valve-leds*/
sudo dmesg | grep -i valve
cat /var/lib/dkms/leds-valve-dkms/0.1/build/make.log
journalctl --user -b | grep -i led
```

## The TV remote does nothing (HDMI-CEC)

- Turn on CEC in the TV's settings (Sony: BRAVIA Sync, Samsung: Anynet+, LG:
  SimpLink) and, if it has one, allow the PC to control it.
- Check that the PC has a CEC device, and that `cecd` runs:

```bash
ls /dev/cec*
systemctl --user status cecd
journalctl --user -u cecd -b
cec-ctl -d /dev/cec0 -S        # the devices on the TV's CEC bus (v4l-utils)
```

No `/dev/cec*`: your GPU's HDMI port has no CEC; a USB CEC adapter
(e.g. Pulse-Eight) works. The Steam Machine wakes up again right after going
to sleep, or other devices lose CEC? That happens on SteamOS too; turn
HDMI-CEC off in the wizard.

## The Steam Machine still reboots when I shut it down

Check that the pinned kernel is installed and running:

```bash
uname -r                                   # should be 7.1.6-1-cachyos
pacman -Q linux-cachyos linux-cachyos-headers
grep '^IgnorePkg' /etc/pacman.conf         # should list both packages
```

Not running it yet? Restart. Not installed? Run the wizard and make sure
**Pin the kernel** under Steam Machine support is ticked. If you have more
kernels installed (e.g. the LTS kernel), pick `linux-cachyos` in the boot menu.

## The kernel pin can't download or verify the kernel

The wizard tries this repo's `kernel-7.1.6-1` release, then the CachyOS
archive and mirror. A file that fails its checksum or CachyOS signature is
deleted, so running the wizard again downloads it once more. Offline? Put
the four files from the
[kernel-7.1.6-1 release](https://github.com/theupriser/steamify-cachyos/releases/tag/kernel-7.1.6-1)
in `/var/cache/steamify/kernel` and run it again.

