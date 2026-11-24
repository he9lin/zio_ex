# Environment

Supply a map as the second argument to `Runtime.run/2`. `Effect.require(key)` produces an expected `{:missing_service, key}` error for a missing key. Use `Effect.access(:key)` when `nil` is an acceptable default. `Effect.access()` returns the entire map.

`contramap/2` adapts the caller's environment to the map a particular effect expects. Here a formatter can read `:currency` directly even though the application's settings are nested.

```elixir
alias ZioEx.{Effect, Runtime}

formatter = Effect.require(:currency) |> Effect.map(fn currency -> "#{currency} 10" end)
checkout = Effect.contramap(formatter, fn env -> env.tenant.settings end)

{:ok, "EUR 10"} = Runtime.run(checkout, %{tenant: %{settings: %{currency: "EUR"}}})
```

`provide_context(effect, map)` replaces the environment for that effect. Enclosing steps see their original environment again after success or failure. `provide(effect, layer)` builds services and merges them over the current environment. See [layers](layer.md).
