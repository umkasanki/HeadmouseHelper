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
    private var lastTime: TimeInterval = 0

    // Trace recording (TremorSettings.trace) — off in normal use.
    private var traceEnabled = false
    private var traceHandle: FileHandle?
    private var traceStart: TimeInterval = 0

    /// Apply the current tremor settings: (re)configure the filter and start or
    /// stop the tap. Safe to call repeatedly.
    func update(_ settings: TremorSettings) {
        filter.configure(settings)
        setTracing(settings.trace)
        log("update enabled=\(settings.enabled) smoothing=\(settings.smoothing) "
            + "vertical=\(settings.effectiveVerticalSmoothing) "
            + "trusted=\(AXIsProcessTrusted()) tapActive=\(tap != nil)")
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
            log("start ABORTED — Accessibility not granted")
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
            log("start FAILED — CGEvent.tapCreate returned nil")
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        filter.reset()
        lastTime = 0
        log("start OK — tap created & enabled")
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
            log("tap DISABLED by \(type == .tapDisabledByTimeout ? "timeout" : "userInput") — re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = event.getDoubleValueField(.mouseEventDeltaY)

        // dt comes from the event clock, not from when we happen to run: the tap is
        // serviced on the main runloop at ordinary priority, so handling time jitters
        // — and a filter carrying a velocity state is sensitive to a wrong dt.
        let now = Double(event.timestamp) / 1_000_000_000
        let dt = lastTime > 0 ? min(max(now - lastTime, 0.001), 0.05) : 0.008
        lastTime = now

        let step = filter.process(dx: dx, dy: dy, dt: dt)
        recordTrace(now: now, dx: dx, dy: dy, step: step, dt: dt)

        // Reposition the cursor along the smoothed path (editing deltas alone does
        // not move it — the location field does). Anchor to the real reported
        // location each event (event.location - rawDelta = the previous cursor
        // position) so the path never drifts if anything else moves the cursor.
        let base = CGPoint(x: event.location.x - dx, y: event.location.y - dy)
        let loc = clampToMainDisplay(CGPoint(x: base.x + step.dx, y: base.y + step.dy))

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

    // MARK: - Trace recording

    /// Writes every processed event to `~/hmh-trace.csv`. These traces are the
    /// fixtures the offline tuning harness replays, so that filter settings are
    /// compared by measurement rather than by how they feel over a remote desktop.
    private func setTracing(_ enabled: Bool) {
        guard enabled != traceEnabled else { return }
        traceEnabled = enabled
        if enabled {
            let url = URL(fileURLWithPath: NSHomeDirectory() + "/hmh-trace.csv")
            try? "ms,dx,dy,outdx,outdy,dt\n".write(to: url, atomically: true, encoding: .utf8)
            traceHandle = try? FileHandle(forWritingTo: url)
            traceHandle?.seekToEndOfFile()
            traceStart = 0
        } else {
            try? traceHandle?.close()
            traceHandle = nil
        }
    }

    private func recordTrace(now: TimeInterval, dx: Double, dy: Double,
                             step: (dx: Double, dy: Double), dt: Double) {
        guard let traceHandle else { return }
        if traceStart == 0 { traceStart = now }
        let line = String(format: "%.3f,%.0f,%.0f,%.4f,%.4f,%.4f\n",
                          (now - traceStart) * 1000, dx, dy, step.dx, step.dy, dt)
        if let data = line.data(using: .utf8) { traceHandle.write(data) }
    }

    /// Lifecycle logging. NSLog isn't captured when the app is launched over SSH, so
    /// while tracing the same lines also go to a file next to the trace.
    private func log(_ message: String) {
        NSLog("HeadmouseHelper EventTap: %@", message)
        guard traceEnabled else { return }
        let line = "\(ProcessInfo.processInfo.systemUptime) EventTap: \(message)\n"
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/hmh-debug.log")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
