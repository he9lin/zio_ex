defmodule ZioEx.Schema.Markdown do
  @moduledoc "Renders a schema as a Markdown field table in declaration order."

  alias ZioEx.Schema

  @spec render(Schema.t()) :: String.t()
  def render(schema) do
    rows =
      case schema do
        {:record, _, _} -> children(schema, "")
        _ -> rows(schema, "$")
      end

    IO.iodata_to_binary(["| Field | Type | Required |\n| --- | --- | --- |\n", rows])
  end

  defp rows(schema, path) do
    [
      "| `",
      String.replace(path, "|", "\\|"),
      "` | ",
      type_name(schema),
      " | yes |\n",
      children(schema, path)
    ]
  end

  defp children({:record, _, fields}, path) do
    Enum.map(fields, fn {key, schema} ->
      field = Atom.to_string(key)
      rows(schema, if(path == "", do: field, else: path <> "." <> field))
    end)
  end

  defp children({:list, item}, path), do: children(item, path <> "[]")
  defp children(_, _), do: []

  defp type_name({:record, module, _}), do: module |> Module.split() |> List.last()
  defp type_name({:list, item}), do: "list of " <> type_name(item)
  defp type_name(type), do: Atom.to_string(type)
end
