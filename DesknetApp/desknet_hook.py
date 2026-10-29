"""Loads the Desknet agent into apps debugged from Xcode.
Imported from ~/.lldbinit-Xcode and ~/.lldbinit-lldb-rpc-server; set on the dummy target so every new
debug target inherits it. Desknet.app rewrites this file on every launch.

Xcode 27's lldb-rpc-server never runs breakpoint script callbacks (RESEARCH.md item 11), so the
entry-point breakpoint carries no callback; a scripted stop hook injects and auto-continues."""
import os
import socket
import time
import lldb

SUPPORT = os.path.expanduser("~/Library/Application Support/Desknet")
LOG = SUPPORT + "/hook.log"
SOCKET = os.path.expanduser("~/Library/Caches/desknet.sock")
MAC_AGENT = SUPPORT + "/Agent/macosx/DesknetAgent.framework/DesknetAgent"
BP_NAME = "desknet-agent"
# iOS (device and Simulator) and macOS app entry points.
ENTRY_POINTS = ("UIApplicationMain", "NSApplicationMain")
# Build-phase mode: agent embedded next to the executable and signed with the app.
EMBEDDED = ("../Frameworks/DesknetAgent.framework/DesknetAgent",  # macOS: <app>/Contents/MacOS/<exe>
            "Frameworks/DesknetAgent.framework/DesknetAgent")     # iOS: <app>.app/<exe>
SKIP = ("/previews/", "XCPreviewAgent", "-Runner.app/", ".xctest/", "/Desknet.app/")

def log(msg):
    # ponytail: unbounded append; rotate (RocketSim does 2 MB) if it ever grows.
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
        return
    for name in ENTRY_POINTS:
        dummy.BreakpointCreateByName(name).AddName(BP_NAME)
    # No target selected yet, so this lands on the dummy target too and is inherited.
    debugger.HandleCommand("target stop-hook add -P desknet_hook.StopHook")
    log("init debugger=%d" % debugger.GetID())

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
        # An exception here makes LLDB keep the stop, so the app would hang at its entry point.
        try:
            return self._handle(exe_ctx)
        except Exception:
            import traceback
            log("error " + traceback.format_exc().replace("\n", " | "))
            return False

    def _handle(self, exe_ctx):
        ids = _hit_ids(exe_ctx.GetThread())
        if not ids:
            return True  # not ours: leave the stop alone
        target = exe_ctx.GetTarget()
        # Breakpoint names aren't copied from the dummy target, so ours is told apart by symbol.
        # ponytail: assumes ours is the lowest ID (dummy bps are copied first).
        target.BreakpointDelete(ids[0])  # once per launch
        _inject(exe_ctx.GetProcess(), target)
        return len(ids) > 1  # keep the stop only if a user breakpoint also hit here

def _viewer_running():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.2)
    try:
        s.connect(SOCKET)
        return True
    except OSError:
        return False
    finally:
        s.close()

def _agent_path(target):
    """Agent path as the target process sees it, or None to leave the app alone."""
    exe = target.GetExecutable().fullpath or ""
    if any(s in exe for s in SKIP):
        return None
    for rel in EMBEDDED:
        if os.path.exists(os.path.normpath(os.path.join(os.path.dirname(exe), rel))):
            # On a device the process runs from its own copy of the bundle, not the build product.
            remote = target.GetModuleAtIndex(0).GetPlatformFileSpec().fullpath or exe
            return os.path.normpath(os.path.join(os.path.dirname(remote), rel))
    # Mac app run from Xcode: load the agent Desknet.app installed. It's signed with the same
    # team as apps built on this Mac, which library validation accepts.
    # ponytail: Simulator agent isn't built yet (PLAN 1.0); SDK apps there already send logs.
    if "macosx" in (target.GetTriple() or "") and ".app/Contents/MacOS/" in exe and os.path.exists(MAC_AGENT):
        return MAC_AGENT
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
    if not _viewer_running():
        log("skip exe=%s Desknet.app not running" % exe)
        return
    error = lldb.SBError()
    token = process.LoadImage(lldb.SBFileSpec(agent, False), error)
    log("load exe=%s agent=%s token=%s error=%s" % (exe, agent, token, error.GetCString()))
