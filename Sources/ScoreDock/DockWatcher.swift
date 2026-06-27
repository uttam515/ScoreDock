import Foundation
import AppKit

public final class DockWatcher {
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let plistPath: String
    
    /// The closure invoked when a Dock configuration or screen layout change is detected.
    public var onChange: (() -> Void)?
    
    public init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.plistPath = homeDir.appendingPathComponent("Library/Preferences/com.apple.dock.plist").path
        
        setupWorkspaceNotifications()
        startWatchingPlist()
    }
    
    private func setupWorkspaceNotifications() {
        // Register for screen changes (resolution, dock position moves, dock show/hide)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func handleScreenParametersChanged() {
        print("[*] Screen parameters changed (Dock resize, reposition, or display update)")
        // Trigger coordinate update
        onChange?()
    }
    
    private func startWatchingPlist() {
        // Clean up any existing watcher state
        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        dispatchSource?.cancel()
        
        // Open file with O_EVTONLY to avoid locking it
        fileDescriptor = open(plistPath, O_EVTONLY)
        guard fileDescriptor != -1 else {
            print("[-] Failed to open com.apple.dock.plist for watching. It may not exist yet.")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            print("[*] com.apple.dock.plist filesystem change detected")
            
            // Invoke callback
            self.onChange?()
            
            let data = source.data
            // If the file is deleted or renamed, the current fd will no longer track it.
            // We must wait a brief duration for the atomic save to finish, then re-initialize the watcher.
            if data.contains(.delete) || data.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.startWatchingPlist()
                }
            }
        }
        
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }
        
        self.dispatchSource = source
        source.resume()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        dispatchSource?.cancel()
    }
}
