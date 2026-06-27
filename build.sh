#!/bin/bash
set -e

# scoredock build script
# Compiles Swift Package Manager target and creates native macOS .app wrappers

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"

echo "[*] Step 1: Ensuring build directory exists..."
mkdir -p "${BUILD_DIR}"

echo "[*] Step 2: Compiling Swift package (debug mode)..."
swift build --configuration debug

BINARY_PATH="${PROJECT_DIR}/.build/debug/ScoreDock"

if [ ! -f "${BINARY_PATH}" ]; then
    echo "[-] Error: Compiled binary not found at ${BINARY_PATH}"
    exit 1
fi

package_app() {
    local app_name=$1
    local bundle_id=$2
    local target_app_dir="${BUILD_DIR}/${app_name}.app"
    local target_macos_dir="${target_app_dir}/Contents/MacOS"
    local target_resources_dir="${target_app_dir}/Contents/Resources"
    
    echo "[*] Packaging ${app_name}.app..."
    mkdir -p "${target_macos_dir}"
    mkdir -p "${target_resources_dir}"
    
    cp "${BINARY_PATH}" "${target_macos_dir}/${app_name}"
    chmod +x "${target_macos_dir}/${app_name}"
    
    cat <<EOF > "${target_app_dir}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
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
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

    echo "[*] Signing ${app_name}.app..."
    codesign --force --deep --sign - "${target_app_dir}"
}

package_app "ScoreDock" "com.scoredock.ScoreDock"
package_app "ScoreDockHelper1" "com.scoredock.ScoreDockHelper1"
package_app "ScoreDockHelper2" "com.scoredock.ScoreDockHelper2"
package_app "ScoreDockHelper3" "com.scoredock.ScoreDockHelper3"
package_app "ScoreDockHelper4" "com.scoredock.ScoreDockHelper4"

echo "[+] Successfully packaged applications in build/"
echo "[*] You can run the main app with: open build/ScoreDock.app"

if [ "$1" == "--run" ]; then
    echo "[*] Terminating existing ScoreDock processes..."
    pkill -x ScoreDock || true
    pkill -x ScoreDockHelper1 || true
    pkill -x ScoreDockHelper2 || true
    pkill -x ScoreDockHelper3 || true
    pkill -x ScoreDockHelper4 || true
    sleep 0.5
    echo "[*] Launching native application..."
    open "${BUILD_DIR}/ScoreDock.app"
    echo "[+] Launch successful."
fi
