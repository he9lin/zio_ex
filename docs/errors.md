# Errors and recovery

Use `Effect.fail(reason)` for an expected outcome such as a missing order. `map_error/2` translates a direct `Cause.Fail` while preserving other causes. `catch_all/2` recovers from an expected error by returning another effect. For selective recovery, `catch_some/2` keeps the original error when its callback returns `nil`.

```elixir
alias ZioEx.{Cause, Effect, Runtime}

lookup =
  Effect.fail(:enoent)
  |> Effect.map_error(fn :enoent -> {:order_missing, 42} end)

{:error, %Cause.Fail{error: {:order_missing, 42}}} = Runtime.run(lookup)

fallback = Effect.catch_some(lookup, fn
  {:order_missing, _} -> Effect.succeed(:empty_cart)
  _ -> nil
end)

{:ok, :empty_cart} = Runtime.run(fallback)
```

| Cause | Meaning |
| --- | --- |
| `Cause.Fail` | An expected error supplied by the program. |
| `Cause.Die` | A defect. Exceptions raised in interpreted callbacks carry the exception and stacktrace. |
| `Cause.Interrupt` | An interrupted or unavailable computation. |
| `Cause.Both` | Both branches of a parallel pair failed. Its fields retain both causes. |

Use `fold/3` to turn an expected error or success into a plain value, `fold_zio/3` when those handlers return effects, and `fold_cause/3` when the handler needs the whole cause. `either/1` moves an expected failure into the success value as `{:error, reason}`.
