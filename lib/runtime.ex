defmodule ZioEx.Runtime do
  @moduledoc "The runtime for the ZioEx effect system."

  alias ZioEx.{Cause, Effect, Fiber, ResourceScope}

  def run(effect_or_layer, env \\ %{}) do
    effect = extract_effect(effect_or_layer)

    # 1. Generate a unique ID for this execution
    meta = %{id: System.unique_integer([:positive]), env: env}
    start_time = System.monotonic_time()

    # 2. Emit the "start" event
    emit_telemetry([:run, :start], %{system_time: System.system_time()}, meta)

    # 3. Execute the loop
    result = loop(effect, [], env)

    # 4. Emit the "stop" event with duration
    duration = System.monotonic_time() - start_time

    emit_telemetry([:run, :stop], %{duration: duration}, Map.put(meta, :result, result))

    result
  end

  defp extract_effect(%ZioEx.Layer{effect: e}), do: e
  defp extract_effect(%Effect{} = e), do: e

  # --- Interpreter Loop ---
  defp loop(%Effect{type: :succeed, data: val}, stack, env), do: continue(val, stack, env)

  defp loop(%Effect{type: :sync, data: f}, stack, env) do
    loop(invoke(fn -> Effect.succeed(f.()) end), stack, env)
  end

  defp loop(%Effect{type: :require, data: key}, stack, env) do
    case Map.fetch(env, key) do
      {:ok, service} -> continue(service, stack, env)
      :error -> unwind(%ZioEx.Cause.Fail{error: {:missing_service, key}}, stack, env)
    end
  end

  defp loop(%Effect{type: :async, data: f}, stack, env) do
    parent = self()
    ref = make_ref()

    resume = fn
      {:ok, val} -> send(parent, {ref, {:ok, val}})
      {:error, cause} -> send(parent, {ref, {:error, cause}})
    end

    {_, monitor} =
      spawn_monitor(
        ResourceScope.inherit(fn ->
          try do
            f.(resume)
          rescue
            e -> resume.({:error, %Cause.Die{exception: e, stacktrace: __STACKTRACE__}})
          end
        end)
      )

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])

        case result do
          {:ok, val} -> continue(val, stack, env)
          {:error, cause} -> unwind(cause, stack, env)
        end

      {:DOWN, ^monitor, :process, _, reason} when reason != :normal ->
        unwind(%Cause.Die{exception: %ErlangError{original: reason}, stacktrace: []}, stack, env)
    end
  end

  defp loop(%Effect{type: :access, data: f}, stack, env) do
    effect =
      invoke(fn ->
        case f.(env) do
          %Effect{} = eff -> eff
          val -> Effect.succeed(val)
        end
      end)

    loop(effect, stack, env)
  end

  defp loop(%Effect{type: :flat_map, data: {inner, f}}, stack, env) do
    loop(inner, [{:map, f} | stack], env)
  end

  defp loop(%Effect{type: :fold_cause, data: {inner, on_cause, on_succ}}, stack, env) do
    loop(inner, [{:fold_cause_handler, {on_cause, on_succ}} | stack], env)
  end

  defp loop(%Effect{type: :fail, data: cause}, stack, env), do: unwind(cause, stack, env)

  defp loop(%Effect{type: :fork, data: eff}, stack, env) do
    continue(Fiber.fork(fn -> run(eff, env) end), stack, env)
  end

  defp loop(%Effect{type: :join, data: %Fiber{} = fiber}, stack, env) do
    case Fiber.join(fiber) do
      {:ok, val} -> continue(val, stack, env)
      {:error, err} -> unwind(err, stack, env)
    end
  end

  defp loop(%Effect{type: :fold, data: {inner, on_err, on_succ}}, stack, env) do
    loop(inner, [{:fold_handler, {on_err, on_succ}} | stack], env)
  end

  defp loop(%Effect{type: :ensuring, data: {inner, finalizer}}, stack, env) do
    # Push a finalizer frame onto the stack
    loop(inner, [{:finalizer, finalizer} | stack], env)
  end

  defp loop(%Effect{type: :provide, data: {inner, local_env}}, stack, global_env) do
    # Switch to the local_env for the duration of the inner effect
    loop(inner, [{:restore_env, global_env} | stack], local_env)
  end

  defp loop(%Effect{type: :zip_par, data: {left, right}}, stack, env) do
    # 1. Spawn both in parallel tasks
    t1 = Task.async(ResourceScope.inherit(fn -> run(left, env) end))
    t2 = Task.async(ResourceScope.inherit(fn -> run(right, env) end))

    # 2. Wait for results
    res1 = Task.await(t1, :infinity)
    res2 = Task.await(t2, :infinity)

    # 3. Handle the outcomes
    case {res1, res2} do
      {{:ok, v1}, {:ok, v2}} -> continue({v1, v2}, stack, env)
      {{:error, c1}, {:error, c2}} -> unwind(%ZioEx.Cause.Both{left: c1, right: c2}, stack, env)
      {{:error, c}, _} -> unwind(c, stack, env)
      {_, {:error, c}} -> unwind(c, stack, env)
    end
  end

  defp loop(%Effect{type: :foreach, data: {items, mapper, limit}}, stack, env) do
    result = invoke(fn -> foreach(items, mapper, limit, env) end)
    loop(result, stack, env)
  end

  defp foreach(items, mapper, limit, env) do
    run_item = fn item -> run(Effect.flat_map(Effect.succeed(item), mapper), env) end

    items
    |> Stream.chunk_every(limit)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      case collect_results(run_batch(batch, run_item, limit), acc) do
        {:ok, _} = success -> {:cont, success}
        {:error, _} = failure -> {:halt, failure}
      end
    end)
    |> case do
      {:ok, reversed} -> Effect.succeed(Enum.reverse(reversed))
      {:error, cause} -> Effect.fail_cause(cause)
    end
  end

  defp run_batch([item], run_item, 1), do: [run_item.(item)]

  defp run_batch(batch, run_item, _limit) do
    batch
    |> Enum.map(fn item -> Task.async(ResourceScope.inherit(fn -> run_item.(item) end)) end)
    |> Task.await_many(:infinity)
  end

  defp collect_results([], acc), do: {:ok, acc}
  defp collect_results([{:ok, value} | rest], acc), do: collect_results(rest, [value | acc])
  defp collect_results([{:error, _} = failure | _], _acc), do: failure

  # --- Continuation Logic ---
  defp continue(val, [], _env), do: {:ok, val}

  defp continue(val, [frame | rest], env) do
    case frame do
      {:finalizer, finalizer} ->
        # Run finalizer, then resume with the original value
        # Note: If finalizer fails, it takes over the outcome
        final_eff = Effect.flat_map(finalizer, fn _ -> Effect.succeed(val) end)
        loop(final_eff, rest, env)

      {:fold_cause_handler, {_, on_succ}} ->
        loop(invoke(fn -> on_succ.(val) end), rest, env)

      {:map, f} ->
        loop(invoke(fn -> f.(val) end), rest, env)

      {:restore_env, outer_env} ->
        continue(val, rest, outer_env)

      _ ->
        continue(val, rest, env)
    end
  end

  # --- Unwind Logic (Handling Cause) ---
  defp unwind(cause, [], _env), do: {:error, cause}

  defp unwind(cause, [frame | rest], env) do
    case frame do
      {:finalizer, finalizer} ->
        final_eff = Effect.flat_map(finalizer, fn _ -> Effect.fail_cause(cause) end)
        # Run finalizer, then resume with the original failure
        loop(final_eff, rest, env)

      {:fold_cause_handler, {on_cause, _}} ->
        loop(invoke(fn -> on_cause.(cause) end), rest, env)

      {:restore_env, outer_env} ->
        unwind(cause, rest, outer_env)

      _ ->
        unwind(cause, rest, env)
    end
  end

  # Limit rescue to user code so defects unwind the currently active frames.
  defp invoke(callback) do
    callback.()
  rescue
    e -> Effect.fail_cause(%Cause.Die{exception: e, stacktrace: __STACKTRACE__})
  end

  defp emit_telemetry(event, measurements, metadata) do
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.execute([:zio_ex | event], measurements, metadata)
    else
      # Do nothing if telemetry isn't installed
      :ok
    end
  end
end
