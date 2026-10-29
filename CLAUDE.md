# Desknet.app

Mac app that shows network logs from apps run from Xcode: iOS Simulator, iOS devices and Mac apps. Status: viewer works for apps that link the `Desknet-iOS` SDK; the injected agent (no-SDK mode) isn't built yet.

- Start here: `docs/PLAN.md`. Design: `docs/DESIGN.md`. Evidence and RocketSim notes: `docs/RESEARCH.md`.
- This folder is the git repo. Branch: `feat/desknet-app`, no worktrees.
- All code (capture, protocol, agents, host, UI) lives here. `../../Desknet` is reference only: port from it, never edit it.
- Build: `xcodebuild -project DesknetApp.xcodeproj -scheme DesknetApp build`. Self-check: see the command at the top of `Checks/main.swift`.
- Test app `../../../ios/MandiriCoinTicker` is read-only for us.
- Never leave `DYLD_INSERT_LIBRARIES` set via `simctl spawn <udid> launchctl setenv`.
- Only edit text between `# BEGIN Desknet Xcode Hook` and `# END Desknet Xcode Hook` in `~/.lldbinit-Xcode` and `~/.lldbinit-lldb-rpc-server`, after backing them up.
- Memory: agentmemory, project `desknetmac` (`../.agentmemory/config.json`, REST at `http://localhost:3111/agentmemory/remember` and `/search`).
- `/Applications/RocketSim.app` is installed for reference. Study how it works; never copy its code (e.g. `RocketSimConnectLLDB.py`) into this repo.
