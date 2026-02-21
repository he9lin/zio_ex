defmodule ZioEx.Result do
  @moduledoc "A container for {:ok, v} | {:error, e} tuples."
  defstruct [:value, :error, :is_ok]

  # Constructors
  def ok(v), do: %__MODULE__{value: v, error: nil, is_ok: true}
  def error(e), do: %__MODULE__{value: nil, error: e, is_ok: false}

  @doc "Lifts a native Elixir tuple into a Result struct."
  def from_tuple({:ok, v}), do: ok(v)
  def from_tuple({:error, e}), do: error(e)

  @doc "Maps the value if the result is ok."
  def map(%__MODULE__{is_ok: true, value: v}, f), do: ok(f.(v))
  def map(%__MODULE__{is_ok: false} = res, _f), do: res

  @doc "Transforms the error if the result is an error."
  def map_error(%__MODULE__{is_ok: false, error: e}, f), do: error(f.(e))
  def map_error(%__MODULE__{is_ok: true} = res, _f), do: res

  @doc "Extracts the native Elixir tuple."
  def to_tuple(%__MODULE__{is_ok: true, value: v}), do: {:ok, v}
  def to_tuple(%__MODULE__{is_ok: false, error: e}), do: {:error, e}
end
