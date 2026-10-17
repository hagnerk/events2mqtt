---
id: SPEC-config-handling
companions:
  - configuration-model.md
  - reference-installation.md
  - known-behaviors.md
  - stack.md
  - architecture-diagrams.md
  - runtime-settings.md
sources:
  - ../../../doc/preliminary_study.md
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Declarative MQTT Rule Engine

## Why

A vision to realize, driven by a pain: home automation tools (Home Assistant, openHAB, Node-RED) use a "when X happens, do Y" model, so overlapping rules such as "boiler on if a valve requests heat" and "boiler off at night" produce outcomes that depend on event order and cannot be predicted or debugged. The owner of a Zigbee home (radiator valves, boiler relay, motion sensors, lamps, switches) wants a headless engine, run in a container and driven from the CLI, where every actuator's state is a readable, ordered function of current inputs and time, and that stays maintainable as rules multiply.

## Capabilities

- **CAP-1**
  - **intent:** The operator configures the engine with YAML, either one file or a `conf.d/` directory of per-room or per-domain files merged at load time.
  - **success:** A configuration split across several `conf.d/` files loads and behaves the same as when it is merged into one file. Any invalid configuration (see Constraints) stops the service at startup with an error that names the faulty item.
- **CAP-2**
  - **intent:** Inputs map an MQTT topic and message field to a variable that holds the last known value. Its type (`bool`, `number` or `string`) is declared, and a string input can also declare its allowed `values`.
  - **success:**
    - After a message arrives on a mapped topic, expressions read the field's value with its declared type.
    - Startup fails on a comparison with the wrong type or with an undeclared value, such as `== "hot"` when the values are `[heat, idle]`.
    - A message that does not match the declaration leaves the last valid value in place and logs a warning.
- **CAP-3**
  - **intent:** Derived states are named, reusable expressions over inputs, latches and the current time.
  - **success:** A policy that refers to a derived state by name gives the same result as one that contains the expression inline.
- **CAP-4**
  - **intent:** Latches turn edge events (button presses) into lasting values. A latch declares its values, its initial value, named events, ordered transitions (triggering event, `from` values, an optional `when` that can read `state_age`, target value), and a `reset_after` timeout. This is the only latch syntax: a toggle is written as two transitions.
  - **success:** The three-level kitchen button scenario in `configuration-model.md` passes: each press is consumed exactly once, no press is ignored, and the latch returns to its initial value after `reset_after`.
- **CAP-5**
  - **intent:** Each output declares a command topic, a default state, an ordered list of named policies (`when` → `state`) and `min_on`/`min_off` protection against short cycling.
  - **success:** The first policy whose condition is true decides the state, and the default applies when none is true. A state change requested before `min_on` or `min_off` has elapsed is held back until that time. The engine publishes `{"state":"ON"}` or `{"state":"OFF"}` to the command topic.
- **CAP-6**
  - **intent:** The engine reconciles continuously. On every input change or time deadline it recomputes every output and publishes only the outputs whose desired state differs from the current or observed state.
  - **success:** Re-evaluating with no change publishes nothing. When an output is linked through `observed` to its actuator's reported state, a manual change on the device or a lost command is corrected on the next reconciliation.
- **CAP-7**
  - **intent:** Time-based expression functions report the instant their value may change, and the engine wakes up at the nearest such instant without polling.
  - **success:** Under a simulated clock, `time_between("23:00","06:00")` changes at exactly 23:00, and `since_true(x) < duration("3m")` becomes false exactly 3 minutes after `x` went false. Functions are listed in `configuration-model.md`.
- **CAP-8**
  - **intent:** The operator runs `events2mqtt explain <output>` to see how each policy evaluated and which one decided.
  - **success:** The output matches the format in `configuration-model.md`, and the same trace is logged every time an output changes state.
- **CAP-9**
  - **intent:** The operator runs `events2mqtt test` to replay the scenarios declared in the configuration (`given`, `events`, `expect`, `then`) under a simulated clock.
  - **success:** The command runs all scenarios without waiting in real time and reports each failing expectation with its scenario name.
- **CAP-10**
  - **intent:** In dry-run mode the engine computes and logs its decisions without publishing.
  - **success:** With dry-run enabled, nothing is published to command topics while the decision logs match those of a normal run.
- **CAP-11**
  - **intent:** The engine's state survives a restart: input values, latch values with the instant of their last transition, and `since_true` instants are saved to disk and restored at startup. Restoring has no age limit: a restored value is the last known value, as if the service had never stopped.
  - **success:** After a restart, a switch latch keeps its value, `since_true` keeps counting from the instant before the restart, and every output gets the same desired state it had before the restart. A latch whose `reset_after` elapsed during the downtime comes back reset.
- **CAP-12**
  - **intent:** The engine stays connected to the MQTT broker. After losing the connection, it reconnects automatically with backoff, subscribes again, and republishes the desired state of every output.
  - **success:** When the broker is restarted, the engine is connected and subscribed again after the restart without operator action. It republishes every output once, even those with no detected difference. Inputs keep their last values during the outage.

## Constraints

- MQTT is the only device interface. Zigbee devices are reached through Zigbee2MQTT.
- Software settings (broker host, port, credentials, time zone, location coordinates, and the other runtime settings) come only from `EVENTS2MQTT_*` environment variables, listed in `runtime-settings.md`. The YAML holds only the rule model, and secrets never appear in it.
- There is no GUI: the engine is configured with YAML plus an embedded expression language, and every operation is available from the CLI. It runs in a container on Proxmox.
- The engine is written in Go, and `go.mod` declares `go 1.23` or later.
- The binary and the CLI are named `events2mqtt`. No other product name appears in code, configuration or documentation.
- Reconciliation follows the desired-state model only, never trigger → action rules.
- Priority is the position in the list, and the first match wins. This applies to both output policies and latch transitions.
- Only latches consume edge events (presses). Inputs, derived states and policies read levels only.
- Each output is defined exactly once across the whole configuration, including `conf.d/` merges.
- The service refuses to start on an unknown reference, a type mismatch, an expression that does not compile, a duplicate output, or a `time_between` bound that falls within a DST transition hour of the configured time zone. That hour is ambiguous; durations are unaffected.
- Time is read only through an injected clock, so every time-dependent behavior can run under a simulated clock.
- Local time uses an explicitly configured time zone, never the container's TZ.
- A press acts immediately. The engine never delays an action to tell a single press from a multi-press gesture.

## Non-goals

- A graphical or web interface.
- Event-driven "trigger → conditions → actions" rules.
- Detection of multi-press gestures inside the engine.
- Incremental evaluation through a dependency graph.
- TLS to the broker in v1; the connection is plaintext.
- Publishing state objects with several fields (`brightness`, `color_temp`, …) or computed values in v1. `state: ON` is already shorthand for `{state: ON}`, so they can be added later without breaking existing configurations.
- A periodic safety tick. The engine wakes only on MQTT messages and reported deadlines.
- A general-purpose scripting language such as Starlark.
- Device protocols other than MQTT.
- In v1, a fail-safe that turns the boiler off when the service stops. This is an accepted risk, described in `known-behaviors.md`.

## Success signal

- Every behavior of the reference installation (`reference-installation.md`) is a scenario in `doc/example.yml`, and `events2mqtt test` passes on that file under a simulated clock.
- A Go integration test (`go test`) runs `doc/example.yml` end to end. It runs the engine in-process with a forged clock, connects it to the dev Mosquitto broker (`infra/dev`), and feeds it simulated Zigbee2MQTT messages. The production binary has no test-only clock option.
  - When the forged clock reaches 23:00, the engine publishes `{"state":"OFF"}` to `zigbee2mqtt/boiler_relay/set` while a valve still reports `heat`, unless a room is below 7 °C.
  - `events2mqtt explain boiler` names `night-cutoff` as the deciding policy.
- Acceptance never depends on real hardware.

## Assumptions

- The spec covers the whole engine described in the study, not only file loading. The configuration model is the engine's behavioral contract and cannot be specified apart from reconciliation, time handling and tooling.
- Frost protection has no hysteresis. `min_on` and `min_off` are the only guard against cycling around the threshold.
