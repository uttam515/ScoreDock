import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Start AppKit Run Loop
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
