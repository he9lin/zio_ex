defmodule ZioEx.Runtime.Validator do
  @doc "Static check to ensure all required services are provided."
  def validate!(workflow_module, %ZioEx.Layer{} = layer) do
    # 1. Get requirements from Workflow metadata
    required = workflow_module.__requirements__()

    # 2. Get provided keys from Layer manifest
    provided = ZioEx.Layer.keys(layer)

    # 3. Check for gaps
    case required -- provided do
      [] ->
        :ok

      missing ->
        raise """
        --- ZioEx Wiring Error ---
        Workflow: #{inspect(workflow_module)}
        Missing Dependencies: #{inspect(missing)}
        Actually Provided: #{inspect(provided)}
        --------------------------
        """
    end
  end
end
