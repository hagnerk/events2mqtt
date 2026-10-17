# Architecture Diagrams

## Reconciliation loop

```
Reconcile -> wait (MQTT message or timer) -> update state if MQTT -> Reconcile -> ...
```

```go
for {
    deadline := engine.Reconcile(state, clock.Now())
    timer.Reset(time.Until(deadline))

    select {
    case msg := <-mqttCh:
        state.Update(msg)
    case <-timer.C:
        // a time deadline was reached; nothing to update
    }
}
```

- `state` is the snapshot of inputs: the last value of each sensor and the value of each latch. Output state is the result of the computation and is kept separately.
- `Reconcile` performs four steps:
  1. It evaluates derived states from `state` and the current time.
  2. For each output, it keeps the first policy that applies.
  3. It publishes only the outputs whose desired state differs from the current or observed state, honoring `min_on` and `min_off`.
  4. It returns the nearest deadline reported during evaluation.
- `select` computes nothing. It wakes the loop on either an MQTT message or the timer.
