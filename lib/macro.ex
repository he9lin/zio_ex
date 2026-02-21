defmodule ZioEx.Macros do
  # - expand returns [expr]; use unquote_splicing so variables from the block
  #   stay in scope (quote handles hygiene)
  # - lhs from {:<-, _, [lhs, rhs]} is used directly in fn unquote(lhs) ->

  defmacro zio(do: block) do
    block
    |> block_to_lines()
    |> expand()
    |> hd()
  end

  defp block_to_lines({:__block__, _, lines}), do: lines
  defp block_to_lines(single), do: [single]

  def expand([line]) do
    case line do
      {:<-, _, [_, _]} -> raise "A zio block cannot end with an arrow (<-)"
      other -> [other]
    end
  end

  def expand([{:<-, _, [lhs, rhs]} | exprs]) do
    [
      quote do
        ZioEx.Effect.flat_map(unquote(rhs), fn unquote(lhs) ->
          (unquote_splicing(expand(exprs)))
        end)
      end
    ]
  end

  def expand([expr | exprs]) do
    [
      quote do
        ZioEx.Effect.flat_map(unquote(expr), fn _ ->
          (unquote_splicing(expand(exprs)))
        end)
      end
    ]
  end
end
