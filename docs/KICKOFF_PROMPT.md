# Kickoff prompt

Paste this into a new session started in `/Users/odikk/Documents/development-project/desktop/DesknetMac/DesknetApp`. (Historical: this started Phase 0. Current state is in PLAN.md.)

---

We're building **Desknet.app**: a Mac app that shows network logs from iOS Simulator apps in a Mac window, opened with `⌘⌃Z` from the Simulator. The user installs this one app and changes nothing in their projects. Xcode's Run button stays the launcher.

Read these before doing anything:

1. `docs/RESEARCH.md`: what we verified on this Mac, and how RocketSim does the same thing with an `~/.lldbinit-Xcode` hook.
2. `docs/DESIGN.md`: architecture, protocol v2, the no-SDK injection flow, and open questions.
3. `docs/PLAN.md`: the task list, with a **Done when** check for each task, plus rules.

Related code:

- `../../Desknet`: the SPM repo, branch `feat/simulator-implementation`. It has uncommitted work; see PLAN.md "Starting state".
- `prototypes/desknet_hook.py` and `prototypes/agent_probe.m`: working prototypes of the LLDB hook and a test dylib.
- `../../../ios/MandiriCoinTicker`: test app only. Don't edit it.

Start with **Phase 0** in PLAN.md. Do the spike tasks one at a time and write each result into `docs/RESEARCH.md` under "Verified on this Mac". Stop after Phase 0 and report. Tell me what changed in the design, if anything, before starting Phase 1.

Constraints:

- Unnotarized for now (no Apple Developer account).
- Not sandboxed; not for the Mac App Store.
- Simulator only. Real devices keep using the `Desknet-iOS` in-app sheet.
- Back up `~/.lldbinit-Xcode` before touching it.
- Never leave `DYLD_INSERT_LIBRARIES` set on a Simulator's `launchctl`.
- Commit only when I ask.
