defmodule ZioEx.Layer.Cache do
  @moduledoc false
  use GenServer

  alias ZioEx.Cause

  def start_link(:empty), do: GenServer.start_link(__MODULE__, :empty)

  def fetch(cache, build) do
    case GenServer.call(cache, :fetch, :infinity) do
      :build ->
        result = run_build(build)
        :ok = GenServer.call(cache, {:complete, result}, :infinity)
        result

      {:cached, result} ->
        result
    end
  end

  defp run_build(build) do
    build.()
  catch
    kind, reason ->
      exception =
        case kind do
          :error -> Exception.normalize(:error, reason, __STACKTRACE__)
          _ -> %ErlangError{original: {kind, reason}}
        end

      {:error, %Cause.Die{exception: exception, stacktrace: __STACKTRACE__}}
  end

  @impl true
  def init(:empty), do: {:ok, :empty}

  @impl true
  def handle_call(:fetch, {pid, _}, :empty) do
    {:reply, :build, {:building, Process.monitor(pid), []}}
  end

  def handle_call(:fetch, from, {:building, monitor, waiters}) do
    {:noreply, {:building, monitor, [from | waiters]}}
  end

  def handle_call(:fetch, _from, {:ready, result} = state) do
    {:reply, {:cached, result}, state}
  end

  def handle_call({:complete, result}, _from, {:building, monitor, waiters}) do
    Process.demonitor(monitor, [:flush])
    {:reply, :ok, finish(result, waiters)}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _, reason}, {:building, monitor, waiters}) do
    cause = %Cause.Die{exception: %ErlangError{original: reason}, stacktrace: []}
    {:noreply, finish({:error, cause}, waiters)}
  end

  defp finish(result, waiters) do
    Enum.each(waiters, &GenServer.reply(&1, {:cached, result}))
    {:ready, result}
  end
end
