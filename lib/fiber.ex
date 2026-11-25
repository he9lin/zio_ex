defmodule ZioEx.Fiber do
  @moduledoc """
  A running effect. Any process may join it once. The result is retained until
  joined or until the process owning the runtime resources exits.
  """
  use GenServer
  alias ZioEx.{Cause, ResourceScope}

  defstruct [:pid]

  @doc false
  def fork(run) do
    {:ok, pid} = ResourceScope.start_child({__MODULE__, {self(), ResourceScope.inherit(run)}})
    %__MODULE__{pid: pid}
  end

  @doc false
  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @doc false
  def join(%__MODULE__{pid: pid}) do
    GenServer.call(pid, :join, :infinity)
  catch
    :exit, {reason, {GenServer, :call, _}} when reason in [:normal, :noproc, :shutdown] ->
      {:error, %Cause.Interrupt{}}
  end

  @impl true
  def init({parent, run}) do
    Process.link(parent)
    {:ok, Task.async(run)}
  end

  @impl true
  def handle_call(:join, _from, %Task{} = task) do
    {:stop, :normal, Task.await(task, :infinity), :joined}
  end

  def handle_call(:join, _from, {:done, result}), do: {:stop, :normal, result, :joined}

  @impl true
  def handle_info({ref, result}, %Task{ref: ref}) do
    Process.demonitor(ref, [:flush])
    {:noreply, {:done, result}}
  end
end
