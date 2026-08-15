import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "artemisa81.ivpn"
  ipcTarget: "artemisa81.ivpn"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: ivpn.unavailable || !ivpn.loggedIn ? urgent : (ivpn.active ? foreground : dim)
  readonly property color barIconColor: ivpn.unavailable || !ivpn.loggedIn
    ? Qt.darker(barForeground, 1.2)
    : (ivpn.active ? barForeground : Qt.darker(barForeground, 1.55))
  readonly property string toggleHint: ivpn.active ? "Disconnect" : "Connect"
  readonly property string tooltip: {
    if (!ivpn.loggedIn) return "IVPN — not logged in"
    if (ivpn.connected && ivpn.serverLabel !== "") return "IVPN — " + ivpn.serverLabel
    return "IVPN — " + ivpn.statusText
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: ivpn
    settings: root.settings
  }

  onOpenedChanged: if (opened) {
    ivpn.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(): void { if (!ivpn.connected) ivpn.toggle() }
    function disconnect(): void { if (ivpn.connected) ivpn.toggle() }
    function refresh(): string { ivpn.refresh(); return "ok" }
    function status(): string { return ivpn.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ivpn.active ? "󰦝" : "󰦞"
    foreground: root.barIconColor
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) ivpn.refresh()
      else if (buttonCode === Qt.MiddleButton) ivpn.toggle()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(340))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: serverPicker.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") ivpn.refresh()
        else if (t === "c" || t === "C") ivpn.toggle()
        else if (t === "f" || t === "F") ivpn.toggleFirewall()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "IVPN"
          // The hero lays title and detail out on one row and lets the detail
          // pill take what it needs, so only something short belongs there.
          meta: ivpn.connected && ivpn.serverCity !== ""
            ? ivpn.statusText + " · " + ivpn.serverCity
            : ivpn.statusText
          detail: ivpn.connected ? ivpn.protocolLabel : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: ivpn.unavailable ? 0.5 : (ivpn.active ? 1.0 : 0.6)
          iconComponent: Component {
            Text {
              text: "󰦝"
              color: root.iconColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              checked: ivpn.active
              busy: ivpn.busy || ivpn.unavailable
              interactive: !ivpn.unavailable && ivpn.loggedIn
              foreground: hero.foreground
              onToggled: ivpn.toggle()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: hero.fontFamily
              }
            }
          }
        }

        Text {
          visible: ivpn.actionStatus !== "" || ivpn.lastError !== "" || !ivpn.loggedIn || ivpn.unavailable
          width: parent.width
          text: ivpn.unavailable
            ? "IVPN is not responding — check: systemctl status ivpn-service"
            : (!ivpn.loggedIn
              ? "Not logged in — run: ivpn login ACCOUNT_ID"
              : (ivpn.actionStatus !== "" ? ivpn.actionStatus : ivpn.lastError))
          color: (ivpn.unavailable || !ivpn.loggedIn || (ivpn.lastError !== "" && ivpn.actionStatus === "")) ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        // Connection facts, only while there is a tunnel to describe.
        Column {
          visible: ivpn.connected
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: [
              { k: "Server", v: ivpn.serverHost },
              { k: "Server IP", v: String(ivpn.status.serverIp || "") },
              { k: "Local IP", v: String(ivpn.status.localIp || "") },
              { k: "DNS", v: String(ivpn.status.dns || "") }
            ]
            Item {
              required property var modelData
              visible: String(modelData.v || "") !== ""
              width: column.width
              height: visible ? detailRow.implicitHeight : 0

              Row {
                id: detailRow
                width: parent.width
                Text {
                  width: parent.width * 0.4
                  text: modelData.k
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width * 0.6
                  text: modelData.v
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        PanelSeparator {
          visible: ivpn.connected
          foreground: root.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "SERVER"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          SearchableDropdown {
            id: serverPicker
            width: parent.width
            showLabel: false
            placeholderText: "Search servers..."
            fontFamily: root.fontFamily
            options: ivpn.servers
            value: ivpn.selectedServer
            onChanged: function(v) { ivpn.selectServer(v) }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Toggle {
          width: parent.width
          label: "Firewall"
          description: "Block all traffic outside the VPN"
          checked: ivpn.firewallOn
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: ivpn.toggleFirewall()
        }
      }
    }
  }
}
