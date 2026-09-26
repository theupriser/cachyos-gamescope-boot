#!/bin/bash
# "HDMI refresh boost" menu item, Steam Machine (Fremont) only: finds the
# highest refresh rate the display runs at the desktop resolution over HDMI,
# tests it live and saves an EDID override per display, loaded only while
# that display is connected (see hdmi_install_hotplug). Two things keep displays below what they can do:
# - Monitors put their fast modes in an extra EDID block (HDMI Forum EEODB);
#   the pinned kernel (7.1.6) only reads the first extension. Newer kernels
#   do, and do HDMI 2.1, so it's only offered with the pinned kernel.
# - Their fastest modes need HDMI 2.1 (FRL), which amdgpu doesn't do on
#   every kernel; a mode with the display's shortest blanking at a slightly
#   lower rate often still fits HDMI 2.0's TMDS limit (600 MHz).
# What a display claims isn't what it accepts: every step is shown and must
# be confirmed, and no answer within 15 s switches back (the screen may be
# black). Sourced by steamify.sh; not meant to be run on its own.

HDMI_FW_DIR=/usr/lib/firmware/edid
# Before 2.1.0 the override was on the kernel command line; only removed now.
HDMI_INITRAMFS_CONF=/etc/mkinitcpio.conf.d/90-steamify-edid.conf
# The saved displays, one per line: <id> TAB <name> TAB <w>x<h> TAB <rates>.
# Their EDIDs are $HDMI_FW_DIR/steamify-<id>.bin.
HDMI_MAP=/etc/steamify/hdmi-edid.conf
# Per output, the ID of the display whose EDID is loaded, or "reset".
HDMI_RUN=/run/steamify-edid
HDMI_HOTPLUG=/usr/local/bin/steamify-edid-hotplug
HDMI_UNIT_NAME=steamify-edid.service
HDMI_UNIT="/etc/systemd/system/$HDMI_UNIT_NAME"
HDMI_UDEV_RULE=/etc/udev/rules.d/90-steamify-edid.rules
# No answer within this time switches back; longer for scripted tests.
HDMI_CONFIRM_SECONDS="${WIZARD_HDMI_CONFIRM_SECONDS:-15}"
# amdgpu's HDMI 2.0 limit; the display's own limit (from its EDID) may be lower.
HDMI_TMDS_MAX_KHZ=600000
# Rates picked and tested in the app ("<output>=<w>x<h>:<rate>,..."), set by
# the backend's apply --hdmi; empty in the terminal menu, which tests itself.
HDMI_CHOICE=()

hdmi_connectors() {
    # Connected HDMI outputs, as "<card>-<connector>" (e.g. card1-HDMI-A-1).
    local d
    for d in /sys/class/drm/card*-HDMI-A-*; do
        [[ "$(cat "$d/status" 2>/dev/null)" == connected ]] && basename "$d"
    done
}

hdmi_boot_file() {
    # The file holding the kernel command line, per boot loader.
    if [[ -f /etc/default/limine ]]; then echo /etc/default/limine
    elif [[ -f /etc/sdboot-manage.conf ]] && command -v sdboot-manage >/dev/null; then echo /etc/sdboot-manage.conf
    elif [[ -f /etc/default/grub ]]; then echo /etc/default/grub
    fi
}

hdmi_cmdline_param() {
    # The drm.edid_firmware= value we set, or nothing.
    local f; f="$(hdmi_boot_file)"
    [[ -n "$f" ]] && grep -oE 'drm\.edid_firmware=[^ "]*steamify-[^ "]*' "$f" 2>/dev/null | head -n 1
}

hdmi_available() {
    # Stays available while on, so it can be turned off after the pin is gone.
    detect_valve_fremont || return 1
    # Saved displays too, so they can be removed without the pin.
    hdmi_status || [[ -n "$(hdmi_saved)" ]] || { pinned_kernel_installed && [[ -n "$(hdmi_connectors)" ]]; }
}

hdmi_status() {
    # On = the connected display runs on its saved EDID. Another display on
    # the port is off, so ticking it sets that one up. The command line: set
    # up by an older version, re-applying moves it over.
    [[ -n "$(hdmi_active_ids)" ]] ||
        { [[ -n "$(hdmi_cmdline_param)" ]] && compgen -G "$HDMI_FW_DIR/steamify-*.bin" >/dev/null; }
}

hdmi_saved() { [[ -f "$HDMI_MAP" ]] && grep -v '^#' "$HDMI_MAP"; }

hdmi_active_ids() {
    # IDs of the connected displays whose saved EDID is loaded.
    local f
    for f in "$HDMI_RUN"/*; do [[ -f "$f" ]] && grep -vx reset "$f"; done
    return 0
}

hdmi_edid_tool() {
    # hdmi_edid_tool <command> ...: EDID parsing and building (python, as
    # it's byte work). Commands:
    #   blocks <edid>                number of blocks the display says it has
    #   id <edid>                    vendor/product/serial, to recognise it
    #   plan <edid> <w> <h> <cur_hz> "<limit_hz> <best> <step>..." for w x h
    #   build <in> <out> <w> <h> <hz>...  full EDID plus a DisplayID block
    #                                with those rates at the shortest blanking
    python3 - "$HDMI_TMDS_MAX_KHZ" "$@" <<'PY'
import sys

src_khz = int(sys.argv[1]); cmd = sys.argv[2]; args = sys.argv[3:]
def load(p): return bytearray(open(p, 'rb').read())
def le(b): return int.from_bytes(b, 'little')

def cta_blocks(e):
    for i in range(128, len(e), 128):
        if e[i] == 0x02: yield i

def data_blocks(e, i):
    # CTA data block collection: (tag, extended tag, offset, length)
    end, p = e[i + 2], i + 4
    while p < i + end and p < i + 127:
        tag, n = e[p] >> 5, e[p] & 0x1f
        yield tag, (e[p + 1] if tag == 7 and n else None), p, n
        p += n + 1

def eeodb(e):
    for i in cta_blocks(e):
        for tag, ext, p, n in data_blocks(e, i):
            if tag == 7 and ext == 0x78: return p + 2
    return None

def nblocks(e):
    p = eeodb(e)
    return 1 + max(e[126], e[p] if p and p < len(e) else 0)

def timings(e):
    # (hz, clk_khz, ha, hb, hf, hs, hpos, va, vb, vf, vs, vpos)
    out = []
    def dtd(b):
        clk = le(b[0:2]) * 10
        if not clk: return
        ha = b[2] | (b[4] >> 4) << 8; hb = b[3] | (b[4] & 15) << 8
        va = b[5] | (b[7] >> 4) << 8; vb = b[6] | (b[7] & 15) << 8
        hf = b[8] | (b[11] >> 6 & 3) << 8; hs = b[9] | (b[11] >> 4 & 3) << 8
        vf = (b[10] >> 4) | (b[11] >> 2 & 3) << 4; vs = (b[10] & 15) | (b[11] & 3) << 4
        if b[17] & 0x80: return  # interlaced
        out.append((clk * 1000 / ((ha + hb) * (va + vb)), clk, ha, hb, hf, hs, b[17] >> 1 & 1,
                    va, vb, vf, vs, b[17] >> 2 & 1))
    for o in range(54, 126, 18): dtd(e[o:o + 18])
    for i in cta_blocks(e):
        d = e[i + 2]
        if d >= 4:
            for o in range(i + d, i + 127 - 17, 18): dtd(e[o:o + 18])
    for i in range(128, len(e), 128):
        if e[i] != 0x70: continue
        p, end = i + 5, i + 5 + e[i + 2]
        while p + 3 <= end:
            tag, n = e[p], e[p + 2]
            if tag == 0 and n == 0: break
            if tag == 0x03:
                for o in range(p + 3, p + 3 + n - 19, 20):
                    b = e[o:o + 20]
                    clk = (le(b[0:3]) + 1) * 10
                    hf, vf = le(b[8:10]), le(b[16:18])
                    ha, hb, va, vb = le(b[4:6]) + 1, le(b[6:8]) + 1, le(b[12:14]) + 1, le(b[14:16]) + 1
                    out.append((clk * 1000 / ((ha + hb) * (va + vb)), clk, ha, hb, (hf & 0x7fff) + 1,
                                le(b[10:12]) + 1, hf >> 15, va, vb, (vf & 0x7fff) + 1, le(b[18:20]) + 1, vf >> 15))
            p += 3 + n
    return out

def tmds_khz(e):
    # The display's own TMDS limit: HDMI Forum VSDB, else the HDMI 1.4 VSDB.
    hf = h14 = 0
    for i in cta_blocks(e):
        for tag, ext, p, n in data_blocks(e, i):
            if tag != 3 or n < 3: continue
            oui = e[p + 3] << 16 | e[p + 2] << 8 | e[p + 1]
            if oui == 0xC45DD8 and n >= 5: hf = e[p + 5] * 5000
            if oui == 0x000C03 and n >= 7: h14 = e[p + 7] * 5000
    lim = hf or h14 or 165000
    return min(lim, src_khz)

def max_vrefresh(e):
    # Range limits descriptor, the HDMI Forum / AMD VRR maximum.
    best = 0
    for o in range(54, 126, 18):
        b = e[o:o + 18]
        if b[0:3] == b'\0\0\0' and b[3] == 0xfd:
            best = max(best, b[6] + (255 if b[4] & 2 else 0))
    for i in cta_blocks(e):
        for tag, ext, p, n in data_blocks(e, i):
            if tag != 3 or n < 3: continue
            oui = e[p + 3] << 16 | e[p + 2] << 8 | e[p + 1]
            if oui == 0xC45DD8 and n >= 10: best = max(best, (e[p + 9] & 0xc0) << 2 | e[p + 10])
            if oui == 0x00001A and n >= 7: best = max(best, e[p + 7])
    return best

def shortest(e, w, h):
    ts = [t for t in timings(e) if t[2] == w and t[7] == h]
    return min(ts, key=lambda t: (t[2] + t[3]) * (t[7] + t[8])) if ts else None

if cmd == 'blocks':
    print(nblocks(load(args[0])))
elif cmd == 'id':
    print(load(args[0])[8:18].hex())
elif cmd == 'name':
    e = load(args[0])
    for o in range(54, 126, 18):
        if e[o:o + 3] == b'\0\0\0' and e[o + 3] == 0xfc:
            print(e[o + 5:o + 18].split(b'\n')[0].decode('ascii', 'replace').strip())
elif cmd == 'plan':
    e = load(args[0]); w, h, cur = int(args[1]), int(args[2]), float(args[3])
    lim, t = tmds_khz(e), shortest(e, w, h)
    if not t: sys.exit(1)
    listed = [x[0] for x in timings(e) if x[2] == w and x[7] == h and x[1] <= lim]
    best = max(listed) if listed else cur
    top = int(lim * 1000 // ((t[2] + t[3]) * (t[7] + t[8])))
    vmax = max_vrefresh(e) or int(max(x[0] for x in timings(e) if x[2] == w and x[7] == h))
    top = min(top, vmax)
    # Not right at the limit: the top rounded down to ten, and the hundred
    # below it as a safe option. Rates the display already lists are left
    # out (its own timing is the safer one), and so is anything not faster
    # than what already works.
    steps = sorted({top // 10 * 10, top // 100 * 100})
    steps = [s for s in steps if s > best + 1 and not any(abs(s - x) < 1 for x in listed)]
    print(lim // 1000, round(best, 2), *steps)
elif cmd == 'options':
    # JSON for the app: the display's name, the HDMI limit and the rates to
    # offer at w x h: its own modes the kernel skips ("monitor"), calculated
    # tens up to the limit ("calculated", ticked) and the exact limit when
    # that's no ten ("limit", not ticked).
    import json
    e, k = load(args[0]), load(args[1]); w, h, cur = int(args[2]), int(args[3]), float(args[4])
    lim, t = tmds_khz(e), shortest(e, w, h)
    name = ''
    for o in range(54, 126, 18):
        if e[o:o + 3] == b'\0\0\0' and e[o + 3] == 0xfc:
            name = e[o + 5:o + 18].split(b'\n')[0].decode('ascii', 'replace').strip()
    rates = []
    if t:
        fits = [x for x in timings(e) if x[2] == w and x[7] == h and x[1] <= lim]
        known = [x[0] for x in timings(k) if x[2] == w and x[7] == h]
        listed = [x[0] for x in fits]
        best = max(listed + [cur])
        for x in sorted(fits):
            if x[0] > cur + 1 and not any(abs(x[0] - y) < 0.5 for y in known):
                rates.append({'hz': round(x[0], 2), 'mhz': round(x[1] / 1000, 1), 'kind': 'monitor', 'pick': True})
        size = (t[2] + t[3]) * (t[7] + t[8])
        vmax = max_vrefresh(e) or int(max(listed + [cur]))
        top = min(int(lim * 1000 // size), vmax)
        tens = [r for r in range(10, top + 1, 10) if r > best + 1 and not any(abs(r - y) < 1 for y in listed)][-3:]
        for r in tens:
            rates.append({'hz': r, 'mhz': round(size * r / 1e6, 1), 'kind': 'calculated', 'pick': True})
        if top % 10 and top > best + 1:
            rates.append({'hz': top, 'mhz': round(size * top / 1e6, 1), 'kind': 'limit', 'pick': False})
    print(json.dumps({'name': name, 'limit': lim // 1000, 'rates': rates}))
elif cmd == 'build':
    e = load(args[0]); w, h = int(args[2]), int(args[3]); rates = [int(r) for r in args[4:]]
    t = shortest(e, w, h)
    n = nblocks(e)
    e = e[:n * 128]
    out = b''
    for hz in rates:
        _, _, ha, hb, hf, hs, hp, va, vb, vf, vs, vp = t
        clk = round((ha + hb) * (va + vb) * hz / 1e4)
        x = (clk - 1).to_bytes(3, 'little') + bytes([0x08])
        for v, pol in ((ha, 0), (hb, 0), (hf, hp), (hs, 0), (va, 0), (vb, 0), (vf, vp), (vs, 0)):
            x += ((v - 1) | pol << 15).to_bytes(2, 'little')
        out += x
    if out:
        blk = bytearray(128)
        blk[0:5] = bytes([0x70, 0x12, 121, 0x00, 0x00])
        blk[5:8] = bytes([0x03, 0x00, len(out)])
        blk[8:8 + len(out)] = out
        blk[126] = (-sum(blk[1:126])) % 256
        blk[127] = (-sum(blk[:127])) % 256
        e += blk
    count = len(e) // 128 - 1
    e[126] = count
    e[127] = (-sum(e[:127])) % 256
    p = eeodb(e)
    if p:
        e[p] = count
        i = p - p % 128
        e[i + 127] = (-sum(e[i:i + 127])) % 256
    open(args[1], 'wb').write(e)
PY
}

hdmi_read_edid() {
    # hdmi_read_edid <card-connector> <out>: the display's complete EDID,
    # read over DDC block by block (the kernel's copy may miss blocks).
    local conn="$1" out="$2" bus n i tmp
    bus="$(basename "$(readlink -f "/sys/class/drm/$conn/ddc")")"; bus="${bus#i2c-}"
    tmp="$(mktemp)"
    cat "/sys/class/drm/$conn/edid" > "$out"
    if [[ -n "$bus" ]] && sudo modprobe i2c-dev 2>/dev/null; then
        n="$(hdmi_edid_tool blocks "$out")"
        : > "$tmp"
        for (( i = 0; i < n; i++ )); do
            # Segment pointer (0x30) selects each pair of blocks.
            sudo i2ctransfer -y "$bus" w1@0x30 $(( i / 2 )) w1@0x50 $(( (i % 2) * 128 )) r128@0x50 2>/dev/null |
                xxd -r -p >> "$tmp" 2>/dev/null ||
                { [[ $i -lt 2 ]] && { sudo i2ctransfer -y "$bus" w1@0x50 $(( i * 128 )) r128@0x50 | xxd -r -p >> "$tmp"; }; } || break
        done
        # Keep the DDC copy only when it's whole and the same display as the
        # kernel's (not the whole block: a live override changes it).
        if [[ "$(stat -c %s "$tmp")" == $(( n * 128 )) &&
            "$(hdmi_edid_tool id "$tmp")" == "$(hdmi_edid_tool id "$out")" ]]; then
            cat "$tmp" > "$out"
        fi
    fi
    rm -f "$tmp"
}

hdmi_debugfs() {
    # debugfs directory of a connector (one of several paths to the same
    # GPU). Only root can list debugfs, so the glob runs under sudo.
    local d
    d="$(sudo sh -c 'for d in /sys/kernel/debug/dri/*/"$1"; do [ -e "$d/edid_override" ] && { echo "$d"; break; }; done' _ "${1#card*-}")"
    [[ -n "$d" ]] && echo "$d"
}

hdmi_override_live() {
    # hdmi_override_live <card-connector> <edid|reset>: swap the EDID the
    # kernel uses right now, without a restart.
    local d; d="$(hdmi_debugfs "$1")" || return 1
    # The kernel takes exactly "reset", without a newline.
    if [[ "$2" == reset ]]; then printf reset | sudo tee "$d/edid_override" >/dev/null
    else sudo tee "$d/edid_override" < "$2" >/dev/null; fi || return 1
    echo 1 | sudo tee "$d/trigger_hotplug" >/dev/null
    sleep 3
}

hdmi_kscreen() {
    # hdmi_kscreen current|mode <output> [<w> <h> <hz>]: KDE's view of the
    # output: "w h hz" of the current mode, or set the mode closest to hz.
    kscreen-doctor -j 2>/dev/null | python3 -c '
import json, sys
what, name = sys.argv[1], sys.argv[2]
for o in json.load(sys.stdin)["outputs"]:
    if o["name"] != name: continue
    modes = {m["id"]: m for m in o["modes"]}
    if what == "current":
        m = modes[o["currentModeId"]]
        print(m["size"]["width"], m["size"]["height"], round(m["refreshRate"], 2))
    else:
        w, h, hz = int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
        ms = [m for m in o["modes"] if m["size"]["width"] == w and m["size"]["height"] == h]
        if ms: print(min(ms, key=lambda m: abs(m["refreshRate"] - hz))["id"])
' "$@"
}

hdmi_set_mode() {
    # hdmi_set_mode <output> <w> <h> <hz>: returns 1 if KDE has no such mode.
    local id rate
    id="$(hdmi_kscreen mode "$@")" || return 1
    [[ -n "$id" ]] || return 1
    kscreen-doctor "output.$1.mode.$id" >/dev/null 2>&1 || return 1
    sleep 2
    rate="$(hdmi_kscreen current "$1" | cut -d' ' -f3)"
    # Whole hertz: the rate asked for can be e.g. 59.97.
    [[ "${rate%.*}" -ge $(( ${4%.*} - 1 )) ]]
}

hdmi_confirm() {
    # No answer (black screen, nobody there) is a no.
    local reply
    read -rt "$HDMI_CONFIRM_SECONDS" -p "$(echo -e "${c_bold}$1${c_reset} [y/N, ${HDMI_CONFIRM_SECONDS}s] ")" reply || { echo; return 1; }
    [[ "$reply" =~ ^[Yy]$ ]]
}

hdmi_remove_boot_param() {
    # Removes the drm.edid_firmware= older versions put on the kernel command
    # line (it applied to whatever display was on that port), then rebuilds
    # the initramfs and boot entries.
    local f
    [[ -n "$(hdmi_cmdline_param)" ]] || { sudo rm -f "$HDMI_INITRAMFS_CONF"; return 0; }
    f="$(hdmi_boot_file)"
    backup_file "$f"
    sudo sed -i -E 's/drm\.edid_firmware=[^ "]*steamify-[^ "]* ?//' "$f"
    sudo rm -f "$HDMI_INITRAMFS_CONF"
    info "Rebuilding the initramfs and boot entries..."
    case "$f" in
        /etc/default/limine) sudo limine-mkinitcpio ;;
        /etc/sdboot-manage.conf) sudo /usr/bin/mkinitcpio -P && sudo sdboot-manage gen ;;
        /etc/default/grub) sudo /usr/bin/mkinitcpio -P && sudo grub-mkconfig -o /boot/grub/grub.cfg ;;
    esac
}

hdmi_write_map() {
    # hdmi_write_map <lines>: the saved displays list.
    sudo mkdir -p "$(dirname "$HDMI_MAP")"
    { printf '# Written by steamify: HDMI refresh boost, one display per line:\n'
      printf '# <id>\t<name>\t<w>x<h>\t<rates>\n'
      [[ -n "$1" ]] && printf '%s\n' "$1"; } | sudo tee "$HDMI_MAP" >/dev/null
}

hdmi_save() {
    # hdmi_save <edid> <w>x<h> <rates>: keep an EDID for the display it was
    # built from (block 0 is the display's own, so is its ID), replacing
    # what was saved for that display before.
    local id name
    id="$(hdmi_edid_tool id "$1")" && [[ -n "$id" ]] || return 1
    name="$(hdmi_edid_tool name "$1")"
    sudo install -Dm644 "$1" "$HDMI_FW_DIR/steamify-$id.bin" || return 1
    hdmi_write_map "$(hdmi_saved | awk -F'\t' -v i="$id" '$1 != i'
        printf '%s\t%s\t%s\t%s' "$id" "${name:-HDMI display}" "$2" "$3")"
}

hdmi_forget() {
    # hdmi_forget <id>|all: remove saved displays; the hotplug script puts
    # a connected one back on its own EDID, and goes when none are left.
    local rest=""
    if [[ "$1" == all ]]; then
        sudo rm -f "$HDMI_FW_DIR"/steamify-*.bin
    else
        rest="$(hdmi_saved | awk -F'\t' -v i="$1" '$1 != i')"
        sudo rm -f "$HDMI_FW_DIR/steamify-$1.bin"
    fi
    if [[ -z "$rest" ]]; then hdmi_remove_hotplug; return; fi
    hdmi_write_map "$rest"
    sudo systemctl restart "$HDMI_UNIT_NAME"
}

hdmi_migrate() {
    # Setups before 2.1.0: steamify-<output>.bin on the kernel command line,
    # the display's ID and mode in the state file. Saved per display now.
    local f out
    local -a smode
    for f in "$HDMI_FW_DIR"/steamify-*-*.bin; do
        [[ -e "$f" ]] || continue
        out="${f##*/steamify-}"; out="${out%.bin}"
        read -ra smode <<< "$(state_get hdmi "$out-mode")"
        [[ ${#smode[@]} -ge 2 ]] && hdmi_save "$f" "${smode[0]}x${smode[1]}" "${smode[*]:2}"
        sudo rm -f "$f"
    done
    state_clear hdmi
    hdmi_remove_boot_param
}

hdmi_install_hotplug() {
    # A saved EDID is only loaded while its display is connected: a udev
    # rule runs the script at every hotplug (and a unit at boot, before the
    # login manager). The script reads the display's ID over DDC, which
    # shows the real display even while an override is loaded, and loads
    # that display's file or resets to its own EDID. Unplugging resets too,
    # so the next display never starts on the wrong one.
    sudo tee "$HDMI_HOTPLUG" > /dev/null << 'EOF'
#!/bin/bash
# Steamify CachyOS, HDMI refresh boost: load a display's saved EDID only
# while it is connected. Runs as root (debugfs).
FW=/usr/lib/firmware/edid RUN=/run/steamify-edid
modprobe i2c-dev 2>/dev/null
mkdir -p "$RUN"
# Hotplug events come in bursts, and the link needs a moment before DDC works.
sleep 1
for c in /sys/class/drm/card*-HDMI-A-*; do
    [ -e "$c" ] || continue
    out="${c##*/}"; out="${out#card*-}"
    new=reset id=""
    if [ "$(cat "$c/status")" = connected ]; then
        bus="$(basename "$(readlink -f "$c/ddc")")"
        for i in 1 2 3 4 5; do
            # Bytes 8-17 of block 0: manufacturer, product, serial, date.
            id="$(i2ctransfer -y "${bus#i2c-}" w1@0x50 0 r18@0x50 2>/dev/null | tr -d ' ' | sed 's/0x//g')"
            [ ${#id} -eq 36 ] && break
            sleep 1
        done
        [ ${#id} -eq 36 ] && [ -f "$FW/steamify-${id:16}.bin" ] && new="${id:16}"
    fi
    [ "$(cat "$RUN/$out" 2>/dev/null || echo reset)" = "$new" ] && continue
    for d in /sys/kernel/debug/dri/*/"$out"; do [ -e "$d/edid_override" ] && break; done
    [ -e "$d/edid_override" ] || continue
    if [ "$new" = reset ]; then printf reset > "$d/edid_override"
    else cat "$FW/steamify-$new.bin" > "$d/edid_override"; fi
    # Before the hotplug below, whose own event runs this again.
    echo "$new" > "$RUN/$out"
    echo 1 > "$d/trigger_hotplug"
done
exit 0
EOF
    sudo chmod 755 "$HDMI_HOTPLUG"
    # StartLimitIntervalSec=0: a burst of hotplugs must not get it rate-limited.
    sudo tee "$HDMI_UNIT" > /dev/null << EOF
[Unit]
Description=Steamify CachyOS: HDMI refresh boost EDID for the connected display
StartLimitIntervalSec=0
Wants=sys-kernel-debug.mount
After=sys-kernel-debug.mount
Before=display-manager.service sddm.service plasmalogin.service

[Service]
Type=oneshot
ExecStart=$HDMI_HOTPLUG

[Install]
WantedBy=graphical.target
EOF
    # restart, not start: a hotplug during a run must still be looked at.
    printf '%s\n' '# Written by steamify: HDMI refresh boost, check the display at every hotplug.' \
        "ACTION==\"change\", SUBSYSTEM==\"drm\", ENV{HOTPLUG}==\"1\", RUN+=\"/usr/bin/systemctl --no-block restart $HDMI_UNIT_NAME\"" |
        sudo tee "$HDMI_UDEV_RULE" >/dev/null || return 1
    sudo systemctl daemon-reload
    sudo udevadm control --reload
    sudo systemctl enable "$HDMI_UNIT_NAME" >/dev/null 2>&1 || { err "Enabling $HDMI_UNIT_NAME failed."; return 1; }
    sudo systemctl restart "$HDMI_UNIT_NAME"
}

hdmi_remove_hotplug() {
    local conn
    sudo systemctl disable "$HDMI_UNIT_NAME" >/dev/null 2>&1
    sudo rm -f "$HDMI_UDEV_RULE" "$HDMI_UNIT" "$HDMI_HOTPLUG" "$HDMI_MAP"
    sudo rm -rf "$HDMI_RUN"
    sudo systemctl daemon-reload
    sudo udevadm control --reload
    for conn in $(hdmi_connectors); do hdmi_override_live "$conn" reset 2>/dev/null; done
    return 0
}

hdmi_tune() {
    # hdmi_tune <card-connector> <tmpdir>: find and confirm the highest rate
    # at the desktop resolution. Sets HDMI_RESULT to "<w> <h> <hz>..." (the
    # confirmed new rates) or leaves it empty.
    local conn="$1" tmp="$2" out="${1#card*-}" cur w h hz plan lim best steps_str
    local -a steps ok_rates=()
    HDMI_RESULT=""
    # From the display's own EDID: a live one left by an earlier test would
    # make its rates look like what the display already does.
    hdmi_override_live "$conn" reset 2>/dev/null
    cur="$(hdmi_kscreen current "$out")"
    [[ -n "$cur" ]] || { warn "$out: KDE doesn't show this output; skipped."; return 0; }
    read -r w h hz <<< "$cur"
    info "$out: desktop resolution ${w}x${h} at ${hz} Hz. Reading the display's EDID..."
    hdmi_read_edid "$conn" "$tmp/$out.orig" || return 1
    if ! plan="$(hdmi_edid_tool plan "$tmp/$out.orig" "$w" "$h" "$hz")"; then
        warn "$out: the display lists no timing for ${w}x${h}; nothing to calculate."
        return 0
    fi
    read -r lim best steps_str <<< "$plan"
    read -ra steps <<< "${steps_str:-}"
    info "$out: HDMI limit ${lim} MHz, fastest mode that fits now: ${best} Hz."
    if [[ ${#steps[@]} -eq 0 ]]; then
        ok "$out: already at the highest rate that fits HDMI here; nothing to change."
        return 0
    fi
    info "$out: steps to try: ${steps[*]} Hz. After each one you're asked whether the"
    info "picture is OK; no answer within ${HDMI_CONFIRM_SECONDS} s (e.g. a black screen) switches back."
    ask_yn "Start the test?" y || return 0

    hdmi_edid_tool build "$tmp/$out.orig" "$tmp/$out.test" "$w" "$h" "${steps[@]}" &&
        hdmi_override_live "$conn" "$tmp/$out.test" ||
        { err "$out: couldn't load the test EDID (debugfs)."; return 1; }
    local s
    for s in "${steps[@]}"; do
        info "$out: switching to ${w}x${h} at $s Hz..."
        if hdmi_set_mode "$out" "$w" "$h" "$s" && hdmi_confirm "Is the picture OK at $s Hz?"; then
            ok "$out: $s Hz works."
            ok_rates+=("$s")
        else
            warn "$out: $s Hz doesn't work; stopping here."
            break
        fi
    done
    if [[ ${#ok_rates[@]} -eq 0 ]]; then
        hdmi_override_live "$conn" reset
        hdmi_set_mode "$out" "$w" "$h" "$hz" >/dev/null
        info "$out: back to ${hz} Hz; nothing changed."
        return 0
    fi
    # Without the steps that failed, so KDE and gamescope never pick them.
    hdmi_edid_tool build "$tmp/$out.orig" "$tmp/$out.final" "$w" "$h" "${ok_rates[@]}" &&
        hdmi_override_live "$conn" "$tmp/$out.final"
    hdmi_set_mode "$out" "$w" "$h" "${ok_rates[-1]}" >/dev/null
    HDMI_RESULT="$w $h ${ok_rates[*]}"
}

# --- For the app: options, live tries, and installing what was confirmed ---
# The EDIDs read by hdmi_options, reused by the tries and the install.
HDMI_CACHE="${XDG_RUNTIME_DIR:-/tmp}/steamify-hdmi"

hdmi_options() {
    # JSON array: per connected HDMI output its name, mode and rate options.
    local conn out cur w h hz opts sep=""
    mkdir -p "$HDMI_CACHE"
    printf '['
    for conn in $(hdmi_connectors); do
        out="${conn#card*-}"
        # A live EDID left by an earlier try would look like the display's own.
        hdmi_status || hdmi_override_live "$conn" reset 2>/dev/null
        cur="$(hdmi_kscreen current "$out")"
        [[ -n "$cur" ]] || continue
        read -r w h hz <<< "$cur"
        hdmi_read_edid "$conn" "$HDMI_CACHE/$out.orig" || continue
        opts="$(hdmi_edid_tool options "$HDMI_CACHE/$out.orig" "/sys/class/drm/$conn/edid" "$w" "$h" "$hz")" || continue
        # Every rate on offer loaded now, while the list is on screen: a try
        # is then only a mode switch (the current mode stays in the EDID).
        hdmi_status || hdmi_preload "$conn" "$w" "$h" "$opts"
        printf '%s{"connector":"%s","output":"%s","width":%s,"height":%s,"hz":%s,"info":%s}' "$sep" "$conn" "$out" "$w" "$h" "$hz" "$opts"
        sep=","
    done
    printf ']'
}

hdmi_preload() {
    # hdmi_preload <card-connector> <w> <h> <options json>: load the EDID
    # with the calculated rates, as hdmi_try would on the first try.
    local conn="$1" out="${1#card*-}"
    local -a rates
    read -ra rates <<< "$(python3 -c 'import json, sys
print(" ".join(str(r["hz"]) for r in json.loads(sys.argv[1])["rates"] if r["kind"] != "monitor"))' "$4")"
    hdmi_edid_tool build "$HDMI_CACHE/$out.orig" "$HDMI_CACHE/$out.test" "$2" "$3" "${rates[@]}" &&
        hdmi_override_live "$conn" "$HDMI_CACHE/$out.test" &&
        cp "$HDMI_CACHE/$out.test" "$HDMI_CACHE/$out.loaded"
}

hdmi_try() {
    # hdmi_try <card-connector> <w> <h> <hz> [<rate>...]: switch to hz, with
    # an EDID holding the given calculated rates (loaded once per set).
    local conn="$1" w="$2" h="$3" hz="$4" out="${1#card*-}"
    shift 4
    [[ -f "$HDMI_CACHE/$out.orig" ]] || hdmi_read_edid "$conn" "$HDMI_CACHE/$out.orig"
    hdmi_edid_tool build "$HDMI_CACHE/$out.orig" "$HDMI_CACHE/$out.test" "$w" "$h" "$@" || return 1
    if ! cmp -s "$HDMI_CACHE/$out.test" "$HDMI_CACHE/$out.loaded" 2>/dev/null; then
        hdmi_override_live "$conn" "$HDMI_CACHE/$out.test" || return 1
        cp "$HDMI_CACHE/$out.test" "$HDMI_CACHE/$out.loaded"
    fi
    hdmi_set_mode "$out" "$w" "$h" "$hz"
}

hdmi_reset() {
    # hdmi_reset <card-connector> <w> <h> <hz>: the display's own EDID again.
    hdmi_override_live "$1" reset
    rm -f "$HDMI_CACHE/${1#card*-}.loaded"
    hdmi_set_mode "${1#card*-}" "$2" "$3" "$4" >/dev/null
}

hdmi_choose() {
    # For HDMI_CHOICE ("<output>=<w>x<h>:<rate>,..." from the app, rates it
    # confirmed): builds the final EDIDs in <tmpdir> like hdmi_tune does.
    local tmp="$1" item out mode rates w h
    local -a r
    for item in "${HDMI_CHOICE[@]}"; do
        out="${item%%=*}"; mode="${item#*=}"; rates="${mode#*:}"; mode="${mode%%:*}"
        w="${mode%x*}"; h="${mode#*x}"
        IFS=',' read -ra r <<< "$rates"
        HDMI_CHOSEN_CONN="$(basename /sys/class/drm/card*-"$out")"
        if [[ -f "$HDMI_CACHE/$out.orig" ]]; then cp "$HDMI_CACHE/$out.orig" "$tmp/$out.orig"
        else hdmi_read_edid "$HDMI_CHOSEN_CONN" "$tmp/$out.orig" || return 1; fi
        hdmi_edid_tool build "$tmp/$out.orig" "$tmp/$out.final" "$w" "$h" "${r[@]}" &&
            hdmi_override_live "$HDMI_CHOSEN_CONN" "$tmp/$out.final" || return 1
        [[ ${#r[@]} -gt 0 ]] && hdmi_set_mode "$out" "$w" "$h" "${r[-1]}" >/dev/null
        HDMI_RESULTS+=("$out|$w $h ${r[*]}")
    done
}

hdmi_enable() {
    local -a HDMI_RESULTS=()
    if [[ -n "$(hdmi_cmdline_param)" ]]; then
        info "Moving the EDID override off the kernel command line, so it only applies to its display..."
        hdmi_migrate && hdmi_install_hotplug || { err "Moving it failed."; return 1; }
        ok "HDMI refresh boost now only applies to the display it was set up for."
        return 0
    fi
    if hdmi_status; then
        ok "Already set up for the connected display. Untick and tick it again to re-test."
        return 0
    fi
    if [[ "${BACKEND:-false}" == true && ${#HDMI_CHOICE[@]} -eq 0 ]]; then
        err "HDMI refresh boost needs you at the screen: pick and test the rates in the app first."
        return 1
    fi
    if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]] || ! command -v kscreen-doctor >/dev/null; then
        err "Run this from the Plasma desktop: the test switches the display mode through KDE."
        return 1
    fi
    sudo pacman -S --needed --noconfirm i2c-tools python >/dev/null 2>&1 || { err "Installing i2c-tools failed."; return 1; }

    local tmp conn out res saved=false rc=0
    local -a smode
    tmp="$(mktemp -d)"
    if [[ ${#HDMI_CHOICE[@]} -gt 0 ]]; then
        # Picked and tested in the app.
        hdmi_choose "$tmp" || rc=1
    else
        for conn in $(hdmi_connectors); do
            hdmi_tune "$conn" "$tmp" || { rc=1; continue; }
            [[ -n "$HDMI_RESULT" ]] && HDMI_RESULTS+=("${conn#card*-}|$HDMI_RESULT")
        done
    fi
    for res in "${HDMI_RESULTS[@]}"; do
        out="${res%%|*}"; read -ra smode <<< "${res#*|}"
        hdmi_save "$tmp/$out.final" "${smode[0]}x${smode[1]}" "${smode[*]:2}" && saved=true || rc=1
    done
    rm -rf "$tmp" "$HDMI_CACHE"
    [[ "$saved" == true ]] || return $rc
    if ! hdmi_install_hotplug; then
        # Nothing half-done left behind; the live EDID lasts until a restart.
        hdmi_remove_hotplug
        err "Making it permanent failed; the display is back on its own EDID."
        return 1
    fi
    ok "HDMI refresh boost is saved for this display; other displays keep their own settings."
    return $rc
}

hdmi_disable() {
    # For the connected display; other saved displays stay (the app lists
    # them). Without the pinned kernel none may stay: newer kernels read the
    # EDID themselves.
    local id
    if [[ -n "$(hdmi_cmdline_param)" ]]; then
        hdmi_forget all; hdmi_remove_boot_param || return 1; state_clear hdmi
    elif [[ "${WANTED[kpin]:-1}" == 0 ]] || ! pinned_kernel_installed; then
        hdmi_forget all
    else
        for id in $(hdmi_active_ids); do hdmi_forget "$id"; done
    fi
    ok "HDMI refresh boost removed for the connected display; it uses its own EDID again."
}
