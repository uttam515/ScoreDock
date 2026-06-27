#!/bin/bash
set -e

# ScoreDock Native macOS Build Script
# Compiles Swift Package Manager target and creates native macOS .app bundles

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_ICON="${PROJECT_DIR}/AppIcon.icns"

# Default configuration
CONFIG="debug"
BUILD_DMG=0
RUN_APP=0

for arg in "$@"; do
    case $arg in
        --release) CONFIG="release" ;;
        --debug)   CONFIG="debug" ;;
        --dmg)     BUILD_DMG=1 ;;
        --run)     RUN_APP=1 ;;
    esac
done

echo "[*] Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Generate a 100% transparent icon for the helper apps to ensure they never show a white square
if [ ! -f "${BUILD_DIR}/Transparent.icns" ]; then
    echo "[*] Generating transparent icon for helper apps..."
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" | base64 --decode > "${BUILD_DIR}/transparent.png"
    mkdir -p "${BUILD_DIR}/transparent.iconset"
    cp "${BUILD_DIR}/transparent.png" "${BUILD_DIR}/transparent.iconset/icon_16x16.png"
    cp "${BUILD_DIR}/transparent.png" "${BUILD_DIR}/transparent.iconset/icon_32x32.png"
    cp "${BUILD_DIR}/transparent.png" "${BUILD_DIR}/transparent.iconset/icon_128x128.png"
    cp "${BUILD_DIR}/transparent.png" "${BUILD_DIR}/transparent.iconset/icon_256x256.png"
    cp "${BUILD_DIR}/transparent.png" "${BUILD_DIR}/transparent.iconset/icon_512x512.png"
    iconutil -c icns "${BUILD_DIR}/transparent.iconset" -o "${BUILD_DIR}/Transparent.icns" 2>/dev/null || true
    rm -rf "${BUILD_DIR}/transparent.png" "${BUILD_DIR}/transparent.iconset"
fi

echo "[*] Compiling Swift package (${CONFIG} mode)..."
swift build --configuration "${CONFIG}"

BINARY_PATH="${PROJECT_DIR}/.build/${CONFIG}/ScoreDock"

if [ ! -f "${BINARY_PATH}" ]; then
    echo "[-] Error: Compiled binary not found at ${BINARY_PATH}"
    exit 1
fi

package_app() {
    local app_name=$1
    local bundle_id=$2
    local is_helper=$3
    
    local target_app_dir
    if [ "${is_helper}" == "true" ]; then
        # Package helpers INSIDE the main app bundle
        target_app_dir="${BUILD_DIR}/ScoreDock.app/Contents/Helpers/${app_name}.app"
    else
        target_app_dir="${BUILD_DIR}/${app_name}.app"
    fi
    
    local target_macos_dir="${target_app_dir}/Contents/MacOS"
    local target_resources_dir="${target_app_dir}/Contents/Resources"
    
    echo "[*] Packaging ${app_name}.app..."
    mkdir -p "${target_macos_dir}"
    mkdir -p "${target_resources_dir}"
    
    cp "${BINARY_PATH}" "${target_macos_dir}/${app_name}"
    chmod +x "${target_macos_dir}/${app_name}"
    
    # Base plist
    local plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${app_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>"

    # Helper apps should be strictly background, main app should be standard
    if [ "${is_helper}" == "true" ]; then
        if [ -f "${BUILD_DIR}/Transparent.icns" ]; then
            cp "${BUILD_DIR}/Transparent.icns" "${target_resources_dir}/AppIcon.icns"
            plist_content+="
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
        fi
        plist_content+="
    <key>LSUIElement</key>
    <true/>"
    else
        # Main App: Add AppIcon if available
        if [ -f "${APP_ICON}" ]; then
            cp "${APP_ICON}" "${target_resources_dir}/AppIcon.icns"
            plist_content+="
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
        fi
    fi

    plist_content+="
</dict>
</plist>"

    echo "${plist_content}" > "${target_app_dir}/Contents/Info.plist"

    echo "[*] Signing ${app_name}.app..."
    codesign --force --deep --sign - "${target_app_dir}"
}

package_app "ScoreDockHelper1" "com.uttam.scoredock.helper1" "true"
package_app "ScoreDockHelper2" "com.uttam.scoredock.helper2" "true"
package_app "ScoreDockHelper3" "com.uttam.scoredock.helper3" "true"
package_app "ScoreDockHelper4" "com.uttam.scoredock.helper4" "true"
package_app "ScoreDock" "com.uttam.scoredock" "false"

echo "[+] Successfully packaged native applications in build/"

if [ $BUILD_DMG -eq 1 ]; then
    echo "[*] Generating DMG installer..."
    
    # Create a staging folder so create-dmg packages the .app bundle itself, not its contents
    mkdir -p "${BUILD_DIR}/dmg_stage"
    cp -r "${BUILD_DIR}/ScoreDock.app" "${BUILD_DIR}/dmg_stage/"
    
    # Remove any existing DMG to prevent create-dmg errors
    rm -f "${BUILD_DIR}/ScoreDock.dmg"
    
    if command -v create-dmg &> /dev/null; then
        create-dmg \
          --volname "Install ScoreDock" \
          --window-pos 200 120 \
          --window-size 600 400 \
          --icon-size 100 \
          --icon "ScoreDock.app" 150 190 \
          --hide-extension "ScoreDock.app" \
          --app-drop-link 450 190 \
          "${BUILD_DIR}/ScoreDock.dmg" \
          "${BUILD_DIR}/dmg_stage/"
        echo "[+] Successfully created ScoreDock.dmg in build/"
    else
        echo "[-] Error: create-dmg is not installed. Run 'brew install create-dmg'"
    fi
fi

if [ $RUN_APP -eq 1 ]; then
    echo "[*] Terminating existing ScoreDock processes..."
    killall ScoreDock 2>/dev/null || true
    killall ScoreDockHelper1 2>/dev/null || true
    killall ScoreDockHelper2 2>/dev/null || true
    killall ScoreDockHelper3 2>/dev/null || true
    killall ScoreDockHelper4 2>/dev/null || true
        
    echo "[*] Launching native application directly to inherit Terminal accessibility permissions..."
    # By running the binary directly instead of using 'open', macOS treats it as a child process 
    # of the Terminal, which allows it to inherit the Terminal's accessibility permissions.
    # This completely fixes the annoyance of having to re-approve it in Settings on every build!
    "${BUILD_DIR}/ScoreDock.app/Contents/MacOS/ScoreDock" &
    echo "[+] Launch successful."
    exit 0
fi
