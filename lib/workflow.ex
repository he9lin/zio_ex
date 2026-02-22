# Experimental: track and validate requirements at compile-time
defmodule ZioEx.Workflow do
  @moduledoc """
  Example:
    defmodule Spa.Workflows.Booking do
      use ZioEx.Workflow
      alias ZioEx.Workflow, as: W

      workflow :create do
        # We use our new tracking version of require
        sms <- W.require_service(:sms)
        db  <- W.require_service(:db)

        ZioEx.Effect.succeed(:ok)
      end
    end

    defmodule Spa.Application do
      use Application

      def start(_type, _args) do
        main_workflow = Spa.Workflows.Booking.run()
        main_layer = Spa.Infrastructure.live_layer()

        # CRITICAL: Verify before the supervisor starts
        ZioEx.Runtime.Validator.validate!(main_workflow, main_layer)

        children = [
          SpaWeb.Endpoint,
          # ... other workers
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
  """
  defmacro __using__(_opts) do
    quote do
      import ZioEx.Workflow, only: [workflow: 2, requirements: 1, field: 1, field: 2]
      Module.register_attribute(__MODULE__, :zio_requirements, accumulate: true)
      @before_compile ZioEx.Workflow
    end
  end

  defmacro requirements(do: block), do: block

  defmacro field(name, _opts \\ []) do
    Module.put_attribute(__CALLER__.module, :zio_requirements, name)
    quote do: unquote(name)
  end

  defmacro workflow(name, do: block) do
    quote do
      def unquote(name)() do
        unquote(block)
      end
    end
  end

  # We wrap the Effect.require to also track the key at compile-time
  defmacro require_service(key) do
    Module.put_attribute(__CALLER__.module, :zio_requirements, key)

    quote do
      ZioEx.Effect.require(unquote(key))
    end
  end

  defmacro __before_compile__(env) do
    reqs = Module.get_attribute(env.module, :zio_requirements) |> Enum.uniq()

    quote do
      def __requirements__, do: unquote(reqs)
    end
  end
end
