defmodule CryptoExchange.Models.TradeTest do
  @moduledoc """
  Comprehensive unit tests for the CryptoExchange.Models.Trade module.
  Tests validation, parsing, utility functions, and edge cases.
  """

  use CryptoExchange.TestSupport.TestCaseTemplate, async: true

  alias CryptoExchange.Models.Trade

  describe "Trade.new/1" do
    test "creates trade with valid attributes" do
      attrs = %{
        symbol: "BTCUSDT",
        price: 50000.0,
        quantity: 0.1,
        side: :buy
      }

      assert {:ok, trade} = Trade.new(attrs)
      assert trade.symbol == "BTCUSDT"
      assert trade.price == 50000.0
      assert trade.quantity == 0.1
      assert trade.side == :buy
    end

    test "accepts string side values" do
      attrs = %{
        symbol: "ETHUSDT",
        price: 3000.0,
        quantity: 5.0,
        side: "BUY"
      }

      assert {:ok, trade} = Trade.new(attrs)
      assert trade.side == :buy
    end

    test "accepts both buy and sell sides" do
      buy_attrs = %{symbol: "BTCUSDT", price: 50000.0, quantity: 0.1, side: :buy}
      sell_attrs = %{symbol: "BTCUSDT", price: 50000.0, quantity: 0.1, side: :sell}

      assert {:ok, buy_trade} = Trade.new(buy_attrs)
      assert {:ok, sell_trade} = Trade.new(sell_attrs)
      
      assert buy_trade.side == :buy
      assert sell_trade.side == :sell
    end

    test "accepts integer values for numeric fields" do
      attrs = %{
        symbol: "ADAUSDT",
        price: 1,
        quantity: 1000,
        side: :sell
      }

      assert {:ok, trade} = Trade.new(attrs)
      assert trade.price == 1
      assert trade.quantity == 1000
    end

    test "rejects invalid symbol - nil" do
      attrs = %{symbol: nil, price: 50000.0, quantity: 0.1, side: :buy}
      assert {:error, :invalid_symbol} = Trade.new(attrs)
    end

    test "rejects invalid symbol - empty string" do
      attrs = %{symbol: "", price: 50000.0, quantity: 0.1, side: :buy}
      assert {:error, :invalid_symbol} = Trade.new(attrs)
    end

    test "rejects invalid price - nil" do
      attrs = %{symbol: "BTCUSDT", price: nil, quantity: 0.1, side: :buy}
      assert {:error, :invalid_price} = Trade.new(attrs)
    end

    test "rejects invalid price - zero" do
      attrs = %{symbol: "BTCUSDT", price: 0, quantity: 0.1, side: :buy}
      assert {:error, :invalid_price} = Trade.new(attrs)
    end

    test "rejects invalid price - negative" do
      attrs = %{symbol: "BTCUSDT", price: -100.0, quantity: 0.1, side: :buy}
      assert {:error, :invalid_price} = Trade.new(attrs)
    end

    test "rejects invalid quantity - nil" do
      attrs = %{symbol: "BTCUSDT", price: 50000.0, quantity: nil, side: :buy}
      assert {:error, :invalid_quantity} = Trade.new(attrs)
    end

    test "rejects invalid quantity - zero" do
      attrs = %{symbol: "BTCUSDT", price: 50000.0, quantity: 0, side: :buy}
      assert {:error, :invalid_quantity} = Trade.new(attrs)
    end

    test "rejects invalid quantity - negative" do
      attrs = %{symbol: "BTCUSDT", price: 50000.0, quantity: -0.1, side: :buy}
      assert {:error, :invalid_quantity} = Trade.new(attrs)
    end

    test "rejects invalid side" do
      attrs = %{symbol: "BTCUSDT", price: 50000.0, quantity: 0.1, side: :invalid}
      assert {:error, :invalid_side} = Trade.new(attrs)
    end

    test "rejects invalid input type" do
      assert {:error, :invalid_input} = Trade.new("not a map")
      assert {:error, :invalid_input} = Trade.new(nil)
      assert {:error, :invalid_input} = Trade.new(123)
    end
  end

  describe "Trade.from_binance_json/1" do
    test "parses WebSocket format correctly with buyer maker true" do
      binance_data = %{
        "s" => "BTCUSDT",
        "p" => "50000.00",
        "q" => "0.1",
        "m" => true
      }

      assert {:ok, trade} = Trade.from_binance_json(binance_data)
      assert trade.symbol == "BTCUSDT"
      assert trade.price == 50000.0
      assert trade.quantity == 0.1
      assert trade.side == :sell  # buyer maker = true means it's a sell
    end

    test "parses WebSocket format correctly with buyer maker false" do
      binance_data = %{
        "s" => "ETHUSDT",
        "p" => "3000.50",
        "q" => "5.25",
        "m" => false
      }

      assert {:ok, trade} = Trade.from_binance_json(binance_data)
      assert trade.symbol == "ETHUSDT"
      assert trade.price == 3000.5
      assert trade.quantity == 5.25
      assert trade.side == :buy  # buyer maker = false means it's a buy
    end

    test "parses REST API format correctly with buyer maker true" do
      binance_data = %{
        "symbol" => "ADAUSDT",
        "price" => "1.25",
        "qty" => "1000.0",
        "isBuyerMaker" => true
      }

      assert {:ok, trade} = Trade.from_binance_json(binance_data)
      assert trade.symbol == "ADAUSDT"
      assert trade.price == 1.25
      assert trade.quantity == 1000.0
      assert trade.side == :sell
    end

    test "parses REST API format correctly with buyer maker false" do
      binance_data = %{
        "symbol" => "BNBUSDT",
        "price" => "300.75",
        "qty" => "10.5",
        "isBuyerMaker" => false
      }

      assert {:ok, trade} = Trade.from_binance_json(binance_data)
      assert trade.symbol == "BNBUSDT"
      assert trade.price == 300.75
      assert trade.quantity == 10.5
      assert trade.side == :buy
    end

    test "handles numeric values in JSON" do
      binance_data = %{
        "s" => "DOGEUSDT",
        "p" => 0.08,
        "q" => 50000.0,
        "m" => false
      }

      assert {:ok, trade} = Trade.from_binance_json(binance_data)
      assert trade.price == 0.08
      assert trade.quantity == 50000.0
      assert trade.side == :buy
    end

    test "handles malformed number strings gracefully" do
      binance_data = %{
        "s" => "BTCUSDT",
        "p" => "invalid_price",
        "q" => "bad_quantity",
        "m" => true
      }

      # Invalid strings parse to 0.0, which fails validation
      assert {:error, :invalid_price} = Trade.from_binance_json(binance_data)
    end

    test "handles nil values gracefully" do
      binance_data = %{
        "s" => "BTCUSDT",
        "p" => nil,
        "q" => nil,
        "m" => false
      }

      # Nil values parse to 0.0, which fails validation
      assert {:error, :invalid_price} = Trade.from_binance_json(binance_data)
    end

    test "rejects invalid format - missing fields" do
      incomplete_data = %{
        "s" => "BTCUSDT",
        "p" => "50000.00"
        # Missing "q" and "m" fields
      }

      assert {:error, :invalid_binance_format} = Trade.from_binance_json(incomplete_data)
    end

    test "rejects completely invalid input" do
      assert {:error, :invalid_binance_format} = Trade.from_binance_json(%{})
      assert {:error, :invalid_binance_format} = Trade.from_binance_json(nil)
      assert {:error, :invalid_binance_format} = Trade.from_binance_json("invalid")
    end
  end

  describe "Trade.to_json/1" do
    test "converts trade to JSON representation" do
      trade = %Trade{
        symbol: "BTCUSDT",
        price: 50000.0,
        quantity: 0.1,
        side: :buy
      }

      json = Trade.to_json(trade)

      assert json["symbol"] == "BTCUSDT"
      assert json["price"] == 50000.0
      assert json["quantity"] == 0.1
      assert json["side"] == "buy"
    end

    test "converts side atoms to uppercase strings" do
      buy_trade = %Trade{symbol: "ETHUSDT", price: 3000.0, quantity: 1.0, side: :buy}
      sell_trade = %Trade{symbol: "ETHUSDT", price: 3000.0, quantity: 1.0, side: :sell}

      buy_json = Trade.to_json(buy_trade)
      sell_json = Trade.to_json(sell_trade)

      assert buy_json["side"] == "buy"
      assert sell_json["side"] == "sell"
    end

    test "handles very small and large numbers" do
      trade = %Trade{
        symbol: "DOGEUSDT",
        price: 0.00001,
        quantity: 1_000_000.0,
        side: :buy
      }

      json = Trade.to_json(trade)
      assert json["price"] == 0.00001
      assert json["quantity"] == 1_000_000.0
    end
  end

  describe "Trade.notional_value/1" do
    test "calculates notional value correctly" do
      trade = %Trade{
        symbol: "BTCUSDT",
        price: 50000.0,
        quantity: 0.1,
        side: :buy
      }

      assert Trade.notional_value(trade) == 5000.0
    end

    test "handles fractional values" do
      trade = %Trade{
        symbol: "ETHUSDT",
        price: 3000.25,
        quantity: 2.5,
        side: :sell
      }

      assert Trade.notional_value(trade) == 7500.625
    end

    test "handles very small amounts" do
      trade = %Trade{
        symbol: "DOGEUSDT",
        price: 0.08,
        quantity: 100.0,
        side: :buy
      }

      assert Trade.notional_value(trade) == 8.0
    end

    test "handles very large amounts" do
      trade = %Trade{
        symbol: "SHIBUSDT",
        price: 0.000001,
        quantity: 1_000_000_000.0,
        side: :sell
      }

      assert Trade.notional_value(trade) == 1000.0
    end
  end

  describe "edge cases and data validation" do
    test "handles very small prices and quantities" do
      attrs = %{
        symbol: "SHIBUSDT",
        price: 0.000001,
        quantity: 100_000.0,
        side: :buy
      }

      assert {:ok, trade} = Trade.new(attrs)
      assert trade.price == 0.000001
      assert trade.quantity == 100_000.0
    end

    test "handles very large prices and quantities" do
      attrs = %{
        symbol: "BTCUSDT",
        price: 999_999.99,
        quantity: 1000.0,
        side: :sell
      }

      assert {:ok, trade} = Trade.new(attrs)
      assert trade.price == 999_999.99
      assert trade.quantity == 1000.0
    end

    test "handles different symbol formats" do
      symbols = ["BTCUSDT", "ETHBTC", "ADAUSD", "DOGEEUR", "BNBBUSD"]
      
      Enum.each(symbols, fn symbol ->
        attrs = %{symbol: symbol, price: 100.0, quantity: 1.0, side: :buy}
        assert {:ok, trade} = Trade.new(attrs)
        assert trade.symbol == symbol
      end)
    end

    test "validates side conversion consistency" do
      # Test all valid side formats
      sides = [
        {:buy, :buy},
        {:sell, :sell},
        {"BUY", :buy},
        {"SELL", :sell}
      ]
      
      Enum.each(sides, fn {input_side, expected_side} ->
        attrs = %{symbol: "BTCUSDT", price: 100.0, quantity: 1.0, side: input_side}
        assert {:ok, trade} = Trade.new(attrs)
        assert trade.side == expected_side
      end)
    end
  end

  describe "property-based testing with generated data" do
    test "validates generated trade data" do
      symbols = ["BTCUSDT", "ETHUSDT", "ADAUSDT", "BNBUSDT", "XRPUSDT"]
      sides = [:buy, :sell]
      
      for _i <- 1..10 do
        symbol = Enum.random(symbols)
        price = :rand.uniform() * 100000 + 0.001  # Ensure positive price
        quantity = :rand.uniform() * 1000 + 0.001  # Ensure positive quantity
        side = Enum.random(sides)
        
        attrs = %{
          symbol: symbol,
          price: price,
          quantity: quantity,
          side: side
        }
        
        assert {:ok, trade} = Trade.new(attrs)
        assert trade.symbol == symbol
        assert trade.price == price
        assert trade.quantity == quantity
        assert trade.side == side
        
        # Test notional value calculation
        expected_notional = price * quantity
        assert Trade.notional_value(trade) == expected_notional
      end
    end
  end

  describe "serialization round-trip" do
    test "maintains data integrity through JSON conversion" do
      original_trade = %Trade{
        symbol: "BTCUSDT",
        price: 50000.0,
        quantity: 0.1,
        side: :buy
      }

      # Convert to JSON and back (simulating API usage)
      json = Trade.to_json(original_trade)
      
      # Create new trade from the JSON-like data
      assert {:ok, restored_trade} = Trade.new(%{
        symbol: json["symbol"],
        price: json["price"],
        quantity: json["quantity"],
        side: String.to_atom(json["side"])
      })

      assert restored_trade.symbol == original_trade.symbol
      assert restored_trade.price == original_trade.price
      assert restored_trade.quantity == original_trade.quantity
      assert restored_trade.side == original_trade.side
    end

    test "handles Binance format parsing round-trip" do
      # Test WebSocket format
      ws_data = %{
        "s" => "ETHUSDT",
        "p" => "3000.50",
        "q" => "2.5",
        "m" => false
      }
      
      assert {:ok, trade_from_ws} = Trade.from_binance_json(ws_data)
      json_output = Trade.to_json(trade_from_ws)
      
      assert json_output["symbol"] == "ETHUSDT"
      assert json_output["price"] == 3000.5
      assert json_output["quantity"] == 2.5
      assert json_output["side"] == "buy"
      
      # Test REST API format
      rest_data = %{
        "symbol" => "ADAUSDT",
        "price" => "1.25",
        "qty" => "1000.0",
        "isBuyerMaker" => true
      }
      
      assert {:ok, trade_from_rest} = Trade.from_binance_json(rest_data)
      json_output2 = Trade.to_json(trade_from_rest)
      
      assert json_output2["symbol"] == "ADAUSDT"
      assert json_output2["price"] == 1.25
      assert json_output2["quantity"] == 1000.0
      assert json_output2["side"] == "sell"
    end
  end
end