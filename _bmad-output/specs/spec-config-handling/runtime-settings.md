# Runtime Settings

Software settings come only from environment variables. The YAML holds only the rule model.

| Variable | Purpose | Default |
|---|---|---|
| `EVENTS2MQTT_CONFIG` | Path to the YAML file or to the `conf.d/` directory | required |
| `EVENTS2MQTT_STATE_FILE` | Path to the persisted state (CAP-11) | required |
| `EVENTS2MQTT_MQTT_HOST` | Broker host | required |
| `EVENTS2MQTT_MQTT_PORT` | Broker port | `1883` |
| `EVENTS2MQTT_MQTT_USERNAME` | Broker user | none |
| `EVENTS2MQTT_MQTT_PASSWORD` | Broker password | none |
| `EVENTS2MQTT_MQTT_CLIENT_ID` | MQTT client identifier | `events2mqtt` |
| `EVENTS2MQTT_TIMEZONE` | IANA time zone name, such as `Europe/Paris` | required; never an implicit UTC |
| `EVENTS2MQTT_LATITUDE` | Latitude for sunrise and sunset | required if the configuration uses `sun_below_horizon` |
| `EVENTS2MQTT_LONGITUDE` | Longitude for sunrise and sunset | required if the configuration uses `sun_below_horizon` |
| `EVENTS2MQTT_DRY_RUN` | `true` computes and logs decisions without publishing (CAP-10) | `false` |
| `EVENTS2MQTT_LOG_LEVEL` | `debug`, `info`, `warn` or `error` | `info` |

The service refuses to start in three cases:
- a required variable is missing;
- a value is invalid (unknown time zone, non-numeric port or coordinate);
- the configuration uses `sun_below_horizon` while the coordinates are missing.
