# Mix prunes unused OTP applications. Load the bundled store only for this example.
Mix.ensure_application!(:mnesia)
Code.require_file("booking_reserved_v1.exs", __DIR__)

defmodule BookingExample.Store do
  alias BookingExample.BookingReservedV1
  alias ZioEx.Schema.JSON
  alias ZioEx.Effect

  @tables [
    reservations: [:slot, :reference, :request],
    outbox: [:event_id, :type, :payload],
    receipts: [:consumer_event, :booking_id],
    drafts: [:booking_id, :status]
  ]

  # This standalone example owns the local node's Mnesia instance.
  def open!(dir) do
    :no = :mnesia.system_info(:is_running)
    File.mkdir_p!(dir)
    Application.put_env(:mnesia, :dir, dir |> Path.expand() |> String.to_charlist())

    case :mnesia.create_schema([node()]) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
    end

    :ok = :mnesia.start()

    for {table, fields} <- @tables do
      case :mnesia.create_table(table, attributes: fields, disc_copies: [node()]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^table}} -> :ok
      end
    end

    :ok = :mnesia.wait_for_tables(Keyword.keys(@tables), 5000)
  end

  def transaction(fun) do
    Effect.sync(fn -> :mnesia.sync_transaction(fun) end)
    |> Effect.flat_map(fn
      {:atomic, value} -> Effect.succeed(value)
      {:aborted, reason} -> Effect.fail(reason)
    end)
  end

  def reserve(request) do
    transaction(fn ->
      if :mnesia.read(:reservations, request.slot, :write) != [], do: :mnesia.abort(:slot_taken)
      # One reservation emits one reserved event. Both identities survive redelivery.
      reference = "BK-" <> Base.encode16(:crypto.strong_rand_bytes(8))
      id = "booking.reserved.v1/" <> reference
      event = %BookingReservedV1{booking_id: reference}
      {:ok, payload} = JSON.encode(BookingReservedV1.schema(), event)
      :mnesia.write({:reservations, request.slot, reference, request})
      :mnesia.write({:outbox, id, "booking.reserved.v1", payload})
      reference
    end)
  end
end

defmodule BookingExample.Billing do
  alias BookingExample.{BookingReservedV1, Store}
  alias ZioEx.Schema.JSON
  alias ZioEx.Effect

  def pending do
    Store.transaction(fn ->
      for {:outbox, id, _, payload} <-
            :mnesia.match_object({:outbox, :_, "booking.reserved.v1", :_}),
          :mnesia.read(:receipts, {:billing_invoices, id}) == [] do
        %{event_id: id, payload: payload}
      end
    end)
  end

  def catch_up,
    do: Effect.flat_map(pending(), fn events -> Effect.foreach(events, &deliver/1) end)

  def deliver(%{event_id: id, payload: payload}) do
    Store.transaction(fn ->
      key = {:billing_invoices, id}

      case :mnesia.read(:receipts, key, :write) do
        [] ->
          booking_id =
            case JSON.decode(BookingReservedV1.schema(), payload) do
              {:ok, event} -> event.booking_id
              {:error, reason} -> :mnesia.abort(reason)
            end

          :mnesia.write({:receipts, key, booking_id})

          if :mnesia.read(:drafts, booking_id, :write) == [] do
            :mnesia.write({:drafts, booking_id, :draft})
          end

          :processed

        [_receipt] ->
          :duplicate
      end
    end)
  end
end
