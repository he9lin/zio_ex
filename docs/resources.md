# Resources and finalizers

Use `Effect.acquire_release_with(acquire, use_resource, release)` when an operation owns a resource. Acquisition is an effect. Both callbacks receive the acquired value and return effects. This example reads the first line of an in-memory I/O device and closes it after use.

```elixir
alias ZioEx.{Effect, Runtime}

open =
  Effect.sync(fn -> StringIO.open("tea\ncoffee\n") end)
  |> Effect.flat_map(&Effect.from_result/1)

first_line =
  Effect.acquire_release_with(
    open,
    fn device -> Effect.sync(fn -> IO.read(device, :line) end) end,
    fn device -> Effect.sync(fn -> StringIO.close(device) end) end
  )

{:ok, "tea\n"} = Runtime.run(first_line)
```

A failed acquisition skips both callbacks. On success the runtime installs the finalizer before invoking the use callback, so even an exception while constructing the use effect triggers release. A successful release preserves the original outcome. A release effect that fails supplies the final failure.

Use `Effect.ensuring(work, finalizer)` when cleanup has no need for an acquired value. These finalizers run as the interpreter handles success or unwinds a cause. Killing the executing BEAM process can prevent it from running cleanup.
