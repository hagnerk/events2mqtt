# Stack and Implementation Decisions

- **Language:** Go. `go.mod` declares `go 1.23` or later, the first version where `timer.Reset` is safe on a timer that expired without being read. Earlier versions would require draining the channel before `Reset`.
- **Expression language:** `github.com/expr-lang/expr`, whose syntax is the one used in the examples. CEL was considered and set aside. Required properties:
  - typing;
  - compilation at load time, so that errors are caught by startup validation;
  - custom functions;
  - time-based functions able to report their deadline to the engine.
- **Sunrise and sunset:** `github.com/nathan-osman/go-sunrise`, computed locally from the coordinates set in environment variables and fed into the same deadline mechanism.
- **Clock:** functions never call `time.Now()`. Time comes through a `Clock` interface, which is what lets scenarios run under a simulated clock. The binary uses the real clock. The end-to-end test is a Go integration test that runs the engine in-process with a forged clock against the dev Mosquitto broker.
- **Time zone:** loaded explicitly, for example `time.LoadLocation("Europe/Paris")`. A container set to UTC would otherwise shift every time range.
- **Time handling:** the engine uses computed deadlines rather than a periodic tick. Precision is exact and there are no needless wake-ups. There is no periodic safety tick: a function that fails to report its deadline is a bug, and scenarios must catch it.
- **No dependency graph:** every output is recomputed on every event. This is cheap at home scale (a few dozen policies take microseconds) and keeps `explain` consistent. A dependency graph would only be a later optimization.
- **No Starlark:** YAML plus an expression language covers the needs. Starlark (`go.starlark.net`) remains the fallback if expressions become too complex.

The main loop is sketched in `architecture-diagrams.md`.
