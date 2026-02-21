defmodule ZioExTest do
  use ExUnit.Case
  import ZioEx.Macros
  alias ZioEx.{Effect, Runtime, Schedule, Layer}

  describe "Core Mechanics" do
    test "succeed returns a constant value" do
      program = Effect.succeed(42)
      assert Runtime.run(program) == {:ok, 42}
    end

    test "sync executes side effects" do
      program = Effect.sync(fn -> 10 + 10 end)
      assert Runtime.run(program) == {:ok, 20}
    end

    test "flat_map chains operations" do
      program =
        Effect.succeed(1)
        |> Effect.flat_map(fn x -> Effect.succeed(x + 1) end)
        |> Effect.flat_map(fn x -> Effect.succeed(x * 10) end)

      assert Runtime.run(program) == {:ok, 20}
    end
  end

  describe "Stack Safety (The Trampoline)" do
    test "executes a very deep chain without blowing the stack" do
      # In a non-trampolined system, 100k nested calls would crash.
      # Here, it should handle it easily using heap-based continuations.
      depth = 100_000

      program =
        Enum.reduce(1..depth, Effect.succeed(0), fn _, acc ->
          Effect.flat_map(acc, fn n -> Effect.succeed(n + 1) end)
        end)

      assert {:ok, ^depth} = Runtime.run(program)
    end
  end

  describe "Environment (The R)" do
    test "access provides the environment to the effect" do
      env = %{api_key: "secret_123"}

      program =
        Effect.access(fn r ->
          Effect.succeed(r.api_key)
        end)

      assert Runtime.run(program, env) == {:ok, "secret_123"}
    end
  end

  describe "Concurrency (Fibers)" do
    test "fork and join allow parallel execution" do
      parent = self()

      program =
        Effect.fork(
          Effect.sync(fn ->
            send(parent, :fiber_running)
            :done_from_fiber
          end)
        )
        |> Effect.flat_map(fn fiber ->
          Effect.join(fiber)
        end)

      assert Runtime.run(program) == {:ok, :done_from_fiber}
      assert_received :fiber_running
    end

    test "structured concurrency: parent crash affects child" do
      # Because we use Task.async, the processes are linked.
      # If the parent process exits, the child task should be killed.
      # The program must join so the runner blocks; otherwise it exits
      # normally and linked tasks are not killed on :normal exit.
      test_pid = self()

      program =
        Effect.fork(
          Effect.sync(fn ->
            Process.sleep(1000)
            send(test_pid, :should_not_happen)
          end)
        )
        |> Effect.flat_map(fn fiber ->
          Effect.join(fiber)
        end)

      # We run this in a separate process that we then kill
      runner_pid = spawn(fn -> Runtime.run(program) end)
      Process.sleep(100)
      Process.exit(runner_pid, :kill)

      refute_receive :should_not_happen, 1100
    end
  end

  describe "Error Unwinding (The E in REA)" do
    test "returns {:error, reason} when no handlers exist" do
      program = Effect.fail(:something_went_wrong)

      assert Runtime.run(program) == {:error, %ZioEx.Cause.Fail{error: :something_went_wrong}}
    end

    test "skips flat_maps and jumps to catch_all" do
      program =
        Effect.fail("initial error")
        |> Effect.flat_map(fn _ ->
          # This should be skipped entirely
          Effect.sync(fn -> send(self(), :should_not_run) end)
        end)
        |> Effect.catch_all(fn err ->
          Effect.succeed("Caught: #{err}")
        end)

      assert Runtime.run(program) == {:ok, "Caught: initial error"}
      refute_receive :should_not_run
    end

    test "nested catch_all handles the error at the correct level" do
      program =
        Effect.fail(:inner_error)
        |> Effect.catch_all(fn :inner_error ->
          Effect.succeed(:recovered_inner)
        end)
        |> Effect.flat_map(fn _ ->
          Effect.fail(:outer_error)
        end)
        |> Effect.catch_all(fn :outer_error ->
          Effect.succeed(:recovered_outer)
        end)

      assert Runtime.run(program) == {:ok, :recovered_outer}
    end

    test "from_result/1 correctly lifts an error tuple into a failing Effect" do
      error_tuple = {:error, :db_timeout}

      program =
        Effect.from_result(error_tuple)
        |> Effect.catch_all(fn :db_timeout -> Effect.succeed("Retry later") end)

      assert Runtime.run(program) == {:ok, "Retry later"}
    end

    test "deep stack unwinding preserves the Environment (R)" do
      # Ensure that even after an error and recovery, the 'R' is still accessible
      env = %{config: "prod"}

      program =
        Effect.fail(:fail)
        |> Effect.catch_all(fn _ ->
          Effect.access(fn r -> Effect.succeed(r.config) end)
        end)

      assert Runtime.run(program, env) == {:ok, "prod"}
    end

    test "unwinding works across join points (Async errors)" do
      # If a forked fiber fails, joining it should trigger the unwind in the parent
      program =
        Effect.fork(Effect.fail(:fiber_crash))
        |> Effect.flat_map(fn fiber ->
          Effect.join(fiber)
        end)
        |> Effect.catch_all(fn :fiber_crash ->
          Effect.succeed(:handled_crash)
        end)

      assert Runtime.run(program) == {:ok, :handled_crash}
    end
  end

  describe "zio macro syntax" do
    test "handles basic assignment with <-" do
      program =
        zio do
          x <- Effect.succeed(10)
          y <- Effect.succeed(x + 5)
          Effect.succeed(y * 2)
        end

      assert Runtime.run(program) == {:ok, 30}
    end

    test "handles anonymous lines (discarding results)" do
      # We use an agent to track side effects
      {:ok, agent} = Agent.start_link(fn -> [] end)

      program =
        zio do
          Effect.sync(fn -> Agent.update(agent, fn state -> state ++ [1] end) end)
          _ <- Effect.sync(fn -> Agent.update(agent, fn state -> state ++ [2] end) end)
          Effect.succeed(:done)
        end

      assert Runtime.run(program) == {:ok, :done}
      assert Agent.get(agent, & &1) == [1, 2]
    end

    test "correctly handles environment access within the block" do
      env = %{multiplier: 3}

      program =
        zio do
          %{multiplier: m} <- Effect.access(fn r -> r end)
          val <- Effect.succeed(10)
          Effect.succeed(val * m)
        end

      assert Runtime.run(program, env) == {:ok, 30}
    end

    test "short-circuits on failure (unwinding integration)" do
      {:ok, agent} = Agent.start_link(fn -> :initial end)

      program =
        zio do
          _ <- Effect.fail(:boom)
          # This line should never execute
          Effect.sync(fn -> Agent.update(agent, fn _ -> :updated end) end)
        end

      assert Runtime.run(program) == {:error, %ZioEx.Cause.Fail{error: :boom}}
      assert Agent.get(agent, & &1) == :initial
    end

    test "supports complex pattern matching in arrows" do
      program =
        zio do
          {:ok, value} <- Effect.succeed({:ok, "secret"})
          Effect.succeed(String.upcase(value))
        end

      assert Runtime.run(program) == {:ok, "SECRET"}
    end

    test "handles single-line zio blocks" do
      program = zio(do: Effect.succeed(:fast))
      assert Runtime.run(program) == {:ok, :fast}
    end
  end

  test "fold handles success" do
    program =
      Effect.succeed(10)
      |> Effect.fold(fn _ -> Effect.succeed(0) end, fn v -> Effect.succeed(v + 1) end)

    assert Runtime.run(program) == {:ok, 11}
  end

  test "fold handles failure" do
    program =
      Effect.fail(:error)
      |> Effect.fold(fn _ -> Effect.succeed(:recovered) end, fn v -> Effect.succeed(v) end)

    assert Runtime.run(program) == {:ok, :recovered}
  end

  test "retry with exponential backoff" do
    start_time = System.monotonic_time(:millisecond)

    # An effect that always fails, retry 2 times with 10ms base delay
    # Delays: attempt 0 -> 10ms, attempt 1 -> 20ms. Total ~30ms minimum.
    program = Effect.fail(:bad) |> Effect.retry(Schedule.recurs_with_backoff(2, 10))

    result = Runtime.run(program)
    end_time = System.monotonic_time(:millisecond)

    assert result == {:error, %ZioEx.Cause.Fail{error: :bad}}
    # It should have run 3 times (initial + 2 retries) with backoff delays
    assert end_time - start_time >= 25, "expected backoff delays (~30ms)"
  end

  test "recovers from a catastrophic Die using fold_cause" do
    # This would normally crash the process
    program =
      Effect.sync(fn -> 1 / 0 end)
      |> Effect.fold_cause(
        fn
          %ZioEx.Cause.Die{exception: %ArithmeticError{}} ->
            Effect.succeed(:recovered_from_math_error)

          _ ->
            Effect.fail(:unhandled)
        end,
        fn _ -> Effect.succeed(:ok) end
      )

    assert Runtime.run(program) == {:ok, :recovered_from_math_error}
  end

  test "ensuring runs even on failure" do
    {:ok, agent} = Agent.start_link(fn -> :open end)

    program =
      Effect.fail(:boom)
      |> Effect.ensuring(Effect.sync(fn -> Agent.update(agent, fn _ -> :closed end) end))

    assert Runtime.run(program) == {:error, %ZioEx.Cause.Fail{error: :boom}}
    assert Agent.get(agent, & &1) == :closed
  end

  test "provide wires up a multi-layer dependency graph" do
    # 1. Define Layers
    config_layer = Layer.succeed(:db_url, "postgres://localhost")

    # DB Layer depends on :db_url
    db_layer =
      Layer.from_function(:db, fn %{db_url: url} ->
        %{query: fn _sql -> "Result from #{url}" end}
      end)

    # 2. Define the Program (Requirements: :db)
    program =
      zio do
        %{db: db} <- Effect.access(fn r -> r end)
        result <- Effect.sync(fn -> db.query.("SELECT *") end)
        Effect.succeed(result)
      end

    # 3. Compose and Provide
    # Vertical composition: config -> db
    full_layer = Layer.to(config_layer, db_layer)

    final_effect = Effect.provide(program, full_layer)

    assert Runtime.run(final_effect) == {:ok, "Result from postgres://localhost"}
  end

  test "Layer.to passes environment from left to right" do
    layer_a = Layer.succeed(:secret, "12345")

    # Layer B needs :secret to create :auth_service
    layer_b =
      Effect.access(fn %{secret: s} ->
        "AuthService with #{s}"
      end)
      |> Layer.from_effect(:auth_service)

    # A >>> B
    combined_layer = Layer.to(layer_a, layer_b)

    program = Effect.access(fn %{auth_service: auth} -> auth end)

    # When we provide the combined layer, the program should see the auth_service
    final_effect = Effect.provide(program, combined_layer)

    assert Runtime.run(final_effect) == {:ok, "AuthService with 12345"}
  end
end
