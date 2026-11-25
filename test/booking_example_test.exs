Code.require_file("../examples/booking/workflow.exs", __DIR__)
Code.require_file("../examples/booking/demo.exs", __DIR__)

defmodule BookingExampleTest do
  use ExUnit.Case, async: true

  alias BookingExample.{Demo, Request}
  alias ZioEx.{Cause, Validation}

  @request %{name: " Ada ", phone: "+12025550123", slot: ~N[2027-01-12 10:00:00]}

  test "valid contact details and a selected slot produce a normalized request" do
    assert %Validation{result: {:ok, %Request{name: "Ada", phone: "+12025550123", slot: slot}}} =
             Request.validate(@request)

    assert slot == @request.slot
  end

  test "invalid contact details return both errors before reserving or texting" do
    {result, state} = Demo.run(%{name: " ", slot: @request.slot}, [])
    assert {:error, %Cause.Fail{error: [name: :required, phone: :required]}} = result
    assert state.reservations == %{}
    assert state.attempts == []
  end

  test "successful first delivery needs only one attempt" do
    {result, state} = Demo.run(@request, [:sent])
    assert {:ok, %{reference: ref, confirmation: :sent}} = result
    assert [%{reference: ^ref, outcome: :sent}] = state.attempts
  end

  test "a temporary outage retries delivery against the same saved reservation" do
    {result, state} = Demo.run(@request, [:offline, :offline, :sent])
    assert {:ok, %{reference: ref, confirmation: :sent}} = result

    assert %{reference: ^ref, request: %Request{name: "Ada"}} =
             Map.fetch!(state.reservations, @request.slot)

    assert map_size(state.reservations) == 1

    assert Enum.map(state.attempts, &{&1.reference, &1.phone, &1.outcome}) ==
             [
               {ref, @request.phone, :offline},
               {ref, @request.phone, :offline},
               {ref, @request.phone, :sent}
             ]
  end

  test "exhausted delivery returns the saved reference with confirmation pending" do
    {result, state} = Demo.run(@request, [:offline, :offline, :offline, :sent])
    assert {:ok, %{reference: ref, confirmation: :pending}} = result
    assert map_size(state.reservations) == 1
    assert Map.fetch!(state.reservations, @request.slot).reference == ref
    assert Enum.map(state.attempts, & &1.outcome) == [:offline, :offline, :offline]
  end
end
