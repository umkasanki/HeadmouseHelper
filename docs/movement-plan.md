# Movement settings — implementation plan

Phase 2 of HeadmouseHelper: a **Movement** tab in the control window for tuning
how the HeadMouse Nano moves the cursor. Work is split into parts that can be
done on separate days; each part ends with a commit.

## Architecture (decided)

Two independent concerns, each solved with the right tool — **no userspace mouse
driver** (no seize + re-inject for tuning):

1. **Speed + acceleration** → set the device's IOKit HID properties
   (`PointerResolution`, acceleration), the way LinearMouse does. Native, no
   latency, applies while tracking is ON. (LinearMouse is MIT — keep attribution.)
2. **Tremor stabilization** → a `CGEventTap` that modifies `mouseMoved`/`dragged`
   `deltaX/deltaY` **in place** (LinearMouse's transformer pattern), using the
   **accela** filter math from opentrack (dead zone + nonlinear gain curve:
   damp small/slow jitter, pass large/fast intent). Applied globally — the filter
   is transparent to steady input, so the trackpad is effectively unaffected and
   we avoid per-device disambiguation. (opentrack is ISC — keep attribution.)

`seize` stays only for the on/off feature. **Separate H/V speed is deferred** —
uniform speed + a good tremor filter should cover the real need; revisit only if
axes genuinely need different sensitivity. Convert-to-scroll: not needed.

Permissions: speed/accel need no extra permission; the tremor event tap needs
**Accessibility** (`AXIsProcessTrustedWithOptions`).

Attribution: add a `NOTICES.md` crediting LinearMouse (MIT) and opentrack /
S. Halik (ISC) with license text.

---

## Part 0 — De-risk the private pointer API  ✅ mostly done

- [x] Spike compiles against the private `IOHIDEventSystemClient` API via a
      bridging header (`spike/IOKitSPI.h`, `spike/PointerSpike.swift`).
- [x] Reads the HeadMouse service client + current `PointerResolution` (≈68.7).
- [ ] Confirm **setting** resolution (+ acceleration "poke") actually changes
      cursor speed on the device (run `./spike/pointer-spike 400`, move head,
      verify slower; `... 120` faster). Tracking must be ON (not seized).

---

## Part 1 — Speed & acceleration + Movement tab  (day 1)

Ends with: Movement tab shows Speed / Acceleration / Disable-acceleration /
Restore-defaults, applied to the HeadMouse live, persisted, reasserted on
replug/wake.

- [ ] **Core — model.** Add `MovementSettings { speed: 0…1, acceleration: 0…40,
      disableAcceleration: Bool }` to `Settings` (resilient decode + defaults).
- [ ] **Core — port.** `PointerTuning` protocol (`apply(_:to:)`,
      `resetToDefaults(_:)`). Unit tests: speed→resolution mapping, clamps,
      Codable round-trip, resilient decode.
- [ ] **Build — bridging header.** Add `App/HeadmouseHelper/IOKitSPI.h` (private
      decls: `IOHIDEventSystemClientCreate`, `IOHIDServiceClientCopyProperty`)
      and `-import-objc-header` in `build-app.sh`. Confirm the app still builds.
- [ ] **App — adapter.** `IOKitPointerTuner: PointerTuning` — create the event
      system client, find the HeadMouse service client(s) by VID/PID, set
      resolution/acceleration (+ acceleration re-poke so resolution applies;
      `disableAcceleration` → −1 or linear-scaling method on Sonoma+).
- [ ] **App — wiring.** Apply movement settings when tracking is ON; reassert on
      hotplug (existing `onDevicesChanged`) and on wake
      (`NSWorkspace.didWakeNotification`).
- [ ] **UI — tabs.** Convert the window content to a `TabView`: **Control**
      (existing circle) + **Movement**. Movement tab: Speed slider, Acceleration
      slider, Disable-acceleration toggle, Restore-defaults button. Live-apply on
      change.
- [ ] **Verify on device:** speed changes, disable-accel works, values persist,
      reassert after replug and after sleep/wake.
- [ ] **Commit.** Add `NOTICES.md` (LinearMouse MIT).

---

## Part 2 — Tremor stabilization  (day 2)

Ends with: a Tremor section that visibly smooths head jitter while keeping
deliberate movement responsive; trackpad unaffected.

- [ ] **Spike.** Minimal `CGEventTap` that halves `mouseMoved` deltas to prove
      in-place modification + the Accessibility permission flow works.
- [ ] **Core — filter.** Port the **accela** algorithm as a pure, testable
      `TremorFilter` (2D): per-axis delta vs last output, dead zone, nonlinear
      gain via the ported gain-curve points, integrate over dt. Unit tests:
      micro-jitter → ~0 output, large motion → passes ~1:1, dead zone respected.
      Credit opentrack / S. Halik (ISC).
- [ ] **Core — model.** `MovementSettings +=`
      `tremor { enabled: Bool, smoothing, deadzone }`.
- [ ] **App — event tap.** `EventTapFilter` — `CGEventTap` on
      `mouseMoved`/`leftMouseDragged`/`rightMouseDragged`; run deltas through
      `TremorFilter`; write back `kCGMouseEventDeltaX/Y`. Start/stop per setting.
- [ ] **Permission.** Request **Accessibility** at launch (only when tremor is
      enabled); add `NSAccessibilityUsageDescription` to `Info.plist`.
- [ ] **UI.** Movement tab += Tremor section (toggle + smoothing + dead-zone).
- [ ] **Verify on device:** head tremor smoothed, deliberate motion responsive
      and lag-free, trackpad normal.
- [ ] **Commit.** Update `NOTICES.md` (opentrack ISC).

---

## Deferred / maybe later

- [ ] Separate horizontal/vertical speed (needs per-device delta scaling in the
      tap → device disambiguation). Only if uniform speed proves insufficient.
- [ ] Convert pointer movement to scroll — explicitly **not** wanted.
- [ ] "Restore system defaults" that restores macOS's own values (vs our app
      defaults).
