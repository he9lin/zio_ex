defmodule ZioEx.Runtime.Cache do
  @table :zio_memo_cache

  def init do
    # Create an ETS table that is public (so any worker can read/write)
    # and optimized for reading.
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  def get(ref) do
    case :ets.lookup(@table, ref) do
      [{^ref, result}] -> {:ok, result}
      [] -> :none
    end
  end

  def put(ref, result) do
    :ets.insert(@table, {ref, result})
    result
  end
end
