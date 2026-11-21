import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Hub.js" as Hub
import "ui"

Panel {
  id: root

  ipcTarget: "io.github.hogar1977.dipstick"

  property var service: null
  property string page: "overview"
  property var pendingAction: null
  property string pendingMessage: ""
  property var barKeys: []
  property var overviewKeys: []

  readonly property var pages: ["overview", "system", "storage", "temp", "network", "settings"]
  readonly property var cfg: Model.config(settings)
  readonly property var live: service ? service.live : ({})
  readonly property color alertColor: service ? service.alertColor : Color.urgent
  readonly property var ctx: ({
    t: function(key) { return strings.t(key) },
    number: function(value, decimals) { return Commons.I18n.formatNumber(value, decimals) }
  })
  readonly property var items: Model.buildItems(live, cfg, ctx)
  readonly property var itemMap: Model.itemMap(items)

  implicitWidth: strip.implicitWidth
  implicitHeight: strip.implicitHeight

  function bytes(value) {
    return Model.formatBytes(value, cfg.units, ctx)
  }

  function itemCount(count) {
    return strings.tn("count.items", count).arg(Commons.I18n.formatNumber(count, 0))
  }

  function syncKeys() {
    var shown = Model.keysOf(Model.barItems(items, cfg))
    if (shown.length === 0) shown = [items[0].key]
    if (!Model.sameList(shown, barKeys)) barKeys = shown
    var ordered = Model.keysOf(Model.overviewItems(items))
    if (!Model.sameList(ordered, overviewKeys)) overviewKeys = ordered
  }

  function receive(next) {
    if (service === next) return
    if (service) service.detach()
    service = next
    if (service) {
      service.attach()
      service.setRefresh(cfg.refreshSec)
    }
  }

  function save(patch) {
    if (!bar || !bar.shell) return
    var next = {}
    for (var key in settings) next[key] = settings[key]
    for (var name in patch) next[name] = patch[name]
    bar.shell.updateEntryInline(moduleName, next)
  }

  function runRightClickCommand() {
    if (bar && cfg.rightClickCommand !== "") bar.run(cfg.rightClickCommand)
    close()
  }

  function handlePress(key, button) {
    if (button === Qt.RightButton) {
      if (key === "cpu") runRightClickCommand()
      return
    }
    if (button !== Qt.LeftButton) return
    var entry = itemMap[key]
    if (entry) page = entry.page
    if (!opened) open()
  }

  function confirm(message, action) {
    pendingMessage = message
    pendingAction = action
    panel.loadedContent.dialog.selectedIndex = 0
    panel.loadedContent.dialogFocus.forceActiveFocus()
  }

  function settleDialog(accepted) {
    var action = pendingAction
    pendingAction = null
    focusKeys()
    if (accepted && action) action()
  }

  function focusKeys() {
    if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
  }

  function reveal(row) {
    var flick = panel.loadedContent.scroll.contentItem
    var position = row.mapToItem(flick.contentItem, 0, 0).y
    if (position < flick.contentY) flick.contentY = position
    else if (position + row.height > flick.contentY + flick.height)
      flick.contentY = position + row.height - flick.height
  }

  function stepPage(direction) {
    var index = pages.indexOf(page)
    page = pages[(index + direction + pages.length) % pages.length]
  }

  function pageCall(method, argument) {
    var current = panel.loadedContent ? panel.loadedContent.pageItem : null
    if (!current || typeof current[method] !== "function") return false
    current[method](argument)
    return true
  }

  function moveVertical(delta) {
    if (pageCall("moveCursor", delta)) return
    var flick = panel.loadedContent.scroll.contentItem
    var limit = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(limit, flick.contentY + delta * Style.space(48)))
  }

  onItemsChanged: syncKeys()
  onCfgChanged: if (service) service.setRefresh(cfg.refreshSec)
  onOpenedChanged: if (opened && service) service.scanTmp()
  Component.onCompleted: {
    syncKeys()
    Hub.subscribe(receive)
  }
  Component.onDestruction: {
    Hub.unsubscribe(receive)
    if (service) service.detach()
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  Grid {
    id: strip
    columns: root.bar && root.bar.vertical ? 1 : Math.max(1, root.barKeys.length)

    Repeater {
      model: root.barKeys

      BarItem {
        required property string modelData
        bar: root.bar
        item: root.itemMap[modelData] || null
        ringSize: root.cfg.ringSize
        alertColor: root.alertColor
        onPressed: function(button) { root.handlePress(modelData, button) }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: strip
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      id: keys
      property alias scroll: scrollView
      property alias pageItem: pageLoader.item
      property alias dialog: confirmDialog
      property alias dialogFocus: dialogHost
      anchors.fill: parent
      implicitHeight: header.implicitHeight + Style.space(8) + pageLoader.implicitHeight
        + (pageAction.visible ? pageAction.implicitHeight + Style.space(8) : 0)
      blocked: root.pendingAction !== null || (!!pageLoader.item && pageLoader.item.editing === true)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.stepPage(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.stepPage(dx)
        else root.moveVertical(dy)
      }
      onActivateRequested: root.pageCall("activateCursor")
      onDeleteRequested: root.pageCall("eraseCursor")
      onTextKey: function(text) { root.pageCall("handleKey", text) }

      Column {
        id: header
        width: parent.width
        spacing: Style.space(8)

        ButtonGroup {
          anchors.horizontalCenter: parent.horizontalCenter
          fontSize: Style.font.bodySmall
          focusable: false
          value: root.page
          options: root.pages.map(function(name) {
            return { value: name, label: strings.t("page." + name) }
          })
          onChanged: function(value) { root.page = value }
        }

        PanelSeparator { width: parent.width }
      }

      ScrollView {
        id: scrollView
        anchors.top: header.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: pageAction.visible ? pageAction.top : parent.bottom
        anchors.bottomMargin: pageAction.visible ? Style.space(8) : 0
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Loader {
          id: pageLoader
          width: scrollView.availableWidth

          function show() {
            var name = root.page.charAt(0).toUpperCase() + root.page.slice(1)
            setSource(Qt.resolvedUrl("ui/" + name + "Page.qml"), { host: root })
          }

          Component.onCompleted: show()

          Connections {
            target: root
            function onPageChanged() { pageLoader.show() }
          }
        }
      }

      Button {
        id: pageAction
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !!pageLoader.item && pageLoader.item.actionLabel !== undefined
        text: visible ? pageLoader.item.actionLabel : ""
        enabled: visible && pageLoader.item.actionEnabled
        opacity: enabled ? 1 : 0.5
        bordered: true
        onClicked: pageLoader.item.runAction()
      }

      Item {
        id: dialogHost
        anchors.fill: parent
        visible: root.pendingAction !== null
        z: 10
        Keys.onPressed: function(event) { event.accepted = confirmDialog.handleKey(event) }

        ConfirmDialog {
          id: confirmDialog
          anchors.fill: parent
          opened: root.pendingAction !== null
          message: root.pendingMessage
          confirmText: strings.t("common.confirm")
          cancelText: strings.t("common.cancel")
          onCanceled: root.settleDialog(false)
          onConfirmed: root.settleDialog(true)
        }
      }
    }
  }
}
