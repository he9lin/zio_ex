defmodule ZioEx.Schema do
  @moduledoc """
  Describes data shared by the JSON codec and Markdown renderer. Every declared
  record field is required on the wire. Fields omitted from the schema are local
  to the struct and retain their defaults when decoding.
  """

  @type t :: :string | :integer | :boolean | {:list, t()} | {:record, module(), [{atom(), t()}]}

  @spec string() :: t()
  def string, do: :string
  @spec integer() :: t()
  def integer, do: :integer
  @spec boolean() :: t()
  def boolean, do: :boolean
  @spec list(t()) :: t()
  def list(item), do: {:list, item}

  @spec record(module(), [{atom(), t()}]) :: t()
  def record(module, fields) do
    spec = module.__info__(:struct) || raise ArgumentError, "#{inspect(module)} has no struct"
    keys = Keyword.keys(fields)
    unknown = keys -- Enum.map(spec, & &1.field)
    missing = for %{field: key, required: true} <- spec, key not in keys, do: key

    cond do
      Enum.uniq(keys) != keys ->
        raise ArgumentError, "duplicate fields in #{inspect(fields)}"

      unknown != [] ->
        raise ArgumentError, "unknown fields for #{inspect(module)}: #{inspect(unknown)}"

      missing != [] ->
        raise ArgumentError, "missing enforced fields for #{inspect(module)}: #{inspect(missing)}"

      true ->
        {:record, module, fields}
    end
  end
end
