# Named workflows

Declare a workflow when you want to check its required services before building them. Put common requirements in the module's `requirements` block. Each workflow also tracks its own literal `require_service/1` calls. Declare indirect and dynamic lookups with the workflow's `requires:` option.

```elixir
defmodule BookingExample do
  use ZioEx.Workflow
  import ZioEx.Macros, only: [zio: 1]
  alias ZioEx.{Effect, Workflow}

  requirements do
    field(:tenant)
  end

  workflow :receipt do
    zio do
      tenant <- Workflow.require_service(:tenant)
      currency <- Workflow.require_service(:currency)
      Effect.succeed({tenant, currency})
    end
  end
end

alias ZioEx.{Layer, Workflow}
live = Layer.and_(Layer.succeed(:tenant, :acme), Layer.succeed(:currency, "USD"))

{:ok, {:acme, "USD"}} = Workflow.run(BookingExample, :receipt, live)
```

`Workflow.run/3` checks the selected workflow's requirements and the declared inputs of the [layer graph](layer.md). Missing inputs, missing workflow services, and duplicate parallel outputs raise before acquisition. After validation, a builder or workflow can still return an effect failure.

To check wiring without running the workflow, call `ZioEx.Runtime.Validator.validate!(BookingExample, :receipt, live)`. The two-argument form checks the requirements of the whole module. Declarations are collected at compile time and checked against the supplied layer when validation runs.
