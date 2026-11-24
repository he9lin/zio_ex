# Atomic references

`Ref.make/1` creates an Agent-backed reference when its effect runs. `Ref.update/2` atomically replaces the current value using a function and succeeds with `:ok`. Use `Ref.get/1` to read the value. For a counter, perform the increment inside the update function so concurrent updates each see the latest state.

```elixir
alias ZioEx.{Effect, Ref, Runtime}
import ZioEx.Macros, only: [zio: 1]

count =
  zio do
    counter <- Ref.make(0)
    _ <- Effect.zip_par(Ref.update(counter, &(&1 + 1)), Ref.update(counter, &(&1 + 1)))
    Ref.get(counter)
  end

{:ok, 2} = Runtime.run(count)
```

Branches share their caller's resource scope. You can return a reference from a branch and use it later while the owner is alive. The backing Agent shuts down when the process owning the scope exits.
