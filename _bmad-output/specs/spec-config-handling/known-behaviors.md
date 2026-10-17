# Known Behaviors

These behaviors follow from the model. The implementation must not "fix" them silently. Documentation and scenarios should make them visible.

## Lamp 3 after switch B is turned off at night

If switch B is turned off right after kitchen motion at night, lamp 3 stays on until 3 minutes after the last motion, because `night-light` takes over.

To allow forcing it off, replace the latch with a three-value one (`auto`, `on`, `off`) and put a forced-off policy at the top of the list.

## Service restart

Without persisted state, a restart returns inputs and latches to their initial state, so every switch reads `off`. `since_true_any` is also infinite until the first motion, so the boiler stays off until then. CAP-11 prevents this by restoring the persisted state. This behavior only remains when there is no persisted state, as on a first start or after the state file is lost.

## Motion sensor delay

Zigbee2MQTT motion sensors set `occupancy` back to `false` after their own delay, often 60 to 90 seconds and configurable in Zigbee2MQTT. Thresholds such as "3 minutes" count from that return to `false`, not from the motion itself.

## Buttons with native multi-click

Many Zigbee buttons detect double presses themselves. They then send `double` instead of two close `single` actions. To get the three-level behavior, either disable multi-click in Zigbee2MQTT or map the `low` → `high` transition to `double`.

## Boiler left ON when the service stops

If the service stops while the relay is `ON`, the boiler heats indefinitely. Two mitigations exist:

- periodic republication of the desired state, with an expiry timeout on the relay side if its firmware supports one;
- failing that, a watchdog that cuts the relay when the service stops responding.

Neither is in v1. This is an accepted known risk.

## Daylight saving time

Durations (`since_true`, `reset_after`, `min_on`, `min_off`) are counted on absolute instants, so DST does not affect them.

Only the wall-clock bounds of `time_between` are affected. In Europe/Paris, 02:00–03:00 does not exist in spring and occurs twice in autumn. A bound in that hour would start at an undefined time, or make the range true twice. Validation therefore refuses such a bound.
