# Collection traversal

`Effect.foreach/3` applies an effect-returning function to each item in an enumerable. It collects successful values in input order. The default runs one item at a time in the caller, stopping at the first failure. An empty input succeeds with an empty list.

```elixir
alias ZioEx.{Effect, Runtime}

prices = %{"tea" => 450, "coffee" => 500, "water" => 200}
fetch_price = fn sku ->
  Effect.access(fn %{prices: catalog} -> Map.fetch!(catalog, sku) end)
end

basket = Effect.foreach(["coffee", "water", "tea"], fetch_price, max_concurrency: 2)
{:ok, [500, 200, 450]} = Runtime.run(basket, %{prices: prices})
```

Set `max_concurrency` to a positive integer. With a limit above one, the runtime starts a batch of up to that size and waits for the entire batch before starting another. If items in the batch fail, their finalizers run and traversal returns the first failure in input order. To retain several independent validation errors, see [validation](validation.md).
