#!/bin/sh
# Desknet build phase: embeds DesknetAgent.framework into Debug builds for real iOS devices and Mac apps.
# Simulator builds are skipped: the LLDB hook injects there without touching the project.
# Paste into a Run Script phase (shell /bin/sh). Inputs/outputs: see docs/DESIGN.md "Build-phase mode".
[ "$CONFIGURATION" = "Debug" ] || exit 0
case "$PLATFORM_NAME" in iphoneos|macosx) ;; *) exit 0 ;; esac

SRC="$HOME/Library/Application Support/Desknet/Agent/$PLATFORM_NAME/DesknetAgent.framework"
DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/DesknetAgent.framework"
if [ ! -d "$SRC" ]; then
    echo "warning: Desknet agent not found at $SRC. Open Desknet.app once to install it."
    exit 0
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
ditto "$SRC" "$DEST"
# Same identity as the app, so library validation (hardened runtime) and device signing accept it.
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$DEST"
