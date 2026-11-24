# Runtime

Use `Runtime.run/2` at a boundary such as a request handler, job, or test. It accepts an effect or layer and an optional environment map that defaults to `%{}`. Running an effect produces `{:ok, value}` or `{:error, cause}`. Running a layer returns its service map on success.

```elixir
alias ZioEx.{Effect, Layer, Runtime}

{:ok, %{region: :west}} = Runtime.run(Layer.succeed(:region, :west))
{:ok, :east} = Runtime.run(Effect.require(:region), %{region: :east})
```

The interpreter keeps a stack of pending steps and finalizers. On success it resumes the next step. On failure it unwinds to a handler, executing finalizers as it goes. For dependency checks before execution, use [named workflows](workflow.md).

## Telemetry events

| Event | Measurements | Metadata |
| --- | --- | --- |
| `[:zio_ex, :run, :start]` | `system_time` | `id`, `env` |
| `[:zio_ex, :run, :stop]` | `duration` | `id`, `env`, `result` |

Match start and stop by `id`. Duration uses native time units, so convert with `System.convert_time_unit(duration, :native, :microsecond)` when reporting microseconds. Operations that start nested runtime runs, including parallel branches, produce their own events.
