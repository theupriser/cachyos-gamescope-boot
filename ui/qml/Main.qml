// Steamify v2: menu -> review -> password -> applying -> done.
// Designed at 1280x720 and scaled to the window, so it fits a TV too.
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic

ApplicationWindow {
    id: win
    required property var backend
    required property var gamepad
    required property bool fullscreen
    required property string iconUrl

    width: 1280; height: 720
    minimumWidth: 960; minimumHeight: 540
    visibility: fullscreen ? Window.FullScreen : Window.Windowed
    title: "Steamify"
    color: t.bg

    // --- Look (from the design) ---
    QtObject {
        id: t
        readonly property color bg: "#0f1319"
        readonly property color bar: "#141a22"
        readonly property color line: "#232c38"
        readonly property color card: "#161d27"
        readonly property color cardSel: "#1f2a3a"
        readonly property color text: "#e6ebf2"
        readonly property color textHi: "#eef2f7"
        readonly property color soft: "#c3ccd8"
        readonly property color mute: "#97a3b4"
        readonly property color faint: "#8b97a8"
        readonly property color accent: "#3ea6ff"
        readonly property color ink: "#06121f"
        readonly property color good: "#7fd1a8"
        readonly property color goodBg: "#173226"
        readonly property color warn: "#f2a33a"
        readonly property color warnBg: "#2a2116"
        readonly property color bad: "#ff9a8a"
        readonly property color badBg: "#2a1c1c"
        readonly property color key: "#2a3444"
        readonly property string display: "Barlow Semi Condensed"
        readonly property string body: "IBM Plex Sans"
        readonly property string mono: "IBM Plex Mono"
    }

    // --- Texts per item (the backend's labels are the fallback) ---
    readonly property var texts: ({
        gaming: { label: "SteamOS conversion", hint: "Boot into gaming mode, Steam on the desktop",
                  body: "Boots straight into gaming mode. Switch to Desktop in Steam works, and Return to Gaming Mode on the desktop brings you back.",
                  changes: ["Autologin into gamescope", "Return to Gaming Mode shortcut", "Steam starts silently on the desktop"] },
        boot: { label: "Boot into", hint: "Where the PC starts",
                body: "Where the PC starts after a restart. Switching back and forth works the same either way.",
                changes: ["Desktop: the Plasma session is set before login", "Gaming: the SteamOS default"] },
        theme: { label: "SteamOS theme", hint: "Vapor look for the desktop, Add to Steam",
                 body: "The Vapor look of SteamOS for the desktop, with its panel, launcher icon and wallpaper.",
                 changes: ["cachyos-vapor global theme", "Add to Steam in right-click menus", "Nested Desktop, Steam keyboard window rule"] },
        glyphs: { label: "Steam Deck/Machine icons", hint: "Deck button icons in gaming mode",
                  body: "Steam shows Steam Deck button icons in gaming mode.", changes: ["STEAM_GAMEPADUI_ARGS -steamos3"] },
        single: { label: "Single user mode", hint: "No password, lock screen or wallet prompts",
                  body: "Like SteamOS: never a login or lock screen, and no KDE wallet password prompts. Typing a password with a controller is no fun.",
                  changes: ["SDDM autologin, no lock screen or user switching", "Valve's empty wallet; your own is kept aside", "Launcher shows Sleep, Restart, Shut Down only"] },
        launcher: { label: "Steamify shortcut", hint: "Icon on the desktop and in the launcher",
                    body: "Opens the newest Steamify, so you never need the install command again.", changes: ["Desktop icon and launcher entry"] },
        cec: { label: "HDMI-CEC", hint: "Use Steam with the TV remote, TV on/off with the PC", experimental: true,
               body: "Use Steam with your TV remote, and the TV turns on and off with the PC. Turn on CEC on the TV too (Sony: BRAVIA Sync, Samsung: Anynet+, LG: SimpLink).",
               changes: ["Valve's cecd and cec-audio-control", "HDMI CEC section in Steam's Display settings", "Volume buttons for the TV in the Quick Access menu"] },
        machine: { label: "Steam Machine support", hint: "LED bar, fan and performance settings in Steam",
                   body: "The front LED bar works, Steam's hardware settings work, and the power button puts it to sleep like a console.",
                   changes: ["leds-valve driver for every kernel (DKMS)", "steamos-manager for Steam's settings", "Console-like power handling"] },
        kpin: { label: "Pin the kernel", hint: "Fixes rebooting after shutdown",
                body: "Newer CachyOS kernels make the Steam Machine reboot instead of shutting down. Untick once CachyOS fixes that.",
                changes: ["linux-cachyos from Steamify's release (signature checked)", "Kept in /var/cache/steamify/kernel", "Added to IgnorePkg"] },
        hdmi: { label: "HDMI refresh boost", hint: "Higher refresh rates over HDMI",
                body: "The pinned kernel keeps many HDMI displays at 60 Hz. Turning this on shows which refresh rates your display can run at the desktop resolution; you pick them, and each one is tried for 15 seconds so you can check the picture before it's installed.",
                changes: ["The display's EDID with the rates you confirmed", "In the initramfs, drm.edid_firmware on the kernel command line", "Off: the display uses its own EDID again"] },
        bios: { label: "Update BIOS", hint: "",
                body: "Installs Valve's newest Steam Machine BIOS, at your own risk. It checks Valve's checksum and asks fwupd whether the file fits this machine, then warns you twice before anything is written.",
                changes: ["Valve's fremont-hw-support package (checksum checked)", "fwupd writes the BIOS during the next restart", "Keep the power on until the machine has fully started again"] }
    })

    // --- State ---
    property string screen: "menu"          // menu review password applying done
    property string inputType: "keyboard"    // controller keyboard remote
    property double remoteAt: 0
    property var want: ({})
    property string boot: "gamescope"
    property int sel: 0                      // row index; rows.length = the Apply button
    property bool reapply: false
    property var plan: []                    // [{id, action}]
    property var steps: ({})                 // id -> "wait"|"run"|"ok"|"fail"
    property var failed: []
    property bool restartNeeded: false
    property string runError: ""
    property bool wrongPassword: false
    property int doneCount: 0
    property string pending: "apply"         // what the password is for: apply | bios
    property string sessionPassword: ""      // kept between the BIOS steps only
    property var biosInfo: ({})
    property bool biosRun: false
    property bool biosChecking: false        // the invisible check before the warnings
    property int biosFocus: 0                // warning 1: 0 = Cancel, 1 = continue
    property real holdProgress: 0            // warning 2: hold A/OK for 5 s
    // HDMI refresh boost: try rates one by one, then install the kept ones.
    property var hdmi: null                  // the first HDMI output from hdmi-options
    property bool hdmiLoading: false
    property var hdmiResult: ({})            // hz -> "ok" | "fail" (tried)
    property var hdmiPick: ({})              // hz -> ticked for Install
    property int hdmiSel: 0                  // rate row; rates.length = the Install button
    property real hdmiHz: 0                  // the rate being tried (e.g. 99.98)
    property real hdmiNow: 0                 // the rate on screen: the last one kept
    property double hdmiBackAt: 0            // when a test returned to the list
    property string hdmiPhase: ""            // switching | settle | ask | back
    property int hdmiSettle: 8               // seconds for the display to show a picture again
    property int hdmiLeft: 15                // seconds to keep it
    property string hdmiChoice: ""           // for apply: <output>=<w>x<h>:<rates>
    property string hdmiNote: ""
    property var afterBusy: null             // a backend call waiting for the last one
    function whenIdle(fn) { if (backend.busy) afterBusy = fn; else fn(); }
    Connections { target: backend; function onBusyChanged() { if (!backend.busy && afterBusy) { var f = afterBusy; afterBusy = null; f(); } } }
    readonly property var hdmiRates: hdmi && hdmi.info ? hdmi.info.rates : []
    function hdmiCalc() {
        // The calculated rates (not the display's own): what the test EDID holds.
        return hdmiRates.filter(function (r) { return r.kind !== "monitor"; }).map(function (r) { return r.hz; });
    }
    function hdmiKept() {
        // The ticked calculated rates (the display's own modes always come along).
        return hdmiRates.filter(function (r) { return r.kind !== "monitor" && hdmiPick[r.hz]; })
                        .map(function (r) { return r.hz; }).sort(function (a, b) { return a - b; });
    }
    function hdmiUntried() { return hdmiKept().filter(function (hz) { return hdmiResult[hz] !== "ok"; }); }
    function hdmiTick(r) {
        if (r.kind === "monitor") return;
        var p = Object.assign({}, hdmiPick); p[r.hz] = !p[r.hz]; hdmiPick = p;
    }
    readonly property bool hdmiCanInstall: hdmiKept().length > 0 || hdmiRates.some(function (r) { return r.kind === "monitor"; })
    function startHdmi() {
        hdmi = null; hdmiChoice = ""; hdmiNote = ""; sessionPassword = "";
        if (!askPassword("hdmi")) hdmiLoad();
    }
    function hdmiLoad() {
        hdmiLoading = true; hdmi = null; hdmiSel = 0; hdmiResult = ({}); hdmiPick = ({}); screen = "hdmi";
        whenIdle(function () { backend.hdmiOptions(sessionPassword); });
    }
    function hdmiSwitch(hz) {
        whenIdle(function () { backend.hdmiTry(sessionPassword, hdmi.connector, hdmi.width, hdmi.height, hz, hdmiCalc().join(",")); });
    }
    function hdmiTry(hz) {
        hdmiHz = hz; hdmiPhase = "switching"; screen = "hdmitest";
        hdmiSwitch(hz);
    }
    function hdmiMark(result) {
        var r = Object.assign({}, hdmiResult); r[hdmiHz] = result; hdmiResult = r;
        // Kept: ticked for Install; didn't work: unticked.
        var p = Object.assign({}, hdmiPick); p[hdmiHz] = result === "ok"; hdmiPick = p;
    }
    function hdmiKeep() { if (hdmiPhase !== "ask" && hdmiPhase !== "settle") return; hdmiMark("ok"); hdmiNow = hdmiHz; hdmiPhase = ""; hdmiBackAt = Date.now(); screen = "hdmi"; }
    function hdmiReject() {
        // Back to the last rate that worked (at first: the one from before).
        if (hdmiPhase !== "ask" && hdmiPhase !== "settle" && hdmiPhase !== "failed") return;
        hdmiMark("fail"); hdmiPhase = "back";
        hdmiSwitch(hdmiNow);
    }
    function hdmiInstall() {
        if (!hdmiCanInstall) return;
        hdmiChoice = hdmi.output + "=" + hdmi.width + "x" + hdmi.height + ":" + hdmiKept().join(",");
        var w = Object.assign({}, want); w.hdmi = true; w.machine = true; w.kpin = true; want = w;
        screen = "menu"; goReview(false);
    }
    function hdmiCancel() {
        var tried = Object.keys(hdmiResult).length > 0;
        hdmiPhase = ""; hdmiChoice = "";
        if (tried && hdmi) whenIdle(function () { backend.hdmiReset(sessionPassword, hdmi.connector, hdmi.width, hdmi.height, hdmi.hz); });
        sessionPassword = ""; screen = "menu";
    }
    Timer {
        interval: 1000; repeat: true; running: screen === "hdmitest" && (hdmiPhase === "settle" || hdmiPhase === "ask")
        onTriggered: {
            if (hdmiPhase === "settle") { hdmiSettle--; if (hdmiSettle <= 0) hdmiPhase = "ask"; return; }
            hdmiLeft--; if (hdmiLeft <= 0) hdmiReject();
        }
    }
    property bool holding: false
    readonly property var bios: status.bios || null
    function biosHint() {
        if (!bios) return "";
        if (!bios.newest) return "Now " + bios.current + ", newest unknown (offline?)";
        if (bios.current === bios.newest) return bios.current + " is up to date";
        return "Now " + bios.current + ", newest " + bios.newest + " · at your own risk";
    }
    ListModel { id: logModel }

    readonly property var status: backend.status || ({})
    readonly property var items: status.items || []
    readonly property var rows: items.filter(function (i) { return !i.parent || want[i.parent]; })

    function nowOn(id) {
        for (var i = 0; i < items.length; i++) if (items[i].id === id) return items[i].on;
        return false;
    }
    function label(it) { return (texts[it.id] && texts[it.id].label) || it.label; }
    function syncFromStatus() {
        reapply = false;
        var w = {};
        for (var i = 0; i < items.length; i++) w[items[i].id] = items[i].kind === "action" ? false : items[i].wanted;
        want = w;
        boot = nowOn("boot") ? "desktop" : "gamescope";
        if (sel > rows.length) sel = 0;
    }
    Connections { target: backend; function onStatusChanged() { if (screen === "menu" || screen === "done") syncFromStatus(); } }

    function toggle(id) {
        hdmiNote = "";
        var w = Object.assign({}, want);
        w[id] = !w[id];
        if (id === "gaming" && !w.gaming) { w.single = false; }
        if (id === "single" && w.single) w.gaming = true;
        // Turning HDMI refresh boost on goes through its own screen: pick
        // the rates and try each one first.
        if (id === "hdmi" && w.hdmi && !nowOn("hdmi") && !hdmiChoice) { startHdmi(); return; }
        if (id === "hdmi" && !w.hdmi) hdmiChoice = "";
        if (id === "machine") w.kpin = w.machine;
        if (id === "kpin" && w.kpin) w.machine = true;
        if (id === "hdmi" && w.hdmi) { w.machine = true; w.kpin = true; }
        if (!w.machine || !w.kpin) w.hdmi = false;
        want = w;
    }
    function computePlan() {
        var p = [];
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            if (it.kind !== "toggle") continue;
            if (it.parent && !want[it.parent]) { if (it.on) p.push({ id: it.id, action: "off" }); continue; }
            if (want[it.id] && !it.on) p.push({ id: it.id, action: "on" });
            else if (!want[it.id] && it.on) p.push({ id: it.id, action: "off" });
            else if (want[it.id] && reapply) p.push({ id: it.id, action: "again" });
        }
        var bootNow = nowOn("boot") ? "desktop" : "gamescope";
        if (want.gaming && boot !== bootNow) p.push({ id: "boot", action: boot === "desktop" ? "desktop" : "gaming" });
        return p;
    }
    function goReview(again) {
        reapply = again; plan = computePlan(); screen = "review";
    }
    function wantedIds() {
        var ids = [];
        for (var i = 0; i < items.length; i++)
            if (items[i].kind === "toggle" && want[items[i].id] && (!items[i].parent || want[items[i].parent])) ids.push(items[i].id);
        return ids;
    }
    function startApply(password) {
        steps = {}; failed = []; restartNeeded = false; runError = ""; doneCount = 0; logModel.clear();
        var s = {};
        for (var i = 0; i < plan.length; i++) s[plan[i].id] = "wait";
        steps = s;
        screen = "applying";
        backend.apply(wantedIds(), want.gaming ? boot : "", reapply, password || "", want.hdmi ? hdmiChoice : "");
        hdmiChoice = "";
    }
    function askPassword(forWhat) {
        pending = forWhat;
        if (backend.needsPassword()) { wrongPassword = false; pw.text = ""; screen = "password"; pw.forceActiveFocus(); return true; }
        return false;
    }
    function onApplyPressed() {
        if (plan.length === 0) return;
        // Just typed for the HDMI screen: not asked again.
        if (hdmiChoice && sessionPassword) { var p = sessionPassword; sessionPassword = ""; startApply(p); return; }
        if (!askPassword("apply")) startApply("");
    }
    function submitPassword() {
        if (!backend.checkPassword(pw.text)) { wrongPassword = true; pw.selectAll(); return; }
        var p = pw.text; pw.text = "";
        if (pending === "bios") { sessionPassword = p; biosCheck(); }
        else if (pending === "hdmi") { sessionPassword = p; hdmiLoad(); }
        else startApply(p);
    }
    // --- BIOS: check -> warning 1 -> warning 2 -> flash ---
    function startBios() {
        if (!bios || !bios.selectable) return;
        biosInfo = {}; sessionPassword = "";
        if (!askPassword("bios")) biosCheck();
    }
    function biosStep(action) {
        steps = {}; failed = []; restartNeeded = false; runError = ""; doneCount = 0; logModel.clear();
        plan = [{ id: "bios", action: action }];
        var s = {}; s.bios = "wait"; steps = s;
        biosRun = true; screen = "applying";
    }
    function biosCheck() {
        // Invisible: stay on the menu (the BIOS row says "Checking…"),
        // then the first warning.
        failed = []; runError = ""; logModel.clear();
        plan = [{ id: "bios", action: "check" }];
        biosRun = true; biosChecking = true; screen = "menu";
        backend.biosPrepare(sessionPassword);
    }
    function biosCancel() { sessionPassword = ""; holdProgress = 0; holding = false; biosRun = false; syncFromStatus(); screen = "menu"; }
    function biosFlash() { holdProgress = 0; holding = false; biosStep("flash"); backend.biosFlash(sessionPassword); }
    Timer {
        interval: 50; repeat: true; running: screen === "bios2" && holding
        onTriggered: { holdProgress = Math.min(1, holdProgress + 0.01); if (holdProgress >= 1) biosFlash(); }
    }
    Connections {
        target: backend
        function onEvent(ev) {
            var s = Object.assign({}, steps);
            if (ev.event === "start") { s[ev.id] = "run"; steps = s; }
            else if (ev.event === "done") { s[ev.id] = ev.ok ? "ok" : "fail"; steps = s; doneCount++; }
            else if (ev.event === "log") { logModel.append({ line: ev.line }); if (logModel.count > 400) logModel.remove(0); }
            else if (ev.event === "hdmi-options") {
                hdmiLoading = false; hdmiSel = 0;
                hdmi = ev.outputs && ev.outputs.length ? ev.outputs[0] : null;
                hdmiNow = hdmi ? hdmi.hz : 0;
                // Straight to the display's own faster mode (the safe one), with
                // the next rate's Try selected for after that.
                var rs = hdmi && hdmi.info ? hdmi.info.rates : [];
                var own = rs.findIndex(function (r) { return r.kind === "monitor"; });
                if (own >= 0) { hdmiSel = Math.min(own + 1, rs.length - 1); hdmiTry(rs[own].hz); }
            }
            else if (ev.event === "hdmi-tried") {
                if (hdmiPhase === "back") { hdmiPhase = ""; hdmiBackAt = Date.now(); screen = "hdmi"; return; }
                // Displays take a few seconds to show a picture after a mode
                // change: the countdown starts after that.
                // The display's own mode always works: kept without asking.
                var ownMode = hdmiRates.some(function (r) { return r.kind === "monitor" && Math.abs(r.hz - hdmiHz) < 0.01; });
                if (ev.ok && ownMode) { hdmiPhase = "ask"; hdmiKeep(); }
                else if (ev.ok) { hdmiPhase = "settle"; hdmiSettle = 8; hdmiLeft = 15; }
                else { hdmiPhase = "failed"; hdmiReject(); }
            }
            else if (ev.event === "hdmi-reset") { }
            else if (ev.event === "finished" && (screen === "hdmi" || screen === "hdmitest")) {
                // Only on an error (sudo): the HDMI commands end without one.
                runError = ev.error === "wrong-password" ? "The password didn't work." : "sudo isn't available.";
                failed = []; restartNeeded = false; sessionPassword = ""; screen = "done";
            }
            else if (ev.event === "bios-ready") { biosChecking = false; biosInfo = ev; biosFocus = 0; holdProgress = 0; screen = "bios1"; }
            else if (ev.event === "finished" && biosChecking) {
                // The check found nothing to do or a problem: say so.
                biosChecking = false; sessionPassword = "";
                failed = ev.failed || []; restartNeeded = false;
                runError = ev.error === "wrong-password" ? "The password didn't work." : (ev.error ? "sudo isn't available." : (ev.nothing ? "The BIOS is already the newest version." : ""));
                screen = "done";
            }
            else if (ev.event === "finished") {
                if (!(biosRun && plan.length && plan[0].action === "check" && !ev.failed.length && !ev.error && !ev.nothing)) sessionPassword = "";
                failed = ev.failed || []; restartNeeded = !!ev.restart;
                runError = ev.error === "wrong-password" ? "The password didn't work." : (ev.error === "start" ? "Steamify couldn't start the changes." : (ev.error ? "sudo isn't available." : ""));
                screen = "done";
            }
        }
        function onRemotePressed() { remoteAt = Date.now(); inputType = "remote"; }
    }

    // --- Input: one set of actions for controller, keyboard and remote ---
    function act(a) {
        if (screen === "menu" && biosChecking) return;
        if (screen === "menu") {
            if (a === "up") sel = Math.max(0, sel - 1);
            else if (a === "down") sel = Math.min(rows.length, sel + 1);
            else if (a === "accept") {
                if (sel === rows.length) { goReview(false); return; }
                var r = rows[sel];
                if (r.kind === "action" && r.id === "bios") { startBios(); return; }
                if (r.kind === "choice") boot = boot === "gamescope" ? "desktop" : "gamescope";
                else if (r.kind === "toggle") toggle(r.id);
            }
            else if ((a === "left" || a === "right") && sel < rows.length && rows[sel].kind === "choice")
                boot = a === "left" ? "gamescope" : "desktop";
            else if (a === "apply") goReview(false);
            else if (a === "reapply") goReview(true);
            else if (a === "back") Qt.quit();
        } else if (screen === "review") {
            if (a === "accept" || a === "apply") onApplyPressed();
            else if (a === "back") { reapply = false; screen = "menu"; }
        } else if (screen === "password") {
            if (a === "accept" || a === "apply") submitPassword();
            else if (a === "back") { pw.text = ""; if (pending === "hdmi") hdmiCancel(); else screen = "review"; }
        } else if (screen === "bios1") {
            if (a === "left") biosFocus = 0;
            else if (a === "right") biosFocus = 1;
            else if (a === "accept") { if (biosFocus === 1) { holdProgress = 0; biosTyped.text = ""; screen = "bios2"; if (inputType === "keyboard") biosTyped.forceActiveFocus(); } else biosCancel(); }
            else if (a === "back") biosCancel();
        } else if (screen === "bios2") {
            if (a === "back") biosCancel();
            else if (a === "hold") holding = true;
            else if (a === "release") { holding = false; if (holdProgress < 1) holdProgress = 0; }
        } else if (screen === "hdmi") {
            if (hdmiLoading) { if (a === "back") hdmiCancel(); return; }
            var n = hdmiRates.length;
            if (a === "up") hdmiSel = Math.max(0, hdmiSel - 1);
            else if (a === "down") hdmiSel = Math.min(n, hdmiSel + 1);
            else if (a === "accept") { if (hdmiSel === n) hdmiInstall(); else hdmiTick(hdmiRates[hdmiSel]); }
            else if (a === "reapply" && hdmiSel < n && Math.abs(hdmiNow - hdmiRates[hdmiSel].hz) >= 0.5) hdmiTry(hdmiRates[hdmiSel].hz);
            else if (a === "apply") hdmiInstall();
            // A second Back meant for the test (it takes a moment to switch
            // back) would otherwise leave the whole screen.
            else if (a === "back" && Date.now() - hdmiBackAt > 1500) hdmiCancel();
        } else if (screen === "hdmitest") {
            if (a === "accept" || a === "apply") hdmiKeep();
            else if (a === "back") hdmiReject();
        } else if (screen === "done") {
            if (a === "accept" && restartNeeded) backend.restart();
            else if (a === "back" || a === "accept") { biosRun = false; syncFromStatus(); screen = "menu"; }
        }
    }
    Connections {
        target: gamepad
        function onButton(b) {
            if (b === "a_up") { if (screen === "bios2") act("release"); return; }
            if (b.slice(-3) === "_up") return;
            inputType = "controller";
            if (b === "a" && screen === "bios2") { act("hold"); return; }
            var map = { a: "accept", b: "back", x: "apply", y: "reapply", start: "apply", up: "up", down: "down", left: "left", right: "right" };
            if (map[b]) act(map[b]);
        }
    }
    function keyAct(e) {
        var fromRemote = Date.now() - remoteAt < 400;
        if (screen === "bios2" && inputType !== "keyboard" && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) {
            if (!e.isAutoRepeat) act("hold"); e.accepted = true; return;
        }
        if (!fromRemote) inputType = "keyboard";
        var k = e.key;
        if (k === Qt.Key_Up) act("up");
        else if (k === Qt.Key_Down) act("down");
        else if (k === Qt.Key_Left) act("left");
        else if (k === Qt.Key_Right) act("right");
        else if (k === Qt.Key_Space) act("accept");
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) act(inputType === "remote" || screen !== "menu" ? "accept" : "apply");
        else if (k === Qt.Key_Escape || k === Qt.Key_Back || k === Qt.Key_Backspace) { if (!e.isAutoRepeat) act("back"); }
        else if (k === Qt.Key_R) act("reapply");
        else return;
        e.accepted = true;
    }

    readonly property var glyphs: ({
        controller: { toggle: "A", choose: "◀ ▶", reapply: "Y", quit: "B", apply: "X", ok: "A", back: "B" },
        keyboard: { toggle: "Space", choose: "← →", reapply: "R", quit: "Esc", apply: "Enter", ok: "Enter", back: "Esc" },
        remote: { toggle: "OK", choose: "◀ ▶", reapply: "Red", quit: "Back", apply: "↓ Apply", ok: "OK", back: "Back" }
    })
    readonly property var g: glyphs[inputType]

    component Glyph: Rectangle {
        property string k
        property bool dark: false
        height: 26; width: Math.max(26, gt.implicitWidth + 14)
        radius: inputType === "controller" && k.length === 1 ? 13 : 7
        color: dark ? t.ink : t.key
        Text { id: gt; anchors.centerIn: parent; text: parent.k; color: parent.dark ? t.accent : t.textHi; font.family: t.body; font.pixelSize: 12; font.weight: Font.DemiBold }
    }
    component Btn: Rectangle {
        property string k
        property string text
        property bool primary: false
        property bool focusRing: false
        signal clicked
        height: 48; radius: 12; width: br.implicitWidth + 36
        color: primary ? t.accent : "#232c38"
        border.width: focusRing ? 2 : 0; border.color: t.textHi
        Row { id: br; anchors.centerIn: parent; spacing: 10
            Glyph { k: parent.parent.k; visible: k !== ""; dark: parent.parent.primary; anchors.verticalCenter: parent.verticalCenter }
            Text { text: parent.parent.text; color: parent.parent.primary ? t.ink : t.text; font.family: t.body; font.pixelSize: 15; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
    component Chip: Rectangle {
        property string text
        property color fg: t.good
        property color bgc: t.goodBg
        height: 24; radius: 6; width: ct.implicitWidth + 16; color: bgc
        Text { id: ct; anchors.centerIn: parent; text: parent.text.toUpperCase(); color: parent.fg; font.family: t.body; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
    }

    component RiskList: Column {
        spacing: 8
        Repeater {
            model: ["A failed or interrupted BIOS update can leave the machine unable to start (bricked). Steamify, CachyOS and Valve take no responsibility for that.",
                    "NEVER turn off the power, unplug the machine or press the power button while it updates, including the restart(s) afterwards.",
                    "The screen can stay black for several minutes. Wait.",
                    "Only on mains power, with all other programs closed."]
            Row { required property string modelData; spacing: 10; width: parent.width
                Rectangle { width: 6; height: 6; radius: 3; color: t.bad; y: 9 }
                Text { text: parent.modelData; width: parent.width - 16; wrapMode: Text.WordWrap; color: t.soft; font.family: t.body; font.pixelSize: 15; lineHeight: 1.3 } }
        }
    }
    // --- The 1280x720 stage, scaled to the window ---
    Item {
        id: stage
        // Scaled like a 1280x720 screen, but stretched to the window's own
        // shape, so the bars reach the edges and the content fills it.
        readonly property real k: Math.min(win.width / 1280, win.height / 720)
        width: win.width / k; height: win.height / k
        x: 0; y: 0
        transformOrigin: Item.TopLeft
        scale: k
        focus: true
        Keys.onPressed: function (e) { if (!(screen === "password" && pw.activeFocus && e.key !== Qt.Key_Escape && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter)) keyAct(e); }
        Keys.onReleased: function (e) { if (screen === "bios2" && !e.isAutoRepeat && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) act("release"); }

        // Header
        Rectangle {
            id: header; width: parent.width; height: 72; color: t.bar
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: t.line }
            Row {
                anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter; spacing: 14
                Image { source: iconUrl; width: 40; height: 40; sourceSize: Qt.size(80, 80); anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Steamify"; color: t.text; font.family: t.display; font.pixelSize: 28; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                Text { text: screen === "menu" ? "v" + (status.version || "") : "/ " + ({review: "Review", password: "Password", applying: biosRun ? "BIOS update" : "Applying", done: "Done", bios1: "BIOS update", bios2: "BIOS update", hdmi: "HDMI refresh boost", hdmitest: "HDMI refresh boost"})[screen]
                       color: t.faint; font.family: screen === "menu" ? t.mono : t.body; font.pixelSize: screen === "menu" ? 13 : 15; anchors.verticalCenter: parent.verticalCenter }
            }
            Rectangle {
                visible: status.steamMachine === true
                anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter
                height: 34; radius: 17; color: "#1b2330"; width: mt.implicitWidth + 28
                Text { id: mt; anchors.centerIn: parent; text: "Steam Machine · CachyOS"; color: "#b8c3d1"; font.family: t.body; font.pixelSize: 14 }
            }
        }

        // ================= MENU =================
        Item {
            visible: screen === "menu"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width

            Text {
                visible: items.length === 0
                anchors.centerIn: parent; color: t.mute; font.family: t.body; font.pixelSize: 18
                text: status.error ? "Couldn't read the current state:\n" + status.error : "Checking what's on…"
                horizontalAlignment: Text.AlignHCenter
            }

            Item {
                id: menuBody; visible: items.length > 0
                x: 40; y: 28; width: parent.width - 80; height: parent.height - 28 - 64 - 20
                // Left: the list
                Column {
                    id: listCol; width: 740; height: parent.height; spacing: 10
                    Row { width: parent.width
                        Text { text: "What do you want?"; color: t.text; font.family: t.display; font.pixelSize: 30; font.weight: Font.DemiBold }
                    }
                    ListView {
                        id: list; width: parent.width; height: parent.height - 50; clip: true; spacing: 0
                        // A fixed model: sub-items fold in and out instead of the
                        // list being rebuilt (and jumping) on every tick.
                        model: items
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        function showSelected() {
                            for (var i = 0; i < count; i++) {
                                var d = itemAtIndex(i);
                                if (d && d.selected) { positionViewAtIndex(i, ListView.Contain); return; }
                            }
                        }
                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool shown: !modelData.parent || !!want[modelData.parent]
                            readonly property int rowIndex: rows.findIndex(function (r) { return r.id === modelData.id; })
                            readonly property bool selected: shown && rowIndex === sel
                            readonly property bool on: modelData.kind === "choice" ? true : !!want[modelData.id]
                            // HDMI refresh boost is set up on its own screen: a button while off.
                            readonly property bool setup: modelData.id === "hdmi" && !modelData.on
                            onSelectedChanged: if (selected) Qt.callLater(list.showSelected)
                            width: list.width - 12; x: 2
                            height: shown ? 62 : 0
                            opacity: shown ? 1 : 0
                            clip: true
                            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            Rectangle {
                                id: card
                                width: parent.width; height: 56; radius: 12
                                color: row.selected ? t.cardSel : t.card
                                border.width: row.selected ? 2 : 0; border.color: t.accent
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { inputType = "keyboard"; if (row.selected) act("accept"); else sel = row.rowIndex; } }
                                // Left: indent, name and hint
                                Text { id: branch; visible: !!row.modelData.parent; x: 20; anchors.verticalCenter: parent.verticalCenter
                                       text: "└"; color: "#56627a"; font.pixelSize: 18 }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    x: row.modelData.parent ? 46 : 16
                                    width: controls.x - x - 16
                                    opacity: row.modelData.kind === "action" && !(bios && bios.selectable) ? 0.6 : 1
                                    Text { text: label(row.modelData); color: t.textHi; font.family: t.body; font.pixelSize: 17; font.weight: Font.DemiBold; elide: Text.ElideRight; width: parent.width }
                                    Text { text: row.modelData.id === "bios" ? biosHint() : ((texts[row.modelData.id] && texts[row.modelData.id].hint) || row.modelData.hint); color: t.mute; font.family: t.body; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
                                }
                                // Right: every control ends on the same edge
                                Item {
                                    id: controls
                                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                    width: 180; height: 32
                                    // choice
                                    Rectangle { visible: row.modelData.kind === "choice"; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 172; height: 32; radius: 10; color: t.bg
                                        Row { anchors.centerIn: parent; spacing: 4
                                            Repeater { model: [["gamescope", "Gaming"], ["desktop", "Desktop"]]
                                                Rectangle { required property var modelData
                                                    width: 80; height: 26; radius: 7; color: boot === modelData[0] ? t.accent : "transparent"
                                                    Text { anchors.centerIn: parent; text: parent.modelData[1]; color: boot === parent.modelData[0] ? t.ink : t.mute; font.family: t.body; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                    MouseArea { anchors.fill: parent; onClicked: boot = parent.modelData[0] } } } } }
                                    // toggle: "now on/off" left of the switch, switch on the edge
                                    Rectangle { id: sw; visible: row.modelData.kind === "toggle" && !row.setup; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 46; height: 26; radius: 13; color: row.on ? t.accent : "#343f50"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Rectangle { width: 20; height: 20; radius: 10; color: "#f4f7fb"; y: 3; x: row.on ? 23 : 3; Behavior on x { NumberAnimation { duration: 120 } } } }
                                    Text { visible: row.modelData.kind === "toggle" && !row.setup; anchors.right: sw.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                           text: row.modelData.on ? "now on" : "now off"; color: row.modelData.on ? t.good : t.faint; font.family: t.mono; font.pixelSize: 12 }
                                    // HDMI refresh boost while off: opens its screen
                                    Rectangle { visible: row.setup; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: sut.implicitWidth + 24; height: 30; radius: 8; color: hdmiChoice && want.hdmi ? t.goodBg : "#1b2b40"
                                        Text { id: sut; anchors.centerIn: parent; font.family: t.body; font.pixelSize: 13; font.weight: Font.DemiBold
                                               color: hdmiChoice && want.hdmi ? t.good : "#7cc4ff"
                                               text: hdmiChoice && want.hdmi ? (hdmiChoice.split(":")[1] ? hdmiChoice.split(":")[1].split(",").join(", ") + " Hz ✓" : "Own modes ✓") : "Set up…" }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { sel = row.rowIndex; startHdmi(); } } }
                                    // action
                                    Rectangle { visible: row.modelData.kind === "action"; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: at.implicitWidth + 24; height: 30; radius: 8; color: t.warnBg
                                        Text { id: at; anchors.centerIn: parent; text: biosChecking ? "Checking…" : bios && bios.selectable ? "Update…" : (bios && bios.newest ? "Up to date" : "Unavailable"); color: t.warn; font.family: t.body; font.pixelSize: 13; font.weight: Font.DemiBold } }
                                }
                            }
                        }
                    }
                }
                // Right: details + system
                Column {
                    x: 772; width: parent.width - 772; height: parent.height; spacing: 16
                    Rectangle {
                        id: detail
                        width: parent.width; height: parent.height - sys.height - 16; radius: 16; color: t.card
                        readonly property var it: sel < rows.length ? rows[sel] : null
                        readonly property var tx: it ? (texts[it.id] || {}) : {}
                        // Long texts scroll instead of running out of the card;
                        // each item starts at the top.
                        onItChanged: detailFlick.contentY = 0
                        Flickable {
                            id: detailFlick
                            anchors.fill: parent; anchors.margins: 24; anchors.rightMargin: 12
                            visible: detail.it !== null; clip: true
                            contentHeight: detailCol.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            Column {
                                id: detailCol; width: detailFlick.width - 12; spacing: 14
                                Row { spacing: 10
                                    Chip { text: detail.it ? (detail.it.kind === "choice" ? (boot === "desktop" ? "Desktop" : "Gaming") : (detail.it.kind === "action" ? "Opt-in" : (detail.it.on ? "On" : "Off"))) : ""
                                           fg: detail.it && detail.it.on ? t.good : "#b8c3d1"; bgc: detail.it && detail.it.on ? t.goodBg : t.line }
                                    Chip { visible: !!detail.tx.experimental; text: "Experimental"; fg: t.warn; bgc: t.warnBg }
                                }
                                Text { text: detail.it ? label(detail.it) : ""; color: t.text; font.family: t.display; font.pixelSize: 26; font.weight: Font.DemiBold; wrapMode: Text.WordWrap; width: parent.width }
                                Text { text: detail.tx.body || ""; color: t.soft; font.family: t.body; font.pixelSize: 15; lineHeight: 1.4; wrapMode: Text.WordWrap; width: parent.width }
                                Text { text: "WHAT IT CHANGES"; color: t.faint; font.family: t.body; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.8; topPadding: 4 }
                                Repeater { model: detail.tx.changes || []
                                    Text { required property string modelData; text: "•  " + modelData; color: t.soft; font.family: t.body; font.pixelSize: 14; wrapMode: Text.WordWrap; width: detailCol.width } }
                            }
                        }
                        Column {
                            anchors.centerIn: parent; spacing: 8; visible: detail.it === null
                            Text { text: plan.length === 0 && computePlan().length === 0 ? "Everything is the way you want it" : "Review what will change"; color: t.text; font.family: t.display; font.pixelSize: 24; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: "then apply it"; color: t.mute; font.family: t.body; font.pixelSize: 15; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                    }
                    Rectangle {
                        id: sys; width: parent.width; height: 82; radius: 16; color: t.card
                        Grid { anchors.fill: parent; anchors.margins: 16; anchors.leftMargin: 20; anchors.rightMargin: 20; columns: 2; columnSpacing: 20; rowSpacing: 10
                            Repeater {
                                model: [["Kernel", (status.kernel || "").replace("-cachyos", "")], ["LED bar", status.steamMachine ? (status.leds || 0) + " LEDs" : "—"],
                                        ["HDMI-CEC", status.cecDevices ? "/dev/" + status.cecDevices.split(" ")[0] : "none"], ["Version", status.version || ""]]
                                Row { required property var modelData; width: (sys.width - 60) / 2
                                    Text { text: parent.modelData[0]; color: t.faint; font.family: t.body; font.pixelSize: 13; width: parent.width / 2 }
                                    Text { text: parent.modelData[1]; color: t.text; font.family: t.mono; font.pixelSize: 13; width: parent.width / 2; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft } }
                            }
                        }
                    }
                }
            }

            // Footer
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 64; color: t.bar
                Rectangle { width: parent.width; height: 1; color: t.line }
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter; spacing: 28
                    Repeater {
                        model: [[g.toggle, "Toggle"], [g.choose, "Choose"], [g.reapply, "Re-apply what's on"], [g.quit, "Quit"]]
                        Row { required property var modelData; spacing: 8
                            Glyph { k: parent.modelData[0]; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: parent.modelData[1]; color: "#b8c3d1"; font.family: t.body; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter } }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                    Text { readonly property int n: computePlan().length; text: hdmiNote ? hdmiNote : (n === 0 ? "Everything is the way you want it" : n + (n === 1 ? " change" : " changes")); color: t.faint; font.family: t.body; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Btn { k: g.apply; text: "Review & apply"; primary: true; focusRing: sel === rows.length; height: 44; onClicked: goReview(false) }
                }
            }
        }

        // ================= REVIEW =================
        Item {
            visible: screen === "review"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width
            Column {
                x: 40; y: 32; width: 740; spacing: 14
                Text { text: plan.length === 0 ? "Nothing to change" : "This will"; color: t.text; font.family: t.display; font.pixelSize: 34; font.weight: Font.DemiBold }
                ListView {
                    width: 740; clip: true; spacing: 8
                    height: Math.min(contentHeight, stage.height - header.height - 32 - 50 - 14 - 66 - 64 - 32)
                    model: plan
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle { required property var modelData; width: 740; height: 56; radius: 12; color: t.card
                        readonly property var st: ({ on: ["Turn on", t.good, t.goodBg], off: ["Turn off", t.bad, t.badBg], again: ["Re-apply", "#7cc4ff", "#1b2b40"],
                                                     desktop: ["Desktop", "#7cc4ff", "#1b2b40"], gaming: ["Gaming", "#7cc4ff", "#1b2b40"],
                                                     check: ["Check", t.warn, t.warnBg], flash: ["Flash", t.bad, t.badBg] })[modelData.action] || ["", t.text, t.card]
                        Row { anchors.fill: parent; anchors.leftMargin: 18; spacing: 14
                            Chip { text: parent.parent.st[0]; fg: parent.parent.st[1]; bgc: parent.parent.st[2]; width: 84; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: (texts[parent.parent.modelData.id] || {}).label || parent.parent.modelData.id; color: t.textHi; font.family: t.body; font.pixelSize: 17; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
                Rectangle { width: 740; height: 52; radius: 12; color: "#1a2230"
                    Text { anchors.verticalCenter: parent.verticalCenter; x: 18; text: "Your password is asked once. Changes to how the PC starts need a restart."; color: t.soft; font.family: t.body; font.pixelSize: 14 } }
            }
            Rectangle {
                x: parent.width - 468; y: 32; width: 428; height: 210; radius: 16; color: t.card
                Column { anchors.fill: parent; anchors.margins: 24; spacing: 12
                    Text { text: "SUMMARY"; color: t.faint; font.family: t.body; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
                    Repeater { model: [["Turn on", "on"], ["Re-apply", "again"], ["Turn off", "off"]]
                        Row { required property var modelData; width: 380
                            Text { text: parent.modelData[0]; color: t.soft; font.family: t.body; font.pixelSize: 15; width: 300 }
                            Text { text: plan.filter(function (p) { return p.action === parent.modelData[1]; }).length; color: t.text; font.family: t.mono; font.pixelSize: 15; width: 80; horizontalAlignment: Text.AlignRight } } }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 64; color: t.bar
                Rectangle { width: parent.width; height: 1; color: t.line }
                Btn { anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter; k: g.back; text: "Back to the menu"; onClicked: act("back") }
                Btn { anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter; k: g.ok; text: "Apply"; primary: true; visible: plan.length > 0; onClicked: onApplyPressed() }
            }
        }

        // ================= PASSWORD =================
        Rectangle {
            visible: screen === "password"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width; color: "#0c1016"
            Rectangle {
                anchors.centerIn: parent; width: 560; height: pwCol.implicitHeight + 72; radius: 20; color: t.card; border.width: 1; border.color: t.line
                Column {
                    id: pwCol; anchors.fill: parent; anchors.margins: 36; anchors.leftMargin: 40; anchors.rightMargin: 40; spacing: 18
                    Row { spacing: 14
                        Rectangle { width: 48; height: 48; radius: 14; color: "#1b2b40"
                            Canvas { anchors.centerIn: parent; width: 24; height: 24
                                onPaint: { var c = getContext("2d"); c.strokeStyle = "#7cc4ff"; c.lineWidth = 1.8; c.beginPath(); c.roundedRect(4.5, 10.5, 15, 10, 2.5, 2.5); c.stroke();
                                           c.beginPath(); c.moveTo(8, 10.5); c.lineTo(8, 8); c.arc(12, 8, 4, Math.PI, 0); c.lineTo(16, 10.5); c.stroke(); } } }
                        Column { spacing: 2; anchors.verticalCenter: parent.verticalCenter
                            Text { text: "Your password, once"; color: t.text; font.family: t.display; font.pixelSize: 30; font.weight: Font.DemiBold }
                            Text { text: "Steamify needs it to change system settings."; color: t.mute; font.family: t.body; font.pixelSize: 14 } }
                    }
                    Text { text: "Password for " + backend.user(); color: t.soft; font.family: t.body; font.pixelSize: 14; font.weight: Font.DemiBold }
                    TextField {
                        id: pw; width: parent.width; height: 52; echoMode: shown ? TextInput.Normal : TextInput.Password
                        property bool shown: false
                        color: t.textHi; font.family: t.body; font.pixelSize: 18; leftPadding: 16; rightPadding: 56
                        placeholderText: "Password"; placeholderTextColor: "#6b778a"
                        background: Rectangle { radius: 12; color: t.bg; border.width: 2; border.color: wrongPassword ? t.bad : t.accent }
                        Keys.onReturnPressed: submitPassword()
                        Keys.onEnterPressed: submitPassword()
                        Keys.onEscapePressed: act("back")
                        Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: pw.shown ? "Hide" : "Show"; color: "#b8c3d1"; font.family: t.body; font.pixelSize: 13
                            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: pw.shown = !pw.shown } }
                    }
                    Text { visible: wrongPassword; text: "That password didn't work. Try again."; color: t.bad; font.family: t.body; font.pixelSize: 14 }
                    Rectangle { width: parent.width; height: 46; radius: 12; color: "#1a2230"
                        Text { anchors.verticalCenter: parent.verticalCenter; x: 14; color: t.soft; font.family: t.body; font.pixelSize: 14
                               text: ({ controller: "Press Steam + X for the on-screen keyboard.", keyboard: "Type your password and press Enter.", remote: "Select the field for the on-screen keyboard." })[inputType] } }
                    Item { width: parent.width; height: 48
                        Btn { k: g.back; text: "Back"; onClicked: act("back") }
                        Btn { anchors.right: parent.right; k: g.ok; text: "Apply"; primary: true; onClicked: submitPassword() } }
                    Text { text: "Only used for this run. Steamify never stores it."; color: t.faint; font.family: t.body; font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }

        // ================= APPLYING =================
        Item {
            visible: screen === "applying"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width
            Column {
                x: 40; y: 32; width: 560; spacing: 18
                Text { text: biosRun ? (plan.length && plan[0].action === "check" ? "Checking the BIOS update" : "Installing the BIOS update") : "Applying your changes"; color: t.text; font.family: t.display; font.pixelSize: 34; font.weight: Font.DemiBold }
                Rectangle { width: 560; height: 10; radius: 5; color: t.line
                    Rectangle { height: 10; radius: 5; color: t.accent; width: plan.length ? parent.width * Math.min(1, (doneCount + 0.3) / plan.length) : 0; Behavior on width { NumberAnimation { duration: 300 } } } }
                Row { width: 560
                    Text { text: "Step " + Math.min(plan.length, doneCount + 1) + " of " + plan.length; color: t.mute; font.family: t.body; font.pixelSize: 14; width: 280 }
                    Text { text: "Don't turn off the PC"; color: t.mute; font.family: t.body; font.pixelSize: 14; width: 280; horizontalAlignment: Text.AlignRight } }
                ListView {
                    id: stepList; width: 560; clip: true; spacing: 8
                    height: stage.height - header.height - 32 - 156 - 32
                    model: plan
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    // Follow the progress: the running step stays in view.
                    readonly property int running: plan.findIndex(function (p) { return steps[p.id] === "run"; })
                    onRunningChanged: if (running >= 0) positionViewAtIndex(running, ListView.Contain)
                    delegate:
                    Rectangle { required property var modelData; required property int index; readonly property string st: steps[modelData.id] || "wait"
                        width: 560; height: 54; radius: 12; color: st === "run" ? t.cardSel : t.card; border.width: st === "run" ? 2 : 0; border.color: t.accent
                        Row { anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; spacing: 14
                            Rectangle { width: 22; height: 22; radius: 11; anchors.verticalCenter: parent.verticalCenter
                                color: parent.parent.st === "ok" ? t.goodBg : (parent.parent.st === "fail" ? t.badBg : "transparent")
                                border.width: parent.parent.st === "wait" || parent.parent.st === "run" ? 2 : 0; border.color: parent.parent.st === "run" ? t.accent : "#343f50"
                                Text { anchors.centerIn: parent; text: parent.parent.parent.st === "ok" ? "✓" : (parent.parent.parent.st === "fail" ? "!" : ""); color: parent.parent.parent.st === "ok" ? t.good : t.bad; font.pixelSize: 13; font.weight: Font.Bold }
                                RotationAnimator on rotation { running: parent.parent.parent.st === "run"; from: 0; to: 360; duration: 1000; loops: Animation.Infinite } }
                            Text { text: ({ on: "Turn on ", off: "Turn off ", again: "Re-apply ", desktop: "Boot into ", gaming: "Boot into ", check: "Download and check the ", flash: "Hand to fwupd: the " })[parent.parent.modelData.action] + ((texts[parent.parent.modelData.id] || {}).label || parent.parent.modelData.id)
                                   color: parent.parent.st === "wait" ? t.faint : t.textHi; font.family: t.body; font.pixelSize: 16; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter; width: 380; elide: Text.ElideRight }
                            Text { text: ({ wait: "Waiting", run: "Working…", ok: "Done", fail: "Problem" })[parent.parent.st]; color: parent.parent.st === "ok" ? t.good : (parent.parent.st === "fail" ? t.bad : "#b8c3d1"); font.family: t.body; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }
            Column {
                x: 632; y: 32; width: parent.width - 672; height: parent.height - 64; spacing: 10
                Text { text: "DETAILS"; color: t.faint; font.family: t.body; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
                Rectangle { width: parent.width; height: parent.height - 30; radius: 16; color: "#0b0e13"; border.width: 1; border.color: "#1d2531"
                    ListView { id: logView; anchors.fill: parent; anchors.margins: 18; clip: true; model: logModel
                        onCountChanged: positionViewAtEnd()
                        delegate: Text { required property string line; width: logView.width; text: line; color: "#aab5c4"; font.family: t.mono; font.pixelSize: 13; wrapMode: Text.WrapAnywhere } } }
            }
        }

        // ================= BIOS: warning 1 =================
        Item {
            visible: screen === "bios1"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width
            Rectangle {
                x: 40; y: 28; width: parent.width - 80; height: parent.height - 28 - 64 - 24; radius: 16; color: "#1d1416"; border.width: 2; border.color: "#b33a3a"
                Row { anchors.fill: parent; anchors.margins: 32; spacing: 40
                    Column { width: 640; spacing: 16
                        Row { spacing: 12
                            Rectangle { width: 44; height: 44; radius: 12; color: "#3a1c1f"; Text { anchors.centerIn: parent; text: "!"; color: t.bad; font.pixelSize: 26; font.weight: Font.Bold } }
                            Text { text: "BIOS update – entirely at your own risk"; color: "#ffd9d3"; font.family: t.display; font.pixelSize: 30; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter } }
                        RiskList { width: 640 }
                    }
                    Rectangle { width: 440; height: 250; radius: 14; color: "#161d27"
                        Column { anchors.fill: parent; anchors.margins: 22; spacing: 12
                            Repeater { model: [["Current BIOS", biosInfo.current || ""], ["New BIOS", biosInfo.newest || ""], ["Checksum", "OK (Valve's package)"],
                                               ["Compatible", biosInfo.compatible === "yes" ? "Yes (checked by fwupd)" : "Not checked (dry run)"]]
                                Row { required property var modelData; width: 396
                                    Text { text: parent.modelData[0]; color: t.faint; font.family: t.body; font.pixelSize: 15; width: 150 }
                                    Text { text: parent.modelData[1]; color: parent.modelData[1].indexOf("Not") === 0 ? t.warn : t.text; font.family: t.mono; font.pixelSize: 15; width: 246; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft } } }
                        } }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 64; color: t.bar
                Rectangle { width: parent.width; height: 1; color: t.line }
                Text { anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter; text: "Do you understand the risks and want to continue?"; color: t.soft; font.family: t.body; font.pixelSize: 15 }
                Row { anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                    Btn { k: biosFocus === 0 ? g.ok : "◀"; text: "Cancel"; focusRing: biosFocus === 0; onClicked: biosCancel() }
                    Btn { k: biosFocus === 1 ? g.ok : "▶"; text: "I understand, continue"; focusRing: biosFocus === 1; color: "#8a2c2c"
                          onClicked: { biosFocus = 1; act("accept"); } } }
            }
        }

        // ================= BIOS: warning 2 (last chance) =================
        Item {
            visible: screen === "bios2"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width
            Rectangle {
                anchors.centerIn: parent; width: 760; height: b2.implicitHeight + 64; radius: 20; color: "#1d1416"; border.width: 2; border.color: "#b33a3a"
                Column { id: b2; anchors.fill: parent; anchors.margins: 32; spacing: 18
                    Text { text: "Last chance: this flashes BIOS " + (biosInfo.newest || ""); color: "#ffd9d3"; font.family: t.display; font.pixelSize: 32; font.weight: Font.DemiBold }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: t.soft; font.family: t.body; font.pixelSize: 16; lineHeight: 1.3
                           text: "After this, keep the power on until the machine has fully started again. Don't touch it, even if the screen is black." }
                    // keyboard: type UPDATE
                    Column { visible: inputType === "keyboard"; width: parent.width; spacing: 8
                        Text { text: "Type UPDATE (in capitals) and press Enter to flash the BIOS:"; color: t.text; font.family: t.body; font.pixelSize: 15; font.weight: Font.DemiBold }
                        TextField { id: biosTyped; width: 320; height: 50; color: t.textHi; font.family: t.mono; font.pixelSize: 20; leftPadding: 14
                            placeholderText: "UPDATE"; placeholderTextColor: "#6b5a5a"
                            background: Rectangle { radius: 10; color: t.bg; border.width: 2; border.color: biosTyped.text === "UPDATE" ? t.bad : "#5a3a3a" }
                            Keys.onReturnPressed: if (text === "UPDATE") biosFlash()
                            Keys.onEnterPressed: if (text === "UPDATE") biosFlash()
                            Keys.onEscapePressed: biosCancel() } }
                    // controller / remote: hold A or OK
                    Column { visible: inputType !== "keyboard"; width: parent.width; spacing: 10
                        Text { text: "Hold " + g.ok + " for 5 seconds to flash the BIOS. Let go to stop."; color: t.text; font.family: t.body; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Rectangle { width: parent.width; height: 14; radius: 7; color: "#3a2224"
                            Rectangle { height: 14; radius: 7; color: t.bad; width: parent.width * holdProgress } } }
                    Row { spacing: 12
                        Btn { k: g.back; text: "Cancel"; onClicked: biosCancel() }
                        Text { visible: bios && bios.dryRun; text: "Dry run: nothing will be flashed."; color: t.warn; font.family: t.body; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter } }
                }
            }
        }

        // ================= HDMI: pick the rates =================
        Item {
            visible: screen === "hdmi"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width
            Text { visible: hdmiLoading; anchors.centerIn: parent; text: "Reading your display…"; color: t.mute; font.family: t.body; font.pixelSize: 18 }
            Text { visible: !hdmiLoading && !hdmi; anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter
                   text: "No HDMI display found at the desktop.\nThis only works from the Plasma desktop, not in gaming mode."; color: t.mute; font.family: t.body; font.pixelSize: 18 }
            Column {
                visible: !hdmiLoading && !!hdmi
                x: 40; y: 28; width: 740; spacing: 12
                Text { text: hdmi ? (hdmi.info.name || "HDMI display") + "  ·  " + hdmi.output : ""; color: t.text; font.family: t.display; font.pixelSize: 30; font.weight: Font.DemiBold }
                Text { text: hdmi ? hdmi.width + "×" + hdmi.height : ""; color: t.mute; font.family: t.mono; font.pixelSize: 14 }
                Text { visible: hdmiRates.length === 0; width: 740; wrapMode: Text.WordWrap; topPadding: 12; color: t.soft; font.family: t.body; font.pixelSize: 16
                       text: "This display already runs its fastest rate that fits HDMI at this resolution. Nothing to add." }
                Repeater {
                    model: hdmiRates
                    Rectangle {
                        required property var modelData; required property int index
                        readonly property bool own: modelData.kind === "monitor"
                        readonly property string res: own ? "own" : (hdmiResult[modelData.hz] || "")
                        width: 740; height: 56; radius: 12
                        color: hdmiSel === index ? t.cardSel : t.card; border.width: hdmiSel === index ? 2 : 0; border.color: t.accent
                        readonly property bool ticked: own || !!hdmiPick[modelData.hz]
                        readonly property bool running: Math.abs(hdmiNow - modelData.hz) < 0.5
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { hdmiSel = parent.index; hdmiTick(parent.modelData); } }
                        Row { anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                            Rectangle { width: 24; height: 24; radius: 6; anchors.verticalCenter: parent.verticalCenter
                                color: parent.parent.ticked ? (parent.parent.own ? "#343f50" : t.accent) : "transparent"; border.width: parent.parent.ticked ? 0 : 2; border.color: "#56627a"
                                Text { anchors.centerIn: parent; text: parent.parent.parent.ticked ? "✓" : ""; color: parent.parent.parent.own ? t.soft : t.ink; font.pixelSize: 15; font.weight: Font.Bold } }
                            Text { text: parent.parent.modelData.hz + " Hz"; width: 100; color: t.textHi; font.family: t.body; font.pixelSize: 18; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                            Text { width: 380; anchors.verticalCenter: parent.verticalCenter; color: t.soft; font.family: t.body; font.pixelSize: 14
                                   text: ({ monitor: "The display's own mode · always included", calculated: "Calculated from the display's timing", limit: "Right at the HDMI 2.0 limit · not recommended" })[parent.parent.modelData.kind] }
                        }
                        Row { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                            Chip { anchors.verticalCenter: parent.verticalCenter; visible: parent.parent.res === "own" || parent.parent.res === "fail"
                                   text: ({ own: "Included", fail: "✗ Didn't work" })[parent.parent.res] || ""
                                   fg: parent.parent.res === "fail" ? t.bad : (parent.parent.res === "ok" ? t.good : "#b8c3d1")
                                   bgc: parent.parent.res === "fail" ? t.badBg : (parent.parent.res === "ok" ? t.goodBg : t.line) }
                            // The rate on screen now: a green marker instead of Try.
                            Rectangle { visible: parent.parent.running; height: 38; radius: 12; width: rt.implicitWidth + 32; color: t.goodBg
                                border.width: hdmiSel === parent.parent.index ? 2 : 0; border.color: t.good; anchors.verticalCenter: parent.verticalCenter
                                Text { id: rt; anchors.centerIn: parent; text: "Running now"; color: t.good; font.family: t.body; font.pixelSize: 15; font.weight: Font.DemiBold } }
                            Btn { visible: !parent.parent.running; height: 38; focusRing: hdmiSel === parent.parent.index; anchors.verticalCenter: parent.verticalCenter
                                  k: hdmiSel === parent.parent.index ? g.reapply : ""; text: parent.parent.res === "" || parent.parent.res === "own" ? "Try" : "Try again"
                                  onClicked: { hdmiSel = parent.parent.index; hdmiTry(parent.parent.modelData.hz); } }
                        }
                    }
                }
            }
            Rectangle {
                visible: !hdmiLoading && !!hdmi
                x: parent.width - 468; y: 28; width: 428; height: 250; radius: 16; color: t.card
                Column { anchors.fill: parent; anchors.margins: 24; spacing: 12
                    Text { text: "HOW IT WORKS"; color: t.faint; font.family: t.body; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: t.soft; font.family: t.body; font.pixelSize: 15; lineHeight: 1.35
                           text: "Tick the rates to install (" + g.ok + "). Try one first (" + g.reapply + "): it's shown, and you press " + g.ok + " to keep it. No answer, or a black screen, switches back.\n\nInstall adds the ticked rates and the display's own modes; they stay after a restart." }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 64; color: t.bar
                Rectangle { width: parent.width; height: 1; color: t.line }
                Btn { anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter; k: g.back; text: "Back to the menu"; onClicked: hdmiCancel() }
                Text { anchors.right: instBtn.left; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; visible: !!hdmi && (!hdmiCanInstall || hdmiUntried().length > 0)
                       text: !hdmiCanInstall ? "Tick a rate first" : "Not tried: " + hdmiUntried().join(", ") + " Hz"
                       color: hdmiCanInstall ? t.warn : t.faint; font.family: t.body; font.pixelSize: 14 }
                Btn { id: instBtn; anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter; k: hdmiSel === hdmiRates.length ? g.ok : g.apply
                      visible: !hdmiLoading && !!hdmi && hdmiRates.length > 0; primary: hdmiCanInstall; opacity: hdmiCanInstall ? 1 : 0.5
                      focusRing: hdmiSel === hdmiRates.length
                      text: "Install" + (hdmiKept().length ? " " + hdmiKept().join(", ") + " Hz" : ""); onClicked: hdmiInstall() }
            }
        }

        // ================= HDMI: keep this rate? =================
        Item {
            visible: screen === "hdmitest"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width
            Rectangle {
                anchors.centerIn: parent; width: 640; height: ht.implicitHeight + 64; radius: 20; color: t.card; border.width: 1; border.color: t.line
                Column { id: ht; anchors.fill: parent; anchors.margins: 32; spacing: 18
                    Text { text: hdmiPhase === "ask" || hdmiPhase === "settle" ? "Keep " + hdmiHz + " Hz?" : (hdmiPhase === "back" ? "Switching back…" : "Switching to " + hdmiHz + " Hz…")
                           color: t.text; font.family: t.display; font.pixelSize: 36; font.weight: Font.DemiBold }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: t.soft; font.family: t.body; font.pixelSize: 16; lineHeight: 1.3
                           text: hdmiPhase === "ask" || hdmiPhase === "settle" ? "Check the picture: sharp, stable, no flicker or dropouts. Your display's menu can show the rate it gets."
                                                     : "The screen may go black for a moment." }
                    Column { visible: hdmiPhase === "ask" || hdmiPhase === "settle"; width: parent.width; spacing: 8
                        Text { text: hdmiPhase === "settle" ? "Waiting for the picture… the countdown starts in " + hdmiSettle + " s" : "Switching back in " + hdmiLeft + " s"; color: t.mute; font.family: t.body; font.pixelSize: 14 }
                        Rectangle { width: parent.width; height: 10; radius: 5; color: t.line
                            Rectangle { height: 10; radius: 5; color: t.accent; width: parent.width * hdmiLeft / 15; Behavior on width { NumberAnimation { duration: 900 } } } } }
                    Row { visible: hdmiPhase === "ask" || hdmiPhase === "settle"; spacing: 12
                        Btn { k: g.back; text: "Switch back"; onClicked: hdmiReject() }
                        Btn { k: g.ok; text: "Keep " + hdmiHz + " Hz"; primary: true; onClicked: hdmiKeep() } }
                }
            }
        }

        // ================= DONE =================
        Item {
            visible: screen === "done"
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width
            Column {
                anchors.centerIn: parent; width: 760; spacing: 20
                Rectangle { width: 72; height: 72; radius: 36; anchors.horizontalCenter: parent.horizontalCenter
                    color: failed.length || runError ? t.warnBg : t.goodBg
                    Text { anchors.centerIn: parent; text: failed.length || runError ? "!" : "✓"; color: failed.length || runError ? t.warn : t.good; font.pixelSize: 36; font.weight: Font.Bold } }
                Text { text: runError ? "Nothing changed" : (biosRun && failed.length ? "The BIOS update stopped" : (failed.length ? "Done, with a problem" : "All done")); color: t.text; font.family: t.display; font.pixelSize: 40; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: t.soft; font.family: t.body; font.pixelSize: 17
                       text: runError ? runError : (biosRun ? (failed.length ? "The BIOS was not changed." : (bios && bios.dryRun ? "Dry run: nothing was flashed. " : "BIOS " + (biosInfo.newest || "") + " is staged and is written during the restart. ") + (failed.length ? "" : "Keep the power on and don't touch the machine until it has fully started again, even if the screen stays black.")) : (plan.length + (plan.length === 1 ? " change" : " changes") + " applied." + (restartNeeded ? " Some take effect after a restart." : ""))) }
                Rectangle { visible: failed.length > 0; anchors.horizontalCenter: parent.horizontalCenter; width: ft.implicitWidth + 32; height: 44; radius: 12; color: t.warnBg
                    Text { id: ft; anchors.centerIn: parent; color: "#f2c27a"; font.family: t.body; font.pixelSize: 14
                           text: "Had a problem: " + failed.map(function (id) { return (texts[id] || {}).label || id; }).join(", ") + ". See the details." } }
                Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 14; topPadding: 8
                    Btn { k: g.back; text: "Back to the menu"; height: 52; onClicked: act("back") }
                    Btn { visible: restartNeeded; k: g.ok; text: "Restart now"; primary: true; height: 52; onClicked: backend.restart() } }
            }
        }
    }
}
