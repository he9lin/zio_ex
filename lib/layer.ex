defmodule ZioEx.Layer do
  alias ZioEx.{Effect, ResourceScope}

  defstruct [:effect, :keys, :manifest]

  @doc false
  def manifest(%__MODULE__{manifest: nil, keys: keys}), do: {:provider, keys, :unknown}
  def manifest(%__MODULE__{manifest: manifest}), do: manifest

  @doc "Retrieves the keys from a layer manifest."
  def keys(%__MODULE__{keys: keys}), do: keys

  @doc """
  Constructs a layer from a simple key-value pair.
  Equivalent to ZLayer.succeed.
  """
  def succeed(key, service) do
    %__MODULE__{
      keys: [key],
      manifest: {:provider, [key], []},
      effect: Effect.succeed(%{key => service})
    }
  end

  @doc """
  Builds a service from an effect. Declare its inputs for checked workflow wiring.

      connect_effect |> Layer.from_effect(:db, requires: [:db_url])
  """
  def from_effect(effect, key, opts \\ []) do
    opts = Keyword.validate!(opts, [:requires])

    %__MODULE__{
      keys: [key],
      manifest: provider_manifest(key, opts),
      effect:
        Effect.map(effect, fn service ->
          %{key => service}
        end)
    }
  end

  @doc """
  Builds a service value from the environment. Pass `requires:` to check the
  inputs before acquisition. The function-only form leaves its inputs unknown.

      Layer.from_function(:db, requires: [:db_url], build: fn %{db_url: url} -> DB.new(url) end)
  """
  def from_function(key, func) when is_function(func, 1), do: from_function(key, build: func)

  def from_function(key, opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:requires, :build])
    func = Keyword.fetch!(opts, :build)

    %__MODULE__{
      keys: [key],
      manifest: provider_manifest(key, opts),
      effect:
        Effect.access(fn env ->
          Effect.succeed(%{key => func.(env)})
        end)
    }
  end

  defp provider_manifest(key, opts) do
    case Keyword.fetch(opts, :requires) do
      :error -> {:provider, [key], :unknown}
      {:ok, keys} when is_list(keys) -> {:provider, [key], Enum.uniq(keys)}
      {:ok, _} -> raise ArgumentError, "requires must be a list of service keys"
    end
  end

  @doc """
  Horizontal Composition (++ in ZIO).
  Combines two layers that don't depend on each other.
  """
  def and_(layer_a, layer_b) do
    %__MODULE__{
      keys: Enum.uniq(layer_a.keys ++ layer_b.keys),
      manifest: {:and, manifest(layer_a), manifest(layer_b)},
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
      manifest: {:to, manifest(layer_a), manifest(layer_b)},
      effect:
        ZioEx.Effect.flat_map(layer_a.effect, fn env_a ->
          # We take the map produced by A and 'provide' it to B's effect
          ZioEx.Effect.provide_context(layer_b.effect, env_a)
        end)
    }
  end

  @doc """
  Ensures the layer's effect is only executed once.
  The cache lives until the process owning the memoized layer exits.
  The first caller supplies the build environment. All callers share its success or failure.
  """
  def memoize(%__MODULE__{} = layer) do
    scope = ResourceScope.current()
    {:ok, cache} = ResourceScope.start_child({ZioEx.Layer.Cache, :empty})

    memoized_effect =
      Effect.access(fn env ->
        build = fn ->
          ResourceScope.within(scope, fn -> ZioEx.Runtime.run(layer.effect, env) end)
        end

        case ZioEx.Layer.Cache.fetch(cache, build) do
          {:ok, services} -> Effect.succeed(services)
          {:error, cause} -> Effect.fail_cause(cause)
        end
      end)

    %{layer | effect: memoized_effect}
  end
end
