import AppKit

enum SysOpen {
    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
    static func openTerminal(at path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", path]
        try? proc.run()
    }
    static func openRemote(_ remote: String) {
        var url = remote
        if url.hasPrefix("git@") {
            url = url.replacingOccurrences(of: ":", with: "/")
                .replacingOccurrences(of: "git@", with: "https://")
        }
        url = url.replacingOccurrences(of: ".git", with: "")
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
