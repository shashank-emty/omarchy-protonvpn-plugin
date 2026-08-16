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
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: ivpn.unavailable || !ivpn.loggedIn ? urgent : (ivpn.active ? foreground : dim)
  readonly property color barIconColor: ivpn.unavailable || !ivpn.loggedIn
    ? Qt.darker(barForeground, 1.2)
    : (ivpn.active ? barForeground : Qt.darker(barForeground, 1.55))
  readonly property string toggleHint: ivpn.active ? "Disconnect" : "Connect"
  readonly property string tooltip: {
    if (!ivpn.loggedIn) return "Proton VPN — not logged in"
    var head = ivpn.connected && ivpn.serverCity !== ""
      ? "Proton VPN — " + ivpn.serverCity
      : "Proton VPN — " + ivpn.statusText
    var geo = ivpn.homeGeo
    if (geo && geo.isp) head += "\nfrom " + String(geo.city || "") + " · " + String(geo.isp)
    return head
  }

  property bool firewallConfirmOpen: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: ivpn
    settings: root.settings
  }

  onOpenedChanged: if (opened) {
    ivpn.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  } else {
    root.firewallConfirmOpen = false
  }

  // Enabling the kill switch while the tunnel is down blocks everything, which
  // is easy to trigger by accident and confusing to diagnose. Turning it off
  // never needs a confirmation.
  function requestFirewall() {
    if (ivpn.firewallOn) { ivpn.setFirewall(false); return }
    if (ivpn.connected) { ivpn.setFirewall(true); return }
    root.firewallConfirmOpen = true
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(): void { if (!ivpn.connected) ivpn.toggle() }
    function disconnect(): void { if (ivpn.connected || ivpn.paused) ivpn.toggle() }
    function pause(): void { ivpn.pause(ivpn.pauseMinutes) }
    function resume(): void { ivpn.resume() }
    function refresh(): string { ivpn.refresh(); return "ok" }
    function status(): string { return ivpn.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        ProtonIcon {
          anchors.centerIn: parent
          iconSize: Style.bar.iconCanvas
          locked: ivpn.connected
          color: root.barIconColor
          badgeColor: Color.bar.background
          fontFamily: root.fontFamily
        }
      }
    }
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    // No height cap: fittedContentHeight's second argument is a maximum, and
    // capping it clips the map and everything below. The panel is still bound
    // by the screen through availableCardHeight.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: serverPicker.popupOpen || root.firewallConfirmOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") ivpn.refresh()
        else if (t === "c" || t === "C") ivpn.toggle()
        else if (t === "f" || t === "F") root.requestFirewall()
        else if (t === "a" || t === "A") ivpn.toggleAntitracker()
        else if (t === "p" || t === "P") { if (ivpn.paused) ivpn.resume(); else ivpn.pause(ivpn.pauseMinutes) }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "Proton VPN"
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
            Item {
              ProtonIcon {
                anchors.centerIn: parent
                iconSize: Style.font.display
                locked: ivpn.connected
                color: root.iconColor
                badgeColor: Color.popups.background
                fontFamily: root.fontFamily
              }
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
            ? "Proton VPN is not responding — check: protonvpn status"
            : (!ivpn.loggedIn
              ? "Not logged in — run: protonvpn signin"
              : (ivpn.actionStatus !== "" ? ivpn.actionStatus : ivpn.lastError))
          color: (ivpn.unavailable || !ivpn.loggedIn || (ivpn.lastError !== "" && ivpn.actionStatus === "")) ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        WorldMap {
          id: map
          width: parent.width
          foreground: root.foreground
          accent: root.accent
          home: ivpn.homeCoords
          server: ivpn.serverCoords
          hop: ivpn.exitCoords
          connected: ivpn.connected
        }

        // Map legend: which dot is which, and the addresses behind them.
        Row {
          width: parent.width
          spacing: Style.space(10)

          Column {
            width: (parent.width - Style.space(10)) / 2
            spacing: Style.space(2)
            Text {
              text: "◍ " + (ivpn.homeLabel !== "" ? ivpn.homeLabel : "Home")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
            }
            Text {
              text: ivpn.homeDetail
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Column {
            width: (parent.width - Style.space(10)) / 2
            spacing: Style.space(2)
            Text {
              text: "◉ " + (ivpn.connected && ivpn.serverCity !== "" ? ivpn.serverCity : "No exit")
              color: ivpn.connected ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
            }
            Text {
              text: ivpn.connected ? String(ivpn.status.serverIp || "") : "not connected"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }
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
              { k: "Tunnel IP", v: String(ivpn.status.localIp || "") },
              { k: "DNS", v: String(ivpn.status.dns || "") },
              { k: "Uptime", v: ivpn.durationText }
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

        // Pause / resume. The Proton VPN CLI has no pause command, so this
        // row is omitted rather than offering buttons that cannot work.
        Row {
          visible: false
          width: parent.width
          spacing: Style.space(8)

          Button {
            visible: ivpn.paused
            text: "Resume"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: ivpn.resume()
          }

          Repeater {
            model: ivpn.paused ? [] : ivpn.pauseDurations
            Button {
              required property var modelData
              text: "Pause " + Model.durationLabel(modelData)
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: ivpn.pause(modelData)
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: ivpn.paused
            text: "tunnel suspended"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { foreground: root.foreground }

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

        Column {
          width: parent.width
          spacing: Style.space(8)

          Toggle {
            width: parent.width
            label: "Kill Switch"
            description: "Block all traffic outside the VPN"
            checked: ivpn.firewallOn
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.requestFirewall()
          }

          Toggle {
            width: parent.width
            label: "NetShield"
            description: "Block ads and trackers at Proton VPN's DNS"
            checked: ivpn.antitrackerOn
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: ivpn.toggleAntitracker()
          }
        }
      }

      ConfirmDialog {
        id: firewallConfirm
        anchors.fill: parent
        opened: root.firewallConfirmOpen
        z: 10
        message: "Enable the kill switch while disconnected? This blocks all network traffic until you connect."
        confirmText: "Enable"
        background: Color.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        onConfirmed: {
          root.firewallConfirmOpen = false
          ivpn.setFirewall(true)
        }
        onCanceled: root.firewallConfirmOpen = false
      }
    }
  }
}
