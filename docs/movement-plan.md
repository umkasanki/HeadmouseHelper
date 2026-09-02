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
   `deltaX/deltaY` **in place** (LinearMouse's transformer pattern), running an
   **alpha-beta (steady-state Kalman) filter** per axis over the accumulated
   position. Applied globally — the filter is transparent to steady input, so the
   trackpad is effectively unaffected and we avoid per-device disambiguation.
   See Part 2 for why an estimator and not a gain curve.

`seize` stays only for the on/off feature. **Separate H/V speed is deferred**
(smoothing is per-axis from the start; revisit speed only if that proves
insufficient). Convert-to-scroll: not needed.

Permissions: speed/accel need no extra permission; the tremor event tap needs
**Accessibility** (`AXIsProcessTrustedWithOptions`).

Attribution: `NOTICES.md` credits LinearMouse (MIT) with license text, and cites
Kalata (1984) for the alpha-beta gains — textbook math, no third-party code.

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

## Part 2 — Tremor stabilization  (restarted 2026-09-02)

A **Stabilization** tab (the 3rd, alongside Control and Movement) that steadies the
cursor without making it sluggish. Delivered by the `CGEventTap` from 2b, editing
mouse-move `deltaX/deltaY` in place.

### The goal, stated properly

Not "remove the shake". The user drives the reference tracker all day at settings
that still visibly shake, and calls it comfortable. Their words, after the runs that
produced the numbers below:

> I saw slight cursor shake, and the trajectories were not perfect, but everything
> was predictable and comfortable.

So the goal is **about a pixel of shake, with a completely predictable speed and a
completely predictable endpoint** — because every movement is aimed at a UI element,
either the one being clicked now or the one being approached next. Predictable
*endpoint* is the stronger requirement and it decomposes into three:

1. **It must arrive.** The cursor ends where the head aimed. Any filter that scales
   movement down loses distance permanently and undershoots.
2. **It must not sail past.** No overshoot at the stop.
3. **It must settle fast enough to commit** — you have to see that you hit the target
   before you click.

### Acceptance criteria (measured, not guessed)

Captured from Windows SmartNav on 2026-09-02 at the user's own profile (Motion 111
of 10-120, speed 13/12, 1920x1080), then re-derived a second way to check the numbers
are properties of SmartNav and not of the analysis. Traces live in
`traces/smartnav-windows/` and are the fixtures for Part 2d.

**Holding still.** Tremor is high-frequency and drift is low-frequency, so they must
be separated by a stated corner frequency — subtracting a moving average instead makes
the answer swing 20x with the window length, measuring mostly the user's own
(intentional) drift. Physiological tremor sits around 4-12 Hz:

| shake RMS above | horizontal | vertical |
|---|---|---|
| 2 Hz | 1.82 px | 0.13 px |
| **4 Hz** | **0.98 px** | **0.08 px** |
| 8 Hz | 0.51 px | 0.04 px |

Two window-free checks that need no corner at all: the largest single cursor step
while held is **4 px horizontal, 1 px vertical**, and the cursor changes position only
**6.2 times per second** while held against 100 Hz while moving — most camera samples
never accumulate a whole pixel. If ours twitches far more often at a matching RMS, it
is too light whatever the RMS says.

**Note the 12x axis asymmetry.** Both axes run identical smoothing (111/111) and near
identical speed, so this is the input, not the filter: this user's head shakes far
more horizontally than vertically. It *contradicts* our own HeadMouse telemetry, where
vertical looked worse (suspected device-side quantization). Both can be true — different
device, different geometry. So do not hard-code which axis needs more smoothing; keep
it adjustable, and re-measure per device.

**Stopping on a target.**

| | short hops | fast sweeps |
|---|---|---|
| approach speed | 1260 px/s | 5070 px/s |
| settle to +/-2 px | **235 ms** median, 380-505 ms p90 | 650 ms median, 1075 worst |
| overshoot past target | none measurable | none measurable |

The 235 ms is robust: it reproduces at dwell thresholds of 30, 50 and 80 px/s, with
only the number of detected stops changing. Loosening the tolerance to +/-3 or +/-5 px
gives 155-210 ms, as expected.

### Why this part was restarted

Five filters were tried on-device and none was usable: fractional per-event gain
(lost travel -> undershoot), a plain 1-euro low-pass (residual shake), a directional
"intent" gate (hold-tremor reads as intentional, ratio ~0.72), a speed-gain curve
(tremor and slow deliberate movement overlap in speed), and a 2nd-order low-pass with
a dwell freeze (best of the five, still shaky and jerky).

Analysing the two reference implementations settled it:

- **Windows SmartNav (excellent)** links the whole of OpenCV into `SmartNAV.exe`
  *solely* for `cvkalman` — create/predict/correct plus exactly the matrix ops that
  file needs, and not one image-processing call. Its smoothing is a **Kalman filter**.
  The user runs its Motion slider at 92% of range *together with* double the factory
  speed, a combination no gain-scaling filter can offer.
- **RJ Cooper's macOS port (unusable)** links no math at all and scales each delta by
  its magnitude: 0.20 / 0.95 / 1.50 across abrupt breakpoints. A 7.5x gain swing means
  the same head movement lands the cursor **somewhere different depending on how fast
  you made it** — aiming is impossible in principle. And it had the raw sub-pixel
  camera signal, so the gap is algorithmic, not a matter of signal quality.

That also **rules out the amplitude-response curve** this plan previously named as the
next idea: RJ Cooper ships precisely that.

### Architecture

An independent **alpha-beta filter** (steady-state constant-velocity Kalman) per axis,
over the *accumulated position* of the incoming deltas; what we hand back is the change
in the position estimate.

- A position estimator, not a gain multiplier -> it arrives, exactly.
- The velocity state extrapolates -> no lag on sustained movement.
- Tremor and intent separate statistically, through the process/measurement noise
  ratio, rather than by a threshold on speed, direction or amplitude — all three of
  which were tried and none of which can separate held tremor from slow intent.

One `smoothing` slider maps exponentially onto the noise ratio; the tracking index
`lambda = noiseRatio * dt^2` is recomputed per event so a jittery event rate does not
change the feel. `dt` comes from the CGEvent timestamp, never wall-clock. Both axes
are exposed separately from the start — both reference tools do it, and the user
genuinely runs a slower, calmer vertical.

**Known risk, to be settled by measurement.** The velocity state that removes lag is
the same thing that can carry the cursor **past** the target as you decelerate.
Kalata's gains are optimal for *tracking* a manoeuvring target, not for *landing* on
one, and the reference shows no measurable overshoot at all. If our overshoot is not
essentially zero we decouple beta from alpha and damp harder than the textbook
coupling gives.

### Part 2a — Filter core

- [ ] `AlphaBetaFilter` (one axis, Kalata gains, seeded by its first sample) and
      `TremorFilter` (2-axis wrapper over accumulated position).
- [ ] `TremorSettings { enabled, smoothing, verticalSmoothing, linkAxes, trace }`,
      migrating the old `strength` key so an existing settings.json is not reset.
- [ ] Delete the old `TremorFilter`, `OneEuroFilter`, the `algorithm` enum, the
      `deadzone` (a hard dead zone caused stick-slip — confirmed on device) and the
      stale presets. NOTICES cites Kalata instead of 1-euro / Angle Mouse.
- [ ] Unit tests, led by the three that encode the failures: it arrives (endpoint
      error zero), it does not lag sustained movement, it does not overshoot.

A draft of all of this exists at `/home/oleg/projects/HeadmouseHelper-wip-kalman/`
(written 2026-09-02, never compiled) — restore and adjust rather than retype.

### Part 2b — Event tap  (done earlier, kept)

`EventTapFilter` was validated on device; it only needs rewiring to the new filter.
Accessibility persists via stable signing. Debug logging moves behind
`TremorSettings.trace`, which also writes `~/hmh-trace.csv`.

### Part 2c — Record our own traces

Every previous attempt was judged by feel over RustDesk, which adds lag and makes
"is that smoother?" unanswerable. Record instead:

- [ ] Apply the `record-trace` preset and capture the same three tasks on the
      HeadMouse: hold still / sweep and stop / short hops. **One task per recording,
      never mixed** — blending them forces the analysis to guess segment boundaries,
      which is why only 3 of 7 pauses in the SmartNav sweep run were usable.
- [ ] Capture twice — with the Nano's rear speed switch off and on, compensating with
      `PointerResolution` so the feel is unchanged. The device reports 8-bit deltas at
      125 Hz, so look for a flat wall at the +/-127 clip, and check whether the finer
      signal survives macOS's count-to-pixel rounding.
- [ ] Commit the traces as fixtures, alongside the SmartNav reference traces.

### Part 2d — Offline tuning against the numbers

- [ ] Score candidate settings by replaying the fixtures in Core tests:
      **endpoint error** (must be zero — the headline metric), **overshoot**,
      **settle time to +/-2 px**, **residual shake RMS while held**, and update rate
      while held. Compare against the table above.
- [ ] Pick the winner on the numbers; only then confirm by feel on device.
- [ ] Save it as the default preset.

### Part 2e — Stabilization tab

- [ ] Enable toggle, Smoothing slider, "Same for both axes", vertical slider,
      live-apply. Drafted in the WIP directory; verify on device.

## Deferred / maybe later

- [ ] Separate horizontal/vertical speed (needs per-device delta scaling in the
      tap → device disambiguation). Only if uniform speed proves insufficient.
- [ ] Convert pointer movement to scroll — explicitly **not** wanted.
- [ ] "Restore system defaults" that restores macOS's own values (vs our app
      defaults).
