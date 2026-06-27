import AppKit
import ApplicationServices

public struct DockFrameInfo {
    public var spannedTileFrame: CGRect
    public var dockBarFrame: CGRect
    public var isHorizontal: Bool
}

public struct DockTileDetector {
    /// Attempts to find the combined union frame of the Dock tiles and the parent Dock bar frame.
    /// The coordinates returned are in AppKit window coordinates (bottom-left of primary screen is 0,0).
    public static func getDockFrameInfo(forAppNames appNames: [String]) -> DockFrameInfo? {
        let dockApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        guard let dockPID = dockApps.first?.processIdentifier else {
            print("[-] Could not find running Dock application process.")
            return nil
        }
        
        let dockElement = AXUIElementCreateApplication(dockPID)
        
        var tileElements: [AXUIElement] = []
        var frames: [CGRect] = []
        for name in appNames {
            if let tileElement = findElement(in: dockElement, matchingTitle: name) {
                tileElements.append(tileElement)
                if let frame = getElementFrame(tileElement) {
                    frames.append(frame)
                }
            }
        }
        
        guard !frames.isEmpty, let firstTile = tileElements.first else {
            return nil
        }
        
        // Find parent Dock bar (AXList)
        var parentRef: CFTypeRef?
        let parentStatus = AXUIElementCopyAttributeValue(firstTile, kAXParentAttribute as CFString, &parentRef)
        guard parentStatus == .success, let parentElement = parentRef else {
            print("[-] Could not find parent Dock bar element.")
            return nil
        }
        
        guard let barFrame = getElementFrame(parentElement as! AXUIElement) else {
            print("[-] Could not get parent Dock bar frame.")
            return nil
        }
        
        // Calculate the bounding box (union) of all found tiles
        var unionFrame = frames[0]
        for i in 1..<frames.count {
            unionFrame = unionFrame.union(frames[i])
        }
        
        let isHorizontal = barFrame.width >= barFrame.height
        
        return DockFrameInfo(
            spannedTileFrame: unionFrame,
            dockBarFrame: barFrame,
            isHorizontal: isHorizontal
        )
    }
    
    private static func findElement(in element: AXUIElement, matchingTitle targetTitle: String) -> AXUIElement? {
        // Check if this element matches the title
        var titleRef: CFTypeRef?
        let titleStatus = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        if titleStatus == .success, let title = titleRef as? String {
            if title == targetTitle {
                return element
            }
        }
        
        // Query children recursively
        var childrenRef: CFTypeRef?
        let childrenStatus = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if childrenStatus == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findElement(in: child, matchingTitle: targetTitle) {
                    return found
                }
            }
        }
        
        return nil
    }
    
    private static func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        let positionStatus = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        
        var sizeRef: CFTypeRef?
        let sizeStatus = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        
        guard positionStatus == .success, sizeStatus == .success,
              let positionVal = positionRef, let sizeVal = sizeRef else {
            return nil
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        AXValueGetValue(positionVal as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        
        // Safety guard against zero or invalid sizes (e.g. while icon is rendering)
        guard size.width > 10, size.height > 10 else {
            return nil
        }
        
        // Convert from Accessibility coordinates (top-left of screen is 0,0)
        // to AppKit coordinates (bottom-left of screen is 0,0).
        guard let primaryScreen = NSScreen.screens.first else {
            return CGRect(origin: position, size: size) // fallback
        }
        
        let screenHeight = primaryScreen.frame.height
        let appKitY = screenHeight - position.y - size.height
        
        return CGRect(x: position.x, y: appKitY, width: size.width, height: size.height)
    }
}
