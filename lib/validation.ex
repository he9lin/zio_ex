defmodule ZioEx.Validation do
  defstruct [:result]

  def succeed(result), do: %__MODULE__{result: {:ok, result}}

  defimpl ZioEx.Semigroup, for: ZioEx.Validation do
    alias ZioEx.Validation

    def combine(%{result: r1}, %{result: r2}) do
      case {r1, r2} do
        # We wrap 'a' and 'b' to ensure we are always concatenating lists
        {{:ok, a}, {:ok, b}} ->
          Validation.succeed(List.wrap(a) ++ List.wrap(b))

        # Errors already use lists, so we just ++ them
        {{:error, e1}, {:error, e2}} ->
          %Validation{result: {:error, e1 ++ e2}}

        # Short-circuiting logic: Error always wins over OK
        {{:error, _}, _} ->
          %Validation{result: r1}

        {_, {:error, _}} ->
          %Validation{result: r2}
      end
    end
  end
end
