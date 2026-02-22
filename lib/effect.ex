defmodule ZioEx.Effect do
  defstruct [:type, :data, requirements: []]

  # Experimental: track and validate requirements at compile-time
  def require(key) do
    %__MODULE__{
      type: :require,
      data: key,
      # Track it here!
      requirements: [key]
    }
  end

  @doc """
  Wraps a callback-based async API into an Effect (ZIO.async style).

  The callback runs in a spawned process. It receives a `resume` function:
  call `resume.({:ok, val})` or `resume.({:error, cause})` when done.
  The runtime awaits the result.

  Example:
      Effect.async(fn resume ->
        ExternalAPI.request(fn
          {:ok, data} -> resume.({:ok, data})
          {:error, e} -> resume.({:error, %ZioEx.Cause.Fail{error: e}})
        end)
      end)
  """
  def async(f) do
    %__MODULE__{
      type: :async,
      data: f
    }
  end

  def succeed(val), do: %__MODULE__{type: :succeed, data: val}

  @doc """
  Lifts a specific Cause struct (Fail, Die, Interrupt, or Both)
  into the Effect error channel.
  """
  def fail_cause(cause) when is_struct(cause) do
    # This matches any of your Cause modules: Fail, Die, Interrupt, or Both
    %__MODULE__{type: :fail, data: cause}
  end

  @doc "Signals an expected failure (E)"
  def fail(err), do: %__MODULE__{type: :fail, data: %ZioEx.Cause.Fail{error: err}}

  @doc "Signals a catastrophic failure (Die)"
  def die(exception),
    do: %__MODULE__{type: :fail, data: %ZioEx.Cause.Die{exception: exception, stacktrace: []}}

  def sync(func), do: %__MODULE__{type: :sync, data: func}

  @doc """
  Reads the environment.
  - `access()` — returns the full env
  - `access(:key)` — returns env[key] for a given atom
  - `access(fn r -> ... end)` — applies the function to env
  """
  def access(), do: %__MODULE__{type: :access, data: fn r -> r end}
  def access(key) when is_atom(key), do: %__MODULE__{type: :access, data: fn r -> Map.get(r, key) end}
  def access(func), do: %__MODULE__{type: :access, data: func}
  def fork(effect), do: %__MODULE__{type: :fork, data: effect}
  def join(fiber), do: %__MODULE__{type: :join, data: fiber}

  def flat_map(eff, func), do: %__MODULE__{type: :flat_map, data: {eff, func}}

  @doc """
  The ultimate recovery operator.
  on_cause: (Cause -> Effect<B>)
  on_success: (A -> Effect<B>)
  """
  def fold_cause(eff, on_cause, on_success) do
    %__MODULE__{type: :fold_cause, data: {eff, on_cause, on_success}}
  end

  # Standard fold now just wraps fold_cause
  def fold(eff, on_err, on_succ) do
    fold_cause(
      eff,
      fn
        %ZioEx.Cause.Fail{error: e} -> on_err.(e)
        # Re-raise Die/Interrupt
        cause -> %__MODULE__{type: :fail, data: cause}
      end,
      on_succ
    )
  end

  def map(eff, f), do: fold(eff, &fail/1, fn v -> succeed(f.(v)) end)

  def catch_all(eff, h), do: fold(eff, h, &succeed/1)

  def either(eff), do: fold(eff, fn e -> succeed({:error, e}) end, fn v -> succeed({:ok, v}) end)

  @doc "Guarantees the finalizer runs after the effect, regardless of outcome."
  def ensuring(eff, finalizer) do
    %__MODULE__{type: :ensuring, data: {eff, finalizer}}
  end

  @doc "Provides a layer to an effect, satisfying its dependencies."
  def provide(effect, layer_or_effect) do
    layer_effect = extract_layer_effect(layer_or_effect)

    # 1. Run the layer to get the env map
    # 2. Access the global env and merge the layer's output into it
    # 3. Run the original effect with the merged env
    flat_map(layer_effect, fn layer_env ->
      access(fn global_env ->
        # Here we 'provide' the environment by merging
        merged_env = Map.merge(global_env, layer_env)
        # We need a way to tell the runtime to use this specific env
        %__MODULE__{type: :provide, data: {effect, merged_env}}
      end)
    end)
  end

  defp extract_layer_effect(%ZioEx.Layer{effect: e}), do: e
  defp extract_layer_effect(%__MODULE__{} = e), do: e

  def retry(effect, schedule, attempt \\ 0) do
    fold(
      effect,
      fn err ->
        case schedule.next.(attempt) do
          {:cont, delay, _} ->
            sync(fn -> Process.sleep(delay) end)
            |> flat_map(fn _ -> retry(effect, schedule, attempt + 1) end)

          :halt ->
            fail(err)
        end
      end,
      fn val -> succeed(val) end
    )
  end

  @doc """
  Tells the runtime: "Run this effect, but use this specific map
  as the environment (R) instead of the global one."
  """
  def provide_context(effect, env) do
    %__MODULE__{type: :provide, data: {effect, env}}
  end

  @doc """
  Runs two effects in parallel and returns a tuple of their results.
  If either fails, the whole effect fails.
  """
  def zip_par(left, right) do
    %__MODULE__{type: :zip_par, data: {left, right}}
  end

  @doc """
  Transforms the environment type required by this effect.
  Often called 'provide_some' or 'local' in other functional libraries.
  """
  def contramap(effect, f) do
    access(fn big_env ->
      # We take the BigEnv, transform it to what the inner effect needs
      small_env = f.(big_env)
      # Then we provide that specific context to the original effect
      provide_context(effect, small_env)
    end)
  end

  @doc """
  Runs a Non-Empty List (NEList) of validation effects in parallel.
  Returns a single effect containing the accumulated Validation result.
  """
  def validate_par([first | rest]) do
    Enum.reduce(rest, first, fn next_eff, acc_eff ->
      # Run in parallel
      zip_par(acc_eff, next_eff)
      |> map(fn {acc_val, next_val} ->
        # Polymorphic dispatch via Semigroup protocol
        ZioEx.Semigroup.combine(acc_val, next_val)
      end)
    end)
  end

  @doc "Lifts a result tuple {:ok, v} | {:error, e} into an Effect"
  def from_result({:ok, v}), do: succeed(v)
  def from_result({:error, e}), do: fail(e)

  @doc """
  Lifts an option.
  If :none, the effect fails with the provided 'error_value'.
  """
  def from_option({:some, val}, _error_value), do: succeed(val)
  def from_option(:none, error_value), do: fail(error_value)

  @doc "A helper to lift nullable Elixir values (nil becomes :none)"
  def from_nullable(nil, error_value), do: fail(error_value)
  def from_nullable(val, _error_value), do: succeed(val)
end
