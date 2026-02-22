defmodule ZioEx.Layer do
  alias ZioEx.Effect

  defstruct [:effect, :keys]

  @doc "Retrieves the keys from a layer manifest."
  def keys(%__MODULE__{keys: keys}), do: keys

  @doc """
  Constructs a layer from a simple key-value pair.
  Equivalent to ZLayer.succeed.
  """
  def succeed(key, service) do
    %__MODULE__{
      keys: List.wrap(key),
      effect: Effect.succeed(%{key => service})
    }
  end

  @doc """
  If we want to pipe an Effect into a Layer, the key should come last.
  Usage: Effect.access(...) |> Layer.from_effect(:db)
  """
  def from_effect(effect, key) do
    %__MODULE__{
      keys: [key],
      effect:
        Effect.map(effect, fn service ->
          %{key => service}
        end)
    }
  end

  @doc """
  Constructs a layer that requires dependencies from the environment.
  Equivalent to ZLayer.fromFunction.
  """
  def from_function(key, func) do
    %__MODULE__{
      keys: [key],
      effect:
        Effect.access(fn env ->
          Effect.succeed(%{key => func.(env)})
        end)
    }
  end

  @doc """
  Horizontal Composition (++ in ZIO).
  Combines two layers that don't depend on each other.
  """
  def and_(layer_a, layer_b) do
    %__MODULE__{
      keys: Enum.uniq(layer_a.keys ++ layer_b.keys),
      effect:
        ZioEx.Effect.zip_par(layer_a.effect, layer_b.effect)
        |> ZioEx.Effect.map(fn {a, b} -> Map.merge(a, b) end)
    }
  end

  @doc """
  Vertical composition: Layer A is used to satisfy the requirements of Layer B.
  The resulting Layer only 'promises' the keys of B.
  """
  def to(%__MODULE__{} = layer_a, %__MODULE__{} = layer_b) do
    %__MODULE__{
      # The output of this pipeline is Layer B's services
      keys: layer_b.keys,
      effect:
        ZioEx.Effect.flat_map(layer_a.effect, fn env_a ->
          # We take the map produced by A and 'provide' it to B's effect
          ZioEx.Effect.provide_context(layer_b.effect, env_a)
        end)
    }
  end

  @doc """
  Ensures the layer's effect is only executed once.
  Subsequent requests for this layer will return the cached environment.
  """
  def memoize(%__MODULE__{} = layer) do
    {:ok, cache} = Agent.start_link(fn -> :uninitialized end)

    memoized_effect =
      Effect.sync(fn ->
        case Agent.get_and_update(cache, fn
          {:result, env} -> {{:cached, env}, {:result, env}}
          {:task, task} -> {{:await, task}, {:task, task}}
          :uninitialized ->
            task = Task.async(fn ->
              {:ok, env} = ZioEx.Runtime.run(layer.effect)
              env
            end)
            {{:run, task}, {:task, task}}
        end) do
          {:cached, env} -> env
          {:await, task} -> Task.await(task)
          {:run, task} ->
            env = Task.await(task)
            Agent.update(cache, fn _ -> {:result, env} end)
            env
        end
      end)

    %{layer | effect: memoized_effect}
  end
end
