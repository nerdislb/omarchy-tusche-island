import QtQuick
import QtQml
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../IslandModel.js" as Model

// Live activities as files: a program drops a small JSON file into
// $XDG_STATE_HOME/live-activities/<id>.json while something runs (the Tesla
// bar's charging session) and removes it when it ends. The dynamic island
// shows each as a minimal capsule beside it and counts down or up by itself
// (IslandModel.liveEntry/liveText/liveTone), so nothing is rewritten every
// minute. The folder and the files are watched, never polled; the clock only
// ticks while something is live. Unlike script activities over IPC, several
// show at once and they survive a reload of the island.
Item {
  id: live

  property var island: null
  readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/live-activities"

  property var raw: ({})          // id -> the file's JSON, as written
  property double now: Date.now()
  readonly property var items: {
    var out = []
    for (var id in raw) {
      var e = Model.liveEntry(id, raw[id], now / 1000)
      if (e) out.push(e)
    }
    out.sort(function(a, b) { return (a.startedAt - b.startedAt) || (a.id < b.id ? -1 : 1) })
    return out
  }
  readonly property var byId: {
    var m = {}
    for (var i = 0; i < items.length; i++) m[items[i].id] = items[i]
    return m
  }
  readonly property var ids: items.map(function(e) { return e.id })

  Timer {
    interval: 20000
    repeat: true
    triggeredOnStart: true
    running: Object.keys(live.raw).length > 0
    onTriggered: live.now = Date.now()
  }

  function set(id, text) {
    var v = null
    try { v = JSON.parse(text) } catch (e) { v = null }
    var r = {}
    for (var k in raw) if (k !== id) r[k] = raw[k]
    if (v) r[id] = v
    raw = r
  }
  function drop(id) {
    if (!(id in raw)) return
    var r = {}
    for (var k in raw) if (k !== id) r[k] = raw[k]
    raw = r
  }

  // The folder must exist before it is watched (a folder created later would
  // go unnoticed); whoever writes first may create it.
  property bool dirReady: false
  Process {
    id: makeDir
    command: ["mkdir", "-p", "-m", "700", live.dir]
    onExited: live.dirReady = true
  }
  Component.onCompleted: makeDir.running = true

  FolderListModel {
    id: folder
    folder: live.dirReady ? "file://" + live.dir : ""
    nameFilters: ["*.json"]
    showDirs: false
    showHidden: false
  }
  Instantiator {
    model: folder
    delegate: FileView {
      required property string fileName
      required property string filePath
      readonly property string key: fileName.replace(/\.json$/, "")
      path: filePath
      printErrors: false
      watchChanges: true
      onFileChanged: reload()
      onLoaded: live.set(key, text())
      onLoadFailed: live.drop(key)
      Component.onDestruction: live.drop(key)
    }
  }
}
