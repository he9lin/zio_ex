defmodule ZioEx.Schema.JSON do
  @moduledoc "Encodes and decodes schema values using Elixir's built-in JSON module."

  alias ZioEx.Schema
  @type path :: [atom() | non_neg_integer()]
  @type error :: {:missing, path()} | {:expected, path(), atom()} | {:invalid_json, term()}

  @spec encode(Schema.t(), term()) :: {:ok, binary()} | {:error, error()}
  def encode(schema, value) do
    with {:ok, wire} <- convert(schema, value, [], :encode), do: {:ok, Elixir.JSON.encode!(wire)}
  end

  @spec decode(Schema.t(), binary()) :: {:ok, term()} | {:error, error()}
  def decode(schema, bytes) do
    case Elixir.JSON.decode(bytes) do
      {:ok, wire} -> convert(schema, wire, [], :decode)
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp convert(:string, value, path, _) when is_binary(value) do
    if String.valid?(value), do: {:ok, value}, else: expected(path, :string)
  end

  defp convert(:integer, value, _, _) when is_integer(value), do: {:ok, value}
  defp convert(:boolean, value, _, _) when is_boolean(value), do: {:ok, value}

  defp convert({:list, item}, values, path, mode) when is_list(values) do
    convert_items(values, item, path, mode, 0, [])
  end

  defp convert({:list, _}, _, path, _), do: expected(path, :list)

  defp convert({:record, module, fields}, value, path, :encode) when is_struct(value, module) do
    convert_fields(fields, value, path, :encode)
  end

  defp convert({:record, module, fields}, wire, path, :decode) when is_map(wire) do
    with {:ok, attrs} <- convert_fields(fields, wire, path, :decode),
         do: {:ok, struct!(module, attrs)}
  end

  defp convert({:record, module, _}, _, path, _), do: expected(path, module)
  defp convert(type, _, path, _) when is_atom(type), do: expected(path, type)

  defp convert_fields(fields, input, path, mode) do
    Enum.reduce_while(fields, {:ok, %{}}, fn {field, schema}, {:ok, acc} ->
      wire_key = Atom.to_string(field)
      {source, target} = if mode == :encode, do: {field, wire_key}, else: {wire_key, field}
      field_path = [field | path]

      with {:ok, raw} <- Map.fetch(input, source),
           {:ok, value} <- convert(schema, raw, field_path, mode) do
        {:cont, {:ok, Map.put(acc, target, value)}}
      else
        :error -> {:halt, {:error, {:missing, Enum.reverse(field_path)}}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp convert_items([], _, _, _, _, acc), do: {:ok, Enum.reverse(acc)}

  defp convert_items([value | rest], schema, path, mode, index, acc) do
    with {:ok, item} <- convert(schema, value, [index | path], mode) do
      convert_items(rest, schema, path, mode, index + 1, [item | acc])
    end
  end

  defp convert_items(_, _, path, _, _, _), do: expected(path, :list)

  defp expected(path, type), do: {:error, {:expected, Enum.reverse(path), type}}
end
