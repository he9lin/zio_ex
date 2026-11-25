# Option and Result

`Option` represents presence as `{:some, value}` and absence as `:none`. Its helpers include `map/2`, `flat_map/2`, `filter/2`, and `get_or_else/2`. When absence should fail a workflow, use `Effect.from_option/2` with the reason to return. For a value that may be `nil`, `Effect.from_nullable/2` performs the same conversion directly.

```elixir
alias ZioEx.{Cause, Effect, Option, Runtime}

quantity = Option.some(3) |> Option.filter(&(&1 > 0))
{:ok, 3} = Runtime.run(Effect.from_option(quantity, :invalid_quantity))
{:error, %Cause.Fail{error: :missing}} = Runtime.run(Effect.from_nullable(nil, :missing))
```

`Result` is a struct with helpers for transforming either side of a tagged result. Use `Result.from_tuple/1` and `Result.to_tuple/1` at its boundaries. If you already have an Elixir result tuple, pass it directly to `Effect.from_result/1`.

```elixir
alias ZioEx.{Effect, Result, Runtime}

price =
  {:ok, 450}
  |> Result.from_tuple()
  |> Result.map(&(&1 * 2))
  |> Result.to_tuple()
  |> Effect.from_result()

{:ok, 900} = Runtime.run(price)
```

These conversions operate on values. To defer a call such as `File.read/1`, put it inside `Effect.sync/1`, then use `Effect.flat_map(&Effect.from_result/1)` in the pipeline.
