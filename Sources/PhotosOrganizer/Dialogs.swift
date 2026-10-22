import AppKit

/// Modal AppKit panels. SwiftUI alerts can't make *No* the default button, which delete needs.
@MainActor
enum Dialogs {
    static func chooseFolder(title: String, startingAt start: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = start ?? FileManager.default.homeDirectoryForCurrentUser
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func show(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        alert.runModal()
    }

    /// Yes/No question. With `defaultNo`, pressing Return answers *No*.
    static func confirm(_ title: String, _ text: String, style: NSAlert.Style = .warning, defaultNo: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        let yes = alert.addButton(withTitle: "Yes")
        let no = alert.addButton(withTitle: "No")
        no.keyEquivalent = "\u{1b}"  // Escape
        if defaultNo {
            yes.keyEquivalent = ""
            no.keyEquivalent = "\r"
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
