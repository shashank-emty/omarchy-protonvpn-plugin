// Parsing helpers for the IVPN CLI. `ivpn` prints human-readable text rather
// than machine output, so everything here is defensive: an unrecognised line
// is skipped instead of poisoning the parsed state.

var FASTEST = "__fastest__"

// `ivpn status` prints "Label  : value" rows. Labels never contain a colon,
// so the first colon separates them; values can (Server IP has UDP:2049).
function parseStatus(raw) {
  var out = {
    state: "UNKNOWN",
    loggedIn: true,
    server: "",
    protocol: "",
    localIp: "",
    serverIp: "",
    connectedAt: "",
    dns: "",
    splitTunnel: "",
    firewall: false,
    allowLan: false
  }

  var lines = String(raw || "").split("\n")
  var sawVpnLine = false

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.trim() === "") continue
    // The tips block at the end is help text, not state.
    if (line.indexOf("Tips:") === 0) break

    var idx = line.indexOf(":")
    if (idx < 0) {
      // The only key-less row is the server description printed directly
      // under "VPN : CONNECTED".
      if (sawVpnLine && out.server === "") out.server = line.trim()
      continue
    }

    var key = line.substring(0, idx).trim()
    var value = line.substring(idx + 1).trim()

    switch (key) {
      case "VPN":
        out.state = value.toUpperCase()
        sawVpnLine = true
        break
      case "Account":
        if (value.toLowerCase().indexOf("not logged in") >= 0) out.loggedIn = false
        break
      case "Protocol":     out.protocol = value; break
      case "Local IP":     out.localIp = value; break
      case "Server IP":    out.serverIp = value; break
      case "Connected":    out.connectedAt = value; break
      case "DNS":          out.dns = value; break
      case "Split Tunnel": out.splitTunnel = value; break
      case "Firewall":     out.firewall = value.toLowerCase().indexOf("enabled") === 0; break
      case "Allow LAN":    out.allowLan = value.toLowerCase() === "true"; break
      default: break
    }
  }

  return out
}

// The status line reads
//   "sg.gw.ivpn.net [sg1.gw.ivpn.net], Singapore (SG), Singapore"
// which splits into hostname, city, country.

// Full human half, for tooltips that have room for it.
function serverLabel(server) {
  var raw = String(server || "").trim()
  if (raw === "") return ""
  var parts = raw.split(",")
  if (parts.length < 2) return raw
  return parts.slice(1).join(",").trim()
}

// Just the city, which already carries the country code: "Singapore (SG)".
// The hero puts title and detail on one row, so anything longer elides the
// title away.
function serverCity(server) {
  var raw = String(server || "").trim()
  if (raw === "") return ""
  var parts = raw.split(",")
  return parts.length < 2 ? raw : parts[1].trim()
}

// "sg.gw.ivpn.net [sg1.gw.ivpn.net]" -> "sg.gw.ivpn.net"
function serverHost(server) {
  var raw = String(server || "").trim()
  if (raw === "") return ""
  var head = raw.split(",")[0].trim()
  var bracket = head.indexOf(" [")
  return bracket > 0 ? head.substring(0, bracket).trim() : head
}

function shortProtocol(protocol) {
  var p = String(protocol || "").toLowerCase()
  if (p.indexOf("wireguard") >= 0) return "WG"
  if (p.indexOf("openvpn") >= 0) return "OpenVPN"
  return String(protocol || "")
}

// `ivpn servers` prints a pipe-separated table:
//   PROTOCOL| LOCATION| CITY| COUNTRY| ISP| IPv? tunnel|
function parseServers(raw, preferredProtocol) {
  var lines = String(raw || "").split("\n")
  var out = []
  var seen = {}
  var wanted = String(preferredProtocol || "").toLowerCase()

  for (var i = 0; i < lines.length; i++) {
    var cells = lines[i].split("|")
    if (cells.length < 5) continue

    var protocol = cells[0].trim()
    var host = cells[1].trim()
    var city = cells[2].trim()
    var country = cells[3].trim()
    var isp = cells[4].trim()

    if (protocol === "" || protocol === "PROTOCOL") continue   // header
    if (host === "" || host === "LOCATION") continue
    if (seen[host]) continue
    // Only filter when the wanted protocol actually matches something, so a
    // stale setting can never empty the whole list.
    if (wanted !== "" && protocol.toLowerCase() !== wanted) continue

    seen[host] = true
    out.push({
      value: host,
      label: city !== "" ? city : host,
      description: country + (isp !== "" && isp !== "<multiple ISPs>" ? " · " + isp : ""),
      country: country
    })
  }

  out.sort(function(a, b) {
    if (a.country !== b.country) return a.country < b.country ? -1 : 1
    return a.label < b.label ? -1 : (a.label > b.label ? 1 : 0)
  })

  out.unshift({ value: FASTEST, label: "Fastest server", description: "Lowest latency available" })
  return out
}

function statusText(state, loggedIn) {
  if (!loggedIn) return "Not logged in"
  switch (String(state || "").toUpperCase()) {
    case "CONNECTED":     return "Connected"
    case "CONNECTING":    return "Connecting…"
    case "RECONNECTING":  return "Reconnecting…"
    case "DISCONNECTING": return "Disconnecting…"
    case "DISCONNECTED":  return "Disconnected"
    case "UNAVAILABLE":   return "Daemon unavailable"
    default:              return "Checking…"
  }
}

function elide(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > 140 ? value.substring(0, 137) + "…" : value
}
