"""Loads the Desknet agent into iOS Simulator apps debugged from Xcode.
Imported from ~/.lldbinit-Xcode and ~/.lldbinit-lldb-rpc-server; set on the dummy target so every new debug target inherits it.

Xcode 27's lldb-rpc-server never runs breakpoint script callbacks (verified 2026-10-29), so the
UIApplicationMain breakpoint carries no callback; a scripted stop hook injects and auto-continues."""
import os
import time
import lldb

AGENT = os.environ.get("DESKNET_AGENT_PATH", "/tmp/dn_agent/libDesknetAgentProbe.dylib")
LOG = os.path.expanduser("~/Library/Application Support/Desknet/hook.log")
BP_NAME = "desknet-agent"
# iOS (device and Simulator) and macOS app entry points.
ENTRY_POINTS = ("UIApplicationMain", "NSApplicationMain")
# Build-phase mode: agent embedded next to the executable and signed with the app.
EMBEDDED = ("../Frameworks/DesknetAgent.framework/DesknetAgent",  # macOS: <app>/Contents/MacOS/<exe>
            "Frameworks/DesknetAgent.framework/DesknetAgent")     # iOS: <app>.app/<exe>

def log(msg):
    # ponytail: unbounded append; rotate (RocketSim does 2 MB) once the app owns this file.
    try:
        with open(LOG, "a") as f:
            f.write("%s pid=%d %s\n" % (time.strftime("%H:%M:%S"), os.getpid(), msg))
    except OSError:
        pass

def __lldb_init_module(debugger, internal_dict):
    dummy = debugger.GetDummyTarget()
    names = lldb.SBStringList()
    dummy.GetBreakpointNames(names)
    # Both init files may be read by one debugger: install once.
    if any(names.GetStringAtIndex(i) == BP_NAME for i in range(names.GetSize())):
        log("init debugger=%d already installed" % debugger.GetID())
        return
    for name in ENTRY_POINTS:
        bp = dummy.BreakpointCreateByName(name)
        bp.AddName(BP_NAME)
    # No target selected yet, so this lands on the dummy target too and is inherited.
    debugger.HandleCommand("target stop-hook add -P desknet_hook.StopHook")
    log("init debugger=%d bp=%d" % (debugger.GetID(), bp.GetID()))

def _hit_ids(thread):
    """Breakpoint IDs of a stop at one of our entry points, else []."""
    if thread.GetStopReason() != lldb.eStopReasonBreakpoint:
        return []
    # By-name breakpoints also match Swift overlays, e.g. "AppKit.NSApplicationMain(Swift.Int32, ...)".
    name = (thread.GetFrameAtIndex(0).GetFunctionName() or "").split("(")[0].rsplit(".", 1)[-1]
    if name not in ENTRY_POINTS:
        return []
    return [thread.GetStopReasonDataAtIndex(i) for i in range(0, thread.GetStopReasonDataCount(), 2)]

class StopHook:
    def __init__(self, target, extra_args, internal_dict):
        pass

    def handle_stop(self, exe_ctx, stream):
        # An exception here makes LLDB keep the stop, so the app would hang at UIApplicationMain.
        try:
            return self._handle(exe_ctx)
        except Exception:
            import traceback
            log("error " + traceback.format_exc().replace("\n", " | "))
            return False

    def _handle(self, exe_ctx):
        thread = exe_ctx.GetThread()
        ids = _hit_ids(thread)
        if not ids:
            return True  # not ours: leave the stop alone
        target = exe_ctx.GetTarget()
        # Breakpoint names aren't copied from the dummy target, so ours is told apart by symbol.
        # ponytail: assumes ours is the lowest ID (dummy bps are copied first); tag via a
        # propagating property if a user bp ever gets a lower ID.
        target.BreakpointDelete(ids[0])  # once per launch
        _inject(exe_ctx.GetProcess(), target)
        return len(ids) > 1  # keep the stop only if a user breakpoint also hit here

def _agent_path(target):
    """Agent path as the target process sees it, or None to leave the app alone."""
    exe = target.GetExecutable().fullpath or ""
    for rel in EMBEDDED:
        if os.path.exists(os.path.normpath(os.path.join(os.path.dirname(exe), rel))):
            # On a device the process runs from its own copy of the bundle, not the build product.
            remote = target.GetModuleAtIndex(0).GetPlatformFileSpec().fullpath or exe
            return os.path.normpath(os.path.join(os.path.dirname(remote), rel))
    # No-SDK mode: Simulator only; Mac apps and devices need the build phase.
    if "-simulator" in (target.GetTriple() or "") and os.path.exists(AGENT):
        return AGENT
    return None

def _inject(process, target):
    exe = target.GetExecutable().fullpath
    names = (target.GetModuleAtIndex(i).GetFileSpec().GetFilename() or "" for i in range(target.GetNumModules()))
    if any("DesknetAgent" in n for n in names):
        log("skip exe=%s already loaded (weak-linked)" % exe)
        return
    agent = _agent_path(target)
    if not agent:
        log("skip triple=%s exe=%s no agent" % (target.GetTriple(), exe))
        return
    error = lldb.SBError()
    token = process.LoadImage(lldb.SBFileSpec(agent, False), error)
    log("load exe=%s agent=%s token=%s error=%s" % (exe, agent, token, error.GetCString()))
