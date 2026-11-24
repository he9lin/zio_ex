# ZioEx

ZioEx is a ZIO-inspired effect system for Elixir. Describe a computation as a value, compose it with other steps, then run it with the services it needs.

## Get started

From a checkout with Elixir `~> 1.19`, fetch the dependencies and open IEx:

```sh
mix deps.get
iex -S mix
```

Paste this into IEx. The same greeting program can run with different environments.

```elixir
alias ZioEx.{Effect, Runtime}

greeting =
  Effect.require(:name)
  |> Effect.map(fn name -> "Hello, #{name}!" end)

{:ok, "Hello, Ada!"} = Runtime.run(greeting, %{name: "Ada"})
{:error, %ZioEx.Cause.Fail{error: {:missing_service, :name}}} = Runtime.run(greeting)
```

To use this checkout from another Mix project, add `{:zio_ex, path: "../zio_ex"}` to its dependencies, adjust the path to your checkout, and run `mix deps.get`.

## Explore the guides

| Guide | What you can do |
| --- | --- |
| [Effects](docs/effect.md) | Sequence operations with pipelines or a `zio do` block. |
| [Runtime](docs/runtime.md) | Run programs, interpret outcomes, and observe Telemetry events. |
| [Errors and recovery](docs/errors.md) | Translate expected errors, recover, and inspect parallel failures. |
| [Environment](docs/environment.md) | Look up services, supply local values, and adapt an environment. |
| [Layers](docs/layer.md) | Build, wire, and share service implementations. |
| [Workflows](docs/workflow.md) | Declare named programs and check their wiring before acquisition. |
| [Scheduling and retries](docs/schedule.md) | Limit attempts, add backoff, and recover after retries run out. |
| [Concurrency](docs/concurrency.md) | Fork and join fibers, run two effects in parallel, and use callbacks. |
| [Collection traversal](docs/traversal.md) | Apply an effect to each item with bounded concurrency. |
| [Resources and finalizers](docs/resources.md) | Release a resource after successful or failed use. |
| [Atomic references](docs/ref.md) | Share mutable state between concurrent effects. |
| [Validation](docs/validation.md) | Collect independent errors and construct a validated value. |
| [Option and Result](docs/option-and-result.md) | Bring optional values and tagged tuples into an effect. |
