import QtQuick
import "../IslandModel.js" as Model

// The notes in the bar as rows, top to bottom: the open card, two waiting
// rows, "+N" for the rest – and the rows still on their way out, which stay
// until whoever draws them calls finishLeave(). Shared by the classic column
// (NotificationColumn.qml) and the dynamic island (DynamicIsland.qml); only
// one of them draws the rows at a time.
QtObject {
  id: queue

  property var service: null
  property bool serving: false

  // { key, kind ("note" | "more"), leaving }
  readonly property ListModel model: ListModel {}
  // rows were placed (the column latches its monitor and anchor then)
  signal synced()

  // What belongs on screen, top to bottom: the open card, two waiting rows,
  // "+N" for the rest.
  readonly property var wanted: {
    if (!serving || !service || !service.current) return []
    var out = [{ key: service.current.key, kind: "note" }]
    var w = service.waiting
    for (var i = 0; i < w.length && i < Model.maxWaitingRows; i++) out.push({ key: w[i].key, kind: "note" })
    if (w.length > Model.maxWaitingRows) out.push({ key: -1, kind: "more" })
    return out
  }
  readonly property int hiddenCount: service ? Math.max(0, service.waiting.length - Model.maxWaitingRows) : 0

  // Entries by key, kept while their row is still rolling away.
  property var cache: ({})
  function entryOf(key) {
    if (service) {
      var b = service.banners
      for (var i = 0; i < b.length; i++) if (b[i].key === key) return b[i]
    }
    return cache[key] || null
  }

  onWantedChanged: Qt.callLater(sync)

  function indexOfKey(key) {
    for (var i = 0; i < model.count; i++) if (model.get(i).key === key) return i
    return -1
  }
  // Where the n-th wanted row goes: before the n-th row that is not leaving.
  function slotIndex(n) {
    var seen = 0
    for (var i = 0; i < model.count; i++) {
      if (model.get(i).leaving) continue
      if (seen === n) return i
      seen++
    }
    return model.count
  }

  function sync() {
    var want = wanted
    var keys = want.map(function(w) { return w.key })
    var nextCache = {}
    for (var c = 0; c < want.length; c++) {
      var e = entryOf(want[c].key)
      if (e) nextCache[want[c].key] = e
    }
    for (var i = 0; i < model.count; i++) {
      var r = model.get(i)
      if (keys.indexOf(r.key) === -1) {
        if (cache[r.key]) nextCache[r.key] = cache[r.key]
        if (!r.leaving) model.setProperty(i, "leaving", true)
      }
    }
    cache = nextCache
    for (var j = 0; j < want.length; j++) {
      var at = indexOfKey(want[j].key)
      var target = slotIndex(j)
      if (at === -1) {
        model.insert(Math.min(target, model.count), { key: want[j].key, kind: want[j].kind, leaving: false })
        continue
      }
      if (model.get(at).leaving) model.setProperty(at, "leaving", false)
      if (at !== target && target < model.count) model.move(at, target, 1)
    }
    if (model.count > 0) synced()
  }

  // A row has rolled away completely.
  function finishLeave(key) {
    var i = indexOfKey(key)
    if (i !== -1 && model.get(i).leaving) model.remove(i)
  }

  // Rows nobody will animate away any more (the look switched while they
  // left): gone at once.
  function dropLeaving() {
    for (var i = model.count - 1; i >= 0; i--) if (model.get(i).leaving) model.remove(i)
  }
}
