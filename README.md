# IVPN — Omarchy bar widget

A bar-widget plugin for [Omarchy](https://omarchy.org/) that connects and
disconnects [IVPN](https://www.ivpn.net/) from the top bar, with a searchable
server picker, live connection details, and a firewall (kill switch) toggle.

![IVPN widget panel](preview.png)

## Requirements

- Omarchy with the Quickshell plugin system (`omarchy plugin` / `omarchy bar`).
- The IVPN client installed, providing `ivpn` on `PATH`, with `ivpn-service`
  running:

  ```bash
  systemctl status ivpn-service
  ```

- A logged-in account. The widget cannot create one; log in once with:

  ```bash
  ivpn login ACCOUNT_ID
  ```

  Until then the widget shows "Not logged in" and the switch is inert.

The plugin only shells out to `ivpn` (`status`, `servers`, `connect`,
`disconnect`, `firewall`). It never handles your Account ID, and the only file
it writes is its own `~/.config/omarchy/ivpn-widget.json`, which remembers the
selected server.

## Install

```bash
omarchy plugin enable artemisa81.ivpn
```

If the bar does not pick it up, restart the shell:

```bash
omarchy restart shell
```

## Use

- **Left click** — open the panel.
- **Middle click** — connect/disconnect without opening the panel.
- **Right click** — force a refresh.

In the panel: `c` toggles the connection, `f` toggles the firewall, `r`
refreshes, `Esc` closes.

The panel shows the current server, its IP, your tunnel IP and the DNS in use
while connected. Picking a different server while already connected moves the
tunnel straight to it; picking one while disconnected just remembers it for the
next connect. "Fastest server" maps to `ivpn connect -fastest`.

The **Firewall** toggle is IVPN's kill switch (`ivpn firewall -on|-off`): it
blocks all traffic outside the tunnel. Turning it on while disconnected will cut
your connectivity until you connect — that is what it is for.

## Settings

Configured per widget in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `refreshIntervalSec` | `5` | How often `ivpn status` is polled (2–60). |
| `protocol` | `WireGuard` | Which protocol's servers to list. One of `WireGuard`, `OpenVPN`. |

IVPN publishes a separate hostname per protocol (`sg.wg.ivpn.net` versus
`sg.gw.ivpn.net`), so the list is filtered to one of them rather than showing
each city twice. If the setting ever matches nothing, the widget falls back to
listing every server instead of showing an empty picker.

## IPC

```bash
omarchy-shell artemisa81.ivpn status       # -> Connected / Disconnected / Not logged in
omarchy-shell artemisa81.ivpn toggle       # open or close the panel
omarchy-shell artemisa81.ivpn connect
omarchy-shell artemisa81.ivpn disconnect
omarchy-shell artemisa81.ivpn refresh
```

## Remove

```bash
omarchy plugin disable artemisa81.ivpn
rm -rf ~/.config/omarchy/plugins/artemisa81.ivpn ~/.config/omarchy/ivpn-widget.json
```
