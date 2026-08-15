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

  // IVPN's own app settings. Read-only, and the source of exact server
  // coordinates: the daemon's servers.json has them too but is 0600 root.
  property var appSettings: ({})
  property string zoneTabText: ""
  property string timezone: ""

  // Optimistic toggle state so the switch reacts on click instead of waiting
  // for the next poll. -1 follows the real state; 0/1 while a toggle settles.
  property int _desired: -1

  readonly property string state: String(status.state || "UNKNOWN")
  readonly property bool loggedIn: status.loggedIn !== false
  readonly property bool connected: state === "CONNECTED"
  readonly property bool paused: state === "PAUSED"
  readonly property bool transitioning: state === "CONNECTING"
    || state === "RECONNECTING" || state === "DISCONNECTING"
  readonly property bool unavailable: state === "UNAVAILABLE"
  readonly property bool active: _desired === -1 ? (connected || paused) : (_desired === 1)
  readonly property bool firewallOn: status.firewall === true
  readonly property bool busy: statusProcess.running || serversProcess.running
    || controlProcess.running || firewallProcess.running || antitrackerProcess.running
  readonly property string statusText: Model.statusText(state, loggedIn)
  readonly property string serverLabel: Model.serverLabel(status.server)
  readonly property string serverCity: Model.serverCity(status.server)
  readonly property string serverHost: Model.serverHost(status.server)
  readonly property string protocolLabel: Model.shortProtocol(status.protocol)

  readonly property bool antitrackerOn: {
    var at = appSettings && appSettings.daemonSettings ? appSettings.daemonSettings.AntiTracker : null
    return !!(at && at.Enabled)
  }
  readonly property bool multiHop: !!(appSettings && appSettings.isMultiHop)

  // Where the tunnel comes out. IVPN's settings file carries exact coordinates,
  // but it tracks the app's *selected* server, which can differ from a server
  // connected via the CLI — so only trust it when the city agrees, and fall
  // back to a zone.tab city lookup otherwise.
  readonly property var serverCoords: {
    if (exitGeo && connected && isFinite(exitGeo.lat)) return { lat: exitGeo.lat, lon: exitGeo.lon }
    var entry = appSettings ? appSettings.serverEntry : null
    var city = String(serverCity || "").replace(/\s*\([A-Z]{2}\)\s*$/, "").trim().toLowerCase()
    if (entry && isFinite(entry.latitude) && isFinite(entry.longitude)
        && (city === "" || String(entry.city || "").trim().toLowerCase() === city))
      return { lat: entry.latitude, lon: entry.longitude }
    return Model.cityCoords(zoneTabText, serverCity)
  }

  readonly property var exitCoords: {
    if (!multiHop) return null
    var ex = appSettings ? appSettings.serverExit : null
    if (ex && isFinite(ex.latitude) && isFinite(ex.longitude)) return { lat: ex.latitude, lon: ex.longitude }
    return null
  }

  // No network lookup by design, so "home" is the timezone's reference city.
  // Approximate, and labelled as such in the panel rather than dressed up as
  // a real position.
  // Opt-in public-address lookup. api.ivpn.net/v4/geo-lookup returns an
  // isIvpnServer flag, so the reply says for itself whether it measured your
  // real ISP or the tunnel exit — no guessing from connection state.
  readonly property bool publicIpLookup: setting("publicIpLookup", false) === true
    || String(setting("publicIpLookup", false)) === "true"
  property var homeGeo: null   // cached real address, only ever set when isIvpnServer is false
  property var exitGeo: null   // live reading of the tunnel exit
  property double _lastLookup: 0

  readonly property var homeCoords: (homeGeo && isFinite(homeGeo.lat) && isFinite(homeGeo.lon))
    ? { lat: homeGeo.lat, lon: homeGeo.lon }
    : Model.zoneCoords(zoneTabText, timezone)
  readonly property string homeLabel: (homeGeo && homeGeo.city)
    ? String(homeGeo.city)
    : String(timezone || "").split("/").pop().replace(/_/g, " ")
  readonly property string homeDetail: {
    if (homeGeo) return String(homeGeo.ip || "") + (homeGeo.isp ? " · " + homeGeo.isp : "")
    if (!publicIpLookup) return "from your timezone"
    // Every lookup made while the tunnel is up reports the exit, so a real
    // address can only be learned during a disconnected moment.
    return connected ? "hidden by the tunnel" : "looking up…"
  }

  property double _now: 0
  readonly property double connectedSince: Model.parseConnectedAt(status.connectedAt)
  readonly property string durationText: (connected && connectedSince > 0 && _now > 0)
    ? Model.formatDuration(_now - connectedSince) : ""

  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 60)
  readonly property string protocol: String(setting("protocol", "WireGuard"))
  readonly property int pauseMinutes: intSetting("pauseMinutes", 5, 1, 1440)
  readonly property string statePath: Quickshell.env("HOME") + "/.config/omarchy/ivpn-widget.json"
  readonly property string appSettingsPath: Quickshell.env("HOME") + "/.config/IVPN/ivpn-settings.json"

  property string _statusOutput: ""
  property string _serversOutput: ""
  // A missing `ivpn` binary may never produce an exit callback at all, so the
  // widget would sit on "Checking…" forever without a deadline.
  property bool _everParsed: false

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

  function protocolFlag() {
    return String(protocol).toLowerCase().indexOf("openvpn") >= 0 ? "ovpn" : "wg"
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
    if (!serversLoaded && !serversProcess.running) serversProcess.running = true
    appSettingsFile.reload()
    geoLookup(false)
  }

  // The address changes the moment the tunnel comes up or goes down, so look
  // again immediately rather than waiting out the throttle.
  onConnectedChanged: geoLookup(true)

  function fail(message) {
    root.lastError = Model.elide(message)
    root.actionStatus = root.lastError
    actionStatusTimer.restart()
  }

  function connectCommand() {
    var cmd = ["ivpn", "connect", "-p", protocolFlag()]
    if (selectedServer === Model.FASTEST) cmd.push("-fastest")
    else cmd.push(selectedServer)
    return cmd
  }

  function toggle() {
    if (controlProcess.running) return
    if (!loggedIn) {
      fail("Not logged in. Run: ivpn login ACCOUNT_ID")
      return
    }
    if (connected || paused || transitioning) {
      _desired = 0
      controlProcess.command = ["ivpn", "disconnect"]
    } else {
      _desired = 1
      controlProcess.command = connectCommand()
    }
    controlProcess.running = true
  }

  function pause(minutes) {
    if (controlProcess.running || !connected) return
    var n = parseInt(String(minutes), 10)
    if (!isFinite(n) || n < 1) n = 1
    if (n > 1440) n = 1440
    controlProcess.command = ["ivpn", "connection", "-pause", String(n)]
    controlProcess.running = true
  }

  function resume() {
    if (controlProcess.running || !paused) return
    controlProcess.command = ["ivpn", "connection", "-resume"]
    controlProcess.running = true
  }

  function saveState() {
    stateFile.setText(JSON.stringify({
      selectedServer: root.selectedServer,
      homeGeo: root.homeGeo
    }, null, 2) + "\n")
  }

  // Ask what the internet currently sees. While the tunnel is up this reports
  // the exit, so a real home address can only be captured while disconnected —
  // hence the cache.
  function geoLookup(force) {
    if (!publicIpLookup) return
    var now = Date.now()
    if (!force && now - root._lastLookup < 60000) return
    root._lastLookup = now
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status !== 200) return
      var geo
      try { geo = JSON.parse(xhr.responseText) } catch (e) { return }
      if (!geo || !isFinite(geo.latitude) || !isFinite(geo.longitude)) return
      var record = {
        ip: String(geo.ip_address || ""),
        city: String(geo.city || geo.country || ""),
        country: String(geo.country || ""),
        isp: String(geo.isp || ""),
        lat: Number(geo.latitude),
        lon: Number(geo.longitude)
      }
      if (geo.isIvpnServer === true) {
        root.exitGeo = record
      } else {
        root.homeGeo = record
        root.saveState()
      }
    }
    xhr.open("GET", "https://api.ivpn.net/v4/geo-lookup")
    xhr.send()
  }

  function selectServer(value) {
    if (!value || value === root.selectedServer) return
    root.selectedServer = value
    root.saveState()
    // Switching servers while up should move the tunnel, not just remember the
    // choice for next time. IVPN reconnects in place when already connected.
    if (connected && !controlProcess.running) {
      _desired = 1
      controlProcess.command = connectCommand()
      controlProcess.running = true
    }
  }

  function setFirewall(on) {
    if (firewallProcess.running) return
    firewallProcess.command = ["ivpn", "firewall", on ? "-on" : "-off"]
    firewallProcess.running = true
  }

  function toggleAntitracker() {
    if (antitrackerProcess.running) return
    antitrackerProcess.command = ["ivpn", "antitracker", antitrackerOn ? "-off" : "-on"]
    antitrackerProcess.running = true
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
        if (saved && saved.homeGeo && isFinite(saved.homeGeo.lat)) root.homeGeo = saved.homeGeo
      } catch (e) {
        // A corrupt or absent file just means "no saved choice yet".
      }
    }
  }

  FileView {
    // IVPN's desktop app settings, read only. Absent if the app has never run,
    // in which case coordinates fall back to zone.tab.
    id: appSettingsFile
    path: root.appSettingsPath
    watchChanges: true
    onFileChanged: appSettingsFile.reload()
    onLoaded: {
      try {
        root.appSettings = JSON.parse(appSettingsFile.text()) || ({})
      } catch (e) {
        root.appSettings = ({})
      }
    }
  }

  FileView {
    id: zoneTabFile
    path: "/usr/share/zoneinfo/zone.tab"
    onLoaded: root.zoneTabText = zoneTabFile.text()
  }

  Process {
    id: timezoneProcess
    running: true
    command: ["timedatectl", "show", "-p", "Timezone", "--value"]
    stdout: StdioCollector {
      id: timezoneStdout
      waitForEnd: true
      onStreamFinished: root.timezone = String(text || "").trim()
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
    // Drives the "up 2h 14m" readout without re-polling the CLI every second.
    id: clockTimer
    interval: 1000
    repeat: true
    running: root.connected
    triggeredOnStart: true
    onTriggered: root._now = Date.now()
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
    // If nothing has parsed by the time this fires, IVPN is not answering:
    // no binary on PATH, or the daemon is down.
    id: watchdogTimer
    interval: 12000
    repeat: false
    running: true
    onTriggered: if (!root._everParsed) root.status = { state: "UNAVAILABLE", loggedIn: true, firewall: false }
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
        root._everParsed = true
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

  Process {
    id: antitrackerProcess
    running: false
    command: []
    stdout: StdioCollector { id: antitrackerStdout; waitForEnd: true }
    stderr: StdioCollector { id: antitrackerStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.fail(String(antitrackerStderr.text || "").trim() || String(antitrackerStdout.text || "").trim() || "Could not change AntiTracker")
      appSettingsFile.reload()
      settleTimer.ticks = 0
      settleTimer.restart()
    }
  }
}
