defmodule ZioEx.SchemaTest do
  use ExUnit.Case, async: true
  alias ZioEx.Schema
  alias ZioEx.Schema.{JSON, Markdown}

  defmodule Item do
    @enforce_keys [:quantity]
    defstruct [:quantity, private: :local]
  end

  defmodule Basket do
    defstruct [:items, :visible]
  end

  defp item, do: Schema.record(Item, quantity: Schema.integer())
  defp basket, do: Schema.record(Basket, items: Schema.list(item()), visible: Schema.boolean())

  test "records, lists and booleans round-trip; only declared fields cross the boundary" do
    value = %Basket{items: [%Item{quantity: 3}], visible: false}
    assert {:ok, bytes} = JSON.encode(basket(), value)

    assert {:ok, %{"items" => [%{"quantity" => 3}], "visible" => false}} =
             Elixir.JSON.decode(bytes)

    assert JSON.decode(basket(), bytes) == {:ok, value}
    assert JSON.decode(item(), ~s({"quantity":1,"future":true})) == {:ok, %Item{quantity: 1}}
  end

  test "string and list roots work with empty and escaped values" do
    schema = Schema.list(Schema.string())

    for value <- [[], ["tea\n", "☕"]] do
      assert {:ok, bytes} = JSON.encode(schema, value)
      assert JSON.decode(schema, bytes) == {:ok, value}
    end
  end

  test "errors identify the failing field or list index on read and write" do
    assert JSON.decode(basket(), ~s({"items":[{}],"visible":true})) ==
             {:error, {:missing, [:items, 0, :quantity]}}

    assert JSON.decode(basket(), ~s({"items":[{"quantity":null}],"visible":true})) ==
             {:error, {:expected, [:items, 0, :quantity], :integer}}

    assert JSON.encode(basket(), %Basket{items: [%Item{quantity: "3"}], visible: true}) ==
             {:error, {:expected, [:items, 0, :quantity], :integer}}

    assert {:error, _} = JSON.encode(item(), %{quantity: 2})
    assert {:error, _} = JSON.decode(item(), "[]")
    assert {:error, {:invalid_json, _}} = JSON.decode(item(), "{")
    assert {:error, {:expected, [], :string}} = JSON.encode(Schema.string(), <<255>>)
  end

  test "schema declarations reject inconsistent struct fields" do
    assert_raise ArgumentError, fn -> Schema.record(Item, extra: Schema.string()) end
    assert_raise ArgumentError, fn -> Schema.record(Item, []) end

    assert_raise ArgumentError, fn ->
      Schema.record(Item, quantity: :integer, quantity: :string)
    end
  end

  test "Markdown describes the declared fields and nested item paths in declaration order" do
    assert Markdown.render(basket()) == """
           | Field | Type | Required |
           | --- | --- | --- |
           | `items` | list of Item | yes |
           | `items[].quantity` | integer | yes |
           | `visible` | boolean | yes |
           """
  end
end
