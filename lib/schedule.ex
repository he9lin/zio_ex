defmodule ZioEx.Schedule do
  @moduledoc "Logic for retrying and repeating effects."
  defstruct [:next]

  @doc "Retries forever with no delay."
  def forever() do
    %__MODULE__{next: fn _attempt -> {:cont, 0, nil} end}
  end

  @doc "Retries up to n times."
  def recurs(n) do
    %__MODULE__{
      next: fn
        attempt when attempt < n -> {:cont, 0, nil}
        _ -> :halt
      end
    }
  end

  @doc "Fixed delay between attempts."
  def spaced(ms) do
    %__MODULE__{next: fn _attempt -> {:cont, ms, nil} end}
  end

  @doc "Exponential backoff."
  def exponential(base_ms) do
    %__MODULE__{
      next: fn attempt ->
        delay = base_ms * :erlang.round(:math.pow(2, attempt))
        {:cont, delay, nil}
      end
    }
  end

  @doc "Retries up to n times with exponential backoff between attempts."
  def recurs_with_backoff(n, base_ms) do
    %__MODULE__{
      next: fn attempt ->
        if attempt < n do
          delay = base_ms * :erlang.round(:math.pow(2, attempt))
          {:cont, delay, nil}
        else
          :halt
        end
      end
    }
  end
end
