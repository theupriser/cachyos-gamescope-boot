# HDMI-CEC: does my PC have it?

The **HDMI-CEC** item in Steamify lets you use Steam with your TV's remote,
and turns the TV on and off with the PC. It only works when the PC has a
CEC device (`/dev/cec*`). Many PCs don't: on desktop PCs CEC is rare.
How it works: [TECHNICAL.md](TECHNICAL.md#hdmi-cec); problems:
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#the-tv-remote-does-nothing-hdmi-cec).

## Graphics cards

- **NVIDIA:** no. The driver doesn't expose CEC on the HDMI port, on Linux
  or Windows.
- **AMD and Intel:** the CEC line of the HDMI port is normally not
  connected on desktop cards. The Linux drivers (`amdgpu`, `i915`) only
  support CEC over a **DisplayPort** connection: some DisplayPort-to-HDMI
  adapters and built-in converter chips pass CEC along ("DP-AUX CEC"). That
  depends on the adapter or chip, not on the graphics card, so it's worth
  trying a different adapter.

## Devices with CEC built in

- the **Valve Steam Machine** (Steamify ticks HDMI-CEC by default there);
- some **Intel NUC** mini PCs, which have a CEC chip on the board;
- the **Raspberry Pi**.

## Any PC: a USB CEC adapter

A USB CEC adapter, such as the **Pulse-Eight USB-CEC adapter** (or a
RainShadow Tech one), sits between the PC and the TV on the HDMI cable and
works on Linux. This is the way to get CEC on a custom build, e.g. with an
NVIDIA card. Steamify installs what these adapters need
(`inputattach-cec-units`), so plug it in and turn on HDMI-CEC.

## Check your PC

After turning on HDMI-CEC in Steamify, the menu lists the CEC devices it
found. Or run:

```bash
ls /dev/cec*
```

No device (and no USB adapter): no CEC on this PC. Also turn on CEC on the
TV itself: it has a brand name there (Sony: BRAVIA Sync, Samsung: Anynet+,
LG: SimpLink, Philips: EasyLink, Panasonic: VIERA Link).

This overview is based on how the Linux drivers work; hardware differs,
so the only sure test is `ls /dev/cec*` on your own PC.
