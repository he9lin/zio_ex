defmodule ZioEx.Runtime do
  @moduledoc "The runtime for the ZioEx effect system."

  alias ZioEx.{Cause, Effect, Fiber}

  def run(effect, env \\ %{}), do: loop(effect, [], env)

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
end
