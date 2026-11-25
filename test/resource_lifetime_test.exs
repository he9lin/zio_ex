defmodule ZioEx.ResourceLifetimeTest do
  use ExUnit.Case, async: true

  alias ZioEx.{Cause, Effect, Layer, Ref, Runtime}

  test "a fiber can be joined from outside the parallel branch that forked it" do
    parent = self()

    work =
      Effect.sync(fn ->
        send(parent, {:working, self()})

        receive do
          :finish -> :finished
        end
      end)

    {:ok, {fiber, _}} = Runtime.run(Effect.zip_par(Effect.fork(work), Effect.succeed(nil)))
    assert_receive {:working, worker}
    joiner = Task.async(fn -> Runtime.run(Effect.join(fiber)) end)
    send(worker, :finish)
    assert Task.await(joiner) == {:ok, :finished}

    {:ok, {failed, _}} =
      Runtime.run(Effect.zip_par(Effect.fork(Effect.fail(:bad)), Effect.succeed(nil)))

    assert Runtime.run(Effect.join(failed)) == {:error, %Cause.Fail{error: :bad}}
  end

  test "deep chains of synchronous effects use bounded process stack" do
    stack_size = fn depth ->
      effect =
        Enum.reduce(1..depth, Effect.succeed(0), fn _, acc ->
          Effect.flat_map(acc, fn n -> Effect.sync(fn -> n + 1 end) end)
        end)

      measure = Effect.map(effect, fn n -> {n, Process.info(self(), :stack_size)} end)
      assert {:ok, {^depth, {:stack_size, size}}} = Runtime.run(measure)
      size
    end

    shallow = stack_size.(10)
    assert stack_size.(10_000) <= shallow + 32
  end

  test "a ref initialized by a short-lived cache caller shares the cache lifetime" do
    cached = Ref.make(:ready) |> Layer.from_effect(:ref) |> Layer.memoize()
    task = Task.async(fn -> Runtime.run(cached) end)
    monitor = Process.monitor(task.pid)
    assert {:ok, %{ref: ref}} = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, _, reason} when reason in [:normal, :noproc]

    assert {:ok, %{ref: ^ref}} = Runtime.run(cached)
    assert {:ok, :ready} = Runtime.run(Ref.get(ref))
  end

  test "refs and memoized layers outlive their branch and stop when the owner exits" do
    parent = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        layer = Effect.sync(fn -> Layer.memoize(Layer.succeed(:db, :connected)) end)
        {:ok, {ref, cached}} = Runtime.run(Effect.zip_par(Ref.make(42), layer))

        resources = DynamicSupervisor.which_children(ZioEx.ResourceScope.current())

        cache =
          Enum.find_value(resources, fn
            {_, pid, :worker, [ZioEx.Layer.Cache]} -> pid
            _ -> nil
          end)

        send(parent, {:resources, ref, cached, cache})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:resources, ref, layer, cache}
    ref_monitor = Process.monitor(ref.agent)
    cache_monitor = Process.monitor(cache)
    assert Runtime.run(Ref.get(ref)) == {:ok, 42}
    assert Runtime.run(layer) == {:ok, %{db: :connected}}
    send(owner, :finish)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :normal}
    assert_receive {:DOWN, ^ref_monitor, :process, _, :shutdown}
    assert_receive {:DOWN, ^cache_monitor, :process, _, :shutdown}
  end
end
