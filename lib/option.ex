defmodule ZioEx.Option do
  @moduledoc "A simple Maybe/Option monad."

  def some(val), do: {:some, val}
  def none(), do: :none

  @doc "Lifts an Option into an Effect. If :none, it fails with a specific error."
  def to_effect({:some, val}, _on_none), do: ZioEx.Effect.succeed(val)
  def to_effect(:none, on_none), do: ZioEx.Effect.fail(on_none)

  def map({:some, val}, f), do: some(f.(val))
  def map(:none, _f), do: :none

  def get_or_else({:some, val}, _default), do: val
  def get_or_else(:none, default), do: default

  def flat_map({:some, val}, f), do: f.(val)
  def flat_map(:none, _f), do: :none

  def or_else({:some, val}, _other), do: some(val)
  def or_else(:none, other), do: other

  def filter({:some, val}, pred), do: if(pred.(val), do: some(val), else: none())
  def filter(:none, _pred), do: :none
end
