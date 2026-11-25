# Scheduling and retries

A schedule tells `Effect.retry/2` whether to try a failed effect again and how long to wait. The first execution happens immediately. The first failure consults the schedule at attempt zero. A success returns immediately. Retry handles expected failures (`Cause.Fail`).

| Schedule | Behavior after an expected failure |
| --- | --- |
| `Schedule.recurs(n)` | Up to `n` extra executions, with no delay. |
| `Schedule.recurs_with_backoff(n, base_ms)` | Up to `n` retries with delays of `base_ms`, twice that, four times that, and so on. |
| `Schedule.spaced(ms)` | Wait the same number of milliseconds between retries, with no attempt limit. |
| `Schedule.exponential(base_ms)` | Double the delay after each retry, with no attempt limit. |
| `Schedule.forever()` | Retry indefinitely with zero delay. |

Use nonnegative integers for counts and millisecond delays. For example, `recurs_with_backoff(3, 100)` allows four executions in total and waits 100, 200, then 400 milliseconds. Each retry runs the same effect description again. Put the operation inside `Effect.sync/1` or another deferred effect so each attempt performs fresh work.

```elixir
alias ZioEx.{Effect, Runtime, Schedule}

unavailable = Effect.fail(:offline)
cached = Effect.retry_or_else(unavailable, Schedule.recurs(2), fn reason, retries ->
  Effect.succeed({:cached_quote, reason, retries})
end)

{:ok, {:cached_quote, :offline, 2}} = Runtime.run(cached)
```

When a finite schedule stops, `retry/2` propagates the last error. `retry_or_else/3` calls the fallback with that error and the number of retries already performed.
