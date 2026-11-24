defmodule ZioEx.Ref do
  @moduledoc "An atomic reference owned by the runtime caller and shared with its branches."
  defstruct [:agent]

  def make(initial_value) do
    ZioEx.Effect.sync(fn ->
      {:ok, agent} = ZioEx.ResourceScope.start_child({Agent, fn -> initial_value end})
      %__MODULE__{agent: agent}
    end)
  end

  def get(%__MODULE__{agent: agent}) do
    ZioEx.Effect.sync(fn -> Agent.get(agent, & &1) end)
  end

  def update(%__MODULE__{agent: agent}, func) do
    ZioEx.Effect.sync(fn -> Agent.update(agent, func) end)
  end
end
