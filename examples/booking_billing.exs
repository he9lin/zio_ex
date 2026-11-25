Code.require_file("booking/workflow.exs", __DIR__)
Code.require_file("booking/billing.exs", __DIR__)

alias BookingExample.{Billing, Booking, Store}
alias ZioEx.{Effect, Layer, Runtime, Workflow}

case System.argv() do
  [command, dir] when command in ["book", "bill"] ->
    Store.open!(dir)

    try do
      case command do
        "book" ->
          request = %{name: "Ada", phone: "+12025550123", slot: ~N[2027-01-12 10:00:00]}

          services =
            Layer.succeed(:request, request)
            |> Layer.and_(Layer.succeed(:reserve, &Store.reserve/1))
            |> Layer.and_(Layer.succeed(:send_sms, fn _, _ -> Effect.succeed(:sent) end))

          IO.inspect(Workflow.run(Booking, :book, services), label: "Booking")

        "bill" ->
          IO.inspect(Runtime.run(Billing.catch_up()), label: "Billing events")
          IO.inspect(:mnesia.dirty_all_keys(:drafts), label: "Invoice drafts")
      end
    after
      :mnesia.stop()
    end

  _ ->
    raise ArgumentError, "usage: mix run examples/booking_billing.exs (book|bill) DATA_DIRECTORY"
end
