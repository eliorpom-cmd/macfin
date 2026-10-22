import CoreGraphics
import Foundation

// Prints the ID of the largest normal window owned by a process, for `screencapture -l`.
// Usage: window-id <pid>
guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-id <pid>\n".utf8))
    exit(2)
}
let windows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    .compactMap { info -> (id: Int, area: Double)? in
        guard let id = info[kCGWindowNumber as String] as? Int,
              let bounds = info[kCGWindowBounds as String] as? [String: Double] else { return nil }
        return (id, (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0))
    }
guard let largest = windows.max(by: { $0.area < $1.area }), largest.area > 0 else { exit(1) }
print(largest.id)
