defmodule ZioEx.WorkflowWiringTest do
  use ExUnit.Case, async: true

  alias ZioEx.{Cause, Effect, Layer, Runtime, Workflow}
  alias ZioEx.Runtime.Validator

  defmodule Booking do
    use ZioEx.Workflow
    import ZioEx.Macros
    alias ZioEx.Workflow, as: W

    requirements do
      field(:tenant)
    end

    workflow :create, requires: [:audit] do
      zio do
        sms <- W.require_service(:sms)
        db <- W.require_service(:db)
        Effect.succeed({sms, db})
      end
    end

    workflow :cancel do
      W.require_service(:db)
    end
  end

  defmodule Indirect do
    use ZioEx.Workflow
    alias ZioEx.Workflow, as: W

    workflow :lookup, requires: [:db] do
      lookup(:db)
    end

    workflow :read do
      W.require_service({:db, :replica})
    end

    defp lookup(key), do: W.require_service(key)
    def helper, do: W.require_service(:helper_service)
  end

  test "explicit requirements cover dynamic helpers and literal keys retain their value" do
    assert Indirect.__requirements__(:lookup) == [:db]
    assert Indirect.__requirements__(:read) == [{:db, :replica}]
    assert :helper_service in Indirect.__requirements__()
    assert Workflow.run(Indirect, :lookup, Layer.succeed(:db, :live)) == {:ok, :live}

    assert Workflow.run(Indirect, :read, Layer.succeed({:db, :replica}, :replica)) ==
             {:ok, :replica}
  end

  test "requirements belong to the selected workflow plus shared module defaults" do
    assert Enum.sort(Booking.__requirements__(:create)) == [:audit, :db, :sms, :tenant]
    assert Enum.sort(Booking.__requirements__(:cancel)) == [:db, :tenant]
    assert Enum.sort(Booking.__requirements__()) == [:audit, :db, :sms, :tenant]

    root = Layer.and_(Layer.succeed(:tenant, :acme), Layer.succeed(:db, :test))
    assert Workflow.run(Booking, :cancel, root) == {:ok, :test}

    assert_raise RuntimeError, ~r/Missing Dependencies/, fn ->
      Workflow.run(Booking, :create, root)
    end
  end

  test "an invalid pipeline names the missing input and consumer before any builder runs" do
    parent = self()
    wrong = Layer.from_function(:url, fn _ -> send(parent, :built) end)
    db = Layer.from_function(:db, requires: [:db_url], build: fn _ -> send(parent, :built) end)
    root = Layer.and_(Layer.to(wrong, db), Layer.succeed(:tenant, :acme))

    assert_raise RuntimeError, ~r/:db_url.*layer.*:db/, fn ->
      Workflow.run(Booking, :cancel, root)
    end

    refute_received :built
  end

  test "parallel branches see the same upstream inputs and only the pipeline outputs are exported" do
    db =
      Layer.from_function(:db, requires: [:db_url], build: fn %{db_url: url} -> {:pool, url} end)

    tenant = Effect.require(:db_url) |> Layer.from_effect(:tenant, requires: [:db_url])
    root = Layer.to(Layer.succeed(:db_url, :localhost), Layer.and_(db, tenant))

    assert Validator.validate!(Booking, :cancel, root) == :ok
    assert Workflow.run(Booking, :cancel, root) == {:ok, {:pool, :localhost}}
    assert Layer.keys(root) == [:db, :tenant]

    siblings = Layer.and_(db, Layer.succeed(:db_url, :localhost))

    assert_raise RuntimeError, ~r/:db_url.*layer.*:db/, fn ->
      Validator.validate!(Booking, :cancel, siblings)
    end
  end

  test "checked wiring rejects duplicate outputs even inside a memoized pipeline" do
    both = Layer.and_(Layer.succeed(:url, 1), Layer.succeed(:url, 2))
    root = both |> Layer.to(Layer.succeed(:db, :test)) |> Layer.memoize()

    assert_raise RuntimeError, ~r/Duplicate.*:url/, fn ->
      Validator.validate!(Booking, :cancel, root)
    end

    assert Runtime.run(both) == {:ok, %{url: 2}}
  end

  test "legacy builders still run and acquisition failures stay in the effect channel" do
    legacy = Layer.from_function(:db, fn _ -> :legacy end)
    tenant = Layer.succeed(:tenant, :acme)
    assert Workflow.run(Booking, :cancel, Layer.and_(legacy, tenant)) == {:ok, :legacy}
    failing = Effect.fail(:offline) |> Layer.from_effect(:db, requires: [])

    assert Workflow.run(Booking, :cancel, Layer.and_(failing, tenant)) ==
             {:error, %Cause.Fail{error: :offline}}
  end
end
