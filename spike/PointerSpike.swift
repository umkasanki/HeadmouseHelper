// PointerSpike.swift — validates setting per-device pointer resolution (speed)
// and acceleration on the HeadMouse via the private IOHIDEventSystemClient API,
// the way LinearMouse does. Lower resolution = faster pointer (~[10, 1995]).
//
//   swiftc spike/PointerSpike.swift -import-objc-header spike/IOKitSPI.h -o spike/pointer-spike
//   ./spike/pointer-spike               # print current pointer properties
//   ./spike/pointer-spike 400           # set resolution 400 (slower), poke accel to apply
//   ./spike/pointer-spike 400 -1        # + disable acceleration
//   ./spike/pointer-spike 400 20        # + acceleration 20

import Foundation
import IOKit
import IOKit.hid

let TARGET_VID = 0x0A95
let TARGET_PID = 0x0003

let targetResolution: Double? = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) : nil
let targetAccel: Double? = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) : nil

guard let systemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
    print("Failed to create IOHIDEventSystemClient"); exit(1)
}
guard let services = IOHIDEventSystemClientCopyServices(systemClient) as? [IOHIDServiceClient] else {
    print("No HID service clients"); exit(1)
}

func copyProp(_ s: IOHIDServiceClient, _ key: String) -> Any? {
    IOHIDServiceClientCopyProperty(s, key as CFString)
}
func intProp(_ s: IOHIDServiceClient, _ key: String) -> Int? { (copyProp(s, key) as? NSNumber)?.intValue }
func fixedProp(_ s: IOHIDServiceClient, _ key: String) -> Double? { intProp(s, key).map { Double($0) / 65_536 } }
@discardableResult
func setFixed(_ s: IOHIDServiceClient, _ key: String, _ value: Double) -> Bool {
    IOHIDServiceClientSetProperty(s, key as CFString, NSNumber(value: Int32(value * 65_536)))
}

// Which key holds the acceleration value (LinearMouse's logic).
func accelType(_ s: IOHIDServiceClient) -> String {
    if let t = copyProp(s, kIOHIDPointerAccelerationTypeKey) as? String { return t }
    if copyProp(s, kIOHIDPointerAccelerationKey) != nil { return kIOHIDPointerAccelerationKey }
    return kIOHIDMouseAccelerationTypeKey
}

var matched = 0
for s in services where intProp(s, kIOHIDVendorIDKey) == TARGET_VID && intProp(s, kIOHIDProductIDKey) == TARGET_PID {
    matched += 1
    let type = accelType(s)
    print("HeadMouse service client:")
    print("  resolution        = \(fixedProp(s, kIOHIDPointerResolutionKey).map { String($0) } ?? "nil")")
    print("  accelerationType  = \(type)")
    print("  acceleration      = \(fixedProp(s, type).map { String($0) } ?? "nil")")

    if let r = targetResolution {
        setFixed(s, kIOHIDPointerResolutionKey, r.clamped(10, 1995))
        // HACK (from LinearMouse): re-poke acceleration so resolution takes effect.
        if let a = targetAccel {
            setFixed(s, type, a == -1 ? -1 : a.clamped(0, 40))
        } else if let a = fixedProp(s, type) {
            setFixed(s, type, a)
        }
        print("  -> set resolution=\(r)\(targetAccel.map { ", acceleration=\($0)" } ?? "")")
        print("  now resolution    = \(fixedProp(s, kIOHIDPointerResolutionKey).map { String($0) } ?? "nil")")
    }
}

extension Double { func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) } }

if matched == 0 {
    print("No HeadMouse service client (connected? tracking ON, not seized?)"); exit(1)
}
print("Done (\(matched) matched).")
