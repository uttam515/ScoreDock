import AppKit

public final class FloatingPanel: NSPanel {
    
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .statusBar // Float above standard windows and native Dock icons
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false // Allow clicking for match interaction / status cycles
        
        // Ensure the overlay persists across spaces and behaves correctly in full screen
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]
        
        // Subtly ensure it doesn't try to draw any window borders or titlebars
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        
        debugLog("[FloatingPanel] Initialized panel. ignoresMouseEvents = \(self.ignoresMouseEvents)")
    }
    
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .leftMouseUp || event.type == .rightMouseUp {
            debugLog("[FloatingPanel] sendEvent: type = \(event.type), locationInWindow = \(event.locationInWindow)")
        }
        super.sendEvent(event)
    }
    
    // Non-activating panel requirements
    public override var canBecomeKey: Bool {
        return false
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
}
