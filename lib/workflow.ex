defmodule ZioEx.Workflow do
  @moduledoc """
  Declares named workflows and their service requirements. Module-level
  `requirements` fields apply to every workflow. A workflow's `requires:` list
  covers indirect or dynamic lookups. Literal keys in `require_service/1`
  inside the workflow are recorded automatically.

      defmodule Booking do
        use ZioEx.Workflow
        alias ZioEx.Workflow, as: W

        workflow :cancel do
          W.require_service(:db)
        end
      end

      db = ZioEx.Layer.from_function(:db, requires: [:db_url], build: &DB.connect/1)
      live = ZioEx.Layer.to(ZioEx.Layer.succeed(:db_url, url), db)
      ZioEx.Workflow.run(Booking, :cancel, live)

  Wiring errors raise before acquisition. Once the graph passes validation,
  execution returns the usual `Runtime.run/2` result.
  """

  alias ZioEx.{Effect, Layer, Runtime}

  def run(module, name, %Layer{} = layer) do
    Runtime.Validator.validate!(module, name, layer)
    module |> apply(name, []) |> Effect.provide(layer) |> Runtime.run()
  end

  defmacro __using__(_opts) do
    quote do
      import ZioEx.Workflow, only: [workflow: 2, workflow: 3, requirements: 1, field: 1, field: 2]
      Module.register_attribute(__MODULE__, :zio_requirements, accumulate: true)
      Module.register_attribute(__MODULE__, :zio_workflows, accumulate: true)
      Module.register_attribute(__MODULE__, :zio_lookups, accumulate: true)
      @before_compile ZioEx.Workflow
    end
  end

  defmacro requirements(do: block), do: block

  defmacro field(name, _opts \\ []) do
    quote do
      @zio_requirements unquote(name)
    end
  end

  defmacro workflow(name, opts \\ [], do: block) do
    requires = Keyword.fetch!(Keyword.validate!(opts, requires: []), :requires)

    quote do
      @zio_workflows {unquote(name), unquote(requires)}
      def unquote(name)(), do: unquote(block)
    end
  end

  defmacro require_service(key) do
    expanded = Macro.expand(key, __CALLER__)

    if Macro.quoted_literal?(expanded) do
      {literal, _} = Code.eval_quoted(expanded, [], __CALLER__)
      Module.put_attribute(__CALLER__.module, :zio_lookups, {__CALLER__.function, literal})
    end

    quote do: ZioEx.Effect.require(unquote(expanded))
  end

  defmacro __before_compile__(env) do
    shared = Module.get_attribute(env.module, :zio_requirements)
    lookups = Module.get_attribute(env.module, :zio_lookups)
    workflows = Module.get_attribute(env.module, :zio_workflows)

    manifests =
      Map.new(workflows, fn {name, declared} ->
        tracked = for {{^name, 0}, key} <- lookups, do: key
        {name, Enum.uniq(shared ++ declared ++ tracked)}
      end)

    # Keep the module-wide accessor for callers of Validator.validate!/2.
    all =
      Enum.uniq(
        shared ++ Enum.flat_map(manifests, &elem(&1, 1)) ++ Enum.map(lookups, &elem(&1, 1))
      )

    quote do
      def __requirements__, do: unquote(Macro.escape(all))

      def __requirements__(name) do
        Map.fetch!(unquote(Macro.escape(manifests)), name)
      end
    end
  end
end
