# Configuration Model

The configuration has four concepts: inputs, derived states, latches and outputs. It also holds test scenarios. Identifiers are in English, as `CLAUDE.md` requires. The source study used French names, mapped in the last section.

## Levels versus edges

- A **level** is a value that lasts over time, such as "it is night" or "the valve requests heat". At any moment it can answer the question "is this true now?". Inputs and derived states are levels.
- An **edge** is something that happens at one instant, such as a button press, and must be consumed exactly once. If a press were a derived value, it would stay true until the next press and its effect would replay on every evaluation.
- Latches are the only bridge from edges to levels. Output policies read levels only.

## Inputs (`inputs`) — CAP-2

```yaml
inputs:
  trv_living_room:
    topic: zigbee2mqtt/trv_living_room
    field: running_state
    type: string            # bool | number | string
    values: [heat, idle]    # optional, strings only
  trv_living_room_temp:
    topic: zigbee2mqtt/trv_living_room
    field: local_temperature
    type: number
```

- **At startup**, validation rejects a comparison with the wrong type (`trv_living_room_temp < "7"`) or with an undeclared value (`trv_living_room == "hot"`).
- **At runtime**, a message whose field is missing or does not match the declaration is ignored. The input keeps its last valid value and a warning is logged.

An input can also report an actuator's own state. Linking it to the output through `observed` makes reconciliation compare the desired state with this observed state (CAP-6). The syntax is `observed: <input name>` on the output.

## Derived states (`derived`) — CAP-3

```yaml
derived:
  heat_demand: any(trv_living_room == "heat", trv_bedroom == "heat")
  cutoff_window: time_between("23:00", "06:00")
```

## Latches (`latches`) — CAP-4

A latch has a single syntax: named events (`events:`) and ordered transitions (`transitions:`), where the first match wins. `state_age` is the time elapsed since the latch's last transition.

A two-value switch is written as two transitions:

```yaml
latches:
  kitchen_a:
    values: [off, on]
    initial: off
    reset_after: 3h
    events:
      press:
        topic: zigbee2mqtt/kitchen_switch_a
        field: action
        equals: single
    transitions:
      - on: press
        from: [off]
        to: on
      - on: press
        from: [on]
        to: off
```

A multi-level button uses `when` to make a transition depend on timing:

```yaml
latches:
  kitchen_level:
    values: [off, low, high]
    initial: off
    reset_after: 3h
    events:
      press:
        topic: zigbee2mqtt/kitchen_pushbutton
        field: action
        equals: single
    transitions:              # evaluated in order, first match wins
      - on: press
        from: [off]
        to: low
      - on: press
        from: [low]
        when: state_age < duration("1s")
        to: high
      - on: press
        from: [low, high]
        to: off
```

Acceptance scenario for the three-level kitchen button:

- A press while `off` gives `low` (one lamp on).
- A press within 1 s of entering `low` gives `high` (more lamps on).
- Any later press, or a press while `high`, gives `off`.

Every combination of state and timing is covered, so no press is ignored. The double press is not detected as a gesture. The first lamp turns on immediately, and the second press upgrades the level.

## Outputs (`outputs`) — CAP-5

```yaml
outputs:
  boiler:
    topic: zigbee2mqtt/boiler_relay/set
    default: OFF
    policies:
      - name: night-cutoff
        when: cutoff_window
        state: OFF
      - name: valve-demand
        when: heat_demand
        state: ON

  kitchen_lamp_1:
    topic: zigbee2mqtt/kitchen_lamp_1/set
    default: OFF
    policies:
      - name: level
        when: kitchen_level in ["low", "high"]
        state: ON

  kitchen_lamp_2:
    topic: zigbee2mqtt/kitchen_lamp_2/set
    default: OFF
    policies:
      - name: level-high
        when: kitchen_level == "high"
        state: ON
```

`min_on` and `min_off` are duration settings on the output (`min_on: 5m`).

The engine publishes `{"state":"ON"}` or `{"state":"OFF"}`, the format Zigbee2MQTT expects on `<device>/set`. `state: ON` and `default: OFF` are shorthand for `{state: ON}` and `{state: OFF}`. Later versions may publish objects with more fields (`{state: ON, brightness: 80}`), compared field by field against the observed state. Zigbee2MQTT is the device abstraction, so the engine has no per-device-type logic.

## Expression functions — CAP-7

Each function that depends on time reports the next instant its value may change.

| Function | Purpose |
|---|---|
| `any(a, b, ...)` | True if at least one argument is true |
| `all(a, b, ...)` | True if every argument is true |
| `duration("30m")` | Builds a duration |
| `since_true(x)` | 0 while `x` is true; otherwise the time since it went false, or infinite if it was never seen true |
| `since_true_any(a, b, ...)` | Smallest `since_true` among the arguments |
| `time_between("23:00", "06:00")` | True if local time is in the range; handles ranges that cross midnight |
| `sun_below_horizon(offset)` | True if the sun is below the horizon, with an optional offset; computed from the configured coordinates |

Examples of reported deadlines:

- `time_between("23:00","06:00")` evaluated at 21:14 returns false, with a deadline at 23:00.
- `since_true(pir_kitchen) < duration("3m")`, after a motion that ended at 18:02, returns true with a deadline at 18:05.

## File layout — CAP-1

The configuration is either one YAML file or a `conf.d/` directory with one file per room or domain (`heating.yaml`, `kitchen.yaml`), merged at load time.

## Scenarios (`scenarios`) — CAP-9

```yaml
scenarios:
  - name: home empty for 30 minutes
    at: "2026-11-02T15:00:00"            # simulated local time at start
    given:                               # initial input values
      trv_living_room: heat
      pir_living_room: { value: false, since: "2026-11-02T14:40:00" }
    events:                              # optional MQTT messages to inject
      - { topic: zigbee2mqtt/kitchen_switch_b, payload: { action: single } }
    expect:                              # output states at that instant
      boiler: ON
    then:                                # later steps, in order
      - set: { trv_office_temp: 6.5 }    # optional input changes
        at: "2026-11-02T15:10:00"        # clock advances to this instant
        expect:
          boiler: OFF
```

- `given` sets a value either directly, or as `{value, since}` to give the instant it was last set.
- A `then` step may also carry `events`.
- `doc/example.yml` holds the complete set of reference scenarios.

## `explain` output — CAP-8

```
$ events2mqtt explain boiler
boiler = OFF (current: OFF)
  [1] night-cutoff     cutoff_window       -> TRUE  <- decides
  [2] empty-home       not home_presence   -> (not evaluated)
  [3] valve-demand     heat_demand         -> (not evaluated, true)
```

## Identifier mapping from the study

| Study | Spec |
|---|---|
| `chaudiere`, `relais_chaudiere` | `boiler`, `boiler_relay` |
| `coupure-nocturne`, `appartement-vide`, `demande-tetes` | `night-cutoff`, `empty-home`, `valve-demand` |
| `plage_coupure`, `demande_chauffage`, `presence_appart` | `cutoff_window`, `heat_demand`, `home_presence` |
| `cuisine_niveau` (`off`, `faible`, `fort`) | `kitchen_level` (`off`, `low`, `high`) |
| `cuisine_a`, `cuisine_b`, `inter_cuisine_a`, `poussoir_cuisine` | `kitchen_a`, `kitchen_b`, `kitchen_switch_a`, `kitchen_pushbutton` |
| `lampe_cuisine_N`, `trv_salon`, `trv_chambre` | `kitchen_lamp_N`, `trv_living_room`, `trv_bedroom` |
| `interrupteur-b`, `veilleuse-nuit`, `nuit`, `mouvement_cuisine_recent` | `switch-b`, `night-light`, `night`, `recent_kitchen_motion` |
