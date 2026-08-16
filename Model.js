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
    allowLan: false,
    load: 0
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
      case "Status":
        out.state = value.toUpperCase()
        sawVpnLine = true
        break
      case "Server":
        out.server = value
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
      case "Load":         out.load = parseInt(value, 10) || 0; break
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

// Parse `protonvpn countries list` output
function parseCountries(raw, preferredProtocol) {
  var lines = String(raw || "").split("\n")
  var out = []

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue

    // Skip header/separator lines
    if (line.indexOf("Country") === 0 || line.indexOf("---") === 0) continue

    // Format: "CountryName               Code" (code is 2 chars at end)
    // Split on 2+ spaces to separate name from code
    var parts = line.split(/\s{2,}/)
    if (parts.length < 2) continue

    var countryName = parts[0]
    var countryCode = parts[parts.length - 1]

    // Must be a valid 2-letter country code
    if (countryCode.length !== 2) continue

    out.push({
      value: countryCode,
      label: countryName,
      description: countryCode,
      country: countryCode
    })
  }

  // Sort alphabetically by country name
  out.sort(function(a, b) {
    if (a.label < b.label) return -1
    if (a.label > b.label) return 1
    return 0
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
    case "PAUSED":        return "Paused"
    case "DISCONNECTED":  return "Disconnected"
    case "UNAVAILABLE":   return "Daemon unavailable"
    default:              return "Checking…"
  }
}

function elide(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > 140 ? value.substring(0, 137) + "…" : value
}

// Parse `protonvpn config list` output. Rows are space-separated
// columns: "Setting                  Value".
function parseConfig(raw) {
  var out = {
    killSwitch: false,
    netshield: false
  }

  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    // Skip header/separator lines.
    if (line.indexOf("Setting") === 0 || line.indexOf("---") === 0) continue

    var parts = line.split(/\s{2,}/)
    if (parts.length < 2) continue
    var key = parts[0]
    var value = parts.slice(1).join(" ").trim()
    var lower = value.toLowerCase()

    if (key === "kill-switch") {
      out.killSwitch = lower === "standard" || lower === "on"
    } else if (key === "netshield") {
      // "Upgrade to enable" and "off" both mean it is not on.
      out.netshield = lower !== "off" && lower !== "malware-only" && lower !== "upgrade to enable"
    }
  }

  return out
}

// ---------------------------------------------------------------------------
// Map
//
// Land raster generated once from Natural Earth 1:110m land polygons, which
// are public domain. Latitude is cropped to +83..-56 so Antarctica and empty
// Arctic ocean do not waste half the panel. Markers are drawn at their true
// fractional position, not snapped to this grid, so the coarse raster only
// affects the backdrop.
var MAP_W = 96
var MAP_H = 37
var LAT_TOP = 83.0
var LAT_BOT = -56.0

var LAND = [
  "000000000000000000000000111111011111111111110000000000000000000000000000010000000000000000000000",
  "000000000000000010000000011000111111111111100000000010000000000000000000000100000000000000000000",
  "000000000000000110000111001000000111111111000000000000000000000000000111111111110000010000000000",
  "000001111100010001111010001111000111111111000000000001110000000000101111111111111111111111100100",
  "111001111111111111111111100011100011110000010000000111111001111111111111111111111111111111111111",
  "000011111111111111111110000100000001100000000000011110111111111111111111111111111111111111111110",
  "000000100001111111111110000111100000000000000000000100111111111111111111111111111111110000100000",
  "000010000000011111111111110111111000000000000001001001111111111111111111111111111111000001100000",
  "000000000000001111111111111111110000000000000001011111111111111111111111111111111111100000000000",
  "000000000000000111111111111111100000000000000001111111111111111111111111111111111111100000000000",
  "000000000000000111111111111110000000000000000010110111110001111111111111111111111111001000000000",
  "000000000000000111111111111100000000000000000011001001011111111111111111111111111100010000000000",
  "000000000000000011111111111100000000000000000010111000000011111111111111111111110010110000000000",
  "000000000000000001111111111000000000000000000011111101000111111111111111111111110000000000000000",
  "000000000000000000111100001000000000000000000111111111111111101111111111111111110000000000000000",
  "000000000000000000011100000000000000000000001111111111111011110000111111111111111000000000000000",
  "000000000000000000001100100100000000000000011111111111111111111100011110011111000000000000000000",
  "000000000000000000000111000000000000000000001111111111111101111000001100011110001000000000000000",
  "000000000000000000000000110000000000000000001111111111111110100000001000001110000000000000000000",
  "000000000000000000000000010011110000000000001111111111111111110000001000000000000000000000000000",
  "000000000000000000000000000111111000000000000111011111111111100000000000000000000100000000000000",
  "000000000000000000000000000111111110000000000000000111111111000000000000001100100000000000000000",
  "000000000000000000000000001111111111000000000000001111111110000000000000000101101001000000000000",
  "000000000000000000000000001111111111111000000000000111111100000000000000000000000000011010000000",
  "000000000000000000000000000111111111111000000000000111111110000000000000000000000100000100000000",
  "000000000000000000000000000011111111110000000000000111111110000000000000000000000001000000000000",
  "000000000000000000000000000001111111110000000000000111111110100000000000000000000111101000000000",
  "000000000000000000000000000001111111100000000000000111111000100000000000000000001111111100000000",
  "000000000000000000000000000001111111000000000000000011111000100000000000000000111111111100000000",
  "000000000000000000000000000001111110000000000000000011111000000000000000000000111111111110000000",
  "000000000000000000000000000001111100000000000000000001110000000000000000000000011111111110000000",
  "000000000000000000000000000001111000000000000000000000000000000000000000000000000000011100000000",
  "000000000000000000000000000011100000000000000000000000000000000000000000000000000000000000000010",
  "000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000000",
  "000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000000000",
  "000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000000000",
  "000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000"
]

// Equirectangular projection to normalised 0..1 panel coordinates.
function project(lat, lon) {
  var la = Number(lat), lo = Number(lon)
  if (!isFinite(la) || !isFinite(lo)) return null
  if (la > LAT_TOP) la = LAT_TOP
  if (la < LAT_BOT) la = LAT_BOT
  return {
    x: (lo + 180) / 360,
    y: (LAT_TOP - la) / (LAT_TOP - LAT_BOT)
  }
}

// zone.tab stores ISO 6709: +DDMM+DDDMM or +DDMMSS+DDDMMSS.
function parseIso6709(text) {
  var m = /^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/.exec(String(text || "").trim())
  if (!m) return null
  var lat = Number(m[2]) + Number(m[3]) / 60 + (m[4] ? Number(m[4]) / 3600 : 0)
  var lon = Number(m[6]) + Number(m[7]) / 60 + (m[8] ? Number(m[8]) / 3600 : 0)
  if (m[1] === "-") lat = -lat
  if (m[5] === "-") lon = -lon
  return { lat: lat, lon: lon }
}

// Find a timezone's reference coordinates in /usr/share/zoneinfo/zone.tab.
// zone.tab rather than zone1970.tab: the newer file drops linked zones, which
// collapses most of the cities we care about onto a single country point.
function zoneCoords(zoneTabText, timezone) {
  var want = String(timezone || "").trim()
  if (want === "") return null
  var lines = String(zoneTabText || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].charAt(0) === "#") continue
    var f = lines[i].split("\t")
    if (f.length < 3) continue
    if (f[2].trim() === want) return parseIso6709(f[1])
  }
  return null
}

// "2026-08-15 21:13:30 +0700 +07" -> epoch milliseconds.
function parseConnectedAt(text) {
  var m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\s*([+-])(\d{2})(\d{2})/.exec(String(text || "").trim())
  if (!m) return 0
  var utc = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6])
  var offset = (+m[8] * 60 + +m[9]) * 60000
  return m[7] === "-" ? utc + offset : utc - offset
}

function formatDuration(ms) {
  if (!isFinite(ms) || ms <= 0) return ""
  var total = Math.floor(ms / 1000)
  var d = Math.floor(total / 86400)
  var h = Math.floor((total % 86400) / 3600)
  var mi = Math.floor((total % 3600) / 60)
  var s = total % 60
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + mi + "m"
  if (mi > 0) return mi + "m " + s + "s"
  return s + "s"
}

// Fallback when IVPN's own settings file has no usable coordinates: match the
// city IVPN reports ("Ashburn, VA" -> "ashburn") against a zone.tab city.
function cityCoords(zoneTabText, city) {
  var want = String(city || "").replace(/\s*\([A-Z]{2}\)\s*$/, "").replace(/,.*$/, "").trim().toLowerCase()
  if (want === "") return null
  var lines = String(zoneTabText || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].charAt(0) === "#") continue
    var f = lines[i].split("\t")
    if (f.length < 3) continue
    var zoneCity = f[2].trim().split("/").pop().replace(/_/g, " ").toLowerCase()
    if (zoneCity === want) return parseIso6709(f[1])
  }
  return null
}

// "5, 15, 30" -> [5, 15, 30]. IVPN accepts 1..1440 minutes; anything outside
// that, duplicated, or unparseable is dropped rather than sent to the CLI.
function parseDurations(text) {
  var parts = String(text || "").split(",")
  var out = []
  var seen = {}
  for (var i = 0; i < parts.length; i++) {
    var n = parseInt(parts[i].trim(), 10)
    if (!isFinite(n) || n < 1 || n > 1440 || seen[n]) continue
    seen[n] = true
    out.push(n)
    if (out.length >= 4) break   // the row has to stay inside the panel
  }
  return out.length > 0 ? out : [5]
}

// 90 -> "1h 30m", 60 -> "1h", 5 -> "5m"
function durationLabel(minutes) {
  var n = Number(minutes)
  if (!isFinite(n) || n < 1) return ""
  if (n < 60) return n + "m"
  var h = Math.floor(n / 60), m = n % 60
  return m === 0 ? h + "h" : h + "h " + m + "m"
}

// "2d ago" / "3h ago" / "just now". A cached home reading is only as good as
// its age, so the panel shows it rather than implying the position is live.
function relativeAge(ms) {
  var age = Number(ms)
  if (!isFinite(age) || age < 0) return ""
  var mins = Math.floor(age / 60000)
  if (mins < 2) return "just now"
  if (mins < 60) return mins + "m ago"
  var hours = Math.floor(mins / 60)
  if (hours < 24) return hours + "h ago"
  return Math.floor(hours / 24) + "d ago"
}
