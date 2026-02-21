defmodule ZioEx.Runtime do
  @moduledoc "The runtime for the ZioEx effect system."

  alias ZioEx.{Cause, Effect, Fiber}

  def run(effect, env \\ %{}) do
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

  # --- Interpreter Loop ---
  defp loop(%Effect{type: :succeed, data: val}, stack, env), do: continue(val, stack, env)

  defp loop(%Effect{type: :sync, data: f}, stack, env) do
    try do
      continue(f.(), stack, env)
    rescue
      e -> unwind(%Cause.Die{exception: e, stacktrace: __STACKTRACE__}, stack, env)
    end
  end

  defp loop(%Effect{type: :access, data: f}, stack, env) do
    case f.(env) do
      %Effect{} = eff -> loop(eff, stack, env)
      val -> continue(val, stack, env)
    end
  end

  defp loop(%Effect{type: :flat_map, data: {inner, f}}, stack, env) do
    loop(inner, [{:map, f} | stack], env)
  end

  defp loop(%Effect{type: :fold_cause, data: {inner, on_cause, on_succ}}, stack, env) do
    loop(inner, [{:fold_cause_handler, {on_cause, on_succ}} | stack], env)
  end

  defp loop(%Effect{type: :fail, data: cause}, stack, env), do: unwind(cause, stack, env)

  defp loop(%Effect{type: :fork, data: eff}, stack, env) do
    task = Task.async(fn -> run(eff, env) end)
    continue(%Fiber{task: task}, stack, env)
  end

  defp loop(%Effect{type: :join, data: %Fiber{task: t}}, stack, env) do
    case Task.await(t) do
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

  defp loop(%Effect{type: :provide, data: {inner, local_env}}, stack, _global_env) do
    # Switch to the local_env for the duration of the inner effect
    loop(inner, stack, local_env)
  end

  defp loop(%Effect{type: :zip_par, data: {left, right}}, stack, env) do
    # 1. Spawn both in parallel tasks
    t1 = Task.async(fn -> run(left, env) end)
    t2 = Task.async(fn -> run(right, env) end)

    # 2. Wait for results
    res1 = Task.await(t1)
    res2 = Task.await(t2)

    # 3. Handle the outcomes
    case {res1, res2} do
      {{:ok, v1}, {:ok, v2}} -> continue({v1, v2}, stack, env)
      {{:error, c1}, {:error, c2}} -> unwind(%ZioEx.Cause.Both{left: c1, right: c2}, stack, env)
      {{:error, c}, _} -> unwind(c, stack, env)
      {_, {:error, c}} -> unwind(c, stack, env)
    end
  end

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
        loop(on_succ.(val), rest, env)

      {:map, f} ->
        loop(f.(val), rest, env)

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
        loop(on_cause.(cause), rest, env)

      _ ->
        unwind(cause, rest, env)
    end
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
