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
- [x] Confirmed **setting** resolution changes cursor speed, inversely
      proportional. Measured effective speed (cursor px per unit of head movement,
      `spike/SpeedProbe.swift`): res 150 → 0.237, res 500 → 0.072, res 1200 →
      0.016. Mechanism validated.

---

## Part 1 — Speed & acceleration + Movement tab  (day 1)

Ends with: Movement tab shows Speed / Acceleration / Disable-acceleration /
Restore-defaults, applied to the HeadMouse live, persisted, reasserted on
replug/wake.

- [x] **Core — model.** `MovementSettings { speed 0…1, acceleration 0…40,
      disableAcceleration }` in `Settings` (resilient decode + defaults).
- [x] **Core — port.** `PointerTuning` protocol; unit tests (speed→resolution
      mapping, clamps, Codable, resilient decode) — 18 Core tests pass.
- [x] **Build — bridging header.** `App/HeadmouseHelper/IOKitSPI.h` +
      `-import-objc-header` in `build-app.sh`.
- [x] **App — adapter.** `IOKitPointerTuner: PointerTuning` — event system
      client, find HeadMouse service client(s), set resolution + acceleration
      (`disableAcceleration` → −1).
- [x] **App — wiring.** Applied while tracking is ON; reasserts on hotplug and
      on wake (`NSWorkspace.didWakeNotification`).
- [x] **UI — tabs.** Segmented control (Control / Movement) under the title bar
      (TabView collapses to an overflow menu on macOS 26). Movement tab:
      Disable-acceleration toggle, Acceleration + Speed as `StepperSlider`
      (− / + circular buttons + centered value field), Restore-defaults.
- [x] **Verify on device:** app applied default speed 0.5 → resolution 860
      (confirmed by reading the device); speed set validated in Part 0.
- [x] **Commit.** `NOTICES.md` added (LinearMouse MIT).

Note: separate H/V still deferred; acceleration slider uses LinearMouse's 0…40
range (device default ≈ 0.6875). "Restore defaults" = app defaults, not macOS'.

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
