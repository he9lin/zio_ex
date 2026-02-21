defmodule ZioEx.Service do
  # This module is used to define a service contract.
  #
  # Example:
  #   defmodule Spa.Services.Payment do
  #    use ZioEx.Service

  #    contract do
  #      field :charge, arity: 2
  #      field :refund, arity: 1
  #    end

  #    # Production implementation
  #    def live(api_key) do
  #      ZioEx.Layer.succeed(:payments, validate!(%{
  #        charge: fn amount, currency ->
  #          # Stripe logic here
  #          {:ok, "ch_#{amount}"}
  #        end,
  #        refund: fn id ->
  #          # Refund logic
  #          :ok
  #        end
  #      }))
  #    end
  #  end
  #
  # In your controller or a background worker
  #
  #  def process_booking(params) do
  #    # This layer is guaranteed to have :charge and :refund
  #    payment_layer = Spa.Services.Payment.live("sk_prod_123")

  #    program = zio do
  #      pay_service <- Effect.require(:payments)
  #      _ <- pay_service.charge(100, "USD")
  #      Effect.succeed(:success)
  #    end

  #    Effect.provide(program, payment_layer) |> Runtime.run()
  #  end
  defmacro __using__(_opts) do
    quote do
      import ZioEx.Service, only: [contract: 1]
      Module.register_attribute(__MODULE__, :zio_callbacks, accumulate: true)
      @before_compile ZioEx.Service
    end
  end

  defmacro contract(do: block) do
    # This captures the field definitions inside the service
    block
  end

  defmacro field(name, arity: arity) do
    quote do
      @zio_callbacks {unquote(name), unquote(arity)}
      @callback unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))) ::
                  any()
    end
  end

  defmacro __before_compile__(env) do
    callbacks = Module.get_attribute(env.module, :zio_callbacks)

    quote do
      @doc "Validates that a map or module conforms to this service contract."
      def validate!(implementation) do
        required = unquote(callbacks)

        Enum.each(required, fn {name, arity} ->
          cond do
            is_atom(implementation) and function_exported?(implementation, name, arity) ->
              :ok

            is_map(implementation) and is_function(Map.get(implementation, name), arity) ->
              :ok

            true ->
              raise "Contract Violation: #{inspect(__MODULE__)} requires #{name}/#{arity}"
          end
        end)

        implementation
      end
    end
  end
end
