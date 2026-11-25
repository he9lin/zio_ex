defmodule BookingExample.Demo do
  alias BookingExample.Booking
  alias ZioEx.{Effect, Layer, Workflow}

  def run(request, sms_outcomes) do
    {:ok, store} = Agent.start_link(fn -> %{} end)

    try do
      {:ok, gateway} = Agent.start_link(fn -> {sms_outcomes, []} end)

      try do
        services =
          Layer.succeed(:request, request)
          |> Layer.and_(Layer.succeed(:reserve, &reserve(store, &1)))
          |> Layer.and_(Layer.succeed(:send_sms, &send_sms(gateway, &1, &2)))

        result = Workflow.run(Booking, :book, services)
        reservations = Agent.get(store, & &1)
        attempts = Agent.get(gateway, fn {_, history} -> Enum.reverse(history) end)
        {result, %{reservations: reservations, attempts: attempts}}
      after
        Agent.stop(gateway)
      end
    after
      Agent.stop(store)
    end
  end

  defp reserve(store, request) do
    Effect.sync(fn ->
      Agent.get_and_update(store, fn bookings ->
        if Map.has_key?(bookings, request.slot) do
          {{:error, :slot_taken}, bookings}
        else
          reference = "BK-#{map_size(bookings) + 1}"
          booking = %{reference: reference, request: request}
          {{:ok, reference}, Map.put(bookings, request.slot, booking)}
        end
      end)
    end)
    |> Effect.flat_map(&Effect.from_result/1)
  end

  defp send_sms(gateway, phone, reference) do
    Effect.sync(fn ->
      Agent.get_and_update(gateway, fn {outcomes, history} ->
        {outcome, rest} = List.pop_at(outcomes, 0, :offline)
        attempt = %{phone: phone, reference: reference, outcome: outcome}
        {outcome, {rest, [attempt | history]}}
      end)
    end)
    |> Effect.flat_map(fn
      :sent -> Effect.succeed(:sent)
      :offline -> Effect.fail(:offline)
    end)
  end
end
