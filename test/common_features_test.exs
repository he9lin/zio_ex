defmodule ZioEx.CommonFeaturesTest do
  use ExUnit.Case, async: true

  alias ZioEx.{Cause, Effect, Runtime, Validation}

  test "map_error transforms expected failures and preserves other outcomes" do
    mapped = Effect.map_error(Effect.fail(:enoent), fn :enoent -> :user_not_found end)
    assert Runtime.run(mapped) == {:error, %Cause.Fail{error: :user_not_found}}

    unused = fn _ -> flunk("unexpected error callback") end
    assert Runtime.run(Effect.map_error(Effect.succeed(:ok), unused)) == {:ok, :ok}

    for cause <- [
          %Cause.Die{exception: :boom},
          %Cause.Interrupt{},
          %Cause.Both{left: %Cause.Fail{error: :a}, right: %Cause.Fail{error: :b}}
        ] do
      assert Runtime.run(Effect.map_error(Effect.fail_cause(cause), unused)) == {:error, cause}
    end
  end

  test "tap observes success once, preserves its value, and propagates failures" do
    observe = fn value -> Effect.sync(fn -> send(self(), {:observed, value}) end) end
    tapped = Effect.tap(Effect.succeed(42), observe)
    refute_received {:observed, _}
    assert Runtime.run(tapped) == {:ok, 42}
    assert_received {:observed, 42}
    refute_received {:observed, _}

    assert Runtime.run(Effect.tap(Effect.fail(:load), observe)) ==
             {:error, %Cause.Fail{error: :load}}

    refute_received {:observed, _}
    failed = Effect.tap(Effect.succeed(42), fn _ -> Effect.fail(:audit) end)
    assert Runtime.run(failed) == {:error, %Cause.Fail{error: :audit}}
  end

  test "validate_with preserves successful value shapes and accumulates independent errors" do
    email = Validation.succeed("a@example.com")
    roles = Validation.succeed([:admin])

    assert Validation.validate_with(email, roles, &{&1, &2}) ==
             Validation.succeed({"a@example.com", [:admin]})

    invalid = Validation.fail({:email, :missing})
    rejected = Validation.fail({:roles, :unknown})
    unused = fn _, _ -> flunk("constructor called with invalid inputs") end
    assert Validation.validate_with(invalid, roles, unused) == invalid
    assert Validation.validate_with(email, rejected, unused) == rejected

    assert %Validation{result: {:error, [email: :missing, roles: :unknown]}} =
             Validation.validate_with(invalid, rejected, unused)
  end

  test "foreach defaults to lazy sequential execution and stops on failure" do
    parent = self()

    program =
      Effect.foreach(1..4, fn n ->
        send(parent, {:visited, n, self()})
        if n == 2, do: Effect.fail(:bad), else: Effect.succeed(n)
      end)

    refute_received {:visited, _, _}
    assert Runtime.run(program) == {:error, %Cause.Fail{error: :bad}}
    assert_received {:visited, 1, ^parent}
    assert_received {:visited, 2, ^parent}
    refute_received {:visited, _, _}
    assert Runtime.run(Effect.foreach([], &Effect.succeed/1)) == {:ok, []}

    assert_raise ArgumentError, fn ->
      Effect.foreach([], &Effect.succeed/1, max_concurrency: 0)
    end
  end

  test "parallel traversal bounds active effects, inherits dependencies and returns input order" do
    parent = self()

    mapper = fn n ->
      Effect.access(fn env ->
        send(parent, {:started, n, self()})

        receive do
          :finish -> {n, env.tag}
        end
      end)
    end

    task =
      Task.async(fn ->
        Runtime.run(Effect.foreach(1..4, mapper, max_concurrency: 2), %{tag: :ok})
      end)

    assert_receive {:started, 1, one}
    assert_receive {:started, 2, two}
    refute_received {:started, _, _}
    send(two, :finish)
    send(one, :finish)
    assert_receive {:started, 3, three}
    assert_receive {:started, 4, four}
    send(four, :finish)
    send(three, :finish)
    assert Task.await(task) == {:ok, [{1, :ok}, {2, :ok}, {3, :ok}, {4, :ok}]}
  end

  test "parallel traversal finishes active finalizers and propagates callback defects" do
    parent = self()

    program =
      Effect.foreach(
        1..3,
        fn
          1 ->
            raise "bad mapper"

          2 ->
            Effect.ensuring(Effect.succeed(2), Effect.sync(fn -> send(parent, :closed) end))

          3 ->
            send(parent, :unexpected)
            Effect.succeed(3)
        end,
        max_concurrency: 2
      )

    assert {:error, %Cause.Die{exception: %RuntimeError{message: "bad mapper"}}} =
             Runtime.run(program)

    assert_received :closed
    refute_received :unexpected
  end

  test "acquire_release_with releases once after use, including construction failures" do
    acquire = Effect.succeed(:handle)
    release = fn :handle -> Effect.sync(fn -> send(self(), :released) end) end

    for {use_resource, expected} <- [
          {fn :handle -> Effect.succeed(:done) end, {:ok, :done}},
          {fn :handle -> Effect.fail(:bad) end, {:error, %Cause.Fail{error: :bad}}}
        ] do
      assert Runtime.run(Effect.acquire_release_with(acquire, use_resource, release)) == expected
      assert_received :released
      refute_received :released
    end

    assert {:error, %Cause.Die{}} =
             Runtime.run(Effect.acquire_release_with(acquire, fn _ -> raise "use" end, release))

    assert_received :released
    refute_received :released

    assert {:error, %Cause.Fail{error: :acquire}} =
             Runtime.run(
               Effect.acquire_release_with(Effect.fail(:acquire), fn _ -> flunk() end, release)
             )

    refute_received :released

    assert {:error, %Cause.Fail{error: :release}} =
             Runtime.run(
               Effect.acquire_release_with(acquire, &Effect.succeed/1, fn _ ->
                 Effect.fail(:release)
               end)
             )
  end
end
