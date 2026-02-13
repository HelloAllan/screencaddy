#!/bin/bash
set -e

APP_NAME="ScreenCaddy"
DMG_NAME="${APP_NAME}.dmg"
DMG_TEMP="${APP_NAME}_temp.dmg"
BUILD_DIR=".build"
BUNDLE_DIR="${BUILD_DIR}/${APP_NAME}.app"
BG_IMAGE="Assets/DMGBackground.svg"
DS_STORE="Assets/DMG_DS_Store"
VOL_NAME="${APP_NAME}"
MOUNT_POINT="/Volumes/${VOL_NAME}"
ICON_SIZE=152

ACTION="${1:-build}"

# Ensure bundle exists
if [ ! -d "${BUNDLE_DIR}" ]; then
    echo "Error: ${BUNDLE_DIR} not found. Run 'make bundle' first."
    exit 1
fi

create_writable_dmg() {
    if [ ! -f "${BG_IMAGE}" ]; then
        echo "Error: ${BG_IMAGE} not found."
        exit 1
    fi
    hdiutil detach "${MOUNT_POINT}" 2>/dev/null || true
    rm -f "${BUILD_DIR}/${DMG_TEMP}"

    hdiutil create -volname "${VOL_NAME}" -fs HFS+ -fsargs "-c c=64,a=16,e=16" \
        -size 200m -layout SPUD "${BUILD_DIR}/${DMG_TEMP}"

    DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${BUILD_DIR}/${DMG_TEMP}" | \
        awk '/Apple_HFS/ {print $1}')

    sleep 2

    cp -R "${BUNDLE_DIR}" "${MOUNT_POINT}/"
    ln -sf /Applications "${MOUNT_POINT}/Applications"

    mkdir -p "${MOUNT_POINT}/.background"
    cp "${BG_IMAGE}" "${MOUNT_POINT}/.background/background.svg"
    SetFile -a V "${MOUNT_POINT}/.background" 2>/dev/null || true
}

apply_saved_layout() {
    # Apply saved .DS_Store if it exists
    if [ -f "${DS_STORE}" ]; then
        cp "${DS_STORE}" "${MOUNT_POINT}/.DS_Store"
    fi
}

case "${ACTION}" in
    layout)
        # Create writable DMG and open for manual arrangement
        create_writable_dmg

        # Set initial background and icon size via AppleScript
        osascript <<EOF
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        delay 1
        set theWindow to container window
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set sidebar width of theWindow to 0

        set theViewOptions to icon view options of theWindow
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to ${ICON_SIZE}
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.svg"

        update without registering applications
        delay 1
    end tell
end tell
EOF
        echo ""
        echo "=== DMG is mounted and open in Finder ==="
        echo "1. Resize the window to fit the background"
        echo "2. Drag the icons where you want them"
        echo "3. When done, run: make dmg-save"
        echo ""
        ;;

    save)
        # Save the .DS_Store from the mounted volume
        if [ ! -d "${MOUNT_POINT}" ]; then
            echo "Error: DMG not mounted at ${MOUNT_POINT}. Run 'make dmg-layout' first."
            exit 1
        fi

        # Copy .DS_Store to project
        cp "${MOUNT_POINT}/.DS_Store" "${DS_STORE}"
        echo "Saved layout to ${DS_STORE}"

        # Find the device and unmount
        DEVICE=$(hdiutil info | grep "${MOUNT_POINT}" | awk '{print $1}' | head -1)
        sync
        hdiutil detach "${DEVICE}" -force 2>/dev/null || hdiutil detach "${MOUNT_POINT}" -force
        sleep 5

        # Convert to final DMG
        rm -f "${BUILD_DIR}/${DMG_NAME}"
        hdiutil convert "${BUILD_DIR}/${DMG_TEMP}" -format UDZO -imagekey zlib-level=9 \
            -o "${BUILD_DIR}/${DMG_NAME}"
        rm -f "${BUILD_DIR}/${DMG_TEMP}"

        echo "Created ${BUILD_DIR}/${DMG_NAME}"
        ;;

    build)
        # Automated build — sets layout entirely via AppleScript so all
        # Finder alias records are created fresh (saved .DS_Store aliases
        # are machine-specific and break on other Macs)
        create_writable_dmg

        # Set window appearance, background, and icon positions via AppleScript
        osascript <<EOF
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        delay 2
        set theWindow to container window
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set sidebar width of theWindow to 0
        -- Window sized to match SVG viewBox (603x313)
        set the bounds of theWindow to {400, 400, 960, 700}

        set theViewOptions to icon view options of theWindow
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to ${ICON_SIZE}
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.svg"

        -- Position icons
        set position of item "${APP_NAME}.app" to {100, 110}
        set position of item "Applications" to {450, 110}

        update without registering applications
        delay 3
        close
    end tell
end tell
EOF
        # Give Finder time to flush .DS_Store to disk
        sleep 2

        # Find the device and unmount
        DEVICE=$(hdiutil info | grep "${MOUNT_POINT}" | awk '{print $1}' | head -1)
        sync
        hdiutil detach "${DEVICE}" -force 2>/dev/null || hdiutil detach "${MOUNT_POINT}" -force
        sleep 5

        # Convert to final DMG
        rm -f "${BUILD_DIR}/${DMG_NAME}"
        hdiutil convert "${BUILD_DIR}/${DMG_TEMP}" -format UDZO -imagekey zlib-level=9 \
            -o "${BUILD_DIR}/${DMG_NAME}"
        rm -f "${BUILD_DIR}/${DMG_TEMP}"

        echo "Created ${BUILD_DIR}/${DMG_NAME}"
        ;;

    *)
        echo "Usage: $0 {layout|save|build}"
        exit 1
        ;;
esac
