defmodule ZioEx.RuntimeCorrectnessTest do
  use ExUnit.Case, async: true

  alias ZioEx.{Cause, Effect, Layer, Runtime}

  test "callback exceptions unwind from the active frame and finalize exactly once" do
    boom = fn _ -> raise "boom" end
    cleanup = Effect.sync(fn -> send(self(), :cleaned) end)

    for effect <- [
          Effect.map(Effect.succeed(1), boom),
          Effect.flat_map(Effect.succeed(1), boom),
          Effect.access(boom),
          Effect.catch_all(Effect.fail(:bad), boom)
        ] do
      assert {:error, %Cause.Die{exception: %RuntimeError{message: "boom"}, stacktrace: [_ | _]}} =
               Runtime.run(Effect.ensuring(effect, cleanup))

      assert_received :cleaned
      refute_received :cleaned
    end

    effect = Effect.sync(fn -> 1 end) |> Effect.ensuring(cleanup) |> Effect.map(boom)
    assert {:error, %Cause.Die{}} = Runtime.run(effect)
    assert_received :cleaned
    refute_received :cleaned
  end

  test "provided environments are scoped on success and failure" do
    cleanup = Effect.access(fn env -> send(self(), {:cleanup, env.name}) end)
    outer = %{name: :outer}
    local = %{name: :local}

    read =
      Effect.access(:name)
      |> Effect.provide_context(local)
      |> Effect.flat_map(fn value -> Effect.map(Effect.access(:name), &{value, &1}) end)

    assert Runtime.run(read, outer) == {:ok, {:local, :outer}}

    failed =
      Effect.fail(:bad)
      |> Effect.ensuring(cleanup)
      |> Effect.provide_context(local)
      |> Effect.ensuring(cleanup)
      |> Effect.catch_all(fn _ -> Effect.access(:name) end)

    assert Runtime.run(failed, outer) == {:ok, :outer}
    assert_received {:cleanup, :local}
    assert_received {:cleanup, :outer}
  end

  test "memoization uses the first environment and preserves failed results for all callers" do
    cached = Effect.require(:url) |> Layer.from_effect(:db) |> Layer.memoize()
    assert Runtime.run(cached, %{url: :first}) == {:ok, %{db: :first}}
    assert Runtime.run(cached, %{url: :second}) == {:ok, %{db: :first}}

    parent = self()

    layer =
      Effect.sync(fn -> send(parent, :initialized) end)
      |> Effect.flat_map(fn _ -> Effect.fail(:unavailable) end)
      |> Layer.from_effect(:db)
      |> Layer.memoize()

    tasks = for _ <- 1..3, do: Task.async(fn -> Runtime.run(layer) end)

    for task <- tasks do
      assert Task.await(task, 1000) == {:error, %Cause.Fail{error: :unavailable}}
    end

    assert_received :initialized
    refute_received :initialized
  end

  test "a killed layer initializer releases other callers with its cause" do
    parent = self()

    cached =
      Effect.sync(fn ->
        send(parent, :building)
        Process.sleep(:infinity)
      end)
      |> Layer.from_effect(:db)
      |> Layer.memoize()

    {builder, monitor} = spawn_monitor(fn -> Runtime.run(cached) end)
    assert_receive :building
    waiter = Task.async(fn -> Runtime.run(cached) end)
    Process.exit(builder, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^builder, :killed}
    assert {:error, %Cause.Die{} = cause} = Task.await(waiter, 1000)
    assert Runtime.run(cached) == {:error, cause}
  end

  test "abnormal async registration unwinds while normal registration permits a later resume" do
    parent = self()

    for register <- [fn _ -> raise "registration" end, fn _ -> exit(:registration) end] do
      task =
        Task.async(fn ->
          Effect.async(register)
          |> Effect.ensuring(Effect.sync(fn -> send(parent, :finalized) end))
          |> Runtime.run()
        end)

      assert {:error, %Cause.Die{}} = Task.await(task, 1000)
      assert_received :finalized
    end

    task =
      Task.async(fn ->
        Runtime.run(Effect.async(fn resume -> send(parent, {:registered, self(), resume}) end))
      end)

    assert_receive {:registered, pid, resume}
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}
    resume.({:ok, :later})
    assert Task.await(task) == {:ok, :later}
  end

  test "zip_par and join wait for work that exceeds five seconds" do
    slow =
      Effect.sync(fn ->
        Process.sleep(5100)
        :done
      end)

    joined = Effect.flat_map(Effect.fork(slow), &Effect.join/1)
    assert Runtime.run(Effect.zip_par(joined, slow)) == {:ok, {:done, :done}}
  end
end
