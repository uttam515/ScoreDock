import AppKit
import SwiftUI
import UserNotifications

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: FloatingPanel?
    private var scoreViewModel: ScoreViewModel?
    private var dockWatcher: DockWatcher?
    private var permissionTimer: Timer?
    private var globalTrackingTimer: Timer?
    
    // Temporary fast-tracking timer after a preferences plist change (move dock, resize)
    private var temporaryTrackingTimer: Timer?
    private var temporaryTrackingStopDate: Date?
    
    private var hudPopover: NSPopover?
    private var preferencesWindow: NSWindow?
    private var pinSubmenu: NSMenu?
    
    private var isHelper: Bool {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "ScoreDock"
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let processName = ProcessInfo.processInfo.processName
        return appName.contains("Helper") || bundleID.contains("Helper") || processName.contains("Helper")
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        if isHelper {
            setupHelperApp()
        } else {
            checkAccessibilityPermission()
            
            // Request push notification permissions
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if granted {
                    print("[AppDelegate] Notifications permitted.")
                } else if let error = error {
                    print("[AppDelegate] Notifications error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func setupHelperApp() {
        // Helpers only show a transparent Dock tile and run their runloop, doing nothing else.
        NSApp.setActivationPolicy(.regular)
        let transparentIcon = NSImage(size: NSSize(width: 1, height: 1))
        NSApp.applicationIconImage = transparentIcon
        print("[+] Helper app initialized successfully.")
    }
    
    private func checkAccessibilityPermission() {
        if AXIsProcessTrusted() {
            setupDockApp()
        } else {
            debugLog("Accessibility permission not authorized yet. Proceeding with fallback debug panel.")
            // Prompt OS native authorization dialog (non-blocking)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            // Setup application immediately with screen-center fallback
            setupDockApp()
            
            // Start non-blocking polling to detect when the user enables it in settings
            startPollingForPermission()
        }
    }
    
    private func startPollingForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.permissionTimer = nil
                debugLog("Accessibility permission granted via System Settings!")
                self?.repositionOverlay()
            }
        }
    }
    
    private func setupDockApp() {
        // Reset the debug log file on startup
        try? FileManager.default.removeItem(atPath: "/Users/uttam/.gemini/antigravity-ide/scratch/scoredock/debug.log")
        debugLog("[AppDelegate] setupDockApp started.")
        
        // 1. Set activation policy to .regular so it registers in the Dock
        NSApp.setActivationPolicy(.regular)
        
        // 2. Set the application icon to a transparent 1x1 image, leaving an empty tile spot
        let transparentIcon = NSImage(size: NSSize(width: 1, height: 1))
        NSApp.applicationIconImage = transparentIcon
        
        // 3. Launch helper applications to allocate additional adjacent tiles (launching 4 helpers for 5 tiles total)
        launchHelpers()
        
        // 4. Initialize the SwiftUI ViewModel
        let viewModel = ScoreViewModel()
        self.scoreViewModel = viewModel
        
        // 5. Create the floating overlay panel
        let panel = FloatingPanel(contentRect: .zero)
        self.overlayPanel = panel
        
        let hostingView = InteractiveHostingView(rootView: ScoreWidgetView(viewModel: viewModel), viewModel: viewModel)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        
        viewModel.onWidgetClicked = { [weak self] in
            self?.toggleHUD()
        }
        
        // Setup native right-click context menu
        setupContextMenu(on: hostingView)
        
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        
        // 7. Set up the Dock Watcher to track repositioning/resizing
        let watcher = DockWatcher()
        watcher.onChange = { [weak self] in
            // Reposition immediately on plist modification, and start temporary high-speed tracking
            // to follow the Dock repositioning/resize layout animations smoothly.
            self?.repositionOverlay()
            self?.startTemporaryTracking()
        }
        self.dockWatcher = watcher
        
        // 8. Start proximity-aware tracking (automatically scales rate between 2Hz and 33Hz based on mouse position)
        startGlobalTracking()
    }
    
    private func setupContextMenu(on view: NSView) {
        let menu = NSMenu(title: "ScoreDock Context Menu")
        menu.delegate = self
        view.menu = menu
    }
    
    @objc private func cycleMatchPressed() {
        MatchCoordinator.shared.cycleNextMatch()
    }
    
    @objc private func pinMatchItemPressed(_ sender: NSMenuItem) {
        if let matchID = sender.representedObject as? String {
            MatchCoordinator.shared.pinMatch(id: matchID)
        } else {
            MatchCoordinator.shared.pinMatch(id: nil)
        }
    }
    
    @objc private func preferencesPressed() {
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "ScoreDock Preferences"
        window.isReleasedWhenClosed = false
        
        let hostingView = NSHostingView(rootView: PreferencesView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 550, height: 450)
        window.contentView = hostingView
        
        self.preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func toggleHUD() {
        guard let panel = self.overlayPanel, let view = panel.contentView, let viewModel = self.scoreViewModel else { return }
        
        if let popover = hudPopover, popover.isShown {
            popover.performClose(nil)
        } else {
            let popover = NSPopover()
            popover.contentSize = NSSize(width: 300, height: 110)
            popover.behavior = .transient
            popover.animates = true
            
            // Apply dark appearance for glassmorphism
            popover.appearance = NSAppearance(named: .vibrantDark)
            
            popover.contentViewController = NSHostingController(rootView: MatchHUDView(viewModel: viewModel))
            
            // Popover appears above the panel relative to the Dock
            let rect = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
            
            // Focus app so the popover transient dismiss behavior works correctly
            NSApp.activate(ignoringOtherApps: true)
            
            self.hudPopover = popover
        }
    }
    
    @objc private func quitPressed() {
        NSApp.terminate(nil)
    }
    
    private func launchHelpers() {
        let helpersDir = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")
        
        // Four helpers + main app = 5 Dock tiles total
        let helperNames = ["ScoreDockHelper1", "ScoreDockHelper2", "ScoreDockHelper3", "ScoreDockHelper4"]
        
        for name in helperNames {
            let helperURL = helpersDir.appendingPathComponent("\(name).app")
            
            if FileManager.default.fileExists(atPath: helperURL.path) {
                print("[*] Launching helper app: \(name)")
                let config = NSWorkspace.OpenConfiguration()
                config.addsToRecentItems = false
                NSWorkspace.shared.openApplication(at: helperURL, configuration: config) { _, error in
                    if let error = error {
                        print("[-] Failed to launch \(name): \(error.localizedDescription)")
                    }
                }
            } else {
                print("[-] Helper app not found at \(helperURL.path)")
            }
        }
    }
    
    private func startGlobalTracking() {
        globalTrackingTimer?.invalidate()
        // Start with a low frequency; the tick loop dynamically updates its own rate
        globalTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tickTracking()
        }
    }
    
    private func tickTracking() {
        let appNames = ["ScoreDock", "ScoreDockHelper1", "ScoreDockHelper2", "ScoreDockHelper3", "ScoreDockHelper4"]
        if let info = DockTileDetector.getDockFrameInfo(forAppNames: appNames) {
            let mouseLoc = NSEvent.mouseLocation // screen coordinates, bottom-left origin
            let barFrame = info.dockBarFrame
            
            // Expand the Dock bar frame by 100px on all sides to detect mouse proximity
            let expandedBar = barFrame.insetBy(dx: -100, dy: -100)
            let isNear = expandedBar.contains(mouseLoc)
            
            // Sync the overlay frame to the current real-time coordinates
            repositionOverlay(with: info)
            
            // Switch between fast 33Hz polling (when near the Dock) and passive 2Hz polling (when away)
            let desiredInterval = isNear ? 0.03 : 0.5
            if let currentTimer = globalTrackingTimer, abs(currentTimer.timeInterval - desiredInterval) > 0.01 {
                currentTimer.invalidate()
                globalTrackingTimer = Timer.scheduledTimer(withTimeInterval: desiredInterval, repeats: true) { [weak self] _ in
                    self?.tickTracking()
                }
            }
        } else {
            // Debug fallback: place the panel at a fixed center location of the screen
            // so we can test click/right-click delivery even without Accessibility permission.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let panel = self.overlayPanel else { return }
                let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
                let panelFrame = CGRect(x: (screenFrame.width - 240) / 2, y: 100, width: 240, height: 60)
                
                // Publish debug states to view
                self.scoreViewModel?.isHorizontal = true
                self.scoreViewModel?.containerWidth = 240
                
                if panel.frame != panelFrame {
                    panel.setFrame(panelFrame, display: true, animate: false)
                    debugLog("Positioned fallback debug panel at \(panelFrame) (Accessibility not trusted yet).")
                }
            }
        }
    }
    
    private func startTemporaryTracking() {
        temporaryTrackingStopDate = Date().addingTimeInterval(2.0) // Track at 33Hz for 2 seconds
        if temporaryTrackingTimer == nil {
            temporaryTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                self?.repositionOverlay()
                
                // Stop tracking once cooldown has expired
                if let self = self, let stopDate = self.temporaryTrackingStopDate, Date() > stopDate {
                    self.stopTemporaryTracking()
                }
            }
        }
    }
    
    private func stopTemporaryTracking() {
        temporaryTrackingTimer?.invalidate()
        temporaryTrackingTimer = nil
        temporaryTrackingStopDate = nil
        repositionOverlay()
    }
    
    private func repositionOverlay(with info: DockFrameInfo) {
        let tileFrame = info.spannedTileFrame
        let barFrame = info.dockBarFrame
        
        // Guard against unreasonably small/dummy coordinate states
        guard tileFrame.width > 20, tileFrame.height > 20, barFrame.width > 20, barFrame.height > 20 else { return }
        
        var panelFrame: CGRect
        
        // Publish orientation state to SwiftUI ScoreWidgetView
        if scoreViewModel?.isHorizontal != info.isHorizontal {
            DispatchQueue.main.async { [weak self] in
                self?.scoreViewModel?.isHorizontal = info.isHorizontal
            }
        }
        
        // Publish available container width to SwiftUI ScoreWidgetView
        if scoreViewModel?.containerWidth != tileFrame.width {
            DispatchQueue.main.async { [weak self] in
                self?.scoreViewModel?.containerWidth = tileFrame.width
            }
        }
        
        if info.isHorizontal {
            // Horizontal Dock: Panel takes full height of Dock bar to prevent clipping during hover scaling,
            // and spans horizontally across all 5 transparent tiles.
            panelFrame = CGRect(x: tileFrame.minX, y: barFrame.minY, width: tileFrame.width, height: barFrame.height)
        } else {
            // Vertical Dock: Panel takes full width of Dock bar and spans vertically across all 5 transparent tiles.
            panelFrame = CGRect(x: barFrame.minX, y: tileFrame.minY, width: barFrame.width, height: tileFrame.height)
        }
        
        // Final sanity checks to prevent app crash with invalid CGRect parameters on NSWindow setFrame
        guard !panelFrame.isNull, !panelFrame.isInfinite, panelFrame.width > 10, panelFrame.height > 10 else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let panel = self.overlayPanel else { return }
            if panel.frame != panelFrame {
                panel.setFrame(panelFrame, display: true, animate: false)
            }
        }
    }
    
    private func repositionOverlay() {
        let appNames = ["ScoreDock", "ScoreDockHelper1", "ScoreDockHelper2", "ScoreDockHelper3", "ScoreDockHelper4"]
        if let info = DockTileDetector.getDockFrameInfo(forAppNames: appNames) {
            repositionOverlay(with: info)
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        globalTrackingTimer?.invalidate()
        temporaryTrackingTimer?.invalidate()
        
        // Main app terminates helpers upon exiting
        if !isHelper {
            terminateHelpers()
        }
    }
    
    private func terminateHelpers() {
        let helperIdentifiers = ["com.uttam.scoredock.helper1", "com.uttam.scoredock.helper2", "com.uttam.scoredock.helper3", "com.uttam.scoredock.helper4"]
        for identifier in helperIdentifiers {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            for app in runningApps {
                app.forceTerminate()
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "Pin Match" {
            menu.removeAllItems()
            
            // 1. None (Auto-cycle)
            let noneItem = NSMenuItem(title: "None (Auto-cycle)", action: #selector(pinMatchItemPressed(_:)), keyEquivalent: "")
            noneItem.target = self
            noneItem.representedObject = nil
            noneItem.state = MatchCoordinator.shared.pinnedMatchID == nil ? .on : .off
            menu.addItem(noneItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 2. Only show matches from favorite teams/tournaments
            let allMatches = MatchCoordinator.shared.matches
            let favoriteMatches = allMatches.filter { MatchCoordinator.shared.isFavorite($0) }
            
            // Fall back: if no favorites matched, show live matches; if none, show all
            let displayMatches: [MatchState]
            if !favoriteMatches.isEmpty {
                displayMatches = favoriteMatches
            } else {
                let liveMatches = allMatches.filter { $0.isLive }
                displayMatches = liveMatches.isEmpty ? allMatches : liveMatches
            }
            
            if displayMatches.isEmpty {
                let emptyItem = NSMenuItem(title: "No matches available", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            } else {
                for match in displayMatches {
                    let liveTag = match.isLive ? " 🔴" : ""
                    let title = "\(match.teamAFlag) \(match.teamA) vs \(match.teamB) \(match.teamBFlag)  ·  \(match.tournament)\(liveTag)"
                    let item = NSMenuItem(title: title, action: #selector(pinMatchItemPressed(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = match.id
                    item.state = MatchCoordinator.shared.pinnedMatchID == match.id ? .on : .off
                    menu.addItem(item)
                }
            }
        } else if menu.title == "ScoreDock Context Menu" {
            menu.removeAllItems()
            
            // 1. Live status indicator
            let statusText: String
            switch MatchCoordinator.shared.providerStatus {
            case .healthy:
                statusText = MatchCoordinator.shared.useRealAPIs ? "🟢 Live" : "🟢 Simulation Mode"
            case .degraded:
                statusText = "🟡 Live (Degraded/Cached)"
            case .failed:
                statusText = "🔴 Offline/Failed"
            }
            
            let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 2. Cycle Match
            let cycleItem = NSMenuItem(title: "🔄 Cycle Match", action: #selector(cycleMatchPressed), keyEquivalent: "")
            cycleItem.target = self
            menu.addItem(cycleItem)
            
            // 3. Pin Match Submenu
            let pinMenuItem = NSMenuItem(title: "📌 Pin Match", action: nil, keyEquivalent: "")
            let pinMenu = NSMenu(title: "Pin Match")
            pinMenu.delegate = self
            pinMenuItem.submenu = pinMenu
            menu.addItem(pinMenuItem)
            self.pinSubmenu = pinMenu
            
            menu.addItem(NSMenuItem.separator())
            
            // 4. Favorites & Settings
            let prefsItem = NSMenuItem(title: "⭐️ Favorites & Settings...", action: #selector(preferencesPressed), keyEquivalent: ",")
            prefsItem.target = self
            menu.addItem(prefsItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 5. Quit
            let quitItem = NSMenuItem(title: "❌ Quit ScoreDock", action: #selector(quitPressed), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
        }
    }
}

// MARK: - Interactive Hosting View for Event Delivery Debugging

public final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    private let viewModel: ScoreViewModel
    
    public init(rootView: Content, viewModel: ScoreViewModel) {
        self.viewModel = viewModel
        super.init(rootView: rootView)
    }
    
    @MainActor required public init(rootView: Content) {
        fatalError("Use init(rootView:viewModel:) instead")
    }
    
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let cardWidth = viewModel.estimatedCardWidth
        let xMin = (bounds.width - cardWidth) / 2
        let activeRect = viewModel.isHorizontal 
            ? CGRect(x: xMin, y: 0, width: cardWidth, height: bounds.height)
            : bounds
        
        guard activeRect.contains(point) else {
            return nil
        }
        
        // Let NSHostingView's internal SwiftUI hierarchy do the fine-grained hit testing,
        // but if it returns nil (due to transparent space or materials), we return `self`
        // to guarantee that the click is captured.
        if let hitView = super.hitTest(point) {
            return hitView
        }
        
        return self
    }
    
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    private func logResponderChain(for responder: NSResponder) {
        var r: NSResponder? = responder
        var chain = ""
        while let current = r {
            chain += "\(type(of: current)) -> "
            r = current.nextResponder
        }
        debugLog("[Responder Chain] \(chain)nil")
    }
    
    public override func mouseDown(with event: NSEvent) {
        debugLog("NSHostingView mouseDown event: \(event)")
        logResponderChain(for: self)
        
        if event.modifierFlags.contains(.control) {
            // Translate Control-Click to right-click context menu popup
            debugLog("NSHostingView mouseDown (control-click) -> showing context menu")
            if let menu = self.menu {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return
            }
        }
        
        super.mouseDown(with: event)
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        debugLog("NSHostingView rightMouseDown event: \(event)")
        logResponderChain(for: self)
        
        if let menu = self.menu {
            debugLog("NSHostingView rightMouseDown -> showing context menu")
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            debugLog("NSHostingView rightMouseDown -> no menu set")
            super.rightMouseDown(with: event)
        }
    }
    
    public override func menu(for event: NSEvent) -> NSMenu? {
        let m = super.menu(for: event)
        debugLog("NSHostingView menu(for:) -> \(String(describing: m))")
        return m
    }
}

// MARK: - Global Debug Logging Utility

public func debugLog(_ message: String) {
    let logMessage = "[\(Date())] \(message)\n"
    if let data = logMessage.data(using: .utf8) {
        let logURL = URL(fileURLWithPath: "/Users/uttam/.gemini/antigravity-ide/scratch/scoredock/debug.log")
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? logMessage.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
    print(message)
}
