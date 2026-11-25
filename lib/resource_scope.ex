defmodule ZioEx.ResourceScope do
  @moduledoc false

  # The calling process owns one supervisor. Parallel branches inherit it so
  # returning a resource from a short-lived branch preserves its lifetime.
  def current do
    case Process.get(__MODULE__) do
      nil ->
        {:ok, scope} = DynamicSupervisor.start_link(strategy: :one_for_one)
        Process.put(__MODULE__, scope)
        scope

      scope ->
        scope
    end
  end

  def inherit(fun) do
    scope = current()

    fn -> within(scope, fun) end
  end

  def within(scope, fun) do
    previous = Process.put(__MODULE__, scope)

    try do
      fun.()
    after
      if previous, do: Process.put(__MODULE__, previous), else: Process.delete(__MODULE__)
    end
  end

  def start_child(spec) do
    DynamicSupervisor.start_child(current(), Supervisor.child_spec(spec, restart: :temporary))
  end
end
