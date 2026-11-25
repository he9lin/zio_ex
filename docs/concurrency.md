# Concurrency

Use `zip_par/2` for independent work whose results you need together. Both branches receive the current environment. The runtime waits for both to finish and returns their values in left-to-right order. If both fail, `Cause.Both` contains both causes.

```elixir
alias ZioEx.{Effect, Runtime}

totals = Effect.zip_par(Effect.succeed(450), Effect.succeed(35))
{:ok, {450, 35}} = Runtime.run(totals)
```

## Fibers

`fork/1` starts an effect and yields a fiber handle. `join/1` waits for its result and propagates its failure. Any process can join a fiber once. A fiber can outlive the parallel branch that created it, within the lifetime of the runtime's owning process.

```elixir
alias ZioEx.{Effect, Runtime}
import ZioEx.Macros, only: [zio: 1]

program =
  zio do
    fiber <- Effect.fork(Effect.sync(fn -> String.upcase("tea") end))
    quantity <- Effect.succeed(3)
    label <- Effect.join(fiber)
    Effect.succeed({label, quantity})
  end

{:ok, {"TEA", 3}} = Runtime.run(program)
```

## Callback-based work

`Effect.async/1` runs a registration function in a separate process. Resume exactly once with `{:ok, value}` or `{:error, cause}`. Registration may return before another process invokes the callback. After normal registration, the runtime waits for the callback without a timeout.

```elixir
alias ZioEx.{Effect, Runtime}

request = Effect.async(fn resume ->
  spawn(fn -> resume.({:ok, :delivered}) end)
end)

{:ok, :delivered} = Runtime.run(request)
```

For a collection of independent operations, see [collection traversal](traversal.md).
