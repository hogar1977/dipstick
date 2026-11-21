import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Column {
  id: root

  property var host: null
  property string view: "categories"
  property string status: "all"
  property string query: ""
  property int cursor: 0

  readonly property var service: host.service
  readonly property var live: host.live
  readonly property var cfg: host.cfg
  readonly property var ctx: host.ctx
  readonly property var scan: live.scan || ({})
  readonly property var summary: scan.summary || ({})
  readonly property var categories: scan.categories || []
  readonly property var files: Model.filterScan(scan.items, query, status).slice(0, 120)
  readonly property var rows: view === "categories" ? categories : files
  readonly property var tmp: Model.tmpPool(live.tmpfs)
  readonly property var others: (live.tmpfs || []).filter(function(item) { return item.mount !== "/tmp" })
  readonly property var ghosts: (scan.ghosts || []).slice(0, 10)
  readonly property var result: service ? service.cleanResult : null
  readonly property bool editing: search.activeFocus
  readonly property bool busy: !!service && service.tmpBusy

  function count(name) {
    return summary[name] ? summary[name].count : 0
  }

  function amount(name) {
    return summary[name] ? summary[name].bytes : 0
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    cursor = Math.max(0, Math.min(rows.length - 1, cursor + delta))
    var row = rowList.itemAt(cursor)
    if (row) host.reveal(row)
  }

  function cleanStale() {
    if (busy || count("stale") === 0) return
    host.confirm(ctx.t("temp.confirmAll").arg(host.itemCount(count("stale"))).arg(host.bytes(amount("stale"))), function() {
      service.cleanTmp(["--all-stale"])
    })
  }

  function cleanRow(index) {
    var row = rows[index]
    if (!row || busy) return
    if (view === "categories") {
      if (row.staleCount === 0) return
      host.confirm(ctx.t("temp.confirmCategory").arg(row.label).arg(host.itemCount(row.staleCount)).arg(host.bytes(row.staleBytes)), function() {
        service.cleanTmp(["--category", row.id])
      })
    } else if (row.canDelete) {
      host.confirm(ctx.t(row.status === "recent" ? "temp.confirmRecent" : "temp.confirmItem").arg(host.bytes(row.size)).arg(row.name), function() {
        service.cleanTmp(["--ids", row.id])
      })
    }
  }

  function activateCursor() {
    cleanRow(cursor)
  }

  function eraseCursor() {
    cleanRow(cursor)
  }

  function handleKey(text) {
    if (text === "P") cleanStale()
    else if (text === "G" || text === "g") service.scanTmp()
    else if (text === "/" && view === "files") search.forceActiveFocus()
    else if (text === "v") view = view === "categories" ? "files" : "categories"
  }

  onViewChanged: cursor = 0
  onStatusChanged: cursor = 0
  onQueryChanged: cursor = 0

  spacing: Style.space(10)

  MetricRow {
    readonly property var usedLevel: root.tmp ? Model.percent(root.tmp.used, root.tmp.total) : null
    icon: Model.glyph("tmp")
    title: "/tmp"
    value: root.tmp ? root.host.bytes(root.tmp.used) + " / " + root.host.bytes(root.tmp.total) : "–"
    level: usedLevel || 0
    over: Model.isOver(usedLevel, root.cfg.limits.tmp)
    alertColor: root.host.alertColor
    note: root.ctx.t("temp.summary")
      .arg(root.host.bytes(root.amount("stale")))
      .arg(root.host.itemCount(root.count("stale")))
      .arg(root.ctx.number(root.count("active"), 0))
      .arg(root.ctx.number(root.count("protected"), 0))
  }

  Row {
    spacing: Style.space(6)

    Button {
      text: root.ctx.t("temp.cleanStale")
      bordered: true
      enabled: !root.busy && root.count("stale") > 0
      onClicked: root.cleanStale()
    }

    Button {
      text: root.busy ? root.ctx.t("temp.working") : root.ctx.t("temp.rescan")
      bordered: true
      enabled: !root.busy
      onClicked: root.service.scanTmp()
    }
  }

  TextLabel {
    visible: !!root.result
    width: parent.width
    font.pixelSize: Style.font.caption
    text: root.result ? root.ctx.t("temp.result")
      .arg(root.host.bytes(root.result.freed))
      .arg(root.host.itemCount(root.result.removedCount))
      .arg(root.ctx.number(root.result.failed.length, 0)) : ""
  }

  ButtonGroup {
    options: [
      { value: "categories", label: root.ctx.t("temp.categories") },
      { value: "files", label: root.ctx.t("temp.files") }
    ]
    value: root.view
    focusable: false
    onChanged: function(value) { root.view = value }
  }

  ButtonGroup {
    visible: root.view === "files"
    fontSize: Style.font.caption
    options: [
      { value: "all", label: root.ctx.t("status.all") },
      { value: "stale", label: root.ctx.t("status.stale") },
      { value: "recent", label: root.ctx.t("status.recent") },
      { value: "active", label: root.ctx.t("status.active") },
      { value: "protected", label: root.ctx.t("status.protected") }
    ]
    value: root.status
    focusable: false
    onChanged: function(value) { root.status = value }
  }

  Rectangle {
    visible: root.view === "files"
    width: parent.width
    height: Style.spacing.controlHeight
    color: "transparent"
    border.width: 1
    border.color: Util.alpha(Color.foreground, search.activeFocus ? 0.8 : 0.25)
    radius: Style.cornerRadius

    TextInput {
      id: search
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      verticalAlignment: TextInput.AlignVCenter
      color: Color.foreground
      selectionColor: Util.alpha(Color.foreground, 0.3)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      maximumLength: 64
      clip: true
      onTextEdited: root.query = text
      Keys.onEscapePressed: root.host.focusKeys()
      Keys.onReturnPressed: root.host.focusKeys()
    }

    TextLabel {
      visible: search.text === ""
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.ctx.t("temp.search")
      muted: true
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(2)

    Repeater {
      id: rowList
      model: root.rows

      Rectangle {
        id: rowItem
        required property var modelData
        required property int index
        readonly property bool category: root.view === "categories"
        width: parent.width
        height: rowColumn.implicitHeight + Style.space(8)
        radius: Style.cornerRadius
        color: index === root.cursor ? Util.alpha(Color.foreground, 0.1) : "transparent"

        Column {
          id: rowColumn
          anchors.left: parent.left
          anchors.right: action.left
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter

          TextLabel {
            width: parent.width
            text: rowItem.category ? rowItem.modelData.label : rowItem.modelData.name
          }

          TextLabel {
            width: parent.width
            muted: true
            font.pixelSize: Style.font.caption
            text: {
              var row = rowItem.modelData
              if (rowItem.category) return root.ctx.t("temp.categoryNote").arg(root.host.itemCount(row.count)).arg(root.host.bytes(row.bytes)).arg(root.host.bytes(row.staleBytes))
              var holders = row.holders.map(function(holder) { return holder.process + " " + holder.pid }).join(", ")
              var parts = [root.ctx.t("status." + row.status), root.host.bytes(row.size), Model.formatAge(row.age, root.ctx)]
              if (holders) parts.push(holders)
              return parts.join("  ·  ")
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.cursor = rowItem.index
        }

        PanelActionButton {
          id: action
          anchors.right: parent.right
          anchors.rightMargin: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          visible: rowItem.category ? rowItem.modelData.staleCount > 0 : rowItem.modelData.canDelete
          iconText: Model.glyph("clean")
          tooltipText: root.ctx.t("temp.clean")
          onClicked: root.cleanRow(rowItem.index)
        }
      }
    }
  }

  TextLabel {
    visible: root.view === "files" && !!root.scan.truncated
    width: parent.width
    muted: true
    font.pixelSize: Style.font.caption
    text: root.ctx.t("temp.truncated")
  }

  PanelSeparator { width: parent.width }

  PanelSectionHeader { text: root.ctx.t("temp.otherMemory") }

  Repeater {
    model: root.others

    MetricRow {
      required property var modelData
      title: modelData.mount
      value: root.host.bytes(modelData.used) + " / " + root.host.bytes(modelData.total)
      level: Model.percent(modelData.used, modelData.total) || 0
    }
  }

  PanelSectionHeader {
    visible: root.ghosts.length > 0
    text: root.ctx.t("temp.ghosts")
  }

  Repeater {
    model: root.ghosts

    MetricRow {
      required property var modelData
      title: modelData.path
      value: root.host.bytes(modelData.size)
      note: modelData.process + " " + modelData.pid
    }
  }
}
