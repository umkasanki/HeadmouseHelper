// SeizeSpike.swift — Phase 0 spike for HeadmouseHelper.
//
// Goal: prove that we can "disable" the HeadMouse Nano without unplugging it,
// by exclusively seizing its HID device via IOHIDManager. While seized, the
// window server no longer receives its pointer reports, so the cursor freezes.
// Other mice / the trackpad are untouched (we match only this VID/PID).
//
// Build & run on the Mac:
//   swiftc spike/SeizeSpike.swift -o spike/seize-spike
//   ./spike/seize-spike [holdSeconds]      # default 15
//
// Needs "Input Monitoring" permission for the running binary (macOS 10.15+).
// If seize returns kIOReturnNotPermitted, grant it in
//   System Settings → Privacy & Security → Input Monitoring
// for this binary (or the terminal running it), then re-run.

import Foundation
import IOKit
import IOKit.hid

let TARGET_VID = 0x0A95 // Origin Instruments Corp.
let TARGET_PID = 0x0003 // HeadMouse Nano

func prop(_ d: IOHIDDevice, _ k: String) -> Any? { IOHIDDeviceGetProperty(d, k as CFString) }
func intProp(_ d: IOHIDDevice, _ k: String) -> Int? { (prop(d, k) as? NSNumber)?.intValue }
func strProp(_ d: IOHIDDevice, _ k: String) -> String? { prop(d, k) as? String }
func log(_ s: String) { print(s); fflush(stdout) }

let holdSeconds: Double = CommandLine.arguments.count > 1
    ? (Double(CommandLine.arguments[1]) ?? 15)
    : 15

// Swallow all reports coming from the seized device; count them so we can prove
// events are flowing to *us* and not to the system.
var swallowedEvents = 0

// ---- 1. Enumerate mouse-like HID devices ----
let listManager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(listManager, [
    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
] as CFDictionary)

let listOpen = IOHIDManagerOpen(listManager, 0)
guard listOpen == kIOReturnSuccess else {
    log("Failed to open list manager: \(String(format: "0x%08X", listOpen))")
    exit(1)
}

let devices = Array((IOHIDManagerCopyDevices(listManager) as? Set<IOHIDDevice>) ?? [])
log("Mouse-like HID devices (\(devices.count)):")
var target: IOHIDDevice?
for d in devices {
    let vid = intProp(d, kIOHIDVendorIDKey) ?? 0
    let pid = intProp(d, kIOHIDProductIDKey) ?? 0
    let name = strProp(d, kIOHIDProductKey) ?? "(unknown)"
    let isTarget = (vid == TARGET_VID && pid == TARGET_PID)
    log(String(format: "  %-24@ VID=0x%04X PID=0x%04X%@",
               name as NSString, vid, pid, isTarget ? "   <-- TARGET" : ""))
    if isTarget { target = d }
}

guard target != nil else {
    log("\nHeadMouse Nano (VID 0x\(String(TARGET_VID, radix: 16)) / PID 0x\(String(TARGET_PID, radix: 16))) not found. Is it plugged in?")
    exit(1)
}
IOHIDManagerClose(listManager, 0)

// ---- 2. Seize only the target device ----
let seizeManager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(seizeManager, [
    kIOHIDVendorIDKey: TARGET_VID,
    kIOHIDProductIDKey: TARGET_PID,
] as CFDictionary)

let inputCallback: IOHIDValueCallback = { _, _, _, _ in
    swallowedEvents += 1
}
IOHIDManagerRegisterInputValueCallback(seizeManager, inputCallback, nil)
IOHIDManagerScheduleWithRunLoop(seizeManager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let seizeResult = IOHIDManagerOpen(seizeManager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
if seizeResult == kIOReturnNotPermitted {
    log("\n❌ SEIZE DENIED (kIOReturnNotPermitted / 0xE00002E2).")
    log("   Grant Input Monitoring to this binary in")
    log("   System Settings → Privacy & Security → Input Monitoring, then re-run.")
    exit(2)
}
guard seizeResult == kIOReturnSuccess else {
    log("\n❌ SEIZE FAILED: \(String(format: "0x%08X", seizeResult))")
    exit(3)
}

log("")
log("✅ SEIZED HeadMouse Nano. Holding for \(Int(holdSeconds))s.")
log("   → NOW move the HeadMouse: the cursor should NOT move.")
log("   → Your trackpad / regular mouse should still work.")
log("")

let releaseTimer = Timer(timeInterval: holdSeconds, repeats: false) { _ in
    log("Releasing seize. Reports swallowed while seized: \(swallowedEvents)")
    IOHIDManagerClose(seizeManager, 0)
    CFRunLoopStop(CFRunLoopGetCurrent())
}
RunLoop.current.add(releaseTimer, forMode: .default)
CFRunLoopRun()
log("Done — device released, cursor control restored.")
