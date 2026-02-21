defmodule ZioEx.Cause do
  defmodule Fail, do: defstruct([:error])
  defmodule Die, do: defstruct([:exception, :stacktrace])
  defmodule Interrupt, do: defstruct([])

  # For parallel failures
  defmodule Both, do: defstruct([:left, :right])
end
