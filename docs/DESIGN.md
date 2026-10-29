# Desknet.app design

## Goal

The user installs one Mac app and does nothing else. Every iOS Simulator app they run from Xcode shows its network logs in the Desknet window, opened with `⌘⌃Z`. Their projects stay untouched.

## The rule that makes it seamless

**If Desknet.app is running, every client sends its logs and `⌘⌃Z` to Desknet.app's window. If it isn't, each client falls back to its own UI.**

| Client | Desknet.app running | Not running |
| --- | --- | --- |
| iOS Simulator app run from **Xcode** (debugger on), no project change | Agent injected by LLDB → Desknet.app | Not injected (recommended, see open question 1) |
| Mac app without hardened runtime, run from Xcode, no project change | Agent injected by LLDB (copied into the app's container first if it's sandboxed) → Desknet.app | Not injected |
| Mac app with hardened runtime | **Build-phase mode** → Desknet.app | Agent loaded, sends nothing |
| Real iOS device | **Build-phase mode** → Desknet.app over USB (usbmuxd) | Agent loaded, sends nothing |
| iOS Simulator app launched from Desknet.app's "Launch with Desknet" | Desknet.app | n/a |

## Repos and ownership (decided 2026-10-29)

- **Everything is built in `DesknetMac/DesknetApp`**: capture, the wire protocol, the agent (one build each for the Simulator, iOS device and macOS), the host listener and the UI.
- **`desktop/Desknet` is reference only.** Port its code and don't edit it. Because nothing depends on it, its `package` access level doesn't matter.
- The `Desknet` SDK can still be linked into an app. In that case the agent's marker check (gate 2) makes it stand down.

## Components

```
Simulator app ──(SDK or injected agent)── NDJSON over Unix socket ──► Desknet.app
                                                                     ├─ DesknetHost listener
Mac app ──(Desknet SDK)── same socket ─────────────────────────────►├─ store, grouped by source
                                                                     └─ window + menu bar item
Xcode Run ── ~/.lldbinit-Xcode block ── desknet hook script ── process load libDesknetAgent.dylib
```

## Transport

- **Socket:** `~/Library/Caches/desknet.sock`, mode `0600`. Simulator clients build the path from `SIMULATOR_HOST_HOME`.
- **Format:** newline-delimited JSON, one message per line.
- **Protocol v2** (replaces today's Swift-synthesized `Codable` enum shape):
  - Every message carries an explicit `type` field, so the format stays stable across Swift versions.
  - Each connection starts with a `hello` message:
    ```json
    {"type":"hello","version":2,"source":{"bundleID":"com.dcd.MandiriCoinTicker","appName":"MandiriCoinTicker","platform":"ios-simulator","deviceName":"iPhone 18 Pro","udid":"57D0…","pid":277,"via":"agent"}}
    {"type":"entry","entry":{…NetworkLogEntry…}}
    {"type":"show"} {"type":"hide"} {"type":"toggle"}
    ```
  - `via` is `sdk` or `agent`.
  - `udid` and `deviceName` come from `SIMULATOR_UDID` and `SIMULATOR_DEVICE_NAME`. Both are expected to exist in Simulator processes but haven't been checked yet.
  - The host rejects versions it doesn't know and logs why.
- **Signal: Desknet.app started.** On launch it runs `xcrun simctl spawn <udid> notifyutil -p desknet.viewer-started` for every booted Simulator, and posts a distributed notification for Mac clients. Clients then reconnect and replay their history right away. The Simulator `notifyutil` path is **not verified yet**.
- **Sending is async.** It must never block the main thread (backlog item from Desknet's `BACKLOG.md`).

## No-SDK mode: Xcode as the launcher

This mirrors RocketSim Connect (see [RESEARCH.md](RESEARCH.md)).

1. **Settings → Xcode Integration → Install** adds a managed block to **both** `~/.lldbinit-Xcode` and `~/.lldbinit-lldb-rpc-server`, creating them if needed. RocketSim writes both; Xcode 27 can run its debugger inside `lldb-rpc-server`, which reads the second file.
   ```
   # BEGIN Desknet Xcode Hook
   command script import "~/Library/Application Support/Desknet/desknet_hook.py"
   # END Desknet Xcode Hook
   ```
   Desknet only ever edits the text between its own markers; everything else in the file is left alone.
2. **On every launch, Desknet.app rewrites `desknet_hook.py`** with the current agent path. That repairs the hook when the app moves or updates.
3. **In each Xcode debug session**, the hook script:
   - sets a plain `UIApplicationMain` breakpoint and a scripted stop hook (`target stop-hook add -P`) on LLDB's dummy target. Every new debug target inherits both.
     - Breakpoint script callbacks don't run under Xcode 27's `lldb-rpc-server`, and breakpoint names aren't inherited (spike 0.1). So the stop hook recognises our stop by frame 0 being `UIApplicationMain`.
     - It deletes the breakpoint once it has injected. Any exception must be caught, or the app stays stopped.
   - in the stop hook, checks that:
     - the target triple contains `-simulator`;
     - the executable sits directly in a `.app`;
     - it isn't a SwiftUI Preview (`/previews/` in the path, or `XCODE_RUNNING_FOR_PREVIEWS=1`);
     - it isn't a test runner (`xctrunner`, `XCTestConfigurationFilePath`, or loaded XCTest modules);
     - the agent file exists;
     - the socket accepts a connection (that is, Desknet.app is running);
   - only then calls `SBProcess.LoadImage(agent)`;
   - returns `False` so the app auto-continues, unless a user breakpoint also hit `UIApplicationMain`.

   The prototype is [`../prototypes/desknet_hook.py`](../prototypes/desknet_hook.py). It has the simulator gate only; the preview, test-runner and socket checks are still to do.
   Xcode 27.1 reads only `~/.lldbinit-Xcode`. Keep writing `~/.lldbinit-lldb-rpc-server` too, for parity with RocketSim and other Xcode versions; the script installs once per debugger.
4. **What the agent does on load:**
   - Gate 1: returns immediately unless the bundle path contains `/Containers/Bundle/Application/`.
   - Gate 2: returns if the app links the SDK. The SDK exports a C marker such as `@_cdecl("desknet_sdk_present")`, and the agent checks for it with `dlsym(RTLD_DEFAULT, …)`. **Required** (spike 0.4): without it, both copies exchange the session-configuration methods and the main thread recurses forever.
   - Then it runs the `Desknet-iOS` start path: capture, the `⌘⌃Z` hook, and the bridge client with `via: agent`.
   - It has no fallback sheet. Agent apps only ever use Desknet.app.
5. **Uninstall:** Settings → Xcode Integration → Remove deletes the managed block and the script.

Fallback launch paths for apps run without the debugger:
- **Launch with Desknet:** a picker of booted Simulators and installed apps that runs `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=<agent> xcrun simctl launch --terminate-running-process <udid> <bundle>`.
- **Copy Xcode env var:** gives `DYLD_INSERT_LIBRARIES=<agent>` for a scheme. Only for users who turn off "Debug executable".

## Build-phase mode (opt-in)

This mode is for targets the LLDB hook can't reach: Mac apps with hardened runtime, and real iOS devices. The Simulator and Mac apps without hardened runtime stay zero-change. It's verified in RESEARCH.md item 18. There's no pbxproj editor: Settings shows this snippet and a Copy button.

1. **The agent ships inside Desknet.app.** On launch, the app writes `~/Library/Application Support/Desknet/Agent/{iphoneos,macosx}/DesknetAgent.framework`, replacing it via temp file and rename.
2. **The user adds a Run Script phase to the app target, after "Compile Sources":**
   ```sh
   # Desknet: embed the network agent in Debug builds for devices and Mac apps.
   [ "$CONFIGURATION" = "Debug" ] || exit 0
   case "$PLATFORM_NAME" in iphoneos|macosx) ;; *) exit 0 ;; esac
   SRC="$HOME/Library/Application Support/Desknet/Agent/$PLATFORM_NAME/DesknetAgent.framework"
   DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/DesknetAgent.framework"
   [ -d "$SRC" ] || { echo "warning: Desknet agent not installed; open Desknet.app once."; exit 0; }
   mkdir -p "$(dirname "$DEST")" && rm -rf "$DEST" && ditto "$SRC" "$DEST"
   codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$DEST"
   ```
   - It also needs the target build setting **`ENABLE_USER_SCRIPT_SANDBOXING = NO`**. With the default `YES`, Xcode's own Run fails.
   - Signing with the app's identity is what gets the agent past library validation (hardened runtime) and device code signing.
3. **How the agent gets loaded**, one of:
   - **Debugger only, Mac:** no other change. The LLDB hook breaks at `NSApplicationMain` and loads `<app>/Contents/Frameworks/DesknetAgent.framework`. Verified.
   - **Always (required for devices):** add two Debug-only build settings. Then the agent loads with or without Xcode. Verified on the Mac and on the iPhone.
     - `OTHER_LDFLAGS = $(inherited) -weak_framework DesknetAgent`
     - `FRAMEWORK_SEARCH_PATHS = $(inherited) "$(HOME)/Library/Application Support/Desknet/Agent/$(PLATFORM_NAME)"`

     The catch: if Desknet.app has never been opened on a machine, the link fails.
   - The LLDB hook on a device (`UIApplicationMain`) isn't verified: under Xcode the hook script didn't run for the device session.
4. **Transport for each target:**
   - **Simulator, and Mac apps that aren't sandboxed:** the agent connects to `~/Library/Caches/desknet.sock`.
   - **Sandboxed Mac apps:** the sandbox blocks that socket. Instead, the agent listens on `<container>/Data/tmp/desknet-agent.sock` and Desknet.app connects to it. Verified in spike 0.8.
   - **iOS devices:** the agent listens on `127.0.0.1:<port>` and Desknet.app connects through usbmuxd (`/var/run/usbmuxd`, `Connect` message).
     - Loopback only, so nothing on the LAN can connect. No `Info.plist` change, and no prompt appeared while it listened.
     - Over USB this is not verified yet (the device was paired over Wi-Fi only). Wi-Fi-only devices would need the CoreDevice tunnel, which isn't tested.
5. **Gates still apply.** The agent stands down if the `Desknet` SDK marker is present. It only exists in Debug builds that have the phase.

Rejected option: setting `launchctl setenv DYLD_INSERT_LIBRARIES` across the whole Simulator. It works (verified), but it loads into every system daemon, so a crash in the agent would take down the whole Simulator.

## Mac app UI

- **Sidebar of sources:** one per `hello` (app, device, pid), plus an "All" entry. It fixes logs from different apps getting mixed (backlog item).
- **Detail view:** reuses `DesknetMonitorRootView`, moved into the public `DesknetHost` product.
- **Window behaviour:**
  - The window opens on `⌘⌃Z` from any client, a Dock click (`applicationShouldHandleReopen`) or the menu bar item.
  - `⌘⌃Z` while Desknet.app is focused hides it.
  - No global hotkey: it would swallow the key before the Simulator gets it.
- **Settings:** Xcode Integration (status, Install/Repair/Remove, last-injected app), the socket path, and Clear logs.
- **Status line:** shows how many clients are connected and their sources.

## Security and privacy

- The socket is owner-only. Other users on the Mac can't connect, but any process running as the same user can. That's acceptable for a debug tool; document it.
- Nothing leaves the Mac, and there are no network listeners.
- The agent only loads into Simulator apps run under Xcode's debugger, or through the explicit launch paths. Real-device and release builds are never touched.
- Logs can contain tokens and personal data. Keep them in memory only; add export redaction later.

## Distribution (decided: unnotarized for now)

- Ad-hoc signed `.app` in a zip or DMG. First launch needs right-click → Open, or `xattr -dr com.apple.quarantine /Applications/Desknet.app`.
- The agent dylib inside also carries the quarantine flag. It still loads in the Simulator (spike 0.3), so no clearing is needed.
- When the app updates the agent on disk, it must replace the file (write to a temp file, then rename), not overwrite it in place. An in-place overwrite made the next load fail (spike 0.3).
- Not the Mac App Store: the sandbox would block the shared socket path and `xcrun simctl`.
- Notarize later once there's an Apple Developer account.

## Known limits

- Captures `URLSession` only: no WebSockets, `Network.framework` or raw sockets. `WKWebView` traffic runs in a separate process.
- Apps run from Xcode with "Debug executable" turned off aren't injected. They need the SDK or "Launch with Desknet".
- Sessions created before `UIApplicationMain` may be missed. Spike 0.2 captured Moya fine with a late load, so we keep `URLProtocol`. RocketSim's `__NSCFURLSessionTask` `resume` swizzle is the fallback if a real app shows gaps.

## Open questions

1. When Desknet.app isn't running, should the hook skip loading the agent? Recommended: **yes**, through the socket check in step 3, so a closed Desknet.app means no swizzling and no swallowed `⌘⌃Z`.
2. Minimum macOS version for the app: recommended macOS 14. Device Hub itself needs 26.6 or later.
3. Ship an x86_64 slice of the agent for Intel Macs?
4. If RocketSim Connect is also installed, two `URLSession` swizzlers run in the same app. Check that they coexist.
