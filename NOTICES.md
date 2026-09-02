# Third-party notices

HeadmouseHelper adapts techniques from the following open-source projects.

## LinearMouse — MIT License

<https://github.com/linearmouse/linearmouse>

The Movement tab's pointer tuning (setting per-device pointer resolution and
acceleration via `IOHIDEventSystemClient` / `IOHIDServiceClient`) is adapted from
LinearMouse's PointerKit.

```
MIT License

Copyright (c) 2021-2024 LinearMouse

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Tremor stabilization — algorithm citation

The Stabilization tab's filter is a steady-state constant-velocity Kalman filter,
i.e. the classic **alpha-beta filter**. The gains are computed from the tracking
index using the standard relation given in:

> Kalata, P. R. "The Tracking Index: A Generalized Parameter for alpha-beta and
> alpha-beta-gamma Target Trackers." IEEE Transactions on Aerospace and Electronic
> Systems, AES-20(2), 1984.

This is textbook estimation theory implemented from the mathematics — not
third-party source code. (Earlier prototypes used opentrack's "accela" filter, the
Angle Mouse technique and the 1-euro filter; all were replaced and none remain in
the app.)
