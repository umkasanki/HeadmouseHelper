// CursorProbe.swift — measures how far the system cursor travels over a window
// of time. Used to confirm the HeadMouse moves the cursor while tracking is ON
// (no seize). Needs no special permission — reads the cursor via CGEvent.
//
//   swiftc spike/CursorProbe.swift -o spike/cursor-probe
//   ./spike/cursor-probe [seconds]     # default 5

import CoreGraphics
import Foundation

func systemCursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
func log(_ s: String) { print(s); fflush(stdout) }

let seconds: Double = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 5) : 5

let start = systemCursor()
var minX = start.x, maxX = start.x, minY = start.y, maxY = start.y
var samples = 0

let sampler = Timer(timeInterval: 0.02, repeats: true) { _ in
    let p = systemCursor()
    minX = min(minX, p.x); maxX = max(maxX, p.x)
    minY = min(minY, p.y); maxY = max(maxY, p.y)
    samples += 1
}
RunLoop.current.add(sampler, forMode: .default)
let stopper = Timer(timeInterval: seconds, repeats: false) { _ in CFRunLoopStop(CFRunLoopGetCurrent()) }
RunLoop.current.add(stopper, forMode: .default)
CFRunLoopRun()

let dx = maxX - minX, dy = maxY - minY, total = dx + dy
log("cursor excursion over \(Int(seconds))s: x=\(Int(dx)) y=\(Int(dy)) total=\(Int(total)) px  (\(samples) samples)")
if total > 50 {
    log("✅ Cursor IS moving — HeadMouse controls the pointer.")
} else {
    log("❌ Cursor barely moved (\(Int(total))px) — pointer did not respond.")
}
