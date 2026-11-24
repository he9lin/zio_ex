# Effects

An effect describes work that the runtime can execute more than once. `Effect.succeed(value)` wraps an already evaluated value. Put I/O or another operation that must run later inside the zero-argument function passed to `Effect.sync/1`.

Use `map/2` when the next function returns a value. Use `flat_map/2` when the next function returns an effect. In a `zio do` block, each `<-` binds the successful value of an effect. The final expression must itself be an effect.

```elixir
alias ZioEx.{Effect, Runtime}
import ZioEx.Macros, only: [zio: 1]

program =
  zio do
    text <- Effect.sync(fn -> "  Ada  " end)
    name <- Effect.succeed(String.trim(text))
    Effect.succeed("Welcome, #{name}")
  end

{:ok, "Welcome, Ada"} = Runtime.run(program)
```

Use `tap/2` for a follow-up effect when the next step still needs the original value. The callback runs on success. Its own failure propagates.

```elixir
alias ZioEx.{Effect, Runtime}

notify = fn name -> Effect.sync(fn -> send(self(), {:welcome, name}) end) end
{:ok, "Ada"} = Effect.succeed("Ada") |> Effect.tap(notify) |> Runtime.run()
receive do
  {:welcome, "Ada"} -> :ok
after
  0 -> raise "notification missing"
end
```

See [errors and recovery](errors.md) for failure handlers.
