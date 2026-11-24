defmodule ZioEx.Validation do
  defstruct [:result]

  def succeed(result), do: %__MODULE__{result: {:ok, result}}

  @doc "Constructs a failed validation containing one error."
  def fail(error), do: %__MODULE__{result: {:error, [error]}}

  @doc "Combines two successful values or collects both validations' errors in input order."
  def validate_with(%__MODULE__{result: {:ok, a}}, %__MODULE__{result: {:ok, b}}, combine) do
    succeed(combine.(a, b))
  end

  def validate_with(%__MODULE__{result: {:error, a}}, %__MODULE__{result: {:error, b}}, _) do
    %__MODULE__{result: {:error, a ++ b}}
  end

  def validate_with(%__MODULE__{result: {:error, _}} = invalid, %__MODULE__{}, _), do: invalid
  def validate_with(%__MODULE__{}, %__MODULE__{result: {:error, _}} = invalid, _), do: invalid

  defimpl ZioEx.Semigroup do
    def combine(left, right) do
      ZioEx.Validation.validate_with(left, right, fn a, b -> List.wrap(a) ++ List.wrap(b) end)
    end
  end
end
