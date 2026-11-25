Code.require_file("booking/workflow.exs", __DIR__)
Code.require_file("booking/demo.exs", __DIR__)

alias BookingExample.Demo
alias ZioEx.Cause

request = %{name: "Ada", phone: "+12025550123", slot: ~N[2027-01-12 10:00:00]}

for {label, input, outcomes} <- [
      {"Invalid request", %{request | name: "", phone: nil}, []},
      {"Temporary SMS outage", request, [:offline, :offline, :sent]},
      {"Prolonged SMS outage", request, [:offline, :offline, :offline]}
    ] do
  {result, state} = Demo.run(input, outcomes)
  IO.puts(label)

  for {attempt, index} <- Enum.with_index(state.attempts, 1) do
    IO.puts("  SMS attempt #{index} for #{attempt.reference}: #{attempt.outcome}")
  end

  case result do
    {:error, %Cause.Fail{error: errors}} ->
      IO.puts("  Rejected: #{inspect(errors)}")

    {:ok, booking} ->
      IO.puts("  Reserved #{booking.reference}, confirmation #{booking.confirmation}")
  end

  IO.puts(
    "  Reservations: #{map_size(state.reservations)}, SMS attempts: #{length(state.attempts)}\n"
  )
end
