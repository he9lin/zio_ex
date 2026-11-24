# Layers

A layer builds an environment map. Use `Layer.succeed/2` to provide a value, `Layer.from_function/2` to compute a service from the environment, or `Layer.from_effect/3` when building the service can itself fail as an effect.

```elixir
alias ZioEx.{Effect, Layer, Runtime}

catalog =
  Layer.from_function(:price_for,
    requires: [:prices],
    build: fn %{prices: prices} -> fn sku -> Map.fetch!(prices, sku) end end
  )

prices = Layer.succeed(:prices, %{"tea" => 450})
services = prices |> Layer.to(catalog) |> Layer.and_(Layer.succeed(:currency, "USD"))

quote_price =
  Effect.access(fn %{price_for: price_for, currency: currency} ->
    {currency, price_for.("tea")}
  end)

{:ok, {"USD", 450}} = quote_price |> Effect.provide(services) |> Runtime.run()
```

- `Layer.to(left, right)` builds the left layer and supplies its outputs as the right layer's environment. The resulting layer exports the right layer's keys. Here `:prices` is private to the construction of `:price_for`.
- `Layer.and_(left, right)` builds independent branches in parallel with the same inputs. Checked workflow wiring rejects duplicate output keys. Direct execution uses the right-hand value on collision.
- `requires:` records the inputs for preflight checks. Omitting it leaves the builder's inputs unknown. Use [Workflow.run/3](workflow.md) to check an explicit graph before its builders run.

## Sharing a service

Call `Layer.memoize(layer)` once and reuse the returned layer. The first caller supplies the build environment. Concurrent and later callers receive the same outcome, including a cached failure. The cache lives until its owning process exits. If each tenant needs a different service, create a separate memoized layer for each tenant.
