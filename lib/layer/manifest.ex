defmodule ZioEx.Layer.Manifest do
  @moduledoc false

  @type t ::
          {:provider, [term()], :unknown | [term()]}
          | {:to | :and, t(), t()}
  @type error :: {:missing_inputs, [term()], [term()]} | {:duplicate_outputs, [term()]}

  @spec check(t(), [term()]) :: {:ok, [term()]} | {:error, error()}
  def check({:provider, outputs, :unknown}, _available), do: {:ok, outputs}

  def check({:provider, outputs, inputs}, available) do
    case inputs -- available do
      [] -> {:ok, outputs}
      missing -> {:error, {:missing_inputs, missing, outputs}}
    end
  end

  def check({:to, left, right}, available) do
    with {:ok, outputs} <- check(left, available), do: check(right, outputs)
  end

  def check({:and, left, right}, available) do
    with {:ok, a} <- check(left, available), {:ok, b} <- check(right, available) do
      case Enum.filter(a, &(&1 in b)) do
        [] -> {:ok, a ++ b}
        duplicates -> {:error, {:duplicate_outputs, duplicates}}
      end
    end
  end
end
