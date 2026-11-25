# Schemas

A schema is a value describing the shape of your data. Use the same declaration to read and write JSON payloads and to document their fields. The JSON codec uses Elixir's built-in JSON module.

Run the booking event example from the project root:

```sh
mix run examples/schema.exs
```

## Declare the payload

```elixir
defmodule ReservationEvent do
  alias ZioEx.Schema

  @enforce_keys [:booking_id]
  defstruct [:booking_id]

  def schema, do: Schema.record(__MODULE__, booking_id: Schema.string())
end
```

Each declared field is required in JSON. A record schema must include its struct's enforced keys. It may omit other struct fields, which keep their local defaults on decode. Compose `Schema.string()`, `Schema.integer()`, `Schema.boolean()`, `Schema.list(item_schema)`, and nested record schemas to describe larger payloads.

## Encode, decode, and document

After defining the module above, try these calls in IEx:

```elixir
alias ZioEx.Schema.{JSON, Markdown}

schema = ReservationEvent.schema()
event = %ReservationEvent{booking_id: "BK-42"}
{:ok, bytes} = JSON.encode(schema, event)
{:ok, ^event} = JSON.decode(schema, bytes)
{:error, {:expected, [:booking_id], :string}} = JSON.decode(schema, ~s({"booking_id":42}))
IO.puts(Markdown.render(schema))
```

| Field | Type | Required |
| --- | --- | --- |
| `booking_id` | string | yes |

Encoding emits the declared fields. Decoding reads those fields by their string keys and ignores additional JSON fields. A missing field returns `{:error, {:missing, path}}`. Wrong types include the expected type and a path from the root, with zero-based indices for list items. Invalid JSON syntax returns `{:error, {:invalid_json, reason}}`. Use `Effect.from_result/1` to handle codec errors as expected effect failures.

The [booking event declaration](../examples/booking/booking_reserved_v1.exs) and [Billing consumer](../examples/booking/billing.exs) use this contract with the existing `booking.reserved.v1` outbox payload.
