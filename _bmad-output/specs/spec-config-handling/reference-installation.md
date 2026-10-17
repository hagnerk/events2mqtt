# Reference Installation

This is the acceptance target for the success signal. It is verified only with simulated data: scenarios under a simulated clock, and end-to-end runs against the dev Mosquitto broker. Device names and topics are illustrative and do not have to match a real installation. Its runnable version, with the test scenarios, is `doc/example.yml`. Both must stay consistent.

## Hardware

- Three Sonoff TRVZB radiator valves (living room, bedroom, office). Their `running_state` field is `heat` or `idle`, and their `local_temperature` field gives the room temperature in °C.
- One Sonoff ZBMINI R2 relay that controls the boiler. It reports its own state on `zigbee2mqtt/boiler_relay`, which is linked to the output through `observed`.
- Three motion sensors (kitchen, living room, entrance), each with an `occupancy` field.
- Four kitchen lamps.
- Switch A controls lamps 1 and 2, and switch B controls lamps 3 and 4. Each switch drives a two-value `off`/`on` latch with one transition per direction.

## Boiler

The policies are listed in priority order:

```yaml
policies:
  - name: frost-protection   # 1. on if any room is below 7 °C, overriding every cutoff
    when: frost_risk
    state: ON
  - name: night-cutoff       # 2. off from 23:00 to 06:00
    when: cutoff_window
    state: OFF
  - name: empty-home         # 3. off after 30 min without motion
    when: not home_presence
    state: OFF
  - name: valve-demand       # 4. on if any valve requests heat
    when: heat_demand
    state: ON
# otherwise: OFF (default)
```

- `heat_demand` uses `any(...)` over the three valves, so one valve is enough.
- `home_presence` uses `since_true_any` over the three motion sensors, with a 30-minute threshold.
- `min_on` and `min_off` are both 5 minutes.
- `frost_risk` uses `any(...)` over the three valves' `local_temperature < 7`. It has no hysteresis, so `min_on` and `min_off` are the only guard against cycling around the threshold.

## Lamps 1, 2 and 4

Each lamp has a single policy: it is ON while its switch's latch is `on`.

## Lamp 3

```yaml
policies:
  - name: switch-b
    when: kitchen_b == "on"
    state: ON
  - name: night-light
    when: night && recent_kitchen_motion
    state: ON
```

- `night` starts 20 minutes before sunset (`sun_below_horizon` with an offset).
- `recent_kitchen_motion` is true when kitchen motion was seen within the last 3 minutes.

## Scenarios to cover

The kitchen part (lamps, switches, pushbutton, night light) is covered by scenarios only.

- The boiler cuts off at 23:00 while a valve still requests heat.
- The boiler turns on at night with nobody home when a room drops below 7 °C.
- The boiler cuts off after 30 minutes without motion.
- The night light on lamp 3 turns off 3 minutes after the last kitchen motion.
- Switch B toggles lamps 3 and 4.
