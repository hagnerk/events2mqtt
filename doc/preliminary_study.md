# domo - MQTT rule engine

Design documentation for a home automation engine driven by declarative rules, communicating exclusively over MQTT (Zigbee devices via Zigbee2MQTT), configured in YAML and fully operable from the command line.

## Table of contents

1. Goals
2. Existing alternatives
3. Principle: desired state rather than events
4. Configuration model
5. Time handling
6. Engine main loop
7. Complete annotated example
8. Debugging tools
9. Behaviors to be aware of
10. Implementation notes

---

## 1. Goals

- Control MQTT actuators (boiler relay, lamps) based on sensors (thermostatic radiator valves, motion sensors, switches) and the time of day.
- Handle rules that overlap or seem contradictory (for example "the boiler turns on if a valve requests heat" and "the boiler is always off at night") without unpredictable behavior.
- Stay readable and maintainable as the number of rules grows.
- Run without a graphical interface, in a container on a Proxmox hypervisor managed from the CLI.

## 2. Existing alternatives

| Tool | Configuration | Notes |
|---|---|---|
| Home Assistant | YAML possible (packages) | Comprehensive but heavy, designed around the web UI, "trigger → conditions → actions" model |
| openHAB | Text files (`.things`, `.items`, `.rules`) | Closest fit without writing code, heavy Java stack, imperative event-driven model |
| Node-RED | Graphical | Out of scope |
| Zigbee2MQTT bindings | Direct links between devices | No logic, but keeps working even when the server is down |

These tools mostly rely on a "when X happens, do Y" model, which is precisely the source of conflicts between rules. Hence the choice of a custom engine written in Go, based on a different model.

## 3. Principle: desired state rather than events

### The problem with the event-driven model

With two rules "valve open → turn the boiler on" and "night → turn the boiler off", the outcome depends on the order in which events arrive. The behavior becomes impossible to predict and to debug.

### The chosen model: reconciliation

The engine works as a reconciliation loop (in the spirit of Kubernetes):

1. It maintains the current state of all inputs (last known value of each sensor).
2. On every input change or time deadline, it recomputes the desired state of each actuator from this global state and the current time.
3. It only publishes to MQTT when the desired state differs from the current state.

### Priority by order

Each actuator has an ordered list of policies. The first one whose condition is true wins, like in a firewall. If none applies, the default value is used.

Priority is therefore not an abstract notion: it is the position in the list. Two "contradictory" rules no longer are; they simply have a visible order.

## 4. Configuration model

The configuration is built on four concepts.

### Inputs (`inputs`)

Map an MQTT topic and a message field to a typed variable.

```yaml
inputs:
  trv_salon:
    topic: zigbee2mqtt/trv_salon
    field: running_state
```

### Derived states (`derived`)

Named, reusable expressions computed from inputs, latches and the current time. They keep policies readable.

```yaml
derived:
  demande_chauffage: any(trv_salon == "heat", trv_chambre == "heat")
  plage_coupure: time_between("23:00", "06:00")
```

### Latches (`latches`)

Turn a one-off event (a button press) into a lasting state ("manual mode enabled"). Without them, we would fall back into the event-driven model.

```yaml
latches:
  cuisine_a:
    values: [off, on]
    initial: off
    on:
      - event:
          topic: zigbee2mqtt/inter_cuisine_a
          field: action
          equals: single
        action: toggle
    reset_after: 3h
```

#### Levels versus edges

Inputs and derived states are **levels**: values that last over time ("it is night", "the valve requests heat"), which can be asked "is this true right now?" at any moment. A button press is an **edge**: something that happens at an instant and must be consumed exactly once.

This is why a button cannot be a derived state. If "short press" were a derived value, it would stay true until the next press and its effect would be replayed on every evaluation of the loop. Latches are the only place where events are consumed: they act as the bridge between edges and levels, so output policies only ever read levels.

#### Example: multi-press button with conditional transitions

A latch can define transitions that depend on its current value and on how long it has been in that value. The engine exposes `state_age` in the context of each latch: the time elapsed since its last transition.

Desired behavior for a single push button:

- one press while off turns one lamp on;
- a second press within one second turns more lamps on;
- any further press (after one second, or once at full level) turns everything off.

```yaml
latches:
  cuisine_niveau:
    values: [off, faible, fort]
    initial: off
    reset_after: 3h
    events:
      press:
        topic: zigbee2mqtt/poussoir_cuisine
        field: action
        equals: single
    transitions:              # evaluated in order, first match wins
      - on: press
        from: [off]
        to: faible
      - on: press
        from: [faible]
        when: state_age < duration("1s")
        to: fort
      - on: press
        from: [faible, fort]
        to: off
```

Transitions follow the same rule as output policies: an ordered list where the first match wins. The second transition only applies within one second of entering `faible`; past that point, the third one takes over and turns everything off. Every combination of state and timing is covered, so no press is ever silently ignored.

Note that the double press is not detected as a separate gesture. Detecting "two presses within one second" would force the engine to wait one second after every press before acting. Here, the first lamp turns on immediately and the second press simply upgrades the level.

The outputs then just read the latch:

```yaml
outputs:
  lampe_cuisine_1:
    topic: zigbee2mqtt/lampe_cuisine_1/set
    default: OFF
    policies:
      - name: niveau
        when: cuisine_niveau in ["faible", "fort"]
        state: ON

  lampe_cuisine_2:
    topic: zigbee2mqtt/lampe_cuisine_2/set
    default: OFF
    policies:
      - name: niveau-fort
        when: cuisine_niveau == "fort"
        state: ON
```

Hardware caveat: many Zigbee buttons detect double presses themselves. They then never send two close `single` actions, but wait briefly and send a `double` instead. With such a device, either disable its multi-click detection if Zigbee2MQTT exposes that option, or use its `double` action for the transition to `fort`.

### Outputs (`outputs`)

Each actuator declares its command topic, its default value and its ordered list of policies.

```yaml
outputs:
  chaudiere:
    topic: zigbee2mqtt/relais_chaudiere/set
    default: OFF
    policies:
      - name: coupure-nocturne
        when: plage_coupure
        state: OFF
      - name: demande-tetes
        when: demande_chauffage
        state: ON
```

An output can only be defined once across the whole configuration, which guarantees that all the rules affecting it live in the same place.

### Functions available in expressions

| Function | Purpose |
|---|---|
| `any(a, b, ...)` | True if at least one argument is true |
| `all(a, b, ...)` | True if all arguments are true |
| `duration("30m")` | Builds a duration |
| `since_true(x)` | 0 if `x` is currently true, otherwise time elapsed since it went back to false (infinite if never seen true) |
| `since_true_any(a, b, ...)` | Smallest `since_true` among the arguments |
| `time_between("23:00", "06:00")` | True if local time falls within the range (handles midnight crossing) |
| `sun_below_horizon(offset)` | True if the sun is below the horizon, with an optional offset |

### File layout

For a growing configuration, a `conf.d/` directory with one file per room or domain (`chauffage.yaml`, `cuisine.yaml`), merged at load time.

## 5. Time handling

### Time is an input like any other

A state such as `plage_coupure` depends on the current time. The difference with a sensor is that nothing publishes an MQTT message at 11 PM: the engine has to wake itself up to recompute.

### Option 1: periodic tick

A full re-evaluation every minute. Simple and cheap (a few dozen policies evaluate in microseconds), but precision is limited to the tick period.

### Option 2: computed deadlines (chosen)

Each time-based function reports, when evaluated, the moment its value may change:

- `time_between("23:00", "06:00")` evaluated at 9:14 PM returns `false` and the deadline 11:00 PM.
- `since_true(pir_cuisine) < duration("3m")` after a motion ending at 6:02 PM returns `true` and the deadline 6:05 PM.

The engine keeps the nearest deadline and schedules a wake-up at that moment. Benefits: precise transitions, no needless wake-ups, and natural support for timeouts (turning a lamp off 3 minutes after the last motion).

A safety tick (for example every minute) can be kept as a complement, in case a function fails to report its deadline.

### Sunrise and sunset

Computed locally from the configured coordinates, using the `github.com/nathan-osman/go-sunrise` library. Often more relevant than a light sensor for detecting nightfall, and integrated into the same deadline mechanism.

## 6. Engine main loop

```go
for {
    deadline := engine.Reconcile(state, clock.Now())
    timer.Reset(time.Until(deadline))

    select {
    case msg := <-mqttCh:
        state.Update(msg)
    case <-timer.C:
        // time reached a deadline, nothing to update
    }
}
```

### Role of `state`

`state` represents the state of the inputs: the last value of each sensor and the value of each latch. It is the snapshot of the world the computation starts from. The state of the outputs is the result of the computation and is kept separately.

### Role of `Reconcile`

On each call:

1. Evaluates derived states from `state` and the current time.
2. For each output, walks through the policies in order and keeps the first one that applies.
3. Compares the desired state to the current state and publishes only the differences (honoring `min_on` and `min_off`).
4. Returns the nearest time deadline encountered during evaluation.

### Role of `select`

It computes nothing: it waits for either an MQTT message (which updates `state`) or the timer expiring. In both cases, the loop starts over and `Reconcile` recomputes everything.

```
Reconcile -> wait (MQTT or timer) -> optional update -> Reconcile -> ...
```

### Observed output state

An actuator that publishes its own state (the boiler relay on `zigbee2mqtt/relais_chaudiere`) can be declared as an input and linked to its output through `observed`. The engine then compares the desired state to the actually observed state. If someone presses the relay's physical button or a message is lost, the loop corrects itself.

## 7. Complete annotated example

The `domo.yaml` file provided with this documentation contains a complete configuration. Here is its logic.

### Hardware

- Three Sonoff TRVZB thermostatic radiator valves (living room, bedroom, office), `running_state` field set to `heat` or `idle`.
- A Zigbee relay controlling the boiler.
- Three motion sensors (kitchen, living room, entrance), `occupancy` field.
- Four lamps in the kitchen.
- Two switches: A controls lamps 1 and 2, B controls lamps 3 and 4.

### Boiler

```yaml
policies:
  - name: coupure-nocturne       # 1. always off from 11 PM to 6 AM
    when: plage_coupure
    state: OFF
  - name: appartement-vide       # 2. off when no motion for 30 min
    when: not presence_appart
    state: OFF
  - name: demande-tetes          # 3. on if a valve requests heat
    when: demande_chauffage
    state: ON
# otherwise: OFF (default)
```

- `demande_chauffage` uses `any(...)`: a single valve requesting heat is enough. Replacing it with `all(...)` would require every valve to request heat at the same time.
- `presence_appart` uses `since_true_any` over the three sensors with a 30-minute threshold.
- `min_on` and `min_off` set to 5 minutes protect the boiler against short cycling.
- A frost-protection rule would be added at the top of the list to override every shutdown.

### Lamps 1, 2 and 4

A single policy each: on if their switch's latch is `on`.

### Lamp 3

```yaml
policies:
  - name: interrupteur-b
    when: cuisine_b == "on"
    state: ON
  - name: veilleuse-nuit
    when: nuit && mouvement_cuisine_recent
    state: ON
```

Shared between switch B and a night light: at night (starting 20 minutes before sunset), it turns on by itself when motion has been detected in the kitchen within the last 3 minutes.

### Test scenarios

The `scenarios` section of the file describes situations with a simulated clock: initial state (`given`), events (`events`), expected results (`expect`), then changes over time (`then`). They cover in particular the 11 PM shutdown, the shutdown after 30 minutes of absence, the night light turning off and switch B's action.

## 8. Debugging tools

### Validation at startup

Unknown references, inconsistent types, expressions that fail to compile, outputs defined twice: the service refuses to start rather than behave unexpectedly.

### `explain` command

Shows, for an output, the evaluation of each policy and which one decides.

```
$ domo explain chaudiere
chaudiere = OFF (current: OFF)
  [1] coupure-nocturne  plage_coupure        -> TRUE  <- decides
  [2] appartement-vide  not presence_appart  -> (not evaluated)
  [3] demande-tetes     demande_chauffage    -> (not evaluated, true)
```

The same content is written to the logs every time an output changes state.

### `test` command

Runs the scenarios with a simulated clock. Lets you modify a rule while checking that nothing else breaks.

### Dry-run mode

Computes and logs decisions without publishing anything, to validate a new configuration alongside the current one.

## 9. Behaviors to be aware of

### Interaction on lamp 3

If switch B is turned off at night right after motion in the kitchen, lamp 3 stays on until 3 minutes after the last motion, since the night light takes over. To allow forcing it off, use a three-value latch (`auto`, `on`, `off`) with a forced-off policy at the top of the list.

### Service restart

As long as no sensor has reported motion, `since_true_any` is infinite: the boiler stays off after a restart until the first motion. Persisting the state of inputs and latches to disk avoids this (and also avoids resetting every switch to `off`).

### Motion sensor delay

Zigbee motion sensors switch `occupancy` back to `false` after their own delay, often 60 to 90 seconds and configurable in Zigbee2MQTT. Thresholds such as "3 minutes" are counted from that return to `false`, not from the motion itself.

### Boiler safety

If the service stops with the relay `ON`, the boiler heats indefinitely. Plan for periodic republication of the desired state with an expiry timeout on the relay side if the firmware supports it, or failing that, a watchdog script that cuts the relay when the service stops responding.

## 10. Implementation notes

### Expression language

`github.com/expr-lang/expr` or CEL (`github.com/google/cel-go`) in Go: typing, compilation at load time, custom functions. Time-based functions must be able to report their deadline back to the engine.

### Injected clock

Never call `time.Now()` inside functions: pass the time through a `Clock` interface. This is what makes test scenarios possible without waiting for real time.

### Time zone

Explicitly load `time.LoadLocation("Europe/Paris")`, otherwise a container configured in UTC would shift every time range. On the day of the switch to winter time, the 02:00-03:00 range occurs twice: avoid placing transitions there or define the behavior explicitly.

### Go timer

Since Go 1.23, `timer.Reset` is safe even if the timer expired without being read. The `go.mod` file must declare `go 1.23` or later. On earlier versions, drain the channel before `Reset` to avoid a spurious wake-up.

### Dependency graph

Recomputing every output on each event is sufficient at the scale of a home and guarantees that `explain` stays consistent. A dependency graph (which output reads which input) would only be a later optimization, and a potential source of subtle bugs for a negligible gain.

### Alternative to YAML

If expressions become too complex, Starlark (`go.starlark.net`) offers a more expressive language while remaining sandboxed. For the needs described here, YAML plus an expression language is enough.