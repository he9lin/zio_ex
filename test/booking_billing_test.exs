Code.require_file("../examples/booking/workflow.exs", __DIR__)
Code.require_file("../examples/booking/billing.exs", __DIR__)

defmodule BookingBillingTest do
  # Each test owns the node-local Mnesia instance and its temporary directory.
  use ExUnit.Case, async: false

  alias BookingExample.{Billing, Booking, Store}
  alias ZioEx.{Effect, Layer, Runtime, Workflow}

  @moduletag :tmp_dir
  setup %{tmp_dir: dir} do
    previous = Application.fetch_env(:mnesia, :dir)
    Store.open!(dir)

    on_exit(fn ->
      :mnesia.stop()

      case previous do
        {:ok, value} -> Application.put_env(:mnesia, :dir, value)
        :error -> Application.delete_env(:mnesia, :dir)
      end
    end)

    :ok
  end

  defp book do
    services =
      Layer.succeed(:request, %{name: "Ada", phone: "+12025550123", slot: ~N[2027-01-12 10:00:00]})
      |> Layer.and_(Layer.succeed(:reserve, &Store.reserve/1))
      |> Layer.and_(Layer.succeed(:send_sms, fn _, _ -> Effect.succeed(:sent) end))

    Workflow.run(Booking, :book, services)
  end

  test "a fresh Billing worker catches up after a store restart", %{tmp_dir: dir} do
    assert {:ok, %{reference: ref}} = book()
    assert {:ok, [event]} = Runtime.run(Billing.pending())
    assert %{"booking_id" => ^ref} = JSON.decode!(event.payload)
    :stopped = :mnesia.stop()
    Store.open!(dir)
    assert {:ok, [^event]} = Runtime.run(Billing.pending())
    assert {:ok, [:processed]} = Runtime.run(Billing.catch_up())
    assert {:ok, []} = Runtime.run(Billing.catch_up())
    assert [ref] == :mnesia.dirty_all_keys(:drafts)
  end

  test "two workers receive the same event and a distinct event for the same booking" do
    {:ok, %{reference: ref}} = book()
    {:ok, [event]} = Runtime.run(Billing.pending())
    parent = self()

    workers =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :deliver -> Runtime.run(Billing.deliver(event))
          end
        end)
      end

    for task <- workers do
      pid = task.pid
      assert_receive {:ready, ^pid}
    end

    Enum.each(workers, &send(&1.pid, :deliver))
    assert Enum.sort(Task.await_many(workers)) == [ok: :duplicate, ok: :processed]
    assert {:ok, :processed} = Runtime.run(Billing.deliver(%{event | event_id: "second-event"}))
    assert [ref] == :mnesia.dirty_all_keys(:drafts)

    assert Enum.sort(:mnesia.dirty_all_keys(:receipts)) ==
             Enum.sort([{:billing_invoices, event.event_id}, {:billing_invoices, "second-event"}])
  end

  test "Billing consumes a v1 payload saved before schemas were introduced" do
    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        :mnesia.write(
          {:outbox, "historical-event", "booking.reserved.v1", ~s({"booking_id":"BK-42"})}
        )
      end)

    assert {:ok, [:processed]} = Runtime.run(Billing.catch_up())
    assert ["BK-42"] == :mnesia.dirty_all_keys(:drafts)
  end

  test "an invalid booking payload fails before Billing records a receipt or draft" do
    event = %{event_id: "invalid-event", payload: ~s({"booking_id":42})}

    assert {:error, %ZioEx.Cause.Fail{error: {:expected, [:booking_id], :string}}} =
             Runtime.run(Billing.deliver(event))

    assert [] == :mnesia.dirty_all_keys(:receipts)
    assert [] == :mnesia.dirty_all_keys(:drafts)
  end

  test "failed outbox and draft writes roll back reservations and receipts", %{tmp_dir: dir} do
    {:atomic, :ok} = :mnesia.delete_table(:outbox)
    assert {:error, _} = book()
    assert [] == :mnesia.dirty_all_keys(:reservations)
    :stopped = :mnesia.stop()
    Store.open!(dir)
    assert {:ok, _} = book()
    {:atomic, :ok} = :mnesia.delete_table(:drafts)
    assert {:error, _} = Runtime.run(Billing.catch_up())
    assert [] == :mnesia.dirty_all_keys(:receipts)
    :stopped = :mnesia.stop()
    Store.open!(dir)
    assert {:ok, [:processed]} = Runtime.run(Billing.catch_up())
  end
end
