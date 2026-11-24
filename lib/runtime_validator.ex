defmodule ZioEx.Runtime.Validator do
  alias ZioEx.Layer

  @doc "Checks declared layer inputs and all service requirements in a workflow module."
  def validate!(module, %Layer{} = layer) do
    check!(inspect(module), module.__requirements__(), layer)
  end

  @doc "Checks the explicit graph and the requirements of one named workflow."
  def validate!(module, name, %Layer{} = layer) do
    check!("#{inspect(module)}.#{name}/0", module.__requirements__(name), layer)
  end

  defp check!(workflow, required, layer) do
    case Layer.Manifest.check(Layer.manifest(layer), []) do
      {:ok, provided} ->
        case required -- provided do
          [] ->
            :ok

          missing ->
            raise "Workflow #{workflow}: Missing Dependencies #{inspect(missing)}. Provided: #{inspect(provided)}"
        end

      {:error, {:missing_inputs, inputs, outputs}} ->
        raise "Workflow #{workflow}: missing #{inspect(inputs)} required by layer providing #{inspect(outputs)}"

      {:error, {:duplicate_outputs, keys}} ->
        raise "Workflow #{workflow}: Duplicate layer outputs #{inspect(keys)}"
    end
  end
end
