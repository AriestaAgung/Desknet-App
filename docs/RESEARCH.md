# Research: RocketSim and Simulator injection

Date: 2026-10-29. Host: macOS 27.2, Xcode 27.1 (27A9269), iOS 27.0 and 27.1 Simulator runtimes, Apple Silicon.

## Limits of this research

- The "How RocketSim gets into Simulator apps" section below comes from RocketSim's public docs.
- The "RocketSim 16.8.0 bundle analysis" section comes from the installed `/Applications/RocketSim.app`.
  - Read with `codesign`, `otool`, `vtool` and `strings`, plus the Python loader RocketSim ships in plain text.
  - REA `inspect-artifact` ran on the linker binary: Evidence `ev_b2878305d16ef616a324a8c8aa6d8d5db47e7a43089ec88dbdd403ac928002bd`, SHA-256 `84c3347f…ca3f`.
  - **No decompilation:** Ghidra isn't installed. The Swift code inside the linker was only read through its strings and class names.
- RocketSim Connect isn't set up on this Mac (`~/.lldbinit-Xcode` doesn't exist), so **RocketSim's own injection was not observed running**.
- RocketSim's loader is proprietary. Learn from how it works, but **don't copy its code** into this repo.

Sources (all under `https://www.rocketsim.app/docs/`):
- `getting-started/setting-up-rocketsim-connect/`
- `features/networking/network-traffic-monitoring/`
- `features/networking/network-speed-control/`
- `features/capturing/device-hub-support/`
- `settings/side-window/`
- `support/faq/`

## How RocketSim gets into Simulator apps

RocketSim calls this "RocketSim Connect". Network monitoring and Simulator Camera only work once it's set up.

- **What gets injected.** A framework bundled inside the app: `RocketSim.app/Contents/Frameworks/RocketSimConnectLinker.framework`.
- **How it's loaded: Xcode's debugger, LLDB.**
  - RocketSim adds a marked block to `~/.lldbinit-Xcode`, a file LLDB reads at the start of every Xcode debug session:
    ```
    # BEGIN RocketSim Connect LLDB Hook
    command source "/Users/<you>/Library/Application Support/com.swiftlee.RocketSim/rocketsim-connect-lldbinit"
    # END RocketSim Connect LLDB Hook
    ```
  - The helper script waits until the app reaches `main` and checks the target is an iOS Simulator app. Mac apps and physical devices are ignored.
  - It then runs `process load` on the framework.
  - Nothing is added to the user's project, and archive or App Store builds are unaffected.
- **Only under Xcode's debugger.** Apps launched without the debugger don't get Connect.
- **Self-repair.** RocketSim owns only the text between its BEGIN and END markers. It repairs the helper script's path when the app moves or updates. Settings → Connect shows status and diagnostics and can remove the hook.
- **Fallback for teams that want explicit integration:** a debug-only code line:
  ```swift
  #if DEBUG
  Bundle(path: "/Applications/RocketSim.app/Contents/Frameworks/RocketSimConnectLinker.nocache.framework")?.load()
  #endif
  ```
  The `.nocache` suffix keeps the system from caching the framework.
- **Finding the Mac app:** the injected framework finds RocketSim through **Bonjour** and opens a local connection. RocketSim is sandboxed (App Store), which likely explains why it uses Bonjour.

## RocketSim 16.8.0 bundle analysis (build 339)

**The Mac app**
- `com.swiftLee.RocketSim`, team `4QMDKC8VLJ`, hardened runtime, **sandboxed**.
- Entitlements include `network.client`, `network.server`, an app group, `files.user-selected.read-write` with bookmarks, a `content-filter-provider` Network Extension and system-extension install.
- It bundles `FBSimulatorControl` and `FBControlCore` (Meta's simulator-control libraries), Sentry, and a `Helpers/rocketsim` CLI.

**The injected framework**
- `Contents/Frameworks/RocketSimConnectLinker.nocache.framework`, version `0.4.13`.
- Universal `x86_64 arm64`, platform `IOSSIMULATOR`, minimum iOS 16.0. Signed by the same team (not ad-hoc), with no hardened-runtime flag.
- About 3.8 MB. Links UIKit, SwiftUI, AVFoundation, CoreData and others.
- Internal modules seen in its class names: `RocketSimConnectCore`, `RocketSimConnectKit`, `RSPulse` (a renamed copy of Pulse), and `SimulatorCameraSupportImplementation`.

**How it captures and connects** (each item is labelled observed or inferred)
- **Capture:** `RocketSimConnectCore.URLSessionSwizzler` targets `__NSCFURLSessionTask`. The selector strings include `resume`, `setDelegate:` and `dataTaskWithRequest:`.
  - Inferred: it hooks task `resume`, not `URLProtocol`. Sessions created before the framework loads would then still be captured.
  - `RSPulse` also contains `CustomHTTPProtocol` and `URLSessionMockingProtocol`, likely for mocking.
- **Autostart:** observed `RocketSimConnectCore.Autoloader` and an `__objc_nlclslist` section. Inferred: an Objective-C `+load` starts it as soon as it's loaded.
- **Discovery:** observed the Bonjour type `_rocketsim._tcp`, the error string `Failed to create bonjour listener` inside the linker, and a `RocketSimConnectionListener` class.
  - Inferred: **the Simulator app listens and advertises**, and the Mac app browses and connects.
  - The sandbox explains this: a sandboxed Mac app can't share a Unix socket path with Simulator processes.
- **Environment flags** seen in the linker: `ROCKETSIM_CONNECT_DEBUG`, `ROCKETSIM_SIMULATOR_CAMERA`, `ROCKETSIM_DISABLE_SIMULATOR_CAMERA`, `IPHONE_SIMULATOR_ROOT`.

**The LLDB loader**
- Shipped as plain text: `Contents/Resources/RocketSimConnect_RocketSimConnectUI.bundle/Contents/Resources/RocketSimConnectLLDB.py`, 2,809 lines.
- **It installs into two files:** `~/.lldbinit-Xcode` and `~/.lldbinit-lldb-rpc-server`. The app's UI text says: "A small block in two Xcode startup files, ~/.lldbinit-Xcode and ~/.lldbinit-lldb-rpc-server, loads Connect when your Simulator app launches."
  - Inferred: on Xcode 27, Xcode's debugger can run inside `lldb-rpc-server`, which reads the second file. **We must write both.**
- **Generated block:** `# BEGIN RocketSim Connect LLDB Hook` … `# END RocketSim Connect LLDB Hook`, containing `command script import` of a generated helper. The helper sets `_mod.LINKER_PATH` to the installed framework.
  - Removal is an `awk` script that deletes the block plus older markers (`RocketSimConnect_hook`, `RocketSimConnectCoreLinker`, `…nocache.framework` lines) and trims trailing blank lines.
  - File access goes through user-selected security-scoped bookmarks: `rocketsim-connect-lldbinit-file-bookmark` and `…-rpc-server-file-bookmark`.
- **Per debugger:** `__lldb_init_module` stops stale observers registered for the same debugger ID, which are stored on the `lldb` module. It then starts one `RocketSimInternalMainObserver`: an `SBListener` on `eBroadcastBitModulesLoaded`, run on a daemon thread.
- **Gating** in `primary_simulator_app_rejection_reason`. It rejects:
  - targets that aren't iOS Simulator (platform name or triple);
  - a missing executable, or one that doesn't sit directly in a `.app`;
  - SwiftUI Previews (`/previews/` in the path, or `XCODE_RUNNING_FOR_PREVIEWS=1`);
  - test runners (`xctrunner`, or `XCTestConfigurationFilePath` set).

  It also skips processes that load test runtime modules (`libxctestbundleinject.dylib`, `xctest`, `.xctest`).
- **Injection point:** it finds `UIApplicationMain` in `UIKitCore` or `UIKit` as those modules load, and runs the main thread to it with a custom thread plan, not a breakpoint the user can see.
- **At that stop it:**
  - turns off `target.parallel-module-load` and `target.preload-symbols`, and tolerates the first being missing in older LLDB;
  - turns off the dyld notification breakpoint;
  - calls `SBProcess.LoadImage(LINKER_PATH)`;
  - restores everything afterwards.
- **Recovery:** most of the 2,809 lines handle edge cases.
  - Not stealing the stop when the user has a breakpoint at the same spot.
  - Telling its own internal stops apart from dyld traps.
  - Timeouts: republish 5s, post-injection monitor 15s, recovery budget 3s.
  - A JSONL log next to the script, rotated at 2 MB.

## RocketSim network monitor

- Captures by swizzling `URLSession` methods, built on the open-source [Pulse](https://github.com/kean/Pulse) library. `URLSession` only, so no WebSockets and no raw sockets.
- The UI has Requests, Logs and an "All" timeline. It adds insights (duplicate calls, failures, slowest endpoints), copy as cURL, and redacted exports and prompts.
- Network Speed Control uses a Network Extension that the user has to approve. Out of scope for us.

## RocketSim and Device Hub

- Its side window attaches to the Simulator inside Device Hub, in both expanded and compact mode.
- It finds booted Simulators through Device Hub. With one booted Simulator it picks that one automatically; with several it uses the focused one.
- It needs Screen Recording permission because the sandbox blocks reading window titles otherwise.

## Verified on this Mac (2026-10-29)

These were tested directly in this session.

**Device Hub**
1. Device Hub is `Xcode.app/Contents/Applications/DeviceHub.app` (`com.apple.dt.Devices`).
   - It loads `.devicekitplugin` bundles from `/Library/Developer/DeviceKit/PlugIns`.
   - It's signed with library validation, so third-party plugins are very likely rejected. Not tested at runtime.
2. Device Hub has **no Shake command**. Device → Keyboard only has "Toggle Software Keyboard".
3. Mac keystrokes reach the Simulator app as `UIPressesEvent`. `⌘⌃Z` handled in-app worked: open, close, open.

**Inside the Simulator**

4. Simulator processes **can't load AppKit** (`dlopen` gives `not in dyld cache`), so a Simulator app can't open a Mac window itself.
5. Simulator processes **can connect to a Unix socket on the Mac** at `$SIMULATOR_HOST_HOME/Library/Caches/desknet.sock`. `SIMULATOR_HOST_HOME` is set to the Mac user's home.
6. Socket permissions of `0600` inside the already-private `~/Library/Caches` work for the bridge.

**Injection**

7. `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=<dylib> xcrun simctl spawn|launch …` loads an ad-hoc-signed dylib into that one process.
8. `xcrun simctl spawn <udid> launchctl setenv DYLD_INSERT_LIBRARIES <dylib>` loads the dylib into **every** later process in that Simulator.
   - That includes system daemons (`launchctl`, `log`, `mlhostd`, …), not only apps.
   - User apps can be told apart because their bundle path contains `/Containers/Bundle/Application/`.
   - The setting was removed after the test.
9. **LLDB injection works:**
   - `simctl launch --wait-for-debugger` → `process attach` → break at `main` → `process load <dylib>` loads it. The target triple is `arm64-apple-ios-simulator`.
   - A **one-shot `UIApplicationMain` breakpoint set on LLDB's dummy target** is inherited by the attached target. Its Python callback ran `SBProcess.LoadImage` and returned `False`, so the app kept running.
   - Tested on MandiriCoinTicker, a SwiftUI app. Prototype: [`../prototypes/desknet_hook.py`](../prototypes/desknet_hook.py).
   - That breakpoint-callback version works in CLI `lldb` only. Inside Xcode it hangs the app (item 11).

**Capture**

10. `URLProtocol.registerClass` only covers `URLSession.shared`. Moya and Alamofire need `URLSessionConfiguration.default` and `.ephemeral` to be hooked as well. That hook exists in the Desknet repo but isn't committed yet.

**Phase 0 spikes** (Xcode 27.1, iPhone 18 Pro iOS 27.0, MandiriCoinTicker run with `⌘R`)

11. **0.1 Xcode Run: works, with a different hook design.**
    - Xcode 27.1 runs its debugger inside `lldb-rpc-server`, and that process reads **`~/.lldbinit-Xcode`**. `~/.lldbinit-lldb-rpc-server` was not read. Each Run creates a new debugger in the same long-lived `lldb-rpc-server` process.
    - **Breakpoint script callbacks never run there.** The `UIApplicationMain` breakpoint is hit, but `SetScriptCallbackFunction` isn't called, so the app hangs at `UIApplicationMain + 0` with a white screen. A one-shot breakpoint is also deleted before its callback would run.
    - **Breakpoint names aren't copied** from the dummy target to Xcode's real target.
    - **What works:** a plain `UIApplicationMain` breakpoint on the dummy target, plus `target stop-hook add -P desknet_hook.StopHook`. The stop hook is inherited too.
      - `handle_stop` checks that frame 0 is `UIApplicationMain`, deletes the lowest matching breakpoint ID, calls `SBProcess.LoadImage`, and returns `False` so the app keeps running.
      - It returns `True` (keeps the stop) when another `UIApplicationMain` breakpoint, such as a user's, was also hit.
    - **Any exception in `handle_stop` leaves the app stopped**, so the whole body is wrapped. Also, `SBTarget` has `BreakpointDelete`, not `BreakpointDeleteByID`.
    - Result: the Xcode run logs `loaded userApp=1 bundle=com.dcd.MandiriCoinTicker`. A launch without the debugger (`simctl launch`) logs nothing.
12. **0.2 Late load still captures.**
    - Test setup:
      - A throwaway copy of MandiriCoinTicker with `Desknet-iOS` removed and the bundle ID changed to `….dnspike`. Built in `/tmp`, then deleted.
      - A spike agent: the `DesknetCore` and `Desknet-iOS` sources, plus a C constructor that calls `Desknet.shared.start()` ([`../prototypes/agent_start.swift`](../prototypes/agent_start.swift), [`agent_start.c`](../prototypes/agent_start.c)).
      - The agent was injected through the same stop hook from CLI `lldb`, and a Python listener stood in for Desknet.app.
    - Result: both Moya `/data/top/totaltoptiervolfull` pages (`page=1`, `page=2`) reached the socket, so the `URLProtocol` + configuration hook is enough for this app. **No switch to `resume` swizzling yet.** Sessions created before `UIApplicationMain` weren't tested.
    - The first entry arrived **twice with the same ID**. The client connects on its first send, replays the store, and then sends the same entry again. The viewer-side `Set<UUID>` check (task 1.5) is needed.
13. **0.3 Quarantine: no effect.** The agent with `com.apple.quarantine` set still loads through `LoadImage` (token 0, no error). The installer doesn't need to clear the flag.
    - Side finding: overwriting the dylib in place with `cp` while the old copy is cached made the next `LoadImage` fail (`failed executing dlopen wrapper function`). Delete and then write, or write to a temp file and rename.
14. **0.4 SDK and agent together: breaks the app. The marker check is required.**
    - Injecting the real agent into MandiriCoinTicker, which links `Desknet-iOS`, doesn't crash right away.
    - Instead the **main thread recurses forever** in `desknet_defaultSessionConfiguration`: the two copies exchange the same selector twice.
    - The result is a white screen and no bridge traffic.
    - Control run: the probe agent in the same app gives normal capture (3 entries).
    - "Class implemented in both" warnings were not checked.
15. **0.5 Simulator environment and wake-up: both work.**
    - In an app injected from Xcode: `SIMULATOR_UDID=57D0AD07-…`, `SIMULATOR_DEVICE_NAME=iPhone 18 Pro`, `SIMULATOR_HOST_HOME=/Users/odikk`.
    - `xcrun simctl spawn <udid> notifyutil -p desknet.viewer-started` reached a `notify_register_dispatch` handler in the app.
16. **0.7 Coexistence with RocketSim: dropped** by the user. Out of scope.
17. **0.8 Injecting into macOS apps** (a throwaway app with sandbox and `network.client`, run under CLI `lldb process load`):
    - **Sandbox, ad-hoc signed:**
      - A dylib outside the container is blocked (`file system sandbox blocked open()`).
      - A dylib copied into `~/Library/Containers/<bundle-id>/Data/` **loads**.
      - `connect()` to `~/Library/Caches/desknet.sock` fails with `EPERM`.
      - TCP to `127.0.0.1` works (the app has `network.client`).
      - The agent can `bind` and `listen` on a Unix socket inside its own container, and a host process outside **can connect in**. The container path was 86 bytes, under the 104-byte `sun_path` limit.
    - **Hardened runtime, team-signed (Xcode's default for a Mac app):**
      - An ad-hoc agent is rejected: `mapping process and mapped file (non-platform) have different Team IDs`. Library validation applies even with `get-task-allow`.
      - Signing the agent with the same Apple Development identity was also rejected (`code signature invalid`; amfid: `Broken signature with Team ID fatal`). Cause not found.
    - **Team-signed, sandboxed, no hardened runtime:** the app failed to launch (`Launchd job spawn failed`, POSIX 163), so the agent couldn't be tested.
    - So the Mac apps blocked today are the ones with hardened runtime on, which is Xcode's default for new projects. An app built without it can be injected if the agent is first copied into its container. The open questions are re-signing with the user's team, or asking the user to add `com.apple.security.cs.disable-library-validation` for Debug.
    - In the probe, `log` meant zsh's builtin, not `/usr/bin/log`. Use the full path in scripts.
18. **0.9 Build-phase mode** (2026-10-29). Throwaway apps generated with `xcodegen` and deleted afterwards. All signed by the personal team `R2D4D7YLB2` with automatic signing.
    - **Test targets:**
      - `BPSpikeMac`: hardened runtime, sandbox, `network.client`.
      - `BPSpikeiOS`: runs on the iPhone 11 Pro `00008030-000428C40C98802E`, iOS device.
    - **Agent:** [`../prototypes/agent_framework.m`](../prototypes/agent_framework.m), built by [`build_agent_framework.sh`](../prototypes/build_agent_framework.sh) into `~/Library/Application Support/Desknet/Agent/{iphoneos,macosx}/DesknetAgent.framework`.
    - **Build phase:** [`../prototypes/desknet_build_phase.sh`](../prototypes/desknet_build_phase.sh), placed after compile.
    - **Step 1, the build phase itself:**
      - It copies the framework into `$FRAMEWORKS_FOLDER_PATH` and signs it with `$EXPANDED_CODE_SIGN_IDENTITY`. It skips when `CONFIGURATION` isn't `Debug` or the platform is the Simulator.
      - The embedded agent ends up with the app's Team ID on both platforms.
      - **Xcode's own Run fails with `ENABLE_USER_SCRIPT_SANDBOXING = YES`**, which is the default for new projects. `ditto` into the `.app` gets `Operation not permitted`, even with declared inputs and outputs. `xcodebuild` from the terminal passed with the same setting. With the setting `NO`, both pass.
      - If the agent is missing, the phase prints a warning and the build still succeeds.
    - **Step 2a, loading through the LLDB hook from inside the bundle:**
      - **Mac: works.**
        - CLI `process load` and Xcode `⌘R` both loaded the embedded agent into the hardened, sandboxed app. This is the case spike 0.8 couldn't get to load: re-signing as part of the build is accepted.
        - The hook needed two changes:
          - break on `NSApplicationMain` too;
          - match the stopped function by its base name. Under Xcode, the frame is the Swift overlay `AppKit.NSApplicationMain(Swift.Int32, …)`, so an exact match never fired and the hook didn't inject.
      - **iOS device: not verified.**
        - With Xcode `⌘R` on the iPhone, the app ran, but the hook never logged `init`, so our script didn't run for that session. Why isn't known.
        - CLI `lldb` with `device process attach` hung after attaching to a `--start-stopped` process.
    - **Step 2b, `-weak_framework DesknetAgent` launched without the debugger:**
      - **Mac: works.** The agent loads at launch. With the framework removed from the bundle, the app still launches.
      - **iOS device: works.** Launched with `devicectl … --console`, the app printed `DesknetAgent loaded` and `DesknetAgent listening 127.0.0.1:39391`.
      - The first launch of one weak-linked install was refused (`invalid code signature, inadequate entitlements or its profile has not been explicitly trusted`). The same build launched fine after reinstalling. This didn't happen again and the cause isn't known.
      - Weak linking needs `FRAMEWORK_SEARCH_PATHS` to point at the agent folder. If the agent isn't installed there, the link fails with `framework not found`. Not tested, but that's how `ld` works.
    - **Step 3, device transport over usbmuxd: not verified.**
      - The iPhone was paired over **Wi-Fi only**. usbmuxd listed it as `ConnectionType = Network`, and `Connect` to port 39391 returned result `2` (bad device), so the Mac never reached the agent.
      - This needs a USB cable. If Wi-Fi-only devices must work, the CoreDevice tunnel is the next thing to test.
      - While the agent listened on loopback and the app made requests, no Local Network prompt appeared (one device screenshot).
      - `Info.plist` was byte-for-byte the same with and without the agent, so no plist change is needed.
      - Still to check: whether a prompt appears once the Mac connects through usbmuxd.

## What we take from RocketSim

| RocketSim | Desknet.app | Why |
| --- | --- | --- |
| Managed block in `~/.lldbinit-Xcode` **and** `~/.lldbinit-lldb-rpc-server` | Same, with our own `# BEGIN/END Desknet` block in both files | Xcode 27 may run the debugger in `lldb-rpc-server` |
| Module-load observer + run to `UIApplicationMain` | `UIApplicationMain` breakpoint + scripted stop hook (spike 0.1: breakpoint callbacks don't run under Xcode) | ~80 lines, verified in Xcode 27.1; theirs handles more races |
| Skip previews, test runners, XCTest modules | Same gates | Without them the agent loads into SwiftUI Previews and unit tests |
| Turn off `parallel-module-load`, `preload-symbols`, dyld notify breakpoint around `LoadImage` | Same, if spike 0.1 shows hangs | They hit real hangs here; ours hasn't yet |
| Framework inside the app bundle | `libDesknetAgent.dylib` inside `Desknet.app` | Agent version always matches the app |
| Bonjour, app side listens (`_rocketsim._tcp`) | Unix socket at a fixed path | We're not sandboxed; already working; no Local Network prompt |
| Swizzle `__NSCFURLSessionTask` `resume` | Keep `URLProtocol` + configuration hook | Spike 0.2 captured Moya with a late load; revisit if an app makes sessions before `UIApplicationMain` |
| Debug-code fallback | `Desknet-iOS` SDK, or a "Launch with Desknet" button | Covers apps run without the debugger |
