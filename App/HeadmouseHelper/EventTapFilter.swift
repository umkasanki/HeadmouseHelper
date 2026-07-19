import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import HeadmouseCore

/// Tremor stabilization via a CGEventTap: intercepts mouse-move/drag events, runs
/// their deltas through TremorFilter, and repositions the cursor along the
/// smoothed path. Requires Accessibility permission (to modify events).
final class EventTapFilter {
    private let filter = TremorFilter()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastLocation: CGPoint?
    private var lastTime: TimeInterval = 0

    /// Apply the current tremor settings: (re)configure the filter and start or
    /// stop the tap. Safe to call repeatedly.
    func update(_ settings: TremorSettings) {
        filter.configure(settings)
        if settings.enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard tap == nil else { return }

        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            NSLog("HeadmouseHelper: Accessibility not granted — grant it, then re-enable stabilization.")
            return
        }

        let mask = CGEventMask(
            (1 << CGEventType.mouseMoved.rawValue) |
                (1 << CGEventType.leftMouseDragged.rawValue) |
                (1 << CGEventType.rightMouseDragged.rawValue) |
                (1 << CGEventType.otherMouseDragged.rawValue)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Self.callback, userInfo: refcon
        ) else {
            NSLog("HeadmouseHelper: failed to create event tap")
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        filter.reset()
        lastLocation = nil
        lastTime = 0
    }

    private func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.tap = nil
        runLoopSource = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<EventTapFilter>.fromOpaque(refcon).takeUnretainedValue()
        return me.handle(type, event)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap on timeout / user input; just re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = event.getDoubleValueField(.mouseEventDeltaY)

        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTime > 0 ? min(max(now - lastTime, 0.001), 0.05) : 0.008
        lastTime = now

        let step = filter.process(dx: dx, dy: dy, dt: dt)

        // Reposition the cursor along the smoothed path (editing deltas alone does
        // not move it — the location field does).
        let base = lastLocation ?? CGPoint(x: event.location.x - dx, y: event.location.y - dy)
        let loc = clampToMainDisplay(CGPoint(x: base.x + step.dx, y: base.y + step.dy))
        lastLocation = loc

        event.location = loc
        event.setDoubleValueField(.mouseEventDeltaX, value: step.dx)
        event.setDoubleValueField(.mouseEventDeltaY, value: step.dy)
        return Unmanaged.passUnretained(event)
    }

    private func clampToMainDisplay(_ point: CGPoint) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX - 1),
            y: min(max(point.y, bounds.minY), bounds.maxY - 1)
        )
    }
}
