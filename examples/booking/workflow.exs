defmodule BookingExample.Request do
  alias ZioEx.Validation

  @enforce_keys [:name, :phone, :slot]
  defstruct @enforce_keys

  def validate(input) do
    contact =
      Validation.validate_with(required(input, :name), required(input, :phone), &{&1, &2})

    slot =
      case Map.get(input, :slot) do
        %NaiveDateTime{} = time -> Validation.succeed(time)
        _ -> Validation.fail({:slot, :invalid})
      end

    Validation.validate_with(contact, slot, fn {name, phone}, time ->
      %__MODULE__{name: name, phone: phone, slot: time}
    end)
  end

  defp required(input, key) do
    with value when is_binary(value) <- Map.get(input, key),
         trimmed when trimmed != "" <- String.trim(value) do
      Validation.succeed(trimmed)
    else
      _ -> Validation.fail({key, :required})
    end
  end
end

defmodule BookingExample.Booking do
  use ZioEx.Workflow
  import ZioEx.Macros, only: [zio: 1]
  alias BookingExample.Request
  alias ZioEx.{Effect, Schedule, Workflow}

  workflow :book do
    zio do
      input <- Workflow.require_service(:request)
      request <- Effect.from_result(Request.validate(input).result)
      reserve <- Workflow.require_service(:reserve)
      send_sms <- Workflow.require_service(:send_sms)
      reference <- reserve.(request)

      # Once the slot is reserved, only delivery is safe to repeat here.
      confirmation <-
        send_sms.(request.phone, reference)
        |> Effect.retry_or_else(Schedule.recurs(2), fn :offline, _ -> Effect.succeed(:pending) end)

      Effect.succeed(%{reference: reference, confirmation: confirmation})
    end
  end
end
