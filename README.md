# Desknet.app

A Mac app that shows the network requests of apps you run from Xcode, on the iOS Simulator and on the Mac. You don't add a package or change code in your project.

Run Desknet, press ⌘R in Xcode, and the app's `URLSession` requests appear in the Desknet window with headers, bodies, status and timing.

## What it captures

| App | Captured | Project change |
| --- | --- | --- |
| iOS Simulator app run from Xcode | Yes | None |
| Mac app run from Xcode, signed by the same team as your Desknet build | Yes, hardened runtime included | None |
| App that links the `Desknet-iOS` SDK | Yes | None (the SDK sends its own logs) |
| Sandboxed Mac app | No | Set `ENABLE_APP_SANDBOX = NO` for Debug, or wait for build-phase mode |
| Mac app signed by another team | No | Build-phase mode, not built yet |
| Real iPhone or iPad | No | Build-phase mode, not built yet |
| App launched without the debugger (home screen, Finder, "Debug executable" off) | No | Needs the SDK |

New macOS projects from Xcode's template are sandboxed by default. The agent loads into them but can't reach Desknet's socket, so nothing shows up.

Only `URLSession` traffic is captured, including Alamofire and Moya. WebSockets, `Network.framework`, raw sockets and `WKWebView` aren't.

## Requirements

- macOS 14 or later, on Apple silicon. The Simulator agent is built for arm64 only.
- Xcode 27. Tested with Xcode 27.1.
- An Apple Development signing identity. Mac apps only load the agent if your Desknet build is signed by the same team as the app.

## Build and run

1. Open `DesknetApp.xcodeproj`.
2. In the `DesknetApp` target → Signing & Capabilities, choose your team. The project is set to team `R2D4D7YLB2`.
3. Run the `DesknetApp` scheme. It builds `Desknet.app` and both agents.

From the terminal:

```shell
xcodebuild -project DesknetApp.xcodeproj -scheme DesknetApp build
```

On every launch, Desknet copies its agents and the LLDB hook into `~/Library/Application Support/Desknet/`.

## One-time setup: the Xcode hook

Add this block to `~/.lldbinit-Xcode` and `~/.lldbinit-lldb-rpc-server`, creating the files if needed. Xcode 27.1 reads the first; the second is for other Xcode versions.

```
# BEGIN Desknet Xcode Hook
command script import "~/Library/Application Support/Desknet/desknet_hook.py"
# END Desknet Xcode Hook
```

Desknet doesn't add this for you yet. An Install/Remove button in Settings is planned.

## Use it

1. Open Desknet.
2. Run your app from Xcode with ⌘R. "Debug executable" must be on in the scheme, which is the default.
3. The app appears under **Apps from Xcode**, with a green dot while it's connected. Select it to see only its requests, or pick **All apps**.

In the window:

- Search by URL, host, path, method, status code or error.
- Select a request to see its endpoint, status, duration, sizes, request and response headers, and bodies. JSON bodies are pretty-printed. Each header and body has a Copy button.
- Requests that fail without a response show as **Failed**.

| Shortcut | Action |
| --- | --- |
| ⌘⌃Z | Show or hide the window. Also works from apps that link the SDK. |
| ⌘L | Show Logs |
| ⌘K | Clear Logs |

Logs stay in memory only and are gone when Desknet quits. Start Desknet before the app you want to capture: the hook loads the agent only when Desknet is running, and only at app launch.

## How it works

```
Xcode ⌘R ── ~/.lldbinit-Xcode ── desknet_hook.py ── loads DesknetAgent.framework into the app
                                                            │
                     NDJSON over ~/Library/Caches/desknet.sock (owner-only)
                                                            ▼
                                                      Desknet.app
```

1. **Hook.** `desknet_hook.py` runs inside Xcode's debugger. It stops each debugged app at `UIApplicationMain` or `NSApplicationMain` and checks that the app is a Simulator or Mac `.app`, isn't a SwiftUI Preview, test runner or Desknet itself, and that Desknet is listening. Then it loads the agent and lets the app continue.
2. **Agent.** `DesknetAgent.framework` registers a `URLProtocol`, hooks `URLSessionConfiguration.default` and `.ephemeral`, and sends each finished request to Desknet. Up to 500 requests are kept while Desknet can't be reached.
3. **Desknet.app.** It listens on the socket, tags each request with the sending process, and finds apps run from Xcode with a process scan.

Mac apps with hardened runtime accept the agent because Xcode signs it with your team while building Desknet. The Simulator doesn't check signatures.

## Troubleshooting

`~/Library/Application Support/Desknet/hook.log` has one line per launch:

| Line | Meaning |
| --- | --- |
| `load exe=… error=None` | Agent loaded |
| `skip … Desknet.app not running` | Desknet wasn't listening. Start it, then rerun the app |
| `skip … no agent` | No agent for that platform. Run Desknet once so it installs the agents |
| no line for your run | The hook didn't load. Check the block in `~/.lldbinit-Xcode` |

- **App listed but no requests:** the app was probably started before Desknet. Rerun it from Xcode.
- **Each request shows twice:** the Simulator app also links `Desknet-iOS`. The agent can't detect the SDK yet. Remove the SDK, or ignore the copies.
- **Desknet's own debug log:** `log stream --predicate 'subsystem == "dev.desknet.app"'`.

## Uninstall

1. Quit Desknet.
2. Remove the Desknet block from `~/.lldbinit-Xcode` and `~/.lldbinit-lldb-rpc-server`.
3. Delete `~/Library/Application Support/Desknet/` and `~/Library/Caches/desknet.sock`.

## Project layout

| Path | Contents |
| --- | --- |
| `DesknetApp/` | The Mac app: window and views, view model, store, socket listener, app scanner, agent installer |
| `DesknetApp/desknet_hook.py` | LLDB hook, shipped in the app's Resources |
| `DesknetAgent/` | The agent: capture, socket client and an Objective-C `+load` entry point. Built for macOS by its own target, and for the Simulator by the app target's "Build Simulator Agent" phase |
| `Checks/main.swift` | Self-check for the wire format, store, app detection and socket repair |
| `docs/` | Design, plan and research notes |

## Development

Run the self-check from the repo root:

```shell
swiftc -o /tmp/bridge_check DesknetApp/Store.swift DesknetApp/Bridge.swift DesknetApp/Diagnostics.swift DesknetApp/RunningApps.swift Checks/main.swift && /tmp/bridge_check
```

It prints `bridge_check: ok`.

The wire format matches what the `Desknet-iOS` SDK sends today (`{"entry":{"_0":{…}}}`, `{"toggle":{}}`), so SDK apps keep working. Don't rename fields in `NetworkLogEntry`.

## Roadmap

Full list in [docs/PLAN.md](docs/PLAN.md).

- Settings → Xcode Integration: install and remove the hook block
- Build-phase mode for real devices, sandboxed Mac apps and other teams' apps
- Protocol v2 with a `hello` message carrying app and device info
- An SDK marker so the agent stands down in apps that link `Desknet-iOS`
- A menu bar item
- "Launch with Desknet" for apps run without the debugger
- An x86_64 Simulator agent for Intel Macs
- Unnotarized release build (zip or DMG)

## Docs

- [docs/DESIGN.md](docs/DESIGN.md): how the pieces fit, transport and security
- [docs/PLAN.md](docs/PLAN.md): tasks and their status
- [docs/RESEARCH.md](docs/RESEARCH.md): what was tested on this Mac, and how RocketSim does it
