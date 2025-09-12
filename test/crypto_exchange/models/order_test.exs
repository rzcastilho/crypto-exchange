defmodule CryptoExchange.Models.OrderTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Models.Order

  describe "parse/1" do
    test "parses valid Binance order response" do
      binance_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "FILLED",
        "type" => "LIMIT",
        "side" => "BUY",
        "origQty" => "0.00100000",
        "executedQty" => "0.00100000",
        "price" => "50000.00000000",
        "time" => 1_640_995_200_000,
        "updateTime" => 1_640_995_201_000
      }

      assert {:ok, order} = Order.parse(binance_data)

      assert order.id == "123456789"
      assert order.symbol == "BTCUSDT"
      assert order.status == :filled
      assert order.type == :limit
      assert order.side == :buy
      assert Decimal.equal?(order.quantity, Decimal.new("0.001"))
      assert Decimal.equal?(order.executed_quantity, Decimal.new("0.001"))
      assert Decimal.equal?(order.price, Decimal.new("50000.00"))
      assert order.created_at == DateTime.from_unix!(1_640_995_200_000, :millisecond)
      assert order.updated_at == DateTime.from_unix!(1_640_995_201_000, :millisecond)
    end

    test "parses order with numeric orderId" do
      binance_data = %{
        "orderId" => 123_456_789,
        "symbol" => "BTCUSDT",
        "status" => "NEW",
        "type" => "MARKET",
        "side" => "SELL",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      assert {:ok, order} = Order.parse(binance_data)
      assert order.id == "123456789"
    end

    test "parses order with optional fields missing" do
      binance_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "NEW",
        "type" => "MARKET",
        "side" => "BUY",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      assert {:ok, order} = Order.parse(binance_data)

      assert order.executed_quantity == nil
      assert order.price == nil
      assert order.stop_price == nil
      assert order.iceberg_quantity == nil
      assert order.time_in_force == nil
      assert order.updated_at == nil
      assert order.fills == nil
    end

    test "parses all order statuses correctly" do
      statuses = [
        {"NEW", :new},
        {"PARTIALLY_FILLED", :partially_filled},
        {"FILLED", :filled},
        {"CANCELED", :canceled},
        {"PENDING_CANCEL", :pending_cancel},
        {"REJECTED", :rejected},
        {"EXPIRED", :expired}
      ]

      base_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "type" => "LIMIT",
        "side" => "BUY",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      Enum.each(statuses, fn {binance_status, expected_atom} ->
        data = Map.put(base_data, "status", binance_status)
        assert {:ok, order} = Order.parse(data)
        assert order.status == expected_atom
      end)
    end

    test "parses all order types correctly" do
      types = [
        {"MARKET", :market},
        {"LIMIT", :limit},
        {"STOP_LOSS", :stop_loss},
        {"STOP_LOSS_LIMIT", :stop_loss_limit},
        {"TAKE_PROFIT", :take_profit},
        {"TAKE_PROFIT_LIMIT", :take_profit_limit},
        {"LIMIT_MAKER", :limit_maker}
      ]

      base_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "NEW",
        "side" => "BUY",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      Enum.each(types, fn {binance_type, expected_atom} ->
        data = Map.put(base_data, "type", binance_type)
        assert {:ok, order} = Order.parse(data)
        assert order.type == expected_atom
      end)
    end

    test "parses both order sides correctly" do
      base_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "NEW",
        "type" => "LIMIT",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      buy_data = Map.put(base_data, "side", "BUY")
      assert {:ok, buy_order} = Order.parse(buy_data)
      assert buy_order.side == :buy

      sell_data = Map.put(base_data, "side", "SELL")
      assert {:ok, sell_order} = Order.parse(sell_data)
      assert sell_order.side == :sell
    end

    test "parses time in force values" do
      base_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "NEW",
        "type" => "LIMIT",
        "side" => "BUY",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      tif_values = [
        {"GTC", :gtc},
        {"IOC", :ioc},
        {"FOK", :fok}
      ]

      Enum.each(tif_values, fn {binance_tif, expected_atom} ->
        data = Map.put(base_data, "timeInForce", binance_tif)
        assert {:ok, order} = Order.parse(data)
        assert order.time_in_force == expected_atom
      end)
    end

    test "returns error for missing required fields" do
      incomplete_data = %{
        "symbol" => "BTCUSDT",
        "status" => "NEW"
        # missing orderId, type, side, origQty, time
      }

      assert {:error, _reason} = Order.parse(incomplete_data)
    end

    test "returns error for invalid status" do
      invalid_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "INVALID_STATUS",
        "type" => "LIMIT",
        "side" => "BUY",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      assert {:error, {:invalid_status, "INVALID_STATUS"}} = Order.parse(invalid_data)
    end

    test "returns error for invalid type" do
      invalid_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "NEW",
        "type" => "INVALID_TYPE",
        "side" => "BUY",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      assert {:error, {:invalid_type, "INVALID_TYPE"}} = Order.parse(invalid_data)
    end

    test "returns error for invalid side" do
      invalid_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "NEW",
        "type" => "LIMIT",
        "side" => "INVALID_SIDE",
        "origQty" => "1.0",
        "time" => 1_640_995_200_000
      }

      assert {:error, {:invalid_side, "INVALID_SIDE"}} = Order.parse(invalid_data)
    end

    test "returns error for invalid data format" do
      assert {:error, :invalid_data_format} = Order.parse("not_a_map")
      assert {:error, :invalid_data_format} = Order.parse(nil)
      assert {:error, :invalid_data_format} = Order.parse(123)
    end

    test "parses decimal fields from strings and numbers" do
      # Test string decimals
      string_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "FILLED",
        "type" => "LIMIT",
        "side" => "BUY",
        "origQty" => "0.12345678",
        "executedQty" => "0.12345678",
        "price" => "50000.99999999",
        "time" => 1_640_995_200_000
      }

      assert {:ok, order} = Order.parse(string_data)
      assert Decimal.equal?(order.quantity, Decimal.new("0.12345678"))
      assert Decimal.equal?(order.executed_quantity, Decimal.new("0.12345678"))
      assert Decimal.equal?(order.price, Decimal.new("50000.99999999"))

      # Test numeric decimals
      numeric_data = %{
        "orderId" => "123456789",
        "symbol" => "BTCUSDT",
        "status" => "FILLED",
        "type" => "LIMIT",
        "side" => "BUY",
        "origQty" => 0.12345678,
        "executedQty" => 0.12345678,
        "price" => 50000.99,
        "time" => 1_640_995_200_000
      }

      assert {:ok, order} = Order.parse(numeric_data)
      assert order.quantity
      assert order.executed_quantity
      assert order.price
    end
  end

  describe "to_map/1" do
    test "converts Order struct to map representation" do
      order = %Order{
        id: "123456789",
        symbol: "BTCUSDT",
        status: :filled,
        type: :limit,
        side: :buy,
        quantity: Decimal.new("0.001"),
        executed_quantity: Decimal.new("0.001"),
        price: Decimal.new("50000.00"),
        created_at: DateTime.from_unix!(1_640_995_200_000, :millisecond),
        updated_at: DateTime.from_unix!(1_640_995_201_000, :millisecond),
        stop_price: nil,
        iceberg_quantity: nil,
        time_in_force: :gtc,
        fills: nil
      }

      result = Order.to_map(order)

      assert result.id == "123456789"
      assert result.symbol == "BTCUSDT"
      assert result.status == "FILLED"
      assert result.type == "LIMIT"
      assert result.side == "BUY"
      assert result.quantity == "0.001"
      assert result.executed_quantity == "0.001"
      assert result.price == "50000.00"
      assert result.time_in_force == "GTC"
      assert result.created_at == DateTime.from_unix!(1_640_995_200_000, :millisecond)
      assert result.updated_at == DateTime.from_unix!(1_640_995_201_000, :millisecond)

      # Nil fields should not be present
      refute Map.has_key?(result, :stop_price)
      refute Map.has_key?(result, :iceberg_quantity)
      refute Map.has_key?(result, :fills)
    end
  end

  describe "validate_params/1" do
    test "validates correct limit order parameters" do
      valid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001",
        "price" => "50000.00",
        "timeInForce" => "GTC"
      }

      assert :ok = Order.validate_params(valid_params)
    end

    test "validates correct market order with quantity" do
      valid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "MARKET",
        "quantity" => "0.001"
      }

      assert :ok = Order.validate_params(valid_params)
    end

    test "validates correct market order with quoteOrderQty" do
      valid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "MARKET",
        "quoteOrderQty" => "100.00"
      }

      assert :ok = Order.validate_params(valid_params)
    end

    test "rejects params missing required fields" do
      incomplete_params = %{
        "symbol" => "BTCUSDT"
        # missing side and type
      }

      assert {:error, {:missing_required_fields, missing}} =
               Order.validate_params(incomplete_params)

      assert "side" in missing
      assert "type" in missing
    end

    test "rejects limit order missing price" do
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001",
        "timeInForce" => "GTC"
        # missing price
      }

      assert {:error, :limit_order_requires_price} = Order.validate_params(invalid_params)
    end

    test "rejects limit order missing quantity" do
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "price" => "50000.00",
        "timeInForce" => "GTC"
        # missing quantity
      }

      assert {:error, :limit_order_requires_quantity} = Order.validate_params(invalid_params)
    end

    test "rejects limit order missing timeInForce" do
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001",
        "price" => "50000.00"
        # missing timeInForce
      }

      assert {:error, :limit_order_requires_time_in_force} = Order.validate_params(invalid_params)
    end

    test "rejects market order without quantity or quoteOrderQty" do
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "MARKET"
        # missing both quantity and quoteOrderQty
      }

      assert {:error, :market_order_requires_quantity_or_quote_order_qty} =
               Order.validate_params(invalid_params)
    end

    test "rejects invalid symbol" do
      invalid_params = %{
        "symbol" => "",
        "side" => "BUY",
        "type" => "MARKET",
        "quantity" => "1.0"
      }

      assert {:error, :invalid_symbol} = Order.validate_params(invalid_params)
    end

    test "rejects invalid side" do
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "INVALID_SIDE",
        "type" => "MARKET",
        "quantity" => "1.0"
      }

      assert {:error, :invalid_side} = Order.validate_params(invalid_params)
    end

    test "rejects invalid type" do
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "INVALID_TYPE",
        "quantity" => "1.0"
      }

      assert {:error, :invalid_type} = Order.validate_params(invalid_params)
    end

    test "works with atom keys" do
      valid_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "MARKET",
        quantity: "1.0"
      }

      assert :ok = Order.validate_params(valid_params)
    end

    test "rejects non-map input" do
      assert {:error, :invalid_params_format} = Order.validate_params("not_a_map")
      assert {:error, :invalid_params_format} = Order.validate_params(nil)
      assert {:error, :invalid_params_format} = Order.validate_params([])
    end
  end

  describe "terminal_state?/1" do
    test "identifies terminal states correctly" do
      terminal_statuses = [:filled, :canceled, :rejected, :expired]

      Enum.each(terminal_statuses, fn status ->
        order = %Order{
          id: "123",
          symbol: "BTCUSDT",
          status: status,
          type: :limit,
          side: :buy,
          quantity: Decimal.new("1"),
          created_at: DateTime.utc_now()
        }

        assert Order.terminal_state?(order) == true
      end)
    end

    test "identifies non-terminal states correctly" do
      non_terminal_statuses = [:new, :partially_filled, :pending_cancel]

      Enum.each(non_terminal_statuses, fn status ->
        order = %Order{
          id: "123",
          symbol: "BTCUSDT",
          status: status,
          type: :limit,
          side: :buy,
          quantity: Decimal.new("1"),
          created_at: DateTime.utc_now()
        }

        assert Order.terminal_state?(order) == false
      end)
    end
  end

  describe "active?/1" do
    test "identifies active states correctly" do
      active_statuses = [:new, :partially_filled]

      Enum.each(active_statuses, fn status ->
        order = %Order{
          id: "123",
          symbol: "BTCUSDT",
          status: status,
          type: :limit,
          side: :buy,
          quantity: Decimal.new("1"),
          created_at: DateTime.utc_now()
        }

        assert Order.active?(order) == true
      end)
    end

    test "identifies inactive states correctly" do
      inactive_statuses = [:filled, :canceled, :rejected, :expired, :pending_cancel]

      Enum.each(inactive_statuses, fn status ->
        order = %Order{
          id: "123",
          symbol: "BTCUSDT",
          status: status,
          type: :limit,
          side: :buy,
          quantity: Decimal.new("1"),
          created_at: DateTime.utc_now()
        }

        assert Order.active?(order) == false
      end)
    end
  end
end
