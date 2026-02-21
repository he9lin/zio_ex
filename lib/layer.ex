defmodule ZioEx.Layer do
  alias ZioEx.Effect

  @doc """
  Constructs a layer from a simple key-value pair.
  Equivalent to ZLayer.succeed.
  """
  def succeed(key, service) do
    Effect.succeed(%{key => service})
  end

  @doc """
  If we want to pipe an Effect into a Layer, the key should come last.
  Usage: Effect.access(...) |> Layer.from_effect(:db)
  """
  def from_effect(effect, key) do
    Effect.map(effect, fn service ->
      %{key => service}
    end)
  end

  @doc """
  Constructs a layer that requires dependencies from the environment.
  Equivalent to ZLayer.fromFunction.
  """
  def from_function(key, func) do
    Effect.access(fn env ->
      Effect.succeed(%{key => func.(env)})
    end)
  end

  @doc """
  Horizontal Composition (++ in ZIO).
  Combines two layers that don't depend on each other.
  """
  def and_(layer_a, layer_b) do
    Effect.flat_map(layer_a, fn map_a ->
      Effect.map(layer_b, fn map_b ->
        Map.merge(map_a, map_b)
      end)
    end)
  end

  @doc """
  Vertical Composition (>>> in ZIO).
  The output of 'left' is passed as the environment to 'right'.
  """
  def to(left_layer, right_layer) do
    Effect.flat_map(left_layer, fn env_from_left ->
      # Here is the fix:
      # Wrap the right_layer so it executes INSIDE the context of env_from_left
      Effect.provide_context(right_layer, env_from_left)
    end)
  end
end
