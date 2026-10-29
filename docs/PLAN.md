# Plan

Read [DESIGN.md](DESIGN.md) and [RESEARCH.md](RESEARCH.md) first. Each task ends with a **Done when** check. Run it before ticking the box.

## Starting state (2026-10-29)

- **Desknet repo:** `desktop/Desknet`, branch `feat/simulator-implementation`, not pushed.
  - Commits `096f49f`…`34d9502`: core split, `Desknet-iOS`, `⌘⌃Z` shortcut, Simulator bridge, `DesknetViewer`.
  - **Uncommitted:** `Sources/DesknetCore/DesknetSessionConfigurationHook.swift` (Alamofire/Moya capture), its test `customSessionFromDefaultConfigurationIsCaptured`, and `BACKLOG.md`. Commit these first (task 1.0).
- **Test app:** `ios/MandiriCoinTicker`. Links `Desknet-iOS` from the local Desknet repo. Uses Moya (`Networking/NetworkManager.swift`) and one `URLSessionWebSocketTask`. Has the user's own uncommitted changes: don't touch them.
- **Test Simulator:** iPhone 18 Pro, iOS 27.0, UDID `57D0AD07-A3AF-45E9-88D3-C0F47DFE3869`. Check with `xcrun simctl list devices booted`.
- **Prototypes in `prototypes/`:**
  - `agent_probe.m`: dylib that only logs where it loaded (os_log subsystem `DesknetAgentProbe`).
  - `desknet_hook.py`: LLDB hook. Reads the agent path from `DESKNET_AGENT_PATH`. Its built-in default `/tmp/dn_agent/...` no longer exists.
- **`~/.lldbinit-Xcode` and `~/.lldbinit` don't exist yet** on this Mac.

Useful commands:

```shell
# Build the probe dylib for the Simulator
xcrun -sdk iphonesimulator clang -target arm64-apple-ios15.0-simulator \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" -fobjc-arc -dynamiclib \
  -framework Foundation prototypes/agent_probe.m -o build/libDesknetAgentProbe.dylib
codesign -s - -f build/libDesknetAgentProbe.dylib

# See where the probe loaded
xcrun simctl spawn booted log show --last 2m --info --debug \
  --predicate 'subsystem == "DesknetAgentProbe"' | grep -o 'loaded .*'
```

## Phase 0: spike (½–1 day)

Results for 0.1–0.5 are in RESEARCH.md items 11–16. To rebuild the spike agent, run `swiftc` over `../../Desknet/Sources/DesknetCore` and `Desknet-iOS` plus `prototypes/agent_start.{swift,c}`, using `-package-name Desknet`.

- [x] **0.1 Xcode Run loads the hook.** Done 2026-10-29. Needed a stop hook instead of a breakpoint callback.
  - Build the probe into `build/`.
  - Create `~/.lldbinit-Xcode` **and** `~/.lldbinit-lldb-rpc-server` with the managed block from DESIGN.md. Point both at a copy of `desknet_hook.py`, with `DESKNET_AGENT_PATH` set inside the script. Note which file Xcode 27.1 actually reads.
  - Run MandiriCoinTicker from Xcode (`⌘R`) on the test Simulator.
  - Then launch it from the Simulator home screen, without the debugger.
  - **Done when** the Xcode run logs `loaded userApp=1 bundle=com.dcd.MandiriCoinTicker` and the home-screen launch logs nothing.
- [x] **0.2 Late load still captures.** Done 2026-10-29. Moya captured; keep `URLProtocol`.
  - The agent loads at `UIApplicationMain`, after `main` starts.
  - In a throwaway copy or branch of MandiriCoinTicker with the `Desknet-iOS` SDK removed, inject a real agent build. A quick prototype is fine: `Desknet-iOS` sources plus a constructor that calls `Desknet.shared.start()`.
  - **Done when** `/data/top/totaltoptiervolfull` from Moya shows up in the viewer. If it's missed, switch to `URLSession` swizzling as RocketSim does, and note it in DESIGN.md.
- [x] **0.3 Quarantine.** Done 2026-10-29. A quarantined agent still loads.
  - Run `xattr -w com.apple.quarantine "0081;00000000;Safari;" build/libDesknetAgentProbe.dylib`, then repeat 0.1.
  - **Done when** we know whether a quarantined agent inside an unnotarized `Desknet.app` still loads. If it doesn't, the installer clears the flag on the agent at first launch.
- [x] **0.4 SDK and agent together.** Done 2026-10-29. Infinite swizzle recursion, so the marker check is required.
  - Inject the agent into an app that already links `Desknet-iOS`.
  - **Done when** we've confirmed it doesn't crash and doesn't swizzle twice, which means the marker check from DESIGN.md is needed. Write down the exact behavior.
- [x] **0.5 Simulator environment and wake-up.** Done 2026-10-29. All three env vars are present and `notifyutil` reaches the app.
  - Print `SIMULATOR_UDID`, `SIMULATOR_DEVICE_NAME` and `SIMULATOR_HOST_HOME` from the probe.
  - Check that `xcrun simctl spawn <udid> notifyutil -p desknet.viewer-started` reaches an app registered with `notify_register_dispatch`.
  - **Done when** both results are written down.
- [x] **0.6 RocketSim bundle analysis.** Done 2026-10-29 on RocketSim 16.8.0; see RESEARCH.md. Not done: decompiling the linker (no Ghidra), and watching RocketSim's own hook run (Connect isn't set up here).
- [ ] **0.7 Coexistence with RocketSim.** Dropped 2026-10-29 by the user: out of scope.
  - Set up RocketSim Connect, then run the Desknet hook in the same Xcode session.
  - **Done when** both load into MandiriCoinTicker, both capture the Moya calls, and nothing hangs.

- [~] **0.8 Inject into macOS apps.** Done 2026-10-29 (RESEARCH.md item 17). Sandboxed apps work if the agent is copied into their container. Hardened-runtime apps need build-phase mode.
- [~] **0.9 Build-phase mode.** Done 2026-10-29 (RESEARCH.md item 18).
  - Verified: the Mac in both load modes, and the iOS device with `-weak_framework`.
  - **Still open, needs a USB cable:**
    - the usbmuxd connection to the device agent (the iPhone was paired over Wi-Fi only);
    - the LLDB hook on a device under Xcode (the script didn't run for that session).

Write all results into RESEARCH.md under "Verified on this Mac" before starting Phase 1.

## Phase 1: core, ported into `DesknetApp/` (this repo)

`desktop/Desknet` is reference only: port its code, never edit it. The project is the Xcode template's `DesknetApp.xcodeproj`, edited to macOS only (no `xcodegen`).

Done so far (2026-10-29, commit `6600e2a`): the `DesknetApp` target builds `Desknet.app` (`dev.desknet.app`, macOS 14+, unsandboxed). It has Desknet's monitor UI, window, `⌘⌃Z` toggle and socket listener, using the SDK's current wire format, so `Desknet-iOS` apps already show their logs. It also dedupes with `Set<UUID>`, caps lines at 64 MB and shows "Failed". Self-check: `Checks/main.swift`.

- [~] **1.0 Project.** App target done; core and agent targets still to add.
  - Targets:
    - `Desknet` (macOS app): not sandboxed, hardened runtime off for now, minimum macOS 14.
    - `DesknetCore`: a framework or static lib with capture, store and protocol, shared by the app and every agent.
    - `DesknetAgent` frameworks: iOS Simulator, iOS device and macOS.
  - **Done when** `xcodebuild` builds all targets from the command line.
- [ ] **1.1 Port capture and store** from `Desknet/Sources/DesknetCore`: the URL protocol, the session-configuration hook, the store, the formatter and the filter. Bring the tests too.
  - **Done when** the ported tests pass on macOS and the iOS Simulator.
- [ ] **1.2 Protocol v2.**
  - Every message gets an explicit `type`, and each connection opens with a `hello` carrying source info (DESIGN.md → Transport). No v1 support.
  - **Done when** a round-trip test covers `hello`, `entry`, `show`, `hide` and `toggle`.
- [ ] **1.3 Agent client.**
  - Async: it never blocks the main thread. It replays history on reconnect.
  - Three transports:
    - the host socket (Simulator, and Mac apps that aren't sandboxed);
    - a container socket the agent listens on (sandboxed Mac apps);
    - `127.0.0.1:<port>` (iOS devices).
  - **Done when** a fake-listener test covers reconnect, replay and no main-thread blocking for each transport.
- [ ] **1.4 Agent gates.** The agent stands down unless it's a user app (bundle path check). It also stands down if the `Desknet` SDK marker is present: spike 0.4 showed infinite swizzle recursion without it.
  - **Done when** loading the agent into an app that links the SDK is a no-op.
- [ ] **1.5 Host listener.**
  - A `DispatchSource` accept loop on `~/Library/Caches/desknet.sock`.
  - Connects out to agents in sandboxed containers, and to devices through usbmuxd.
  - Read buffer capped. A `Set<UUID>` dedupe, since the client resends its first entry (spike 0.2).
  - A store grouped by `hello` source.
  - **Done when** the Simulator, a Mac app and the device all show up as separate sources.

## Phase 2: Desknet.app (this repo)

- [ ] **2.1 UI.**
  - Port the monitor view and detail view.
  - A sidebar of sources plus "All".
  - Show "Failed" instead of "Running" for failed requests.
  - Dock reopen and a menu bar item. `⌘⌃Z` toggles the window from any client.
  - **Done when** the window works with Simulator logs.
- [ ] **2.2 Install the agents and the hook.**
  - On launch, write the agent frameworks and `desknet_hook.py` to `~/Library/Application Support/Desknet/`, replacing each via temp file and rename.
  - Settings → Xcode Integration: Install, Repair and Remove for the managed block in `~/.lldbinit-Xcode` and `~/.lldbinit-lldb-rpc-server`.
  - **Done when** a project with no SDK, run from Xcode on the Simulator, shows its logs, and Remove leaves the rest of each file byte-for-byte unchanged.
- [ ] **2.3 Build-phase mode UI.**
  - Settings shows the snippet from DESIGN.md, the `ENABLE_USER_SCRIPT_SANDBOXING = NO` note and the weak-link settings, each with a Copy button. No pbxproj editing.
  - **Done when** a hardened Mac app and the iPhone show logs after the user pastes the snippet.
- [ ] **2.4 Fallback launchers.**
  - "Launch with Desknet": a Simulator and app picker, then `simctl launch` with `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES`.
  - **Done when** an app launched from the picker shows its logs without Xcode.

## Phase 3: ship unnotarized

- [ ] **3.1** Archive, ad-hoc sign, zip or DMG. README covers install, first-open (right-click → Open), the Xcode integration and uninstall.
  - **Done when** a fresh download, quarantined, opens, installs the hook and captures MandiriCoinTicker.

## Rules for whoever continues

- Never edit the user's projects. MandiriCoinTicker is only a test target, and its uncommitted changes belong to the user.
- Never set `launchctl setenv DYLD_INSERT_LIBRARIES` on a Simulator outside a quick test, and always run `unsetenv` afterwards. It injects into every Simulator daemon.
- Back up `~/.lldbinit-Xcode` before the first edit, and only change text between the Desknet markers.
- Commits go on `feat/desknet-app`, one branch, no worktrees. End commit messages with `Co-Authored-By: Claude <noreply@anthropic.com>`.
- `desktop/Desknet` is reference only. Don't edit it.
