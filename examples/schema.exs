Code.require_file("booking/booking_reserved_v1.exs", __DIR__)

alias BookingExample.BookingReservedV1
alias ZioEx.Schema.{JSON, Markdown}

schema = BookingReservedV1.schema()
event = struct!(BookingReservedV1, booking_id: "BK-42")

{:ok, payload} = JSON.encode(schema, event)
IO.puts(payload)
IO.inspect(JSON.decode(schema, payload), label: "Billing receives")
IO.inspect(JSON.decode(schema, ~s({"booking_id":42})), label: "Invalid payload")
IO.puts(Markdown.render(schema))
