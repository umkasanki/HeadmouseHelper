# Instrumented bench run — Windows SmartNav

Output of `tools/bench/bench.html` run on the user's Windows PC on 2026-09-02 with
SmartNav profile `Default` (Motion 111, speed 13/12). Unlike the free-form captures
in `smartnav-windows/`, every movement here has a **known intent**: which target was
lit, where it was, where the click landed. That makes endpoint error, overshoot and
acquisition time direct measurements rather than inferences.

The same page is meant to be run again on the Mac once our filter works, so the two
systems are compared with one instrument and one set of tasks.

## Reading the file

`meta.dpr` is 1.4125 — the browser reports CSS pixels, so **multiply every coordinate
by `dpr`** to get physical screen pixels comparable with the native captures.

`moves` is `[t_ms, clientX, clientY, screenX, screenY]`, one row per pointer sample
(coalesced events are unpacked, so the full ~100 Hz rate is preserved).
`events` carries `target_on` / `click` / `hold_start` / `hold_end` / `phase`.

## Results

| | short hops (450 px) | sweeps (1740 px) | precision (680 px, r=15 px) |
|---|---|---|---|
| endpoint error, median | 4.5 px | 16 px | 7 px |
| time to reach target | 600-880 ms | 800-900 ms | 680-970 ms |
| dwell before click | 350-550 ms | 370-560 ms | 270-440 ms |
| overshoot past target | none | none | none |

Acquisition time barely grows with distance — 1740 px takes about as long as 450 px.

## Contaminated trials

Trips to the Point-N-Click panel or popups from other programs show up as a gap of
>300 ms in the pointer stream together with a path far longer than the straight-line
distance (e.g. 1105 px travelled for a 341 px hop). Filter on that; 8/12, 6/10 and
7/10 trials survive. A future revision of the page should log `blur`/`focus` and
pointer-exit so these are marked explicitly rather than inferred.
