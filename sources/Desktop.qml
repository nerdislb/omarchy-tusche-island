import QtQuick
import Quickshell
import Quickshell.Io
import "../IslandModel.js" as Model

// Read-only links into the rest of this desktop, so the island shows what
// other tools already know instead of keeping its own copy:
//
//   Flux (fluxd socket)       agent sessions working or idle (herdr and
//                             OpenClaw), the paired phone's battery
//   Omarchy agent usage       subscription limits close to running out
//   Hermes turn markers      live Desktop/TUI turns (read-only, one home)
//
// No chat bodies or credentials leave Hermes. Flux only receives "subscribe".
Item {
  id: desk

  property var island: null

  function on(key) { return island ? island.setting(key, true) !== false : true }
  readonly property bool fluxEnabled: on("flux")
  readonly property bool agentsEnabled: on("agents")
  readonly property bool hermesEnabled: agentsEnabled && on("hermes")
  readonly property bool agentDoneEnabled: agentsEnabled && on("agentDone")
  readonly property bool phoneEnabled: fluxEnabled && on("phone")
  readonly property bool limitsEnabled: on("aiLimits")

  // ------------------------------------------------------------------
  // Flux: newline-delimited JSON over its user socket; state is pushed.
  // ------------------------------------------------------------------
  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/flux/fluxd.sock"
  property var fluxState: ({})
  property Socket sock: null
  readonly property bool connected: !!sock && sock.connected
  property int retryDelay: 3000

  function connectNow() {
    if (!fluxEnabled || (sock && sock.connected)) return
    if (sock) sock.destroy()
    sock = socketComponent.createObject(desk)
    sock.connected = true
  }

  function handle(line) {
    if (!line) return
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg && msg.event === "state") fluxState = msg.data || {}
  }

  Component {
    id: socketComponent
    Socket {
      id: socket
      path: desk.socketPath
      parser: SplitParser { onRead: data => desk.handle(data) }
      onConnectedChanged: {
        if (socket !== desk.sock) return
        if (connected) {
          desk.retryDelay = 3000
          socket.write(JSON.stringify({ id: 1, method: "subscribe", params: {} }) + "\n")
          socket.flush()
        } else {
          desk.fluxState = ({})
        }
      }
    }
  }

  Component.onCompleted: connectNow()
  onFluxEnabledChanged: if (fluxEnabled) connectNow(); else if (sock) { sock.connected = false; fluxState = ({}) }

  Timer {
    interval: desk.retryDelay
    repeat: true
    running: desk.fluxEnabled && !desk.connected
    onTriggered: {
      desk.retryDelay = Math.min(desk.retryDelay * 2, 60000)
      desk.connectNow()
    }
  }

  // Hermes collector is a child of this source, not an independent service.
  // It reads the existing turn marker and title metadata; no REST token needed.
  readonly property string hermesHome: String(island ? island.setting("hermesHome", "") : "")
    || Quickshell.env("HERMES_HOME") || (Quickshell.env("HOME") + "/.hermes")
  property var hermesState: ({})
  property double hermesReceived: 0
  function handleHermes(line) {
    var next
    try { next = JSON.parse(line) } catch (e) { next = {} }
    hermesReceived = Date.now()
    if (JSON.stringify(next) !== JSON.stringify(hermesState)) hermesState = next
  }
  Process {
    id: hermesProcess
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("../bin/hermes-status.py").toString().replace(/^file:\/\//, "")),
              "--home", desk.hermesHome, "--watch"]
    running: desk.hermesEnabled
    stdout: SplitParser { onRead: data => desk.handleHermes(data) }
    onRunningChanged: if (!running) { desk.hermesState = ({}); desk.hermesReceived = 0 }
  }
  onHermesEnabledChanged: hermesProcess.running = hermesEnabled
  onHermesHomeChanged: { hermesProcess.running = false; hermesState = ({}) }
  Timer {
    interval: 2000
    repeat: true
    running: desk.hermesEnabled
    onTriggered: {
      if (!hermesProcess.running) hermesProcess.running = true
      else if (desk.hermesReceived && Date.now() - desk.hermesReceived > 8000) hermesProcess.running = false
    }
  }

  // ---- agents
  readonly property var agents: Model.desktopAgents(fluxState, hermesState, agentsEnabled, fluxEnabled, hermesEnabled)
  readonly property var working: agents.filter(function(a) { return a && a.status === "working" })
  // Agents waiting for input or approval (herdr "blocked"), minus the ones
  // snoozed from the requester ("Later", 10 minutes).
  property var snoozed: ({})     // pane -> until (ms)
  // IPC demo ("attentionDemo on"): a fake waiting agent for testing the UI.
  property var demoBlocked: []
  property double clock: Date.now()
  Timer { interval: 30000; running: Object.keys(desk.snoozed).length > 0; repeat: true; onTriggered: desk.clock = Date.now() }
  readonly property var blocked: {
    clock
    return demoBlocked.concat(agents.filter(function(a) { return a && a.status === "blocked" && !(desk.snoozed[a.pane] > Date.now()) }))
  }
  function snooze(pane) {
    var s = {}
    for (var k in snoozed) if (snoozed[k] > Date.now()) s[k] = snoozed[k]
    s[String(pane)] = Date.now() + 10 * 60000
    snoozed = s
  }
  // User-initiated focus: Hermes raises its existing window; other sources
  // retain their own destinations. No untrusted strings are shell-evaluated.
  function focusAgent(a) {
    if (!a || !island) return
    var command = Model.agentFocusCommand(a)
    if (command.length) Quickshell.execDetached(command)
  }

  // pane -> { status, since, title, agent }
  property var seen: ({})
  property bool primed: false

  onAgentsChanged: {
    var now = Date.now()
    var next = {}
    for (var i = 0; i < agents.length; i++) {
      var a = agents[i]
      if (!a || !a.pane) continue
      var before = seen[a.pane]
      var since = before && before.status === a.status ? before.since : now
      next[a.pane] = { status: a.status, since: since, title: a.title || "", agent: a.agent || "" }
      if (primed && a.status === "blocked" && (!before || before.status !== "blocked") && island) island.flash()
      // A run that finished after a real stretch of work (not a flicker).
      if (primed && agentDoneEnabled && before && before.status === "working" && a.status === "idle"
          && now - before.since >= 20000 && island)
        island.announceAgentDone(a)
    }
    seen = next
    if (fluxState.herdr || hermesState.available) primed = true
    syncActivity()
  }

  // Working agents appear as a regular live activity ("agents").
  property string shownKey: ""
  function syncActivity() {
    if (!island) return
    // From `agents` directly: this runs inside its change handler, before
    // bindings derived from it are guaranteed to be up to date.
    var list = agents.filter(function(a) { return a && a.status === "working" })
    if (list.length === 0) {
      if (shownKey !== "") { island.activityStore.end("agents", ""); shownKey = "" }
      return
    }
    var first = list[0]
    var payload = list.length === 1
      ? { title: first.title || first.agent || "Agent", subtitle: (first.agent || "Agent") + " · working",
          icon: "󰚩", color: "accent", value: "" }
      : { title: list.length + " agents working", icon: "󰚩", color: "accent", value: "",
          subtitle: list.map(function(a) { return a.title || a.agent }).join(" · ") }
    var key = JSON.stringify(payload)
    if (key === shownKey && island.activityStore.items["agents"]) return
    shownKey = key
    island.activityStore.update("agents", payload)
  }

  // ---- phone
  readonly property var phone: {
    if (!phoneEnabled) return null
    var list = Array.isArray(fluxState.devices) ? fluxState.devices : []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].paired && list[i].online && list[i].battery)
        return { name: String(list[i].name || "Phone"), charge: Number(list[i].battery.charge),
                 charging: list[i].battery.charging === true }
    return null
  }
  readonly property bool phoneLow: phone !== null && !phone.charging && phone.charge <= 20
  // Warned once per discharge: a reconnect at the same charge stays quiet;
  // charging or a real recovery re-arms it.
  property bool phoneWarned: false
  onPhoneChanged: if (phone && (phone.charging || phone.charge > 25)) phoneWarned = false
  onPhoneLowChanged: {
    if (!phoneLow || phoneWarned || !island) return
    phoneWarned = true
    island.showHud({ key: "phone", layout: "label", label: phone.name + " battery low", icon: "󰁺",
                     valueText: Math.round(phone.charge) + "%", color: island.urgentColor, duration: 3500 })
  }

  // ------------------------------------------------------------------
  // AI subscription limits (the files Omarchy's agents widget reads)
  // ------------------------------------------------------------------
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/agents/usage"
  readonly property var providers: {
    var v = island ? island.setting("aiProviders", ["claude", "codex", "antigravity"]) : []
    return Array.isArray(v) ? v.map(function(x) { return String(x) }) : []
  }
  property var usage: ({})   // provider -> [limits]

  Instantiator {
    model: desk.limitsEnabled ? desk.providers : []
    delegate: FileView {
      required property string modelData
      path: desk.usageDir + "/" + modelData + ".json"
      printErrors: false
      watchChanges: true
      onFileChanged: reload()
      onLoaded: desk.setUsage(modelData, Model.usageLimits(text(), modelData))
      onLoadFailed: desk.setUsage(modelData, [])
    }
  }

  // key -> last seen percent, to announce only real crossings.
  property var levels: ({})

  function setUsage(provider, limits) {
    var u = {}
    for (var k in usage) u[k] = usage[k]
    u[provider] = limits
    usage = u
    var lv = {}
    for (var j in levels) lv[j] = levels[j]
    for (var i = 0; i < limits.length; i++) {
      var l = limits[i]
      var before = lv[l.key]
      lv[l.key] = l.percent
      if (before === undefined || !island) continue
      var name = Model.providerName(l.provider) + " · " + Model.shortLimit(l.label)
      if (before < 0.999 && l.percent >= 0.999)
        island.showHud({ key: "limit", layout: "label", label: name + " limit reached", icon: "󰚩",
                         valueText: "100%", color: island.urgentColor, duration: 4000 })
      else if (before < 0.9 && l.percent >= 0.9)
        island.showHud({ key: "limit", layout: "label", label: name, icon: "󰚩",
                         valueText: Math.round(l.percent * 100) + "%", color: island.orangeColor, duration: 3500 })
      else if (before >= 0.9 && l.percent < 0.5)
        island.showHud({ key: "limit", layout: "label", label: name + " reset", icon: "󰚩",
                         valueText: Math.round(l.percent * 100) + "%", color: island.greenColor, duration: 3000 })
    }
    levels = lv
  }

  // The tightest limit across providers (null when nothing is tracked).
  // Limits reset by the clock too, not only when a record changes.
  property double now: Date.now()
  Timer { interval: 30000; running: desk.limitsEnabled; repeat: true; onTriggered: desk.now = Date.now() }
  readonly property var topLimit: {
    if (!limitsEnabled) return null
    var best = null
    for (var n = 0; n < providers.length; n++) {
      var list = usage[providers[n]] || []
      for (var i = 0; i < list.length; i++) {
        var l = Object.assign({}, list[i], { percent: Model.limitPercent(list[i], now) })
        if (!best || l.percent > best.percent) best = l
      }
    }
    return best
  }

  function summary() {
    return {
      flux: connected,
      hermes: hermesEnabled && hermesState.available === true,
      hermesAgents: hermesEnabled && Array.isArray(hermesState.agents) ? hermesState.agents.length : 0,
      agents: agents.length,
      working: working.map(function(a) { return a.agent + ": " + (a.title || "") }),
      phone: phone,
      topLimit: topLimit ? { provider: topLimit.provider, label: topLimit.label, percent: topLimit.percent } : null
    }
  }
}
