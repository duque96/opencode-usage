# OpenCode Usage

A tiny macOS **menu bar app** that shows your [OpenCode Go](https://opencode.ai/v2/docs/console/go/) usage at a glance.

> **Unofficial project.** Not affiliated with or endorsed by OpenCode.

```
OpenCode Go: 5h 3% · Semanal 5% · Mensual 2%
```

The three windows reported by the API are:

| Label in the app | API window | Meaning |
|---|---|---|
| `5h` | `rolling` | 5-hour rolling window |
| `Semanal` | `weekly` | Weekly window |
| `Mensual` | `monthly` | Monthly plan window |

Each percentage is colored independently: **green** (< 70 %), **orange** (≥ 70 %), **red** (≥ 90 %).

Click the menu bar item to see the reset time for each window.

## Features

- Three usage windows in the menu bar: 5-hour rolling, weekly and monthly.
- Per-window color thresholds.
- Reset dates in the dropdown.
- Refreshes every 5 minutes and whenever the menu opens.
- Configurable language (System / Español / English) and refresh interval.
- API key stored in the macOS Keychain.
- Optional launch at login.
- Native AppKit, no third-party dependencies, ~500 lines of Swift.

## Requirements

- macOS 13 Ventura or later.
- Xcode Command Line Tools:
  ```sh
  xcode-select --install
  ```
- An OpenCode account with a **Go** or **Go Plus** subscription.

## 1. Create an API key

1. Sign in to the [OpenCode Console](https://opencode.ai/console).
2. Open **Account → Personal API keys**.
3. Click **Add API key**.
4. Recommended permissions: **Restricted → Usage: Read**.
   A normal personal key also works, but a restricted key is safer.
5. Copy the key. It starts with `oc_sk_` and is shown only once.

> The key is personal. Do not share it or commit it to a repository.

## 2. Configure the API key

### Option A — in the app (recommended)

1. Click the menu bar item.
2. Choose **Settings…** (⌘,).
3. Paste the API key.
4. Optionally choose the **language** and **refresh interval**.
5. Click **Test** to verify the connection, then **Save**.

The key is stored in the **macOS Keychain**, not in a plain file.

If the app starts without a key, it opens Settings automatically.

### Option B — key file (automation / headless)

The app also reads `~/.config/opencode-usage/key` when the Keychain has no key.
This is useful for scripts or machines where you do not want to use the UI.

```sh
mkdir -p ~/.config/opencode-usage
printf '%s' 'oc_sk_...' > ~/.config/opencode-usage/key
chmod 600 ~/.config/opencode-usage/key
```

If both exist, the Keychain key wins.

## 3. Language and refresh interval

Open **Settings…** (⌘,) to change:

- **Language**: System, Español or English. This controls the menu labels
  (`Semanal`/`Weekly`, `Mensual`/`Monthly`, menu actions).
- **Refresh**: 1, 5, 15, 30 or 60 minutes. The menu bar item also refreshes
  when you open the menu.

## 4. Build and run

```sh
git clone https://github.com/duque96/opencode-usage.git
cd opencode-usage
./build.sh
open dist/OpenCodeUsage.app
```

`build.sh` compiles the Swift source with `swiftc` and ad-hoc signs the app.
The menu bar item appears immediately.

## 5. Install at login (optional)

```sh
./install.sh
```

This builds the app, copies it to `~/Applications/OpenCodeUsage.app`, and loads
the LaunchAgent `~/Library/LaunchAgents/es.duque.opencodeusage.plist`, which
starts it when you log in.

`KeepAlive` only restarts the app if it crashes. Choosing **Salir** in the menu
stops it without relaunching.

To disable autostart:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/es.duque.opencodeusage.plist
rm ~/Library/LaunchAgents/es.duque.opencodeusage.plist
rm -rf ~/Applications/OpenCodeUsage.app
```

## How it works

The app calls:

```http
GET https://opencode.ai/inference/go/v1/usage
Authorization: Bearer <api-key>
```

Example response:

```json
{
  "usage": {
    "rolling": { "status": "ok", "percent": 3, "resetsAt": "2026-10-25T13:39:22.000Z" },
    "weekly":  { "status": "ok", "percent": 5, "resetsAt": "2026-10-26T00:00:00.000Z" },
    "monthly": { "status": "ok", "percent": 2, "resetsAt": "2026-11-14T08:40:42.000Z" }
  }
}
```

`percent` is the usage of that window; `resetsAt` is ISO 8601 UTC.

> **Heads-up:** this endpoint is undocumented and may change without notice.
> The app is a thin client; if OpenCode changes the response shape or path, it
> will stop working until updated.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Menu bar shows `OpenCode Go: —` | No API key configured. Open **Settings…** and paste one. |
| Menu bar shows `OpenCode Go: !` | Request failed. Open the menu to see the error. |
| `Falta ~/.config/opencode-usage/key` | No key in the Keychain or the legacy file. Configure one in Settings. |
| HTTP 401 / 403 | The key is invalid, expired, revoked, or lacks the Usage permission. Create a new one. |
| HTTP 404 | The endpoint changed. Please open an issue. |
| Nothing appears in the menu bar | Run the binary from a terminal to see errors: `~/Applications/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage` |
| macOS says the app cannot be opened | It is not notarized. Build it locally with `./build.sh`, or right-click the app and choose **Open**. |

Logs from the LaunchAgent go to `/tmp/opencodeusage.log`.

## Security

- The API key is stored in the **macOS Keychain** when configured in the app.
- The optional legacy file is read with mode `600`.
- It is only sent to `opencode.ai` over HTTPS.
- The app has no telemetry and no third-party dependencies.
- Revoke the key in the Console if you stop using the app.

## Project layout

```
OpenCodeUsage.swift   AppKit menu bar app
Info.plist            Bundle metadata (LSUIElement, no Dock icon)
build.sh              Compile with swiftc and ad-hoc sign
install.sh            Install to ~/Applications and load the LaunchAgent
.github/workflows/    CI build on macOS
```

## License

[MIT](LICENSE)
