# Plan

Read [DESIGN.md](DESIGN.md) and [RESEARCH.md](RESEARCH.md) first. Each task ends with a **Done when** check. Run it before ticking the box.

## Phase 0: spikes (done 2026-10-29)

Results are in RESEARCH.md items 11–19. Test setup: Xcode 27.1, iPhone 18 Pro Simulator (iOS 27.0), MandiriCoinTicker and Cleano.

- [x] **0.1 Xcode Run loads the hook.** Needs a scripted stop hook; breakpoint callbacks don't run under `lldb-rpc-server`.
- [x] **0.2 Late load still captures.** Moya traffic is captured when the agent loads at `UIApplicationMain`, so `URLProtocol` stays.
- [x] **0.3 Quarantine.** A quarantined agent still loads.
- [x] **0.4 SDK and agent together.** Two copies of the same swizzle recurse forever. The agent now uses its own selector names (RESEARCH.md item 19).
- [x] **0.5 Simulator environment and wake-up.** `SIMULATOR_UDID`, `SIMULATOR_DEVICE_NAME` and `SIMULATOR_HOST_HOME` are set; `notifyutil` reaches the app.
- [x] **0.6 RocketSim bundle analysis.** See "What we take from RocketSim" in RESEARCH.md.
- **0.7 Coexistence with RocketSim.** Dropped: out of scope.
- [x] **0.8 Inject into macOS apps.** An agent signed with the same team as the app loads, hardened runtime included (item 19). Sandboxed apps need the agent in their container.
- [~] **0.9 Build-phase mode.** Verified on the Mac and, with `-weak_framework`, on an iPhone. **Still open, needs a USB cable:** the usbmuxd connection to the device agent, and the LLDB hook on a device under Xcode.

## Phase 1: core, ported into `DesknetApp/` (this repo)

`desktop/Desknet` is reference only: port its code, never edit it. The project is the Xcode template's `DesknetApp.xcodeproj`, edited to macOS only (no `xcodegen`).

Done so far: `Desknet.app` (`dev.desknet.app`, macOS 14+, unsandboxed) with Desknet's monitor UI, window, `⌘⌃Z` toggle and socket listener on the SDK's current wire format, so `Desknet-iOS` apps show their logs. It lists apps run from Xcode and filters logs by app. Mac and Simulator apps without the SDK are captured by the injected agent. Self-check: `Checks/main.swift`.

- [~] **1.0 Project.** `DesknetApp` and `DesknetAgent` (macOS framework, embedded) targets done. The Simulator build of the agent comes from the "Build Simulator Agent" script phase. Still to add: the iOS device build. No shared `DesknetCore`: the agent has its own copy of the capture code.
  - Targets:
    - `Desknet` (macOS app): not sandboxed, hardened runtime off for now, minimum macOS 14.
    - `DesknetCore`: a framework or static lib with capture, store and protocol, shared by the app and every agent.
    - `DesknetAgent` frameworks: iOS Simulator, iOS device and macOS.
  - **Done when** `xcodebuild` builds all targets from the command line.
- [~] **1.1 Port capture and store.** The URL protocol, configuration hook and store are ported into `DesknetAgent/DesknetAgent.swift`. Still to do: the formatter, ignore patterns and the tests. Original task: port from `Desknet/Sources/DesknetCore`: the URL protocol, the session-configuration hook, the store, the formatter and the filter. Bring the tests too.
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
- [~] **1.4 Agent gates.** The hook skips previews, test runners and Desknet.app itself, and loads only while Desknet.app is listening. The agent checks for `desknet_sdk_present`, but the SDK doesn't export it yet, so Simulator apps that also link `Desknet-iOS` show each request twice. Original task: The agent stands down unless it's a user app (bundle path check). It also stands down if the `Desknet` SDK marker is present: spike 0.4 showed infinite swizzle recursion without it.
  - **Done when** loading the agent into an app that links the SDK is a no-op.
- [ ] **1.5 Host listener.**
  - A `DispatchSource` accept loop on `~/Library/Caches/desknet.sock`.
  - Connects out to agents in sandboxed containers, and to devices through usbmuxd.
  - Read buffer capped. A `Set<UUID>` dedupe, since the client resends its first entry (spike 0.2).
  - A store grouped by `hello` source.
  - **Done when** the Simulator, a Mac app and the device all show up as separate sources.

## Phase 2: Desknet.app (this repo)

- [~] **2.1 UI.** Done except the menu bar item.
  - Port the monitor view and detail view.
  - A sidebar of sources plus "All".
  - Show "Failed" instead of "Running" for failed requests.
  - Dock reopen and a menu bar item. `⌘⌃Z` toggles the window from any client.
  - **Done when** the window works with Simulator logs.
- [~] **2.2 Install the agents and the hook.** Agents and `desknet_hook.py` are installed on launch. The lldbinit block is still added by hand.
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
