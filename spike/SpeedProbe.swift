// SpeedProbe.swift — measures effective pointer speed over a window: raw device
// movement (sum of |dx|+|dy| from the HeadMouse) AND system-cursor excursion,
// and their ratio (cursor px per unit of device movement). The ratio normalizes
// for how much the user actually moved their head, so different resolution
// settings can be compared fairly.
//
//   swiftc spike/SpeedProbe.swift -o spike/speed-probe
//   ./spike/speed-probe [seconds]     # default 5

import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

let TARGET_VID = 0x0A95
let TARGET_PID = 0x0003
let seconds: Double = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 5) : 5

var deviceMovement = 0
let callback: IOHIDValueCallback = { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    if usagePage == UInt32(kHIDPage_GenericDesktop),
       usage == UInt32(kHIDUsage_GD_X) || usage == UInt32(kHIDUsage_GD_Y) {
        deviceMovement += abs(IOHIDValueGetIntegerValue(value))
    }
}

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(mgr, [
    kIOHIDVendorIDKey: TARGET_VID, kIOHIDProductIDKey: TARGET_PID,
] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(mgr, callback, nil)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
guard IOHIDManagerOpen(mgr, 0) == kIOReturnSuccess else {
    print("Failed to open device for listening (Input Monitoring?)"); exit(1)
}

func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
let start = cursor()
var minX = start.x, maxX = start.x, minY = start.y, maxY = start.y
let sampler = Timer(timeInterval: 0.02, repeats: true) { _ in
    let p = cursor()
    minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
}
RunLoop.current.add(sampler, forMode: .default)
let stopper = Timer(timeInterval: seconds, repeats: false) { _ in CFRunLoopStop(CFRunLoopGetCurrent()) }
RunLoop.current.add(stopper, forMode: .default)
CFRunLoopRun()

let excursion = max(0, (maxX - minX) + (maxY - minY))
let ratio = deviceMovement > 0 ? excursion / Double(deviceMovement) : 0
print(String(format: "device=%d  cursor=%.0f px  ratio=%.3f px/unit", deviceMovement, excursion, ratio))
