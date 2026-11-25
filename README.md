# ZioEx

ZioEx is a ZIO-inspired effect system for Elixir. Describe a computation as a value, compose it with other steps, then run it with the services it needs.

## Get started

From a checkout with Elixir `~> 1.19`, open IEx. The library, examples, and tests use only Elixir and Erlang/OTP.

```sh
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

## Try appointment booking

Run three bookings against an in-memory reservation store and a scripted SMS provider:

```sh
mix run examples/booking.exs
```

An invalid request reports both missing contact fields before the store or gateway is called. If the gateway goes offline after a reservation is saved, the workflow retries just the text. The temporary outage ends with one reservation and three delivery attempts. If all attempts fail, the caller still receives the booking reference with confirmation pending. Each scenario starts with an empty store. [Booking workflow](examples/booking/workflow.exs) · [Demo adapters](examples/booking/demo.exs)

### Deliver a reservation to Billing after a restart

The example uses Mnesia, included with Erlang/OTP. Run each command separately using the same data directory:

```sh
booking_dir="$(mktemp -d)"
mix run examples/booking_billing.exs book "$booking_dir"
mix run examples/booking_billing.exs bill "$booking_dir"
mix run examples/booking_billing.exs bill "$booking_dir"
```

Booking commits the reservation and its JSON outbox event together. The first Billing run creates an invoice draft. The second finds no pending events and shows the same draft. Keep the data directory across restarts and run one local VM against it at a time.

Billing records its receipt and invoice draft in a single transaction. The receipt key identifies the consumer and event, and the draft key identifies the booking. Concurrent redeliveries therefore produce one draft. [Booking and Billing example](examples/booking/billing.exs) · [Redelivery and rollback tests](test/booking_billing_test.exs)

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
| [Schemas](docs/schema.md) | Encode and decode a struct as JSON and render its fields as Markdown. |
| [Validation](docs/validation.md) | Collect independent errors and construct a validated value. |
| [Option and Result](docs/option-and-result.md) | Bring optional values and tagged tuples into an effect. |
