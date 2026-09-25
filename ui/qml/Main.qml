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
        bios: { label: "Update BIOS", hint: "Runs in the terminal version (two warnings, typed confirmation)",
                body: "Installs Valve's newest Steam Machine BIOS, at your own risk. The app leaves this to the terminal version, which asks twice and wants UPDATE typed.",
                changes: ["Run steamify.sh in Konsole for this"] }
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
        var w = {};
        for (var i = 0; i < items.length; i++) w[items[i].id] = items[i].kind === "action" ? false : items[i].wanted;
        want = w;
        boot = nowOn("boot") ? "desktop" : "gamescope";
        if (sel > rows.length) sel = 0;
    }
    Connections { target: backend; function onStatusChanged() { if (screen === "menu" || screen === "done") syncFromStatus(); } }

    function toggle(id) {
        var w = Object.assign({}, want);
        w[id] = !w[id];
        if (id === "gaming" && !w.gaming) { w.single = false; }
        if (id === "single" && w.single) w.gaming = true;
        if (id === "machine") w.kpin = w.machine;
        if (id === "kpin" && w.kpin) w.machine = true;
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
        backend.apply(wantedIds(), want.gaming ? boot : "", reapply, password || "");
    }
    function onApplyPressed() {
        if (plan.length === 0) return;
        if (backend.needsPassword()) { wrongPassword = false; pw.text = ""; screen = "password"; pw.forceActiveFocus(); }
        else startApply("");
    }
    function submitPassword() {
        if (!backend.checkPassword(pw.text)) { wrongPassword = true; pw.selectAll(); return; }
        var p = pw.text; pw.text = "";
        startApply(p);
    }
    Connections {
        target: backend
        function onEvent(ev) {
            var s = Object.assign({}, steps);
            if (ev.event === "start") { s[ev.id] = "run"; steps = s; }
            else if (ev.event === "done") { s[ev.id] = ev.ok ? "ok" : "fail"; steps = s; doneCount++; }
            else if (ev.event === "log") { logModel.append({ line: ev.line }); if (logModel.count > 400) logModel.remove(0); }
            else if (ev.event === "finished") {
                failed = ev.failed || []; restartNeeded = !!ev.restart;
                runError = ev.error === "wrong-password" ? "The password didn't work." : (ev.error ? "sudo isn't available." : "");
                screen = "done";
            }
        }
        function onRemotePressed() { remoteAt = Date.now(); inputType = "remote"; }
    }

    // --- Input: one set of actions for controller, keyboard and remote ---
    function act(a) {
        if (screen === "menu") {
            if (a === "up") sel = Math.max(0, sel - 1);
            else if (a === "down") sel = Math.min(rows.length, sel + 1);
            else if (a === "accept") {
                if (sel === rows.length) { goReview(false); return; }
                var r = rows[sel];
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
            else if (a === "back") screen = "menu";
        } else if (screen === "password") {
            if (a === "accept" || a === "apply") submitPassword();
            else if (a === "back") { pw.text = ""; screen = "review"; }
        } else if (screen === "done") {
            if (a === "accept" && restartNeeded) backend.restart();
            else if (a === "back" || a === "accept") { syncFromStatus(); screen = "menu"; }
        }
    }
    Connections {
        target: gamepad
        function onButton(b) {
            inputType = "controller";
            var map = { a: "accept", b: "back", x: "apply", y: "reapply", start: "apply", up: "up", down: "down", left: "left", right: "right" };
            if (map[b]) act(map[b]);
        }
    }
    function keyAct(e) {
        var fromRemote = Date.now() - remoteAt < 400;
        if (!fromRemote) inputType = "keyboard";
        var k = e.key;
        if (k === Qt.Key_Up) act("up");
        else if (k === Qt.Key_Down) act("down");
        else if (k === Qt.Key_Left) act("left");
        else if (k === Qt.Key_Right) act("right");
        else if (k === Qt.Key_Space) act("accept");
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) act(inputType === "remote" || screen !== "menu" ? "accept" : "apply");
        else if (k === Qt.Key_Escape || k === Qt.Key_Back || k === Qt.Key_Backspace) act("back");
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
            Glyph { k: parent.parent.k; dark: parent.parent.primary; anchors.verticalCenter: parent.verticalCenter }
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

    // --- The 1280x720 stage, scaled to the window ---
    Item {
        id: stage
        width: 1280; height: 720
        anchors.centerIn: parent
        scale: Math.min(win.width / 1280, win.height / 720)
        focus: true
        Keys.onPressed: function (e) { if (!(screen === "password" && pw.activeFocus && e.key !== Qt.Key_Escape && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter)) keyAct(e); }

        // Header
        Rectangle {
            id: header; width: parent.width; height: 72; color: t.bar
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: t.line }
            Row {
                anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter; spacing: 14
                Image { source: iconUrl; width: 40; height: 40; sourceSize: Qt.size(80, 80); anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Steamify"; color: t.text; font.family: t.display; font.pixelSize: 28; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                Text { text: screen === "menu" ? "v" + (status.version || "") : "/ " + ({review: "Review", password: "Password", applying: "Applying", done: "Done"})[screen]
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
                x: 40; y: 28; width: 1200; height: parent.height - 28 - 64 - 20
                // Left: the list
                Column {
                    id: listCol; width: 740; height: parent.height; spacing: 10
                    Row { width: parent.width
                        Text { text: "What do you want?"; color: t.text; font.family: t.display; font.pixelSize: 30; font.weight: Font.DemiBold }
                    }
                    ListView {
                        id: list; width: parent.width; height: parent.height - 50; clip: true; spacing: 6
                        model: rows
                        currentIndex: Math.min(sel, rows.length - 1)
                        highlightFollowsCurrentItem: false
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool selected: index === sel
                            readonly property bool on: modelData.kind === "choice" ? true : !!want[modelData.id]
                            width: list.width - 12; height: 56; radius: 12
                            x: 2
                            color: selected ? t.cardSel : t.card
                            border.width: selected ? 2 : 0; border.color: t.accent
                            opacity: modelData.kind === "action" ? 0.6 : 1
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { inputType = "keyboard"; if (sel === row.index) act("accept"); else sel = row.index; } }
                            Row {
                                anchors.fill: parent; anchors.leftMargin: modelData.parent ? 22 : 16; anchors.rightMargin: 16; spacing: 14
                                Text { visible: !!modelData.parent; text: "└"; color: "#56627a"; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter }
                                Column { anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    width: parent.width - (modelData.parent ? 40 : 0) - (modelData.kind === "choice" ? 200 : 150)
                                    Text { text: label(modelData); color: t.textHi; font.family: t.body; font.pixelSize: 17; font.weight: Font.DemiBold; elide: Text.ElideRight; width: parent.width }
                                    Text { text: (texts[modelData.id] && texts[modelData.id].hint) || modelData.hint; color: t.mute; font.family: t.body; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
                                }
                                // choice
                                Rectangle { visible: modelData.kind === "choice"; anchors.verticalCenter: parent.verticalCenter
                                    width: 170; height: 32; radius: 10; color: t.bg
                                    Row { anchors.centerIn: parent; spacing: 4
                                        Repeater { model: [["gamescope", "Gaming"], ["desktop", "Desktop"]]
                                            Rectangle { required property var modelData
                                                width: 80; height: 26; radius: 7; color: boot === modelData[0] ? t.accent : "transparent"
                                                Text { anchors.centerIn: parent; text: parent.modelData[1]; color: boot === parent.modelData[0] ? t.ink : t.mute; font.family: t.body; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                MouseArea { anchors.fill: parent; onClicked: boot = parent.modelData[0] } } } } }
                                // toggle
                                Row { visible: modelData.kind === "toggle"; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                                    Text { text: modelData.on ? "now on" : "now off"; color: modelData.on ? t.good : t.faint; font.family: t.mono; font.pixelSize: 12; width: 56; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                                    Rectangle { width: 46; height: 26; radius: 13; color: row.on ? t.accent : "#343f50"; anchors.verticalCenter: parent.verticalCenter
                                        Rectangle { width: 20; height: 20; radius: 10; color: "#f4f7fb"; y: 3; x: row.on ? 23 : 3; Behavior on x { NumberAnimation { duration: 120 } } } } }
                                // action
                                Rectangle { visible: modelData.kind === "action"; anchors.verticalCenter: parent.verticalCenter
                                    width: at.implicitWidth + 24; height: 30; radius: 8; color: t.warnBg
                                    Text { id: at; anchors.centerIn: parent; text: "In the terminal"; color: t.warn; font.family: t.body; font.pixelSize: 13; font.weight: Font.DemiBold } }
                            }
                        }
                    }
                }
                // Right: details + system
                Column {
                    x: 772; width: parent.width - 772; height: parent.height; spacing: 16
                    Rectangle {
                        width: parent.width; height: parent.height - sys.height - 16; radius: 16; color: t.card
                        readonly property var it: sel < rows.length ? rows[sel] : null
                        readonly property var tx: it ? (texts[it.id] || {}) : {}
                        Column {
                            anchors.fill: parent; anchors.margins: 24; spacing: 14
                            visible: parent.it !== null
                            Row { spacing: 10
                                Chip { text: parent.parent.parent.it ? (parent.parent.parent.it.kind === "choice" ? (boot === "desktop" ? "Desktop" : "Gaming") : (parent.parent.parent.it.kind === "action" ? "Opt-in" : (parent.parent.parent.it.on ? "On" : "Off"))) : ""
                                       fg: parent.parent.parent.it && parent.parent.parent.it.on ? t.good : "#b8c3d1"; bgc: parent.parent.parent.it && parent.parent.parent.it.on ? t.goodBg : t.line }
                                Chip { visible: !!parent.parent.parent.tx.experimental; text: "Experimental"; fg: t.warn; bgc: t.warnBg }
                            }
                            Text { text: parent.parent.it ? label(parent.parent.it) : ""; color: t.text; font.family: t.display; font.pixelSize: 26; font.weight: Font.DemiBold; wrapMode: Text.WordWrap; width: parent.width }
                            Text { text: parent.parent.tx.body || ""; color: t.soft; font.family: t.body; font.pixelSize: 15; lineHeight: 1.4; wrapMode: Text.WordWrap; width: parent.width }
                            Text { text: "WHAT IT CHANGES"; color: t.faint; font.family: t.body; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.8; topPadding: 4 }
                            Repeater { model: parent.parent.tx.changes || []
                                Text { required property string modelData; text: "•  " + modelData; color: t.soft; font.family: t.body; font.pixelSize: 14; wrapMode: Text.WordWrap; width: parent.width } }
                        }
                        Column {
                            anchors.centerIn: parent; spacing: 8; visible: parent.it === null
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
                    Text { readonly property int n: computePlan().length; text: n === 0 ? "Everything is the way you want it" : n + (n === 1 ? " change" : " changes"); color: t.faint; font.family: t.body; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
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
                Repeater {
                    model: plan
                    Rectangle { required property var modelData; width: 740; height: 56; radius: 12; color: t.card
                        readonly property var st: ({ on: ["Turn on", t.good, t.goodBg], off: ["Turn off", t.bad, t.badBg], again: ["Re-apply", "#7cc4ff", "#1b2b40"],
                                                     desktop: ["Desktop", "#7cc4ff", "#1b2b40"], gaming: ["Gaming", "#7cc4ff", "#1b2b40"] })[modelData.action]
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
                x: 812; y: 32; width: 428; height: 210; radius: 16; color: t.card
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
                Btn { anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter; k: g.back; text: "Back to the menu"; onClicked: screen = "menu" }
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
                Text { text: "Applying your changes"; color: t.text; font.family: t.display; font.pixelSize: 34; font.weight: Font.DemiBold }
                Rectangle { width: 560; height: 10; radius: 5; color: t.line
                    Rectangle { height: 10; radius: 5; color: t.accent; width: plan.length ? parent.width * Math.min(1, (doneCount + 0.3) / plan.length) : 0; Behavior on width { NumberAnimation { duration: 300 } } } }
                Row { width: 560
                    Text { text: "Step " + Math.min(plan.length, doneCount + 1) + " of " + plan.length; color: t.mute; font.family: t.body; font.pixelSize: 14; width: 280 }
                    Text { text: "Don't turn off the PC"; color: t.mute; font.family: t.body; font.pixelSize: 14; width: 280; horizontalAlignment: Text.AlignRight } }
                Repeater {
                    model: plan
                    Rectangle { required property var modelData; readonly property string st: steps[modelData.id] || "wait"
                        width: 560; height: 54; radius: 12; color: st === "run" ? t.cardSel : t.card; border.width: st === "run" ? 2 : 0; border.color: t.accent
                        Row { anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; spacing: 14
                            Rectangle { width: 22; height: 22; radius: 11; anchors.verticalCenter: parent.verticalCenter
                                color: parent.parent.st === "ok" ? t.goodBg : (parent.parent.st === "fail" ? t.badBg : "transparent")
                                border.width: parent.parent.st === "wait" || parent.parent.st === "run" ? 2 : 0; border.color: parent.parent.st === "run" ? t.accent : "#343f50"
                                Text { anchors.centerIn: parent; text: parent.parent.parent.st === "ok" ? "✓" : (parent.parent.parent.st === "fail" ? "!" : ""); color: parent.parent.parent.st === "ok" ? t.good : t.bad; font.pixelSize: 13; font.weight: Font.Bold }
                                RotationAnimator on rotation { running: parent.parent.parent.st === "run"; from: 0; to: 360; duration: 1000; loops: Animation.Infinite } }
                            Text { text: ({ on: "Turn on ", off: "Turn off ", again: "Re-apply ", desktop: "Boot into ", gaming: "Boot into " })[parent.parent.modelData.action] + ((texts[parent.parent.modelData.id] || {}).label || parent.parent.modelData.id)
                                   color: parent.parent.st === "wait" ? t.faint : t.textHi; font.family: t.body; font.pixelSize: 16; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter; width: 380; elide: Text.ElideRight }
                            Text { text: ({ wait: "Waiting", run: "Working…", ok: "Done", fail: "Problem" })[parent.parent.st]; color: parent.parent.st === "ok" ? t.good : (parent.parent.st === "fail" ? t.bad : "#b8c3d1"); font.family: t.body; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }
            Column {
                x: 632; y: 32; width: 608; height: parent.height - 64; spacing: 10
                Text { text: "DETAILS"; color: t.faint; font.family: t.body; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
                Rectangle { width: parent.width; height: parent.height - 30; radius: 16; color: "#0b0e13"; border.width: 1; border.color: "#1d2531"
                    ListView { id: logView; anchors.fill: parent; anchors.margins: 18; clip: true; model: logModel
                        onCountChanged: positionViewAtEnd()
                        delegate: Text { required property string line; width: logView.width; text: line; color: "#aab5c4"; font.family: t.mono; font.pixelSize: 13; wrapMode: Text.WrapAnywhere } } }
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
                Text { text: runError ? "Nothing changed" : (failed.length ? "Done, with a problem" : "All done"); color: t.text; font.family: t.display; font.pixelSize: 40; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: t.soft; font.family: t.body; font.pixelSize: 17
                       text: runError ? runError : (plan.length + (plan.length === 1 ? " change" : " changes") + " applied." + (restartNeeded ? " Some take effect after a restart." : "")) }
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
