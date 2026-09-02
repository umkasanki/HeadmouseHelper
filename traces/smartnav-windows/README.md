# SmartNav reference traces (Windows)

Cursor traces captured from **NaturalPoint SmartNav 3.30** on the user's Windows PC
on 2026-09-02 — the behaviour this project's stabilization is aiming to match.
See `docs/movement-plan.md`, Part 2, for the metrics derived from them.

Valid as a measurement of the filter because `SmartNAV.exe` positions the cursor
absolutely (`SetCursorPos`), so the on-screen path is the filter's output with no
Windows pointer ballistics on top.

| File | Task |
|---|---|
| `trace-hold-113521.csv` | look at one point, do not move the cursor |
| `trace-sweep-113645.csv` | corner to corner, stopping dead on a target |
| `trace-hops-113744.csv` | between two icons a few cm apart, pausing on each |

Conditions: profile `Default` — Motion (smoothing) **111** of a 10–120 range, speed
13 horizontal / 12 vertical, `linkXY` off, relative positioning, cursor gravity and
dwell clicking **off**. Screen 1920×1080. 30 s per run. Only the head tracker drove
the cursor.

## Format, and a parsing trap

Columns are `ms,x,y`: milliseconds since the recording started, then absolute screen
coordinates, one row per cursor change.

The recorder ran on a Russian-locale Windows, where PowerShell formats a fraction
with a **comma** — so the `ms` field is itself split across two comma-separated
fields. Parse defensively:

```
fields = line.split(",")
if len(fields) == 4:  ms = fields[0] + "." + fields[1]; x = fields[2]; y = fields[3]
else:                 ms = fields[0];                   x = fields[1]; y = fields[2]
```

Read naively, the milliseconds' fractional part masquerades as the X coordinate —
which looks exactly like the cursor teleporting across a 1000 px range.
