import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  // Parsed `ivpn status`.
  property var status: ({ state: "UNKNOWN", loggedIn: true, firewall: false })
  property var servers: []
  property bool serversLoaded: false
  property string selectedServer: Model.FASTEST

  // Optimistic toggle state so the switch reacts on click instead of waiting
  // for the next poll. -1 follows the real state; 0/1 while a toggle settles.
  property int _desired: -1

  readonly property string state: String(status.state || "UNKNOWN")
  readonly property bool loggedIn: status.loggedIn !== false
  readonly property bool connected: state === "CONNECTED"
  readonly property bool transitioning: state === "CONNECTING"
    || state === "RECONNECTING" || state === "DISCONNECTING"
  readonly property bool unavailable: state === "UNAVAILABLE"
  readonly property bool active: _desired === -1 ? connected : (_desired === 1)
  readonly property bool firewallOn: status.firewall === true
  readonly property bool busy: statusProcess.running || serversProcess.running
    || controlProcess.running || firewallProcess.running
  readonly property string statusText: Model.statusText(state, loggedIn)
  readonly property string serverLabel: Model.serverLabel(status.server)
  readonly property string serverCity: Model.serverCity(status.server)
  readonly property string serverHost: Model.serverHost(status.server)
  readonly property string protocolLabel: Model.shortProtocol(status.protocol)

  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 60)
  readonly property string protocol: String(setting("protocol", "WireGuard"))
  readonly property string statePath: Quickshell.env("HOME") + "/.config/omarchy/ivpn-widget.json"

  property string _statusOutput: ""
  property string _serversOutput: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
    if (!serversLoaded && !serversProcess.running) serversProcess.running = true
  }

  function fail(message) {
    root.lastError = Model.elide(message)
    root.actionStatus = root.lastError
    actionStatusTimer.restart()
  }

  function toggle() {
    if (controlProcess.running) return
    if (!loggedIn) {
      fail("Not logged in. Run: ivpn login ACCOUNT_ID")
      return
    }
    if (connected || transitioning) {
      _desired = 0
      controlProcess.command = ["ivpn", "disconnect"]
    } else {
      _desired = 1
      controlProcess.command = selectedServer === Model.FASTEST
        ? ["ivpn", "connect", "-fastest"]
        : ["ivpn", "connect", selectedServer]
    }
    controlProcess.running = true
  }

  function selectServer(value) {
    if (!value || value === root.selectedServer) return
    root.selectedServer = value
    stateFile.setText(JSON.stringify({ selectedServer: value }, null, 2) + "\n")
    // Switching servers while up should move the tunnel, not just remember the
    // choice for next time. IVPN reconnects in place when already connected.
    if (connected && !controlProcess.running) {
      _desired = 1
      controlProcess.command = value === Model.FASTEST
        ? ["ivpn", "connect", "-fastest"]
        : ["ivpn", "connect", value]
      controlProcess.running = true
    }
  }

  function toggleFirewall() {
    if (firewallProcess.running) return
    firewallProcess.command = ["ivpn", "firewall", firewallOn ? "-off" : "-on"]
    firewallProcess.running = true
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    onFileChanged: stateFile.reload()
    onLoaded: {
      try {
        var saved = JSON.parse(stateFile.text())
        if (saved && saved.selectedServer) root.selectedServer = String(saved.selectedServer)
      } catch (e) {
        // A corrupt or absent file just means "no saved choice yet".
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // connect/disconnect take several seconds to settle; poll faster for a
    // while so the icon catches up without waiting for the periodic refresh.
    id: settleTimer
    property int ticks: 0
    interval: 1000
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 8) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 3000
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: ["ivpn", "status"]
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    onExited: function(exitCode) {
      var text = String(statusStdout.text || root._statusOutput || "")
      // `ivpn status` exits non-zero when logged out but still prints usable
      // state, so parse the output rather than trusting the exit code alone.
      if (text.trim() !== "") {
        root.status = Model.parseStatus(text)
        if (root._desired !== -1 && root.connected === (root._desired === 1)) root._desired = -1
      } else if (exitCode !== 0) {
        root.status = { state: "UNAVAILABLE", loggedIn: true, firewall: false }
      }
    }
  }

  Process {
    id: serversProcess
    running: false
    command: ["ivpn", "servers"]
    stdout: StdioCollector { id: serversStdout; waitForEnd: true; onStreamFinished: root._serversOutput = text }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var parsed = Model.parseServers(serversStdout.text || root._serversOutput || "", root.protocol)
      // Only the synthetic "Fastest" row means the filter matched nothing.
      if (parsed.length <= 1) parsed = Model.parseServers(serversStdout.text || root._serversOutput || "", "")
      root.servers = parsed
      root.serversLoaded = parsed.length > 1
    }
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector { id: controlStdout; waitForEnd: true }
    stderr: StdioCollector { id: controlStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.fail(String(controlStderr.text || "").trim() || String(controlStdout.text || "").trim() || "IVPN command failed")
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      settleTimer.ticks = 0
      settleTimer.restart()
    }
  }

  Process {
    id: firewallProcess
    running: false
    command: []
    stdout: StdioCollector { id: firewallStdout; waitForEnd: true }
    stderr: StdioCollector { id: firewallStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.fail(String(firewallStderr.text || "").trim() || String(firewallStdout.text || "").trim() || "Could not change the IVPN firewall")
      settleTimer.ticks = 0
      settleTimer.restart()
    }
  }
}
