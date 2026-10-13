import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "views"
import "sources"
import "IslandModel.js" as Model
import "views/GlassMath.js" as GlassMath
import "bridge" as Bridge

// Tusche Island: a theme-native activity island for Omarchy.
//
// A keep-loaded panel plugin: the shell mounts it at startup and it draws its
// own layer-shell strip across the top of one monitor. Only the island (and
// the split bubble) take input; everything else in the strip is click-through.
//
// Data flows one way: live sources (MPRIS, PipeWire, UPower, backlight,
// gpu-screen-recorder) feed plain properties on this root, those resolve to a
// single `view` name, and the frame moves to that view's size while the
// matching content fades in.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: manifest && manifest.id ? manifest.id : "nerdibeard.tusche-island"

  // ------------------------------------------------------------------
  // Settings: this plugin's entry in ~/.config/omarchy/shell.json plugins[]
  // ------------------------------------------------------------------
  property var settings: ({})

  function setting(key, fallback) {
    var v = settings ? settings[key] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property bool notch: false // No hardware-notch styling in this local variant.
  // "auto": show the resting island only when it has something to say
  // (agents, next meeting, limits...), else a small lip under the bar;
  // "pill": always the resting island; "hidden": nothing until live.
  readonly property string idleMode: {
    var m = String(setting("idle", "auto"))
    return ["auto", "pill", "hidden"].indexOf(m) !== -1 ? m : "auto"
  }
  readonly property bool idleHidden: idleMode === "hidden"
  readonly property bool idleQuiet: idleMode === "auto" && idleFace === "ticker" && idleSignals.length === 0
  readonly property real scaleFactor: Math.max(0.6, Math.min(2, Number(setting("scale", 1)) || 1))
  // Same gap under the bar as Omarchy's own popups, unless set.
  readonly property int topMargin: {
    var v = setting("topMargin", null)
    return v === null || !isFinite(Number(v)) ? Style.gapsOut : s(Number(v))
  }
  readonly property bool reserveSpace: setting("reserveSpace", false) === true
  readonly property string monitorSetting: String(setting("monitor", "primary"))
  readonly property bool expandOnHover: setting("expandOnHover", false) === true
  // In the bar: with the bar widget mounted, the bar shows the island and
  // opens it as a native popup; this panel's own strip stays unmapped.
  readonly property bool barMode: Bridge.IslandBus.widgets > 0 && setting("barMode", true) !== false
  QtObject {
    Component.onCompleted: Bridge.IslandBus.island = root
    Component.onDestruction: if (Bridge.IslandBus.island === root) Bridge.IslandBus.island = null
  }
  readonly property string clockFormat: String(setting("clockFormat", "HH:mm"))
  readonly property bool showVolume: setting("volume", false) === true
  readonly property bool showBrightness: setting("brightness", false) === true
  readonly property bool showCharging: setting("charging", true) !== false
  readonly property bool showTrackChange: setting("trackChange", true) !== false
  readonly property bool showRecording: setting("recording", true) !== false
  readonly property bool showMic: setting("mic", true) !== false
  readonly property var notchSize: null
  readonly property string idleFace: {
    var f = String(setting("idleFace", "ticker"))
    return ["ticker", "clock", "none"].indexOf(f) !== -1 ? f : "ticker"
  }
  readonly property bool artworkTint: setting("visualizerColor", "accent") === "artwork"
  readonly property int mediaLingerMs: Math.max(0, Number(setting("mediaLingerSeconds", 30))) * 1000
  // How notes look in the bar without a theme material: "window" or "bubble".
  readonly property string noteStyle: Model.noteStyle(setting("noteStyle", "window"))

  property var disabledPlugins: []
  // Options of the Tusche Bar plugin, if installed (Model.barOptions); the
  // island follows its `edge` ("none" | "theme").
  property var barOptions: ({})
  // Theme material (the bar's edge option "theme"; Tusche & Papier): the
  // current theme's bar-material.json – notes and popups take its light and
  // shadow. Off for themes without the file.
  readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"
  property var themeMaterial: null
  FileView {
    id: materialFile
    path: root.themeDir + "/bar-material.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.themeMaterial = JSON.parse(text()) } catch (e) { root.themeMaterial = null } }
    onLoadFailed: root.themeMaterial = null
  }
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    // the theme's green/orange too: Chrom and Tusche share background and
    // accent, so the palette signals below would not fire between them
    onLoaded: { materialFile.reload(); themeColorsFile.reload() }
  }
  readonly property var material: barOptions.edge === "theme" ? GlassMath.material(themeMaterial, barOptions.glass, barOptions.glassMotion) : null
  property bool configLoaded: false

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var cfg = Model.parseConfig(text())
      root.settings = Model.entryFor(cfg, root.pluginId)
      root.barOptions = Model.barOptions(cfg)
      root.disabledPlugins = Array.isArray(cfg.disabledPlugins) ? cfg.disabledPlugins : []
      root.configLoaded = true
    }
    onLoadFailed: {
      root.settings = ({})
      root.configLoaded = true
    }
  }

  // ------------------------------------------------------------------
  // Theme: Omarchy's shell tokens, plus the theme's green/yellow for the
  // charging and privacy tones the shell palette does not name.
  // ------------------------------------------------------------------
  property var themeColors: ({})

  FileView {
    id: themeColorsFile
    path: Commons.Color.currentThemePath + "/colors.toml"
    onLoaded: root.themeColors = Model.parseColors(text())
  }

  Connections {
    target: Commons.Color
    function onBackgroundChanged() { themeColorsFile.reload() }
    function onAccentChanged() { themeColorsFile.reload() }
  }

  // The same live palette and border renderer as Omarchy's popup cards.
  readonly property color surface: Commons.Color.popups.background
  readonly property color fg: Commons.Color.popups.text
  readonly property color fgDim: Util.alpha(fg, 0.65)
  readonly property color accentColor: Commons.Color.accent
  readonly property color urgentColor: Commons.Color.urgent
  readonly property color greenColor: themeColors.green || themeColors.color2 || Commons.Color.accent
  readonly property color orangeColor: themeColors.orange || themeColors.color3 || Commons.Color.accent
  readonly property real corner: Math.min(Style.cornerRadius, Style.space(2))
  readonly property var frameSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
  readonly property color rim: Commons.Color.popups.border
  // Prefer the theme's on-selection text where the theme names one.
  readonly property color accentText: themeColors.selection_foreground || surface
  function bodyAt(t) { return surface }
  // Numbers, time and icons in the theme's (Nerd) monospace; words too,
  // unless "textFont" names another family ("theme" keeps the theme font).
  readonly property string fontFamily: Style.font.family
  readonly property string textFamily: {
    var t = String(setting("textFont", "theme"))
    return t === "theme" ? Style.font.family : t
  }

  function s(px) { return Math.round(Style.space(px) * scaleFactor) }

  // Device pixel grid (1.25 on a 125% display).
  readonly property real dpr: win.devicePixelRatio > 0 ? win.devicePixelRatio : 1
  function snap(v) { return Math.round(v * dpr) / dpr }

  // Content appears only once the shape has (nearly) reached the new size,
  // so a view is never drawn cut off by a shape still growing towards it.
  readonly property bool shapeSettled: Math.abs(stage.w - s(viewSize.w)) < s(18)
    && Math.abs(stage.h - s(viewSize.h)) < s(12)
  function showing(name) { return view === name && shapeSettled }
  function f(px) { return Math.max(6, Math.round(px * Style.fontScale * scaleFactor)) }

  // Nothing announces itself for the first moments after (re)load, so the
  // initial volume/brightness/battery reads do not pop HUDs.
  property bool ready: false
  Timer { interval: 2500; running: true; onTriggered: root.ready = true }

  // ------------------------------------------------------------------
  // Media (MPRIS)
  // ------------------------------------------------------------------
  readonly property var players: Mpris.players ? Mpris.players.values : []
  property string currentPlayerKey: ""
  property int playerTick: 0
  readonly property var player: { playerTick; return Model.pickPlayer(players, currentPlayerKey) }

  // Remember what is on screen so the choice survives a pause. Deferred so
  // the write does not land inside the evaluation of `player` itself.
  onPlayerChanged: Qt.callLater(function() {
    if (root.player) root.currentPlayerKey = Model.playerKey(root.player)
  })

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() {
        // A player that starts playing takes over the island, unless it is
        // only a poorer copy of a song another player already shows.
        if (modelData.isPlaying && Model.candidates(root.players).indexOf(modelData) !== -1)
          root.currentPlayerKey = Model.playerKey(modelData)
        root.playerTick++
      }
      function onTrackTitleChanged() { root.playerTick++ }
      function onTrackArtistChanged() { root.playerTick++ }
    }
  }

  // Demo data (IPC `demo`) stands in for live sources so every state can be
  // previewed without a player running.
  property var demo: null
  readonly property var demoMedia: demo && demo.media ? demo.media : null
  readonly property bool demoOwnsMedia: !!demo && demo.media !== undefined

  readonly property bool hasMedia: demoOwnsMedia ? demoMedia !== null : player !== null
  readonly property bool mediaPlaying: demoMedia ? demoMedia.playing === true : (player ? player.isPlaying : false)
  readonly property string mediaTitle: demoMedia ? demoMedia.title : (player ? (player.trackTitle || "") : "")
  readonly property string mediaArtist: demoMedia ? demoMedia.artist : (player ? (player.trackArtist || "") : "")
  readonly property string mediaArt: demoMedia ? (demoMedia.art || "") : (player ? (player.trackArtUrl || "") : "")
  readonly property real mediaLength: demoMedia ? demoMedia.length
    : (player && player.lengthSupported ? player.length : 0)
  readonly property bool mediaCanSeek: !demoMedia && !!player && player.canSeek && player.positionSupported
  readonly property bool mediaCanNext: demoMedia ? true : (!!player && player.canGoNext)
  readonly property bool mediaCanPrevious: demoMedia ? true : (!!player && player.canGoPrevious)
  property real mediaPosition: 0

  // Keep the activity up for a while after pausing, during brief pauses, so a
  // quick pause does not make the island collapse and re-open.
  property bool mediaLinger: false
  onMediaPlayingChanged: {
    if (!mediaPlaying && hasMedia && mediaLingerMs > 0) {
      mediaLinger = true
      lingerTimer.restart()
    }
  }
  Timer { id: lingerTimer; interval: root.mediaLingerMs; onTriggered: root.mediaLinger = false }

  // MPRIS position is not pushed; poll it while something shows it.
  Timer {
    interval: 500
    repeat: true
    running: root.hasMedia && root.view === "media-expanded"
    triggeredOnStart: true
    onTriggered: {
      if (root.demoMedia) {
        if (root.demoMedia.playing) root.mediaPosition = (root.mediaPosition + 0.5) % Math.max(1, root.mediaLength)
      } else if (root.player && root.player.positionSupported) {
        root.player.positionChanged()
        root.mediaPosition = root.player.position
      }
    }
  }

  function updateDemo(mutator) {
    var next = JSON.parse(JSON.stringify(root.demo || {}))
    mutator(next)
    root.demo = next
  }

  function mediaToggle() {
    if (demoMedia) updateDemo(function(d) { d.media.playing = !d.media.playing })
    else if (player && player.canTogglePlaying) player.togglePlaying()
  }

  function mediaNext() {
    if (demoMedia) root.mediaPosition = 0
    else if (player && player.canGoNext) player.next()
  }

  function mediaPrevious() {
    if (demoMedia) root.mediaPosition = 0
    else if (player && player.canGoPrevious) player.previous()
  }

  function mediaSeek(fraction) {
    if (!mediaCanSeek || mediaLength <= 0) return
    var target = Math.max(0, Math.min(1, fraction)) * mediaLength
    player.position = target
    mediaPosition = target
  }

  // Track change → brief now-playing card. Debounced because players send
  // title and artist as separate updates.
  readonly property string trackSignature: mediaTitle + "\u0001" + mediaArtist
  property string shownTrack: ""
  onTrackSignatureChanged: trackDebounce.restart()

  Timer {
    id: trackDebounce
    interval: 450
    onTriggered: {
      var sig = root.trackSignature
      if (sig === root.shownTrack) return
      root.shownTrack = sig
      if (root.ready && root.showTrackChange && root.mediaPlaying && root.mediaTitle !== "" && !root.userExpanded)
        root.showHud({ layout: "track", duration: 3200 })
    }
  }

  // ------------------------------------------------------------------
  // Audio (PipeWire): output volume HUD and microphone privacy activity
  // ------------------------------------------------------------------
  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  onVolumeChanged: volumeHud()
  onMutedChanged: volumeHud()

  function volumeHud() {
    if (!ready || !showVolume || !sink) return
    showHud({
      key: "volume",
      layout: "progress",
      icon: Model.volumeIcon(volume, muted),
      value: muted ? 0 : volume,
      valueText: muted ? "Mute" : Math.round(volume * 100) + "%",
      color: muted ? fgDim : fg,
      duration: 1500
    })
  }

  function adjustVolume(delta) {
    if (!sink || !sink.audio || delta === 0) return
    sink.audio.muted = false
    sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + (delta > 0 ? 0.05 : -0.05)))
  }

  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property bool micActive: {
    for (var i = 0; i < pwNodes.length; i++)
      if (Model.isMicStream(pwNodes[i])) return true
    return false
  }

  // ------------------------------------------------------------------
  // Power (UPower): charging and low-battery HUDs
  // ------------------------------------------------------------------
  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!(battery && battery.isPresent)
  readonly property real batteryLevel: hasBattery ? Model.clamp01(battery.percentage) : 0
  readonly property bool charging: hasBattery && battery.state !== UPowerDeviceState.Discharging
    && battery.state !== UPowerDeviceState.Empty && battery.state !== UPowerDeviceState.Unknown

  onChargingChanged: {
    if (!ready || !showCharging || !charging) return
    edgeSweep++
    showHud({
      key: "power",
      layout: "label",
      label: "Charging",
      icon: Model.batteryIcon(batteryLevel, true),
      valueText: Model.percentText(batteryLevel),
      color: greenColor,
      duration: 2600
    })
  }

  property real lastBatteryLevel: -1
  onBatteryLevelChanged: {
    var previous = lastBatteryLevel
    lastBatteryLevel = batteryLevel
    if (!ready || !showCharging || charging || previous < 0) return
    var crossed = (previous > 0.2 && batteryLevel <= 0.2) || (previous > 0.1 && batteryLevel <= 0.1)
    if (!crossed) return
    showHud({
      key: "power",
      layout: "label",
      label: "Low Battery",
      icon: Model.batteryIcon(batteryLevel, false),
      valueText: Model.percentText(batteryLevel),
      color: urgentColor,
      duration: 3500
    })
  }

  // ------------------------------------------------------------------
  // Backlight: sysfs does not notify, so poll the one small file.
  // ------------------------------------------------------------------
  property string backlightDir: ""
  property int brightnessMax: 0
  property real brightness: -1

  Process {
    id: backlightProbe
    running: true
    command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/brightness\" ] && echo \"$d\" && cat \"$d/max_brightness\" && break; done"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        if (lines.length < 2) return
        root.brightnessMax = parseInt(lines[1], 10) || 0
        root.backlightDir = lines[0]
      }
    }
  }

  FileView {
    id: brightnessFile
    path: root.backlightDir ? root.backlightDir + "/brightness" : ""
    blockLoading: true
  }

  Timer {
    interval: 350
    repeat: true
    running: root.backlightDir !== "" && root.brightnessMax > 0 && root.showBrightness
    onTriggered: {
      brightnessFile.reload()
      var raw = parseInt(brightnessFile.text(), 10)
      if (isNaN(raw)) return
      var level = Model.clamp01(raw / root.brightnessMax)
      var previous = root.brightness
      root.brightness = level
      if (previous < 0 || Math.abs(level - previous) < 0.001 || !root.ready) return
      root.showHud({
        key: "brightness",
        layout: "progress",
        icon: Model.brightnessIcon(level),
        value: level,
        valueText: Math.round(level * 100) + "%",
        color: root.fg,
        duration: 1500
      })
    }
  }

  // ------------------------------------------------------------------
  // Screen recording (gpu-screen-recorder, which Omarchy's capture uses)
  // ------------------------------------------------------------------
  property bool recording: false
  property int recordingElapsed: 0

  Process {
    id: recordingProbe
    command: ["sh", "-c", "p=$(pgrep -of '^gpu-screen-recorder') && ps -o etimes= -p \"$p\""]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.demo && root.demo.recording !== undefined) return
        var elapsed = parseInt(String(text || "").trim(), 10)
        root.recording = !isNaN(elapsed)
        if (!isNaN(elapsed)) root.recordingElapsed = elapsed
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.showRecording
    triggeredOnStart: true
    onTriggered: if (!recordingProbe.running) recordingProbe.running = true
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.recordingActivity
    onTriggered: root.recordingElapsed++
  }

  // Same command the bar's recording indicator runs.
  function stopRecording() {
    if (demo && demo.recording !== undefined) {
      updateDemo(function(d) { d.recording = false })
      collapse()
      return
    }
    Quickshell.execDetached(["omarchy-capture-screenrecording", "--stop-recording"])
    collapse()
    recordingRecheck.restart()
  }

  Timer {
    id: recordingRecheck
    interval: 900
    onTriggered: if (!recordingProbe.running) recordingProbe.running = true
  }

  // ------------------------------------------------------------------
  // Takeovers: the island replaces Omarchy's notification service and its
  // on-screen display (the volume, brightness, microphone, keyboard light,
  // power and download popups at the bottom of the screen).
  //
  // Only one program can own each, so on first run the island disables the
  // Omarchy plugin (leaving a marker so it knows it did), and does the job
  // itself once that plugin has let go. Setting "notifications": false or
  // "osd": false, or disabling/removing this plugin, gives the job back.
  // ------------------------------------------------------------------
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/tusche-island"
  readonly property bool wantsNotifications: setting("notifications", false) === true
  readonly property bool wantsOsd: setting("osd", false) === true
  readonly property bool omarchyNotificationsOff: disabledPlugins.indexOf("omarchy.notifications") !== -1
  readonly property bool omarchyOsdOff: disabledPlugins.indexOf("omarchy.osd") !== -1
  property bool notificationsReady: false
  property bool osdReady: false
  property var takeoverRequested: ({})

  onWantsNotificationsChanged: syncTakeovers()
  onOmarchyNotificationsOffChanged: syncTakeovers()
  onWantsOsdChanged: syncTakeovers()
  onOmarchyOsdOffChanged: syncTakeovers()
  onConfigLoadedChanged: {
    syncTakeovers()
    fillDefaultSettings()
    syncKeybind()
  }

  function syncTakeovers() {
    if (!configLoaded) return
    syncTakeover("notifications", wantsNotifications, omarchyNotificationsOff)
    syncTakeover("osd", wantsOsd, omarchyOsdOff)
    if (!(wantsNotifications && omarchyNotificationsOff)) notificationsReady = false
    if (!(wantsOsd && omarchyOsdOff)) osdReady = false
    takeoverReadyTimer.restart()
  }

  // `name` is both the Omarchy plugin (omarchy.<name>) and the marker file.
  function syncTakeover(name, wants, off) {
    if (wants === off || takeoverRequested[name]) return
    takeoverRequested[name] = true
    var args = ["sh", stateDir + "/" + name + "-takeover", "omarchy." + name]
    if (wants)
      Quickshell.execDetached(["sh", "-c",
        "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\" && \"$OMARCHY_PATH/bin/omarchy-plugin-disable\" \"$2\""].concat(args))
    else
      // Only hand back what this plugin took.
      Quickshell.execDetached(["sh", "-c",
        "[ -f \"$1\" ] && \"$OMARCHY_PATH/bin/omarchy-plugin-enable\" \"$2\" && rm -f \"$1\""].concat(args))
  }

  // Give Omarchy's plugins a moment to let go after a reload.
  Timer {
    id: takeoverReadyTimer
    interval: 1500
    onTriggered: {
      root.notificationsReady = root.wantsNotifications && root.omarchyNotificationsOff
      root.osdReady = root.wantsOsd && root.omarchyOsdOff
    }
  }

  // ------------------------------------------------------------------
  // Settings in place: every setting the island's entry in shell.json lacks
  // is written there with its default, so people change values instead of
  // looking keys up. Values already there are never touched.
  // ------------------------------------------------------------------
  // shell.json is only ever written by Omarchy's shell (in-process, atomic):
  // this merges `changes` into the plugin's current entry and hands the whole
  // entry to shell.updateEntryInline, which replaces it.
  function saveSettings(changes) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    var next = {}
    for (var k in settings) if (k !== "id") next[k] = settings[k]
    for (var c in changes) next[c] = changes[c]
    return shell.updateEntryInline(pluginId, next)
  }

  onShellChanged: fillDefaultSettings()

  function fillDefaultSettings() {
    if (!configLoaded) return
    var missing = Model.missingSettings(settings)
    if (missing.length === 0) return
    var changes = {}
    for (var i = 0; i < missing.length; i++) changes[missing[i]] = Model.defaultSettings[missing[i]]
    saveSettings(changes)
  }

  // ------------------------------------------------------------------
  // Keybinding: the "keybind" setting (SUPER + ALT + I) toggles
  // reserveSpace. It lives in a marked block in ~/.config/hypr/bindings.lua.
  // A key something else already uses is left alone, "keybind": false
  // drops it, and disabling/removing the plugin removes the block.
  // ------------------------------------------------------------------
  readonly property string bindingsFile: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
  readonly property string keybind: {
    var k = setting("keybind", Model.defaultSettings.keybind)
    return k === false ? "" : String(k).trim()
  }
  // Shell snippets for the file in $1 and plugin id $2. Edits are written to
  // a new file beside it and renamed over it, and a bindings.lua that is a
  // symlink or not a regular file is left alone.
  readonly property string bindingsGuard: "[ -f \"$1\" ] && [ ! -L \"$1\" ] || exit 0; "
  // Replace the file with stdin, atomically.
  readonly property string bindingsReplace:
    "t=$(mktemp \"$1.island.XXXXXX\") || exit 1; cat > \"$t\" && chmod --reference=\"$1\" \"$t\" " +
    "&& mv -f \"$t\" \"$1\" || rm -f \"$t\"; "
  readonly property string removeBindingsBlock:
    bindingsGuard +
    "grep -qxF -e \"-- BEGIN $2\" \"$1\" || exit 0; " +
    "sed \"/^-- BEGIN $2\\$/,/^-- END $2\\$/d\" \"$1\" | { " + bindingsReplace + "}; true"

  onKeybindChanged: syncKeybind()

  function syncKeybind() {
    if (!configLoaded) return
    var parsed = Model.parseKeybind(keybind)
    if (!parsed) {
      Quickshell.execDetached(["sh", "-c", removeBindingsBlock, "sh", bindingsFile, pluginId])
      return
    }
    var bind = "o.bind(\"" + keybind + "\", \"Toggle island reserved space\", " +
               "\"omarchy-shell tusche-island reserveSpace toggle\")"
    var block = [
      "-- BEGIN " + pluginId,
      "-- Added by the " + pluginId + " plugin and removed with it. Change the key",
      "-- with \"keybind\" in its entry in ~/.config/omarchy/shell.json.",
      bind,
      "-- END " + pluginId
    ].join("\n")
    // $1 file, $2 id, $3 block, $4 bind line, $5 mask, $6 key. Only check for
    // a clash when our block doesn't already hold this key, since Hyprland
    // lists our own binding too.
    Quickshell.execDetached(["sh", "-c",
      bindingsGuard +
      "[ \"$(sed -n \"/^-- BEGIN $2\\$/,/^-- END $2\\$/p\" \"$1\")\" = \"$3\" ] && exit 0; " +
      "if ! grep -qxF -e \"$4\" \"$1\" && hyprctl binds -j 2>/dev/null | jq -e --argjson m \"$5\" --arg k \"$6\" " +
      "'any(.[]; .modmask == $m and (.key | ascii_downcase) == ($k | ascii_downcase))' >/dev/null; then " +
      "  (" + removeBindingsBlock + "); exit 0; fi; " +
      "{ sed \"/^-- BEGIN $2\\$/,/^-- END $2\\$/d\" \"$1\" | sed -e :a -e '/^\\n*$/{$d;N;ba' -e '}'; " +
      "echo; printf '%s\\n' \"$3\"; } | { " + bindingsReplace + "}",
      "sh", bindingsFile, pluginId, block, bind, String(parsed.mask), parsed.key])
  }

  // The shell destroys this object on reloads and restarts too, so only act
  // if, a few seconds later, the plugin is really gone from shell.json. Then
  // hand back everything the island took over and remove its keybinding.
  // The shell can be mid-reload right then, so re-enabling is retried, and a
  // marker goes once its plugin is no longer listed as disabled.
  Component.onDestruction: Quickshell.execDetached(["sh", "-c",
    "sleep 4; c=\"$HOME/.config/omarchy/shell.json\"; " +
    // Still configured (in plugins[] or in the bar layout, where the bar
    // widget keeps its entry): only a reload, keep everything.
    "jq -e --arg id \"$1\" '[.plugins[]?, ((.bar.layout // {}) | (.left // [])[], (.center // [])[], (.right // [])[])] " +
    "| any(.[]; (type == \"object\" and .id == $id) or . == $id)' \"$c\" >/dev/null 2>&1 && exit 0; " +
    "for t in notifications osd; do " +
    "  [ -f \"$2/$t-takeover\" ] || continue; " +
    "  for try in 1 2 3; do \"$OMARCHY_PATH/bin/omarchy-plugin-enable\" \"omarchy.$t\" >/dev/null 2>&1 && break; sleep 2; done; " +
    "  sleep 1; jq -e --arg p \"omarchy.$t\" '(.disabledPlugins // []) | index($p)' \"$c\" >/dev/null 2>&1 " +
    "    || rm -f \"$2/$t-takeover\"; " +
    "done; " +
    "set -- \"$3\" \"$1\"; " + removeBindingsBlock,
    "sh", pluginId, stateDir, bindingsFile])

  // Omarchy's `omarchy osd` and every script that calls it land here while
  // the island owns the OSD. Volume comes from PipeWire already, so its
  // popups are dropped; the rest show as island HUDs.
  function showOsd(payloadJson) {
    var payload
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { return }
    var next = Model.osdHud(payload, { volume: showVolume && !sink, brightness: showBrightness })
    if (!next) return
    next.color = next.dim ? fgDim : fg
    showHud(next)
  }

  IpcHandler {
    target: "osd"
    enabled: root.osdReady
    function show(payloadJson: string): string { root.showOsd(payloadJson); return "ok" }
    function close(): string {
      if (root.hud && ["osd", "volume", "brightness"].indexOf(root.hud.key) !== -1) root.hud = null
      return "ok"
    }
    function state(): string { return root.hud ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  Notifications {
    id: notifications
    island: root
    active: root.notificationsReady
    columnMode: root.barMode
  }

  // In the bar the island serves notifications as a column under itself
  // (NotificationColumn.qml) with a bell segment beside the clock.
  readonly property bool columnNotes: barMode && notificationsReady
  readonly property var noteCurrent: notifications.current
  readonly property var noteLine: notifications.line
  readonly property int unreadCount: notifications.unread
  readonly property bool doNotDisturb: notifications.doNotDisturb
  function setDoNotDisturb(value) { notifications.setDoNotDisturb(value) }
  function markAllRead() { notifications.markAllRead() }
  // The pointer on the island in the bar (holds the low-urgency line).
  property bool barHovered: false
  function notificationClearInbox() {
    notifications.clearInbox()
    collapse()
  }
  // A deferred requester picked from the inbox: back to its buttons.
  function requeueNote(key) {
    notifications.requeue(key)
    collapse()
  }
  NotificationColumn { id: noteColumn; island: root; service: notifications }

  // An app's tone from the theme: mail blue, chats green, phone cyan,
  // agents orange, updates yellow, else the accent; critical and failures
  // (announceFailure) are urgent.
  function noteTone(entry) {
    if (!entry) return accentColor
    if (entry.critical) return urgentColor
    var tc = themeColors || {}
    var app = String(entry.app || "") + " " + String(entry.desktopEntry || "")
    if (/^(systemd|coredump)$/.test(String(entry.app || ""))) return urgentColor
    if (/mail|thunderbird|geary/i.test(app)) return tc.blue || tc.color4 || accentColor
    if (/whatsapp|signal|telegram|discord|slack|chat/i.test(app)) return greenColor
    if (/flux|phone|pixel|kdeconnect/i.test(app)) return tc.cyan || tc.color6 || accentColor
    if (/claude|codex|agent|openclaw|antigravity/i.test(app)) return orangeColor
    if (/update|omarchy/i.test(app)) return tc.yellow || tc.color3 || orangeColor
    return accentColor
  }

  readonly property var notification: notifications.current
  readonly property int notificationsPending: notifications.pending
  readonly property var inbox: notifications.inbox
  readonly property bool showInbox: setting("inbox", true) !== false

  function notificationOpen(key) {
    notifications.open(key)
    if (inboxOpen && inbox.length === 0) collapse()
  }

  function notificationDismiss(key) {
    notifications.dismiss(key)
    if (inboxOpen && inbox.length === 0) collapse()
  }

  function notificationAction(key, id) { notifications.invokeAction(key, id) }

  function notificationClearAll() {
    notifications.clearAll()
    collapse()
  }

  // Opens the list of waiting notifications (bell click, or Omarchy's
  // notification-history keybind).
  function openInbox() {
    hud = null
    inboxOpen = true
    userExpanded = true
    if (!hovered) {
      collapseTimer.interval = 8000
      collapseTimer.restart()
    }
  }

  // An icon URL that will actually load, or "" for the glyph fallback.
  // Quickshell hands appIcon over as image://icon/<name> even when the theme
  // has no such icon (which renders as a magenta checkerboard), so theme
  // names are checked before use.
  function themedIcon(name) {
    var n = String(name || "")
    if (!n) return ""
    if (n.charAt(0) === "/") return "file://" + n
    return Quickshell.iconPath(n, true) || ""
  }

  function notificationIcon(entry) {
    if (!entry || entry.glyph) return ""
    var image = String(entry.image || "")
    if (image) {
      if (image.charAt(0) === "/") return "file://" + image
      if (image.indexOf("image://icon/") === 0) return themedIcon(image.substring(13))
      return image
    }
    var icon = String(entry.appIcon || "")
    if (icon.indexOf("image://icon/") === 0) icon = icon.substring(13)
    if (icon.indexOf("file://") === 0 || (icon.indexOf("://") !== -1 && icon.indexOf("image://icon/") !== 0)) return icon
    var themed = themedIcon(icon)
    if (themed) return themed
    var desktop = entry.desktopEntry ? DesktopEntries.byId(entry.desktopEntry) : null
    if (!desktop && entry.app) desktop = DesktopEntries.heuristicLookup(entry.app)
    return desktop && desktop.icon ? themedIcon(desktop.icon) : ""
  }

  // ------------------------------------------------------------------
  // Timer, stopwatch, Bluetooth devices, calendar, script activities
  // ------------------------------------------------------------------
  Clocks { id: clockSource; island: root }
  Devices { island: root }
  Calendar { id: calendarSource; island: root }
  Activities { id: activitySource; island: root }
  // Flux (agents, phone) and AI usage limits, read-only.
  Desktop { id: desktopSource; island: root }

  readonly property var clocks: clockSource
  readonly property var calendar: calendarSource
  readonly property var activityStore: activitySource
  readonly property var desktop: desktopSource
  readonly property var activity: activitySource.current

  function endActivity(id) { activitySource.end(id, "") }

  // ---- calendar view
  property bool calendarOpen: false
  // The "add calendar" field. Kept here (not in the view) so the keyboard
  // grab below is derived from it and can never get out of step with it.
  property bool calendarAdding: false
  readonly property bool calendarTyping: calendarAdding && view === "calendar-expanded"

  function openCalendar() {
    hud = null
    inboxOpen = false
    outputsOpen = false
    calendarOpen = true
    userExpanded = true
    // No calendars yet: open straight into the field.
    calendarAdding = !calendarSource.hasAny
    if (!hovered) {
      collapseTimer.interval = 10000
      collapseTimer.restart()
    }
  }

  // Calendar links can also live in this plugin's shell.json entry
  // ("calendars"); the settings watcher picks the change up.
  function editCalendars(op, link) {
    var url = String(link)
    var list = (Array.isArray(settings.calendars) ? settings.calendars : []).filter(function(x) { return x !== url })
    if (op === "add") list.push(url)
    saveSettings({ calendars: list })
  }

  function addCalendar(link) {
    var l = String(link || "").trim()
    if (!l) return
    // Saved in the island's own file; the result (event count, or what went
    // wrong) is reported once the new link has actually been fetched.
    calendarSource.add(l)
  }

  function removeCalendar(link) { calendarSource.remove(link) }

  // "Paste" button: add whatever link is on the clipboard.
  Process {
    id: clipboardRead
    // Only the first 4 KiB: a link, not whatever else is on the clipboard.
    command: ["sh", "-c", "wl-paste --no-newline --type text 2>/dev/null | head -c 4096"]
    stdout: StdioCollector {
      onStreamFinished: {
        var link = String(text || "").trim().split(/\s+/)[0] || ""
        if (/^(https?|webcal):\/\//i.test(link) || /\.ics$/i.test(link)) {
          root.addCalendar(link)
          root.calendarAdding = false
        } else {
          root.showHud({ key: "calendar", layout: "label", label: "No calendar link copied", icon: "󰃭",
                         valueText: "", color: root.orangeColor, duration: 2200 })
        }
      }
    }
  }

  function addCalendarFromClipboard() {
    if (!clipboardRead.running) clipboardRead.running = true
  }

  function openLink(url) {
    Quickshell.execDetached(["xdg-open", String(url)])
    collapse()
  }

  // ------------------------------------------------------------------
  // Camera in use: any process holding a /dev/video* device open.
  // ------------------------------------------------------------------
  property bool cameraActive: false

  Process {
    id: cameraProbe
    command: ["sh", "-c", "find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/video*' -print -quit 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.demo && root.demo.camera !== undefined) return
        root.cameraActive = String(text || "").trim() !== ""
      }
    }
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.setting("camera", true) !== false
    triggeredOnStart: true
    onTriggered: if (!cameraProbe.running) cameraProbe.running = true
  }

  // ------------------------------------------------------------------
  // Media tint: the theme accent, or (visualizerColor: "artwork") the most
  // vivid color of the cover for the equalizer.
  // ------------------------------------------------------------------
  ColorQuantizer {
    id: quantizer
    source: root.artworkTint && root.mediaArt ? root.mediaArt : ""
    depth: 3
    rescaleSize: 64
  }

  readonly property color mediaTint: {
    if (!artworkTint) return accentColor
    var best = null
    var bestScore = 0
    var colors = quantizer.colors || []
    for (var i = 0; i < colors.length; i++) {
      var c = colors[i]
      if (c.hsvValue < 0.35) continue
      var score = c.hsvSaturation * c.hsvValue
      if (score > bestScore) { best = c; bestScore = score }
    }
    return best && bestScore > 0.12 ? Qt.hsva(best.hsvHue, Math.max(0.45, best.hsvSaturation), Math.max(0.75, best.hsvValue), 1) : accentColor
  }

  // ------------------------------------------------------------------
  // Audio outputs ("Play on")
  // ------------------------------------------------------------------
  readonly property var audioOutputs: pwNodes.filter(function(n) { return n && n.isSink && !n.isStream && n.audio })
  property bool outputsOpen: false

  function openOutputs() { outputsOpen = true; userExpanded = true }
  function closeOutputs() { outputsOpen = false }

  function outputGlyph(node) {
    if (!node) return "󰓃"
    var id = (String(node.name || "") + " " + String(node.description || "")).toLowerCase()
    if (id.indexOf("bluez") !== -1 || id.indexOf("headphone") !== -1 || id.indexOf("headset") !== -1) return "󰋋"
    if (id.indexOf("hdmi") !== -1 || id.indexOf("displayport") !== -1) return "󰡁"
    return "󰓃"
  }

  // Output names usually share a long card prefix ("Raptor Lake-P/U/H cAVS
  // Speaker", "... HDMI / DisplayPort 1 Output"); drop the shared words.
  function outputLabel(node) {
    var name = String(node && (node.description || node.nickname || node.name) || "")
    var first = name.split(" ")[0]
    // Compare only against outputs from the same card (same first word), so
    // a Bluetooth headset in the list doesn't stop the trimming.
    var group = audioOutputs.map(function(n) { return String(n.description || n.nickname || n.name || "") })
      .filter(function(a) { return a.split(" ")[0] === first })
    if (group.length < 2) return name
    var words = name.split(" ")
    var common = 0
    while (common < words.length - 1 && group.every(function(a) {
      var w = a.split(" ")
      return w.length > common + 1 && w[common] === words[common]
    })) common++
    return words.slice(common).join(" ") || name
  }

  function selectOutput(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    closeOutputs()
    showHud({
      key: "output", layout: "label",
      label: outputLabel(node),
      icon: outputGlyph(node), valueText: "Playing on", color: accentColor, duration: 1800
    })
  }

  // ------------------------------------------------------------------
  // Idle face: the glance ticker on the resting island.
  // ------------------------------------------------------------------
  SystemClock {
    id: idleClock
    precision: SystemClock.Minutes
  }

  // What the resting island can say that the bar above does not already
  // show: working agents, the next meeting, a nearly spent AI limit, a
  // phone or laptop running low, today's all-day events, Do Not Disturb.
  // The time and date stay in the bar.
  readonly property var idleSignals: {
    var items = []
    var now = idleClock.date.getTime()
    var working = desktop.working
    if (working.length > 0)
      items.push({ key: "agents", text: "󰚩 " + (working.length === 1 ? (working[0].title || working[0].agent) : working.length + " working"),
                   color: accentColor })
    var next = calendar.next
    if (next && next.start - now < 12 * 3600000 && next.start > now)
      items.push({ key: "event", text: "󰃭 " + Model.untilText(next.start, now), color: accentColor })
    var festivals = calendar.todayAllDay
    if (festivals.length > 0) items.push({ key: "festival", text: "✦ " + festivals[0], color: orangeColor })
    var top = desktop.topLimit
    if (top && top.percent >= 0.9)
      items.push({ key: "limit", text: "󰚩 " + Model.providerName(top.provider) + " " + Model.shortLimit(top.label) + " " + Math.round(top.percent * 100) + "%",
                   color: top.percent >= 0.999 ? urgentColor : orangeColor })
    if (desktop.phoneLow)
      items.push({ key: "phone", text: "󰁺 " + desktop.phone.name + " " + Math.round(desktop.phone.charge) + "%", color: urgentColor })
    if (hasBattery && !charging && batteryLevel <= 0.2)
      items.push({ key: "battery", text: Model.batteryIcon(batteryLevel, false) + " " + Model.percentText(batteryLevel), color: urgentColor })
    if (notifications.doNotDisturb) items.push({ key: "dnd", text: "󰂛 Silenced", color: orangeColor })
    return items
  }

  readonly property var idleItems: {
    if (idleFace === "clock") {
      var ampm = clockFormat.indexOf("AP") !== -1
      // Qt only gives 12-hour "h" when AM/PM is in the same format, so format
      // with it and drop the suffix: "10:57", not "22:57".
      return [{ key: "time", text: ampm ? Qt.formatDateTime(idleClock.date, "h:mm AP").replace(/\s*[AaPp][Mm]$/, "")
                                        : Qt.formatDateTime(idleClock.date, "HH:mm") }]
    }
    // Hovering a quiet island: a hint of what a click opens.
    return idleSignals.length > 0 ? idleSignals
      : [{ key: "open", text: "󰔛 Timer · 󰃭 " + Qt.formatDateTime(idleClock.date, "ddd d") }]
  }

  property int idleIndex: 0
  readonly property var idleItem: idleItems.length > 0 ? idleItems[idleIndex % idleItems.length] : null

  // Flip to the next glance every few seconds, but only while the island
  // is actually resting (no point animating under a live activity).
  Timer {
    interval: 5000
    repeat: true
    running: root.idleFace === "ticker" && (root.view === "idle" || root.view === "idle-hover") && root.idleItems.length > 1
    onTriggered: root.idleIndex = (root.idleIndex + 1) % root.idleItems.length
  }

  TextMetrics {
    id: idleMetrics
    font.family: root.fontFamily
    font.pixelSize: root.f(12)
    font.bold: true
    text: root.idleItem ? root.idleItem.text : ""
  }

  // ------------------------------------------------------------------
  // Edge light: what the lip of the island says about the current state.
  // ------------------------------------------------------------------
  readonly property var edgeState: {
    var v = view
    if (v === "hud-progress" && hud)
      return { tone: hud.color || fg, level: 0.95, progress: Math.max(0, Math.min(1, Number(hud.value) || 0)) }
    if (v === "timer" || (v === "clock-expanded" && clockSource.timerActive))
      return { tone: orangeColor, level: clockSource.timerPaused ? 0.35 : 0.95, progress: 1 - clockSource.timerProgress }
    if (v === "stopwatch" || v === "clock-expanded")
      return { tone: accentColor, level: clockSource.stopwatchRunning ? 0.8 : 0.3, pulse: clockSource.stopwatchRunning, period: 2000 }
    if (v.indexOf("recording") === 0)
      return { tone: urgentColor, level: 0.95, pulse: true, period: 1600 }
    if ((v === "activity" || v === "activity-expanded") && activity && activity.progress >= 0)
      return { tone: toneFor(activity.color), level: 0.95, progress: activity.progress }
    if (v === "activity" || v === "activity-expanded")
      return { tone: activity ? toneFor(activity.color) : accentColor, level: 0.8, pulse: true, period: 1800 }
    if (v === "media" || v === "hud-track" || v === "media-expanded")
      return { tone: mediaTint, level: mediaPlaying ? (v === "media-expanded" ? 0.6 : 0.9) : 0.25, pulse: mediaPlaying, period: 900 }
    if (v === "notification" || v === "notification-actions")
      return { tone: notification && notification.critical ? urgentColor : accentColor, level: 0.55 }
    if (v === "hud-label" && hud)
      return { tone: hud.color || accentColor, level: 0.85 }
    if (v === "mic")
      return { tone: cameraActive ? greenColor : orangeColor, level: 0.85, pulse: true, period: 2400 }
    if (v === "calendar")
      return { tone: accentColor, level: 0.85, pulse: true, period: 2400 }
    if (v === "inbox")
      return { tone: accentColor, level: 0.6 }
    if (v === "idle" || v === "idle-hover")
      return { tone: accentColor, level: v === "idle-hover" ? 0.6 : 0.32 }
    if (v === "tab")
      return { tone: accentColor, level: 0.45 }
    return { tone: accentColor, level: 0.2 }
  }
  property int edgeSweep: 0

  // A bead of light runs along the lip when something arrives.
  onNotificationChanged: if (notification) edgeSweep++

  // ------------------------------------------------------------------
  // State
  // ------------------------------------------------------------------
  readonly property bool recordingActivity: showRecording
    && (demo && demo.recording !== undefined ? demo.recording === true : recording)
  readonly property bool mediaActivity: hasMedia && (mediaPlaying || mediaLinger || (demoMedia !== null))
  readonly property bool micActivity: showMic && (demo && demo.mic !== undefined ? demo.mic === true : micActive)
  // In the bar the bell segment holds the inbox; the pill stays free.
  readonly property bool inboxActivity: showInbox && inbox.length > 0 && !columnNotes
  readonly property bool timerActivity: clockSource.timerActive
  readonly property bool stopwatchActivity: clockSource.stopwatchActive
  readonly property bool scriptActivity: activitySource.current !== null
  readonly property bool calendarActivity: setting("calendar", true) !== false && calendarSource.soon

  // An agent waiting for you (herdr "blocked"): the most important thing.
  readonly property bool attentionActivity: setting("attention", true) !== false && desktop.blocked.length > 0
  readonly property var attentionAgent: desktop.blocked.length > 0 ? desktop.blocked[0] : null

  // A flash instead of a sound: the bar widget inverts the segment twice
  // when this counter moves (an agent starts waiting for you).
  property int flashSerial: 0
  function flash() { flashSerial++ }

  // Something really broke (a failed systemd unit, a core dump): announced
  // once as an ordinary notification, so it reaches the column (or Omarchy's
  // toasts) and waits in the inbox; a click opens the details in a terminal.
  function announceFailure(f) {
    var crash = f.kind === "crash"
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", crash ? "coredump" : "systemd",
      "-u", "normal", "-g", crash ? "\u{f00e4}" : "\u{f0026}",
      crash ? "Program crashed" : "Service failed", f.name + (f.scope ? " (" + f.scope + ")" : ""),
      "--exec", "xdg-terminal-exec", "--", "bash", "-lc", f.command + "; echo; read -n1 -p 'Press any key to close'"])
  }
  Failures { island: root }

  readonly property var activityList: Model.activities({
    attention: attentionActivity,
    recording: recordingActivity,
    media: mediaActivity,
    mic: micActivity || (setting("camera", true) !== false && cameraActive),
    inbox: inboxActivity,
    timer: timerActivity,
    stopwatch: stopwatchActivity,
    activity: scriptActivity,
    calendar: calendarActivity
  })
  readonly property string primary: activityList.length > 0 ? activityList[0] : ""
  readonly property string secondary: activityList.length > 1 ? activityList[1] : ""

  property bool userExpanded: false
  property bool inboxOpen: false
  // Which activity an opened island is about (the bubble's, when the
  // bubble was clicked).
  property string openFocus: ""
  property var hud: null
  readonly property bool hovered: islandHover.hovered

  readonly property string view: Model.viewFor({
    userExpanded: userExpanded,
    inboxOpen: inboxOpen,
    outputsOpen: outputsOpen,
    calendarOpen: calendarOpen,
    focus: openFocus,
    hasMedia: hasMedia,
    recording: recordingActivity,
    hud: hud,
    notification: notification !== null,
    notificationActions: notification !== null && notification.actions.length > 0,
    primary: primary,
    idleHidden: idleHidden,
    idleQuiet: idleQuiet,
    hovered: hovered
  })
  readonly property var viewCounts: ({ inbox: inbox.length, outputs: audioOutputs.length })
  readonly property var viewSize: {
    var v = Model.sizeFor(view, viewCounts, notchSize)
    // The resting pill grows to fit what the ticker is showing, so the
    // island breathes a little as the glances change.
    if ((view === "idle" || view === "idle-hover") && (idleFace === "ticker" || idleFace === "clock")) {
      var unit = Style.spacing.scale * scaleFactor
      var needed = Math.ceil(idleMetrics.advanceWidth / unit) + 44 + (view === "idle-hover" ? 12 : 0)
      return { w: Math.min(260, Math.max(v.w, needed)), h: v.h, r: v.r }
    }
    return v
  }
  function slotSize(name) {
    if (name === "inbox-expanded" && columnNotes) return Model.noteInboxSize(inbox.length)
    return Model.sizeFor(name, viewCounts, notchSize)
  }
  readonly property bool showBubble: secondary !== "" && !userExpanded && hud === null

  function showHud(next) {
    hud = next
    hudTimer.interval = Math.max(600, Number(next.duration) || 1600)
    hudTimer.restart()
  }

  Timer { id: hudTimer; onTriggered: root.hud = null }

  function expand() {
    hud = null
    userExpanded = true
    // Opened without the pointer on it (IPC, keybind): close on its own.
    if (!hovered) {
      collapseTimer.interval = 6000
      collapseTimer.restart()
    }
  }

  function collapse() {
    userExpanded = false
    inboxOpen = false
    outputsOpen = false
    calendarOpen = false
    calendarAdding = false
    openFocus = ""
    collapseTimer.stop()
  }

  function toggleExpanded() {
    if (userExpanded) collapse()
    else expand()
  }

  // Leaving an opened island closes it, the way a notch shelf does.
  Timer {
    id: collapseTimer
    interval: 500
    // In the bar the popup closes the native way (outside click, Esc).
    onTriggered: if (!root.barMode && !root.hovered && !root.calendarTyping) root.collapse()
  }

  Timer {
    id: hoverExpandTimer
    interval: 380
    onTriggered: if (root.hovered && !root.userExpanded) root.expand()
  }

  onHoveredChanged: {
    if (hovered) {
      collapseTimer.stop()
      if (expandOnHover) hoverExpandTimer.restart()
    } else {
      hoverExpandTimer.stop()
      if (userExpanded) {
        collapseTimer.interval = 500
        collapseTimer.restart()
      }
    }
  }

  function islandClicked(button) {
    if (button === Qt.MiddleButton) {
      if (hasMedia) mediaToggle()
      return
    }
    // The bell owns the pill when nothing else is live: open the inbox.
    if (!userExpanded && primary === "inbox") {
      openInbox()
      return
    }
    toggleExpanded()
  }

  // ------------------------------------------------------------------
  // Shell contract + IPC
  // ------------------------------------------------------------------
  readonly property bool opened: userExpanded

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (payload && payload.title) toast(payload)
    else expand()
  }

  function close() { collapse() }
  function toggle() { toggleExpanded() }

  function toneFor(name) {
    var n = String(name || "")
    if (n === "" || n === "accent") return accentColor
    if (n === "green" || n === "success") return greenColor
    if (n === "orange" || n === "yellow" || n === "warning") return orangeColor
    if (n === "red" || n === "urgent" || n === "error") return urgentColor
    if (n === "foreground") return fg
    return n
  }

  function announceAgentDone(agent) {
    toast({ title: agent.title || agent.agent || "Agent", body: "Done · " + (agent.agent || "agent"),
            icon: "󰄬", color: "green", duration: 5000 })
    Quickshell.execDetached(Model.agentDoneCommand(agent))
  }

  function toast(payload) {
    showHud({
      key: "toast",
      layout: "toast",
      title: String(payload.title || ""),
      body: String(payload.body || ""),
      icon: String(payload.icon || ""),
      color: toneFor(payload.color),
      duration: Number(payload.duration) || 4000
    })
  }

  readonly property string demoCoverPath: Quickshell.env("HOME") + "/.local/state/omarchy/tusche-island/demo-cover.png"
  property bool demoCoverReady: false
  Process {
    running: true
    command: ["test", "-f", root.demoCoverPath]
    onExited: function(code) { root.demoCoverReady = code === 0 }
  }

  function runDemo(kind) {
    // Switching demo data swaps the "current track"; that is not a real track
    // change, so mark it as already shown before the debounce looks at it.
    Qt.callLater(function() { root.shownTrack = root.trackSignature })
    // A demo cover if one has been made (the showcase does), else the
    // current wallpaper stands in for album art.
    var art = demoCoverReady ? "file://" + demoCoverPath : ""
    var media = { playing: true, title: "Midnight City", artist: "M83", art: art, length: 243 }
    if (kind === "off") {
      demo = null; hud = null; collapse(); recordingProbe.running = true; cameraProbe.running = true
      clocks.cancelTimer(); clocks.resetStopwatch(); activitySource.end("demo", ""); calendarSource.refresh()
    } else if (kind === "media") {
      demo = { media: media }; mediaPosition = 71
    } else if (kind === "paused") {
      media.playing = false; demo = { media: media }; mediaPosition = 71
    } else if (kind === "recording") {
      demo = { recording: true }; recordingElapsed = 42
    } else if (kind === "mic") {
      demo = { mic: true }
    } else if (kind === "split") {
      demo = { media: media, recording: true }; recordingElapsed = 42; mediaPosition = 71
    } else if (kind === "expanded") {
      demo = { media: media }; mediaPosition = 71; expand()
    } else if (kind === "recording-expanded") {
      demo = { media: media, recording: true }; recordingElapsed = 42; mediaPosition = 71; expand()
    } else if (kind === "idle-expanded") {
      demo = { media: null, recording: false, mic: false }; expand()
    } else if (kind === "volume" || kind.indexOf("volume:") === 0) {
      var vol = kind.indexOf(":") > 0 ? Math.max(0, Math.min(100, parseInt(kind.split(":")[1], 10) || 0)) / 100 : 0.62
      showHud({ layout: "progress", icon: Model.volumeIcon(vol, false), value: vol, valueText: Math.round(vol * 100) + "%", color: fg, duration: 1600 })
    } else if (kind === "brightness") {
      showHud({ layout: "progress", icon: Model.brightnessIcon(0.8), value: 0.8, valueText: "80%", color: fg, duration: 2500 })
    } else if (kind === "charging") {
      showHud({ layout: "label", label: "Charging", icon: Model.batteryIcon(0.8, true), valueText: "80%", color: greenColor, duration: 3000 })
    } else if (kind === "lowbattery") {
      showHud({ layout: "label", label: "Low Battery", icon: Model.batteryIcon(0.1, false), valueText: "10%", color: urgentColor, duration: 3000 })
    } else if (kind === "track") {
      demo = { media: media }; mediaPosition = 0; showHud({ layout: "track", duration: 3200 })
    } else if (kind === "notification" || kind === "notification-actions") {
      notifications.inject({
        app: "Slack", appIcon: "slack", summary: "Design review",
        body: "Can you share the island screenshots before standup?",
        actions: kind === "notification-actions" ? [{ id: "reply", text: "Reply" }, { id: "read", text: "Mark as Read" }] : []
      })
    } else if (kind === "inbox") {
      var samples = [
        { app: "Slack", appIcon: "slack", summary: "Design review", body: "Can you share the island screenshots?" },
        { app: "Chromium", appIcon: "chromium", summary: "GitHub", body: "Pull request #42 was merged" },
        { app: "omarchy-update", glyph: "󰚰", summary: "Update available", body: "Omarchy 4.0.5 is ready to install" }
      ]
      for (var i = 0; i < samples.length; i++) {
        notifications.inject(samples[i])
        notifications.retire(notifications.current.key)
      }
      openInbox()
    } else if (kind === "timer") {
      clocks.startTimer(272, "Tea")
    } else if (kind === "stopwatch") {
      clocks.resetStopwatch(); clocks.toggleStopwatch()
    } else if (kind === "activity") {
      activitySource.update("demo", { title: "Building nerdibeard.tusche-island", subtitle: "Compiling views · 14 of 22", icon: "󰏗", progress: 0.64, color: "green", ttl: 60 })
    } else if (kind === "calendar") {
      calendarSource.demo()
    } else if (kind === "calendar-view") {
      calendarSource.demo(); openCalendar()
    } else if (kind === "camera") {
      demo = { camera: true }; cameraActive = true
    } else if (kind === "device") {
      showHud({ key: "device", layout: "label", label: "WH-1000XM5", icon: Model.deviceGlyph("audio-headset"), valueText: "82%", color: greenColor, duration: 3000 })
    } else if (kind === "outputs") {
      demo = { media: media }; mediaPosition = 71; openOutputs()
    } else if (kind === "toast") {
      toast({ title: "Build finished", body: "nerdibeard.tusche-island · 0 errors", icon: "󰄬", color: "green" })
    } else {
      return "unknown demo: " + kind
    }
    return "ok"
  }

  function noteDemo(kind) {
    var samples = {
      mail: { app: "OmaMail", glyph: "\u{f01ee}", summary: "Lena Berger", body: "Termin morgen um 10? Ich bringe die Unterlagen mit." },
      chat: { app: "WhatsApp", glyph: "\u{f05a3}", summary: "Familie (3)", body: "Mama: Kommst du am Sonntag zum Essen?" },
      phone: { app: "Flux", glyph: "\u{f011c}", summary: "Pixel 9 Pro", body: "Akku 20 % · bitte laden" },
      low: { app: "Claude Code", glyph: "\u{f06a9}", summary: "Agent fertig", body: "nbtiles · 320 Tests grün", low: true },
      critical: { app: "OpenClaw", glyph: "\u{f0ecc}", summary: "Freigabe nötig", body: "beardibot möchte „git push origin main“ ausführen.",
                  critical: true, actions: [{ id: "review", text: "Open to review" }] },
      actions: { app: "Slack", glyph: "\u{f0369}", summary: "Design review", body: "Can you share the island screenshots?",
                 actions: [{ id: "reply", text: "Reply" }, { id: "read", text: "Mark as Read" }] }
    }
    if (kind === "burst") {
      notifications.inject(samples.chat); notifications.inject(samples.low); notifications.inject(samples.phone)
      return "ok"
    }
    if (kind === "story") {
      notifications.inject(samples.mail); notifications.inject(samples.chat); notifications.inject(samples.phone)
      notifications.inject(samples.critical)
      return "ok"
    }
    if (kind === "many") {
      var list = [samples.mail, samples.chat, samples.phone, samples.actions, samples.mail]
      for (var i = 0; i < list.length; i++) notifications.inject(list[i])
      return "ok"
    }
    if (!samples[kind]) return "kinds: mail chat phone low critical actions burst story many"
    notifications.inject(samples[kind])
    return "ok"
  }

  // Save "reserveSpace" in this plugin's shell.json entry; the settings
  // watcher above applies it.
  function setReserveSpace(next) {
    saveSettings({ reserveSpace: next })
    showHud({
      key: "reserveSpace", layout: "label",
      label: next ? "Space kept for the island" : "Windows fill the top",
      icon: next ? "󰊔" : "󰊓", valueText: "", color: fg, duration: 1600
    })
  }

  IpcHandler {
    target: "tusche-island"

    function expand(): string { root.expand(); return "ok" }
    // on | off | toggle: keep a strip free for the island, or let windows
    // fill the top of the screen under it.
    function reserveSpace(mode: string): string {
      if (["on", "off", "toggle"].indexOf(mode) === -1) return "usage: reserveSpace on|off|toggle"
      var next = mode === "toggle" ? !root.reserveSpace : mode === "on"
      root.setReserveSpace(next)
      return next ? "on" : "off"
    }
    function collapse(): string { root.collapse(); return "ok" }
    function toggle(): string { root.toggleExpanded(); return "ok" }
    function flash(): void { root.flash() }
    // Same notification path as a completion, with no real agent/focus action.
    function agentDoneDemo(): void {
      root.announceAgentDone({ agent: "Codex", title: "Preview · Agent completion popout" })
    }
    // A sample failure through the real path (a notification, no real outage).
    function failureDemo(name: string): void {
      root.announceFailure({ kind: "unit", scope: "user", name: name || "demo.service",
                             command: "echo 'Failure demo: nothing really failed.'" })
    }
    function attentionDemo(on: string): void {
      root.desktop.demoBlocked = on === "on"
        ? [{ pane: "demo:1", agent: "Codex", status: "blocked", title: "git push origin feat/alpha46 freigeben?", project: "nbtiles", workspace: "demo" }]
        : []
      if (on === "on") root.flash()
    }
    function toast(title: string, body: string, icon: string, color: string): string {
      root.toast({ title: title, body: body, icon: icon, color: color })
      return "ok"
    }
    function show(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function demo(kind: string): string { return root.runDemo(kind) }
    // Notification look in the bar: noteStyle window|bubble (the former
    // name "workbench" is stored as "window"), notifications true|false
    // (take over Omarchy's popups).
    function set(key: string, value: string): string {
      var v = String(value || "")
      if (key === "noteStyle" && (v === "window" || v === "bubble" || v === "workbench")) {
        var style = Model.noteStyle(v)
        root.saveSettings({ noteStyle: style })
        return style
      }
      if (key === "notifications" && (v === "true" || v === "false")) { root.saveSettings({ notifications: v === "true" }); return v }
      return "usage: set noteStyle window|bubble · set notifications true|false"
    }
    // Sample notifications through the real queue (no sender behind them).
    function noteDemo(kind: string): string { return root.noteDemo(kind) }
    function markRead(): string { root.markAllRead(); return "ok" }
    // The column's buttons, for keybinds: open | dismiss | later | next |
    // action:<id> on the open card (next pulls the first waiting row up).
    function note(action: string): string {
      var cur = notifications.current
      var a = String(action || "")
      if (a === "next") {
        if (notifications.waiting.length === 0) return "none"
        notifications.promote(notifications.waiting[0].key)
        return "ok"
      }
      if (!cur) return "none"
      if (a === "open") root.notificationOpen(cur.key)
      else if (a === "dismiss") root.notificationDismiss(cur.key)
      else if (a === "later") notifications.later(cur.key)
      else if (a.indexOf("action:") === 0) root.notificationAction(cur.key, a.substring(7))
      else return "usage: note open|dismiss|later|next|action:<id>"
      return "ok"
    }

    // Timer: "25m", "90s", "1h30m", "10:00", or plain minutes.
    function timer(duration: string, label: string): string {
      var seconds = Model.parseDuration(duration)
      if (seconds <= 0) return "bad duration: " + duration
      root.clocks.startTimer(seconds, label)
      return "ok"
    }
    function timerToggle(): string { root.clocks.toggleTimer(); return "ok" }
    function timerCancel(): string { root.clocks.cancelTimer(); return "ok" }
    // Stopwatch: start | pause | toggle | reset
    function stopwatch(action: string): string {
      var a = String(action || "toggle")
      if (a === "reset") root.clocks.resetStopwatch()
      else if (a === "start" && !root.clocks.stopwatchRunning) root.clocks.toggleStopwatch()
      else if (a === "pause" && root.clocks.stopwatchRunning) root.clocks.toggleStopwatch()
      else if (a === "toggle") root.clocks.toggleStopwatch()
      return "ok"
    }
    // Live activity for scripts; payload is JSON (see Activities.qml).
    function activity(id: string, payloadJson: string): string {
      var payload = {}
      try { payload = JSON.parse(payloadJson || "{}") } catch (e) { return "bad json" }
      return activitySource.update(id, payload)
    }
    function endActivity(id: string, message: string): string { return activitySource.end(id, message) }
    function activities(): string { return JSON.stringify(activitySource.list()) }
    function refreshCalendar(): string { calendarSource.refresh(); return "ok" }
    function calendar(): string { root.openCalendar(); return "ok" }
    function addCalendar(link: string): string { root.addCalendar(link); return "ok" }
    function removeCalendar(link: string): string { root.removeCalendar(link); return "ok" }
    function addCalendarFromClipboard(): string { root.addCalendarFromClipboard(); return "ok" }
    function state(): string {
      return JSON.stringify({
        view: root.view,
        barMode: root.barMode,
        geometry: { x: island.x, y: island.y, width: island.width, height: island.height,
          exclusiveZone: win.exclusiveZone, corner: root.corner, topMargin: root.topMargin, gapsOut: Style.gapsOut },
        palette: { background: String(root.surface), foreground: String(root.fg), accent: String(root.accentColor) },
        reducedMotion: Style.reduceMotion,
        primary: root.primary,
        secondary: root.secondary,
        expanded: root.userExpanded,
        hud: root.hud ? root.hud.layout : null,
        media: { has: root.hasMedia, playing: root.mediaPlaying, title: root.mediaTitle },
        recording: root.recordingActivity,
        mic: root.micActivity,
        battery: root.hasBattery ? Math.round(root.batteryLevel * 100) : null,
        brightness: root.brightness,
        timer: root.clocks.timerActive ? Math.ceil(root.clocks.timerLeft / 1000) : null,
        stopwatch: root.clocks.stopwatchActive ? Math.round(root.clocks.stopwatchElapsed / 100) / 10 : null,
        activity: root.activity ? root.activity.id : null,
        nextEvent: root.calendar.next ? root.calendar.next.title : null,
        attention: root.desktop.blocked.map(function(a) { return a.agent + ": " + (a.title || "") }),
        idle: { mode: root.idleMode, quiet: root.idleQuiet, signals: root.idleSignals.map(function(i) { return i.key }) },
        bar: { edge: String(root.barOptions.edge || "none"), material: !!root.material },
        desktop: root.desktop.summary(),
        camera: root.cameraActive,
        outputs: root.audioOutputs.length,
        calendarTyping: root.calendarTyping,
        calendar: {
          sources: root.calendar.sources.length,
          status: root.calendar.sources.map(function(l) { return root.calendar.statusOf(l) || "pending" }),
          upcoming: root.calendar.events.length,
          omamail: root.calendar.omamailSources.length,
          justAdded: root.calendar.justAdded !== ""
        },
        notifications: {
          serving: root.notificationsReady,
          wants: root.wantsNotifications,
          requested: root.takeoverRequested.notifications === true,
          omarchyDisabled: root.omarchyNotificationsOff,
          showing: root.notification ? root.notification.summary : null,
          pending: root.notificationsPending,
          inbox: root.inbox.length,
          dnd: notifications.doNotDisturb,
          column: root.columnNotes,
          style: root.noteStyle,
          current: root.noteCurrent ? root.noteCurrent.summary : null,
          waiting: notifications.waiting.map(function(e) { return e.summary }),
          line: root.noteLine ? root.noteLine.summary : null,
          unread: notifications.unread
        },
        screen: win.screen ? win.screen.name : null
      })
    }
    function ping(): string { return "ok" }
  }

  // ------------------------------------------------------------------
  // Window
  // ------------------------------------------------------------------
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    var wanted = monitorSetting
    if (wanted === "focused" && Hyprland.focusedMonitor) wanted = Hyprland.focusedMonitor.name
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === wanted) return screens[i]
    return screens[0]
  }

  PanelWindow {
    id: win

    screen: root.targetScreen
    visible: !root.barMode
    anchors { top: true; left: true; right: true }
    // Tall enough for the biggest view (a full inbox or output list); only
    // the island itself takes input, the rest of the strip is click-through.
    implicitHeight: root.s(360) + root.topMargin
    color: "transparent"

    WlrLayershell.namespace: "tusche-island"
    WlrLayershell.layer: root.setting("layer", "top") === "overlay" ? WlrLayer.Overlay : WlrLayer.Top
    // Keyboard only while the calendar's link field is up (typing and
    // Ctrl+V go straight in; Esc hands it back). Otherwise the island never
    // takes focus from the app you're in.
    WlrLayershell.keyboardFocus: root.calendarTyping ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Normal with a zero zone respects the existing bar without reserving space.
    // Setting exclusiveZone also forces Normal; do not combine it with Ignore.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: root.reserveSpace ? root.s(32) + root.topMargin : 0

    // Esc always hands the keyboard back, wherever focus is inside.
    Shortcut {
      sequence: "Escape"
      enabled: root.calendarTyping
      onActivated: root.calendarAdding = false
    }

    mask: Region {
      item: island
      Region { item: bubble; intersection: Intersection.Combine }
    }

    Item {
      id: stage
      anchors.fill: parent

      // Short, non-overshooting geometry changes. Honor Omarchy Reduced Motion.
      property real w: root.s(root.viewSize.w)
      property real h: root.s(root.viewSize.h)
      property real r: root.corner
      Behavior on w { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      Behavior on h { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

      Ui.BorderSurface {
        x: island.x; y: island.y
        width: island.width; height: island.height
        radius: root.corner
        visible: island.width > 4
        color: root.surface
        borderSpec: root.frameSpec
      }

      // A plain Rectangle with scissor clipping on purpose: clipping through
      // an offscreen layer blurs everything inside at fractional scaling.
      Rectangle {
        id: island

        // Snapped to device pixels: at fractional scaling an edge between
        // pixels is drawn as a soft, lighter line.
        x: root.snap((stage.width - width) / 2)
        y: root.snap(root.topMargin)
        width: root.snap(Math.max(0, stage.w))
        height: root.snap(Math.max(0, stage.h))
        radius: Math.max(0, Math.min(stage.r, height / 2, width / 2))
        // The shapes above paint the body; this only clips and hosts content.
        color: "transparent"
        clip: true
        opacity: width < 4 ? 0 : 1

        transformOrigin: Item.Top

        Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }

        HoverHandler { id: islandHover }

        Item {
          id: content
          // ViewSlots read this to put themselves on the pixel grid.
          readonly property real dpr: root.dpr
          width: island.width
          height: island.height

          MouseArea {
            id: islandPress
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) { root.islandClicked(mouse.button) }
            onWheel: function(wheel) { root.adjustVolume(wheel.angleDelta.y) }
          }

          // Status light along the lip, kept clear of the rounded corners.
          EdgeLight {
            readonly property real inset: Math.min(island.radius, island.height / 2) * 0.85 + root.s(6)
            x: root.snap(inset)
            width: Math.max(0, island.width - inset * 2)
            height: Math.max(2, root.snap(root.s(2)))
            y: root.snap(island.height - height - root.s(2))
            tone: root.edgeState.tone
            level: root.edgeState.level
            progress: root.edgeState.progress === undefined ? -1 : root.edgeState.progress
            pulse: root.edgeState.pulse === true
            pulsePeriod: root.edgeState.period || 1400
            sweepKey: root.edgeSweep
          }

          // The resting face follows the island's own size (it never waits
          // for the shape to settle, since the shape resizes to fit it).
          ViewSlot {
            active: root.view === "idle" || root.view === "idle-hover"
            width: island.width; height: island.height
            IdleFace { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("media")
            width: root.s(root.slotSize("media").w); height: root.s(root.slotSize("media").h)
            MediaCompact { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("recording")
            width: root.s(root.slotSize("recording").w); height: root.s(root.slotSize("recording").h)
            RecordingCompact { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("mic")
            width: root.s(root.slotSize("mic").w); height: root.s(root.slotSize("mic").h)
            MicCompact { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("hud-progress")
            width: root.s(root.slotSize("hud-progress").w); height: root.s(root.slotSize("hud-progress").h)
            HudProgress { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("hud-label")
            width: root.s(root.slotSize("hud-label").w); height: root.s(root.slotSize("hud-label").h)
            HudLabel { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("hud-track")
            width: root.s(root.slotSize("hud-track").w); height: root.s(root.slotSize("hud-track").h)
            TrackHud { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("hud-toast")
            width: root.s(root.slotSize("hud-toast").w); height: root.s(root.slotSize("hud-toast").h)
            ToastHud { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("media-expanded")
            width: root.s(root.slotSize("media-expanded").w); height: root.s(root.slotSize("media-expanded").h)
            MediaExpanded { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("recording-expanded")
            width: root.s(root.slotSize("recording-expanded").w); height: root.s(root.slotSize("recording-expanded").h)
            RecordingExpanded { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("recording-media-expanded")
            width: root.s(root.slotSize("recording-media-expanded").w); height: root.s(root.slotSize("recording-media-expanded").h)
            RecordingExpanded { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("notification")
            width: root.s(root.slotSize("notification").w); height: root.s(root.slotSize("notification").h)
            NotificationView { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("notification-actions")
            width: root.s(root.slotSize("notification-actions").w); height: root.s(root.slotSize("notification-actions").h)
            NotificationView { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("inbox")
            width: root.s(root.slotSize("inbox").w); height: root.s(root.slotSize("inbox").h)
            InboxCompact { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("inbox-expanded")
            width: root.s(root.slotSize("inbox-expanded").w); height: root.s(root.slotSize("inbox-expanded").h)
            InboxView { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("timer")
            width: root.s(root.slotSize("timer").w); height: root.s(root.slotSize("timer").h)
            ClockCompact { anchors.fill: parent; island: root; mode: "timer" }
          }

          ViewSlot {
            active: root.showing("stopwatch")
            width: root.s(root.slotSize("stopwatch").w); height: root.s(root.slotSize("stopwatch").h)
            ClockCompact { anchors.fill: parent; island: root; mode: "stopwatch" }
          }

          ViewSlot {
            active: root.showing("attention")
            width: root.s(root.slotSize("attention").w); height: root.s(root.slotSize("attention").h)
            Text { renderType: Text.NativeRendering;
              anchors.fill: parent; anchors.margins: root.s(6)
              textFormat: Text.PlainText
              text: root.attentionAgent ? (root.attentionAgent.agent || "Agent") + " is waiting" : ""
              elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
              font.family: root.fontFamily; font.pixelSize: root.f(12); color: root.orangeColor
            }
          }
          ViewSlot {
            active: root.showing("attention-expanded")
            width: root.s(root.slotSize("attention-expanded").w); height: root.s(root.slotSize("attention-expanded").h)
            RequesterView { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("activity")
            width: root.s(root.slotSize("activity").w); height: root.s(root.slotSize("activity").h)
            ActivityCompact { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("calendar")
            width: root.s(root.slotSize("calendar").w); height: root.s(root.slotSize("calendar").h)
            CalendarCompact { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("clock-expanded")
            width: root.s(root.slotSize("clock-expanded").w); height: root.s(root.slotSize("clock-expanded").h)
            ClockExpanded { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("activity-expanded")
            width: root.s(root.slotSize("activity-expanded").w); height: root.s(root.slotSize("activity-expanded").h)
            ActivityExpanded { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("outputs-expanded")
            width: root.s(root.slotSize("outputs-expanded").w); height: root.s(root.slotSize("outputs-expanded").h)
            OutputsView { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("calendar-expanded")
            width: root.s(root.slotSize("calendar-expanded").w); height: root.s(root.slotSize("calendar-expanded").h)
            CalendarView { anchors.fill: parent; island: root }
          }

          ViewSlot {
            active: root.showing("idle-expanded")
            width: root.s(root.slotSize("idle-expanded").w); height: root.s(root.slotSize("idle-expanded").h)
            IdleExpanded { anchors.fill: parent; island: root }
          }
        }
      }

      // A second activity appears as a small, framed status tile.
      Ui.BorderSurface {
        id: bubble

        readonly property real d: root.s(32)
        readonly property real restX: island.x + island.width + root.s(8)

        width: d
        height: d
        radius: root.corner
        y: root.notch ? root.s(4) : root.topMargin
        x: root.showBubble ? restX : island.x + island.width - d
        color: root.surface
        borderSpec: root.frameSpec
        opacity: root.showBubble ? 1 : 0

        visible: opacity > 0.01
        clip: true

        Behavior on x { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }


        BubbleContent {
          anchors.fill: parent
          island: root
          kind: root.secondary
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.secondary === "inbox") { root.openInbox(); return }
            root.openFocus = root.secondary
            root.expand()
          }
        }
      }
    }
  }
}
