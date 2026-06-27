# ScoreDock 🏏⚽️🏀

ScoreDock is a lightweight, ultra-efficient macOS native application that brings live sports scores directly to your desktop. Written entirely in Swift and SwiftUI, it sits on your screen like a native widget and rotates through your favorite live matches.

## Features
- **Native macOS Widget:** Glassmorphism UI that feels right at home on macOS.
- **Auto-Rotation:** Smoothly cycles between your favorite ongoing and upcoming matches.
- **Hover & Interact:** Hover to expand the widget. Swipe left/right to cycle matches. Right-click to instantly deep-link to the live ESPN Gamecast.
- **Smart Preferences:** A Google Sports-inspired settings UI. Easily select your favorite sport and add active teams or tournaments with one click.
- **Background Efficiency:** Bypasses heavy Electron/Web technologies. Uses native AppKit and Swift Concurrency (`async/await`) for zero-lag background fetching.
- **Live Notifications:** (Coming Soon) Get native macOS push notifications when wickets fall or goals are scored!

## Tech Stack
- **Language:** Swift 5+
- **UI:** SwiftUI (Glassmorphism, Spring Animations, Layout)
- **App Framework:** AppKit (NSApplication, NSPopover, NSWorkspace)
- **State Management:** Combine
- **Networking:** URLSession & Swift Concurrency (`async/await`)

## Building and Running

ScoreDock uses a custom build script that leverages the native `swiftc` compiler for rapid compilation, completely bypassing Xcode.

1. Clone the repository.
2. Ensure you have the Swift toolchain installed (via Xcode Command Line Tools).
3. Run the build script:
```bash
./build.sh
```
4. The script will compile the app and place the `.app` bundle in the `build/` directory, and will automatically launch it.

## Customizing Favorites

Click the Settings gear icon (or right-click the app in the dock) to open Preferences:
- Use the **Search Bar** to instantly find and add active teams/tournaments.
- Click the `(+)` icon to save them to your "Your Favorites" section.
- Customize the "Upcoming Match Lookahead" window in the API Config tab to see games up to 48 hours in the future.

## License
MIT License
