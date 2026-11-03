pragma Singleton
import QtQuick

// Shared between this plugin's panel (the island's state and sources) and its
// bar widget (what the bar shows). Both live in the same shell engine; the
// panel registers itself here and the widget reads it.
QtObject {
  // The running island (Island.qml root), or null while it is (re)loading.
  property var island: null
  // How many bar widgets are mounted. With one or more the island draws
  // nothing of its own and the bar widget shows it instead.
  property int widgets: 0
  // Mounted widgets (one per bar/monitor), and the one that opened the popup.
  property var list: []
  property var owner: null

  function register(w) {
    if (list.indexOf(w) === -1) list = list.concat([w])
    widgets = list.length
  }
  function unregister(w) {
    list = list.filter(function(x) { return x !== w })
    widgets = list.length
    if (owner === w) owner = null
  }
  // The bell as its own bar module (modules/Bell.qml): while one is mounted
  // the island's widgets leave their bell out, so the island alone sits in
  // the bar's middle.
  property var bellList: []
  property int bells: 0
  function registerBell(b) {
    if (bellList.indexOf(b) === -1) bellList = bellList.concat([b])
    bells = bellList.length
  }
  function unregisterBell(b) {
    bellList = bellList.filter(function(x) { return x !== b })
    bells = bellList.length
  }
  // The island widget on a given monitor (the bell opens the inbox there).
  function widgetOn(screenName) {
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].screenName === screenName) return list[i]
    return list.length > 0 ? list[0] : null
  }
  // Without an owner: the widget on the focused monitor, else the first.
  function pick(onFocused, w) {
    if (onFocused) return true
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].onFocusedScreen) return false
    return list.length > 0 && list[0] === w
  }
}
