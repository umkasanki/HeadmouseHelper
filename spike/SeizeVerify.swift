// SeizeVerify.swift — self-verifying Phase 0 spike for HeadmouseHelper.
//
// The user watches the Mac via RustDesk, which itself moves the Mac cursor, so
// both a visual check and a naive "did the cursor move?" check are confounded by
// RustDesk noise. This runs three phases to isolate the signal:
//
//   Phase 1  SEIZED  + STAY STILL     → RustDesk/idle noise floor.
//   Phase 2  SEIZED  + MOVE HEAD      → if cursor excursion ≈ phase 1 while the
//                                       device is active, seize is blocking.
//   Phase 3  UNSEIZED + MOVE HEAD     → positive control: what "head drives the
//                                       cursor" looks like.
//
// Build & run on the Mac:
//   swiftc spike/SeizeVerify.swift -o spike/seize-verify
//   ./spike/seize-verify

import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

let TARGET_VID = 0x0A95 // Origin Instruments Corp.
let TARGET_PID = 0x0003 // HeadMouse Nano

func log(_ s: String) { print(s); fflush(stdout) }
func systemCursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

// Mutated from the C-convention HID callback (globals are allowed there).
var reportCount = 0
var deviceMovement = 0 // sum of |dx| + |dy| from relative X/Y reports

let hidCallback: IOHIDValueCallback = { _, _, _, value in
    reportCount += 1
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    if usagePage == UInt32(kHIDPage_GenericDesktop),
       usage == UInt32(kHIDUsage_GD_X) || usage == UInt32(kHIDUsage_GD_Y) {
        deviceMovement += abs(IOHIDValueGetIntegerValue(value))
    }
}

func countdown(_ label: String) {
    log(label)
    for n in stride(from: 3, through: 1, by: -1) {
        log("  starting in \(n)…")
        Thread.sleep(forTimeInterval: 1)
    }
    log("  GO (6s)")
}

func measure(seize: Bool, seconds: Double) -> (reports: Int, deviceMove: Int, cursorExcursion: Double, opened: Bool) {
    reportCount = 0
    deviceMovement = 0

    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    IOHIDManagerSetDeviceMatching(mgr, [
        kIOHIDVendorIDKey: TARGET_VID,
        kIOHIDProductIDKey: TARGET_PID,
    ] as CFDictionary)
    IOHIDManagerRegisterInputValueCallback(mgr, hidCallback, nil)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

    let opt: IOOptionBits = seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0
    let openResult = IOHIDManagerOpen(mgr, opt)
    guard openResult == kIOReturnSuccess else {
        log("  open failed (seize=\(seize)): \(String(format: "0x%08X", openResult))")
        return (0, 0, 0, false)
    }

    var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
    let sampler = Timer(timeInterval: 0.03, repeats: true) { _ in
        let p = systemCursor()
        minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
        minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
    }
    RunLoop.current.add(sampler, forMode: .default)
    let stopper = Timer(timeInterval: seconds, repeats: false) { _ in CFRunLoopStop(CFRunLoopGetCurrent()) }
    RunLoop.current.add(stopper, forMode: .default)
    CFRunLoopRun()

    sampler.invalidate()
    IOHIDManagerClose(mgr, opt)
    let excursion = max(0, (maxX - minX) + (maxY - minY))
    return (reportCount, deviceMovement, excursion, true)
}

// ---- Ensure the device is present ----
let listManager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(listManager, [
    kIOHIDVendorIDKey: TARGET_VID,
    kIOHIDProductIDKey: TARGET_PID,
] as CFDictionary)
IOHIDManagerOpen(listManager, 0)
let found = (IOHIDManagerCopyDevices(listManager) as? Set<IOHIDDevice>)?.isEmpty == false
IOHIDManagerClose(listManager, 0)
guard found else {
    log("HeadMouse Nano not found. Is it plugged in?")
    exit(1)
}

countdown("PHASE 1 — SEIZED + STAY COMPLETELY STILL (head AND hands).")
let p1 = measure(seize: true, seconds: 6)
log(String(format: "  reports=%d deviceMovement=%d cursorExcursion=%.1f px\n", p1.reports, p1.deviceMove, p1.cursorExcursion))

countdown("PHASE 2 — SEIZED + MOVE YOUR HEAD (don't touch the Windows mouse).")
let p2 = measure(seize: true, seconds: 6)
log(String(format: "  reports=%d deviceMovement=%d cursorExcursion=%.1f px\n", p2.reports, p2.deviceMove, p2.cursorExcursion))

countdown("PHASE 3 — NOT seized + MOVE YOUR HEAD (positive control).")
let p3 = measure(seize: false, seconds: 6)
log(String(format: "  reports=%d deviceMovement=%d cursorExcursion=%.1f px\n", p3.reports, p3.deviceMove, p3.cursorExcursion))

log("--- VERDICT ---")
log(String(format: "noise floor (p1) = %.1f px | seized+move (p2) = %.1f px | unseized+move (p3) = %.1f px",
           p1.cursorExcursion, p2.cursorExcursion, p3.cursorExcursion))
if p2.deviceMove < 20 || p3.deviceMove < 20 {
    log("⚠️  Inconclusive: not enough head movement (p2=\(p2.deviceMove), p3=\(p3.deviceMove)). Re-run and move more.")
} else if p2.cursorExcursion <= p1.cursorExcursion * 2 && p3.cursorExcursion > p1.cursorExcursion * 3 {
    log("✅ SEIZE WORKS: moving the head barely changed the cursor while seized (p2≈p1),")
    log("   but clearly moved it when unseized (p3≫p1). Head events are blocked by seize.")
} else if p2.cursorExcursion > p1.cursorExcursion * 3 {
    log("❌ Seize did NOT block: head movement still drove the cursor while seized.")
} else {
    log("🤔 Ambiguous — numbers below, needs a human read.")
}
