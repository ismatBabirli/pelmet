import AppKit

// AppKit lifecycle entry point.
// Works when run via `swift run` AND inside a proper .app bundle.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
