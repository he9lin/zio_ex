defmodule BookingExample.BookingReservedV1 do
  alias ZioEx.Schema

  @enforce_keys [:booking_id]
  defstruct [:booking_id]

  def schema, do: Schema.record(__MODULE__, booking_id: Schema.string())
end
