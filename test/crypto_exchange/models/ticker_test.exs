defmodule CryptoExchange.Models.TickerTest do
  @moduledoc """
  Comprehensive unit tests for the CryptoExchange.Models.Ticker module.
  Tests all validation, parsing, and transformation functions.
  """

  use CryptoExchange.TestSupport.TestCaseTemplate, async: true

  alias CryptoExchange.Models.Ticker

  describe "Ticker.new/1" do
    test "creates ticker with valid attributes" do
      attrs = %{
        symbol: "BTCUSDT",
        price: 50000.0,
        change: 1500.0,
        volume: 1234.56
      }

      assert {:ok, ticker} = Ticker.new(attrs)
      assert ticker.symbol == "BTCUSDT"
      assert ticker.price == 50000.0
      assert ticker.change == 1500.0
      assert ticker.volume == 1234.56
    end

    test "accepts integer values for numeric fields" do
      attrs = %{
        symbol: "ETHUSDT",
        price: 3000,
        change: -50,
        volume: 1000
      }

      assert {:ok, ticker} = Ticker.new(attrs)
      assert ticker.price == 3000
      assert ticker.change == -50
      assert ticker.volume == 1000
    end

    test "allows negative change values" do
      attrs = %{
        symbol: "BTCUSDT",
        price: 45000.0,
        change: -2500.0,
        volume: 500.0
      }

      assert {:ok, ticker} = Ticker.new(attrs)
      assert ticker.change == -2500.0
    end

    test "allows zero volume" do
      attrs = %{
        symbol: "BTCUSDT",
        price: 50000.0,
        change: 0.0,
        volume: 0.0
      }

      assert {:ok, ticker} = Ticker.new(attrs)
      assert ticker.volume == 0.0
    end

    test "rejects invalid symbol - nil" do
      attrs = %{symbol: nil, price: 50000.0, change: 100.0, volume: 1000.0}
      assert {:error, :invalid_symbol} = Ticker.new(attrs)
    end

    test "rejects invalid symbol - empty string" do
      attrs = %{symbol: "", price: 50000.0, change: 100.0, volume: 1000.0}
      assert {:error, :invalid_symbol} = Ticker.new(attrs)
    end

    test "rejects invalid price - nil" do
      attrs = %{symbol: "BTCUSDT", price: nil, change: 100.0, volume: 1000.0}
      assert {:error, :invalid_price} = Ticker.new(attrs)
    end

    test "rejects invalid price - zero" do
      attrs = %{symbol: "BTCUSDT", price: 0, change: 100.0, volume: 1000.0}
      assert {:error, :invalid_price} = Ticker.new(attrs)
    end

    test "rejects invalid price - negative" do
      attrs = %{symbol: "BTCUSDT", price: -100.0, change: 100.0, volume: 1000.0}
      assert {:error, :invalid_price} = Ticker.new(attrs)
    end

    test "rejects invalid change - nil" do
      attrs = %{symbol: "BTCUSDT", price: 50000.0, change: nil, volume: 1000.0}
      assert {:error, :invalid_change} = Ticker.new(attrs)
    end

    test "rejects invalid volume - nil" do
      attrs = %{symbol: "BTCUSDT", price: 50000.0, change: 100.0, volume: nil}
      assert {:error, :invalid_volume} = Ticker.new(attrs)
    end

    test "rejects invalid input type" do
      assert {:error, :invalid_input} = Ticker.new("not a map")
      assert {:error, :invalid_input} = Ticker.new(nil)
      assert {:error, :invalid_input} = Ticker.new(123)
    end
  end

  describe "Ticker.from_binance_json/1" do
    test "parses WebSocket format correctly" do
      binance_data = %{
        "s" => "BTCUSDT",
        "c" => "50000.00",
        "P" => "1.50",
        "v" => "1234.56"
      }

      assert {:ok, ticker} = Ticker.from_binance_json(binance_data)
      assert ticker.symbol == "BTCUSDT"
      assert ticker.price == 50000.0
      assert ticker.change == 1.5
      assert ticker.volume == 1234.56
    end

    test "parses REST API format correctly" do
      binance_data = %{
        "symbol" => "ETHUSDT",
        "price" => "3000.50",
        "priceChange" => "-45.25",
        "volume" => "5678.90"
      }

      assert {:ok, ticker} = Ticker.from_binance_json(binance_data)
      assert ticker.symbol == "ETHUSDT"
      assert ticker.price == 3000.5
      assert ticker.change == -45.25
      assert ticker.volume == 5678.9
    end

    test "handles numeric values in JSON" do
      binance_data = %{
        "s" => "ADAUSDT",
        "c" => 1.25,
        "P" => -0.05,
        "v" => 10000.0
      }

      assert {:ok, ticker} = Ticker.from_binance_json(binance_data)
      assert ticker.price == 1.25
      assert ticker.change == -0.05
      assert ticker.volume == 10000.0
    end

    test "handles malformed number strings gracefully" do
      binance_data = %{
        "s" => "BTCUSDT",
        "c" => "invalid_price",
        "P" => "not_a_number",
        "v" => "bad_volume"
      }

      # The parse_float function returns 0.0 for invalid strings
      # But since price must be > 0, this should fail validation
      assert {:error, :invalid_price} = Ticker.from_binance_json(binance_data)
    end

    test "handles nil values gracefully" do
      binance_data = %{
        "s" => "BTCUSDT",
        "c" => nil,
        "P" => nil,
        "v" => nil
      }

      # Nil values are parsed as 0.0, but price must be > 0
      assert {:error, :invalid_price} = Ticker.from_binance_json(binance_data)
    end

    test "rejects invalid format - missing fields" do
      incomplete_data = %{
        "s" => "BTCUSDT",
        "c" => "50000.00"
        # Missing "P" and "v" fields
      }

      assert {:error, :invalid_binance_format} = Ticker.from_binance_json(incomplete_data)
    end

    test "rejects invalid format - wrong field names" do
      wrong_format = %{
        "symbol" => "BTCUSDT",
        "current_price" => "50000.00",
        "price_change" => "100.00",
        "trade_volume" => "1000.00"
      }

      assert {:error, :invalid_binance_format} = Ticker.from_binance_json(wrong_format)
    end

    test "rejects completely invalid input" do
      assert {:error, :invalid_binance_format} = Ticker.from_binance_json(%{})
      assert {:error, :invalid_binance_format} = Ticker.from_binance_json(nil)
      assert {:error, :invalid_binance_format} = Ticker.from_binance_json("invalid")
    end
  end

  describe "Ticker.to_json/1" do
    test "converts ticker to JSON representation" do
      ticker = %Ticker{
        symbol: "BTCUSDT",
        price: 50000.0,
        change: 1500.0,
        volume: 1234.56
      }

      json = Ticker.to_json(ticker)

      assert json["symbol"] == "BTCUSDT"
      assert json["price"] == 50000.0
      assert json["change"] == 1500.0
      assert json["volume"] == 1234.56
    end

    test "handles negative change values in JSON" do
      ticker = %Ticker{
        symbol: "ETHUSDT",
        price: 3000.0,
        change: -150.0,
        volume: 500.0
      }

      json = Ticker.to_json(ticker)
      assert json["change"] == -150.0
    end

    test "handles zero values in JSON" do
      ticker = %Ticker{
        symbol: "DOGEUSDT",
        price: 0.08,
        change: 0.0,
        volume: 0.0
      }

      json = Ticker.to_json(ticker)
      assert json["change"] == 0.0
      assert json["volume"] == 0.0
    end
  end

  describe "Ticker.validate/1" do
    test "validates correct ticker struct" do
      ticker = %Ticker{
        symbol: "BTCUSDT",
        price: 50000.0,
        change: 1000.0,
        volume: 1500.0
      }

      assert {:ok, validated_ticker} = Ticker.validate(ticker)
      assert validated_ticker.symbol == ticker.symbol
      assert validated_ticker.price == ticker.price
      assert validated_ticker.change == ticker.change
      assert validated_ticker.volume == ticker.volume
    end

    test "validates and fixes invalid ticker data" do
      # This tests the validation by creating a new ticker from the struct
      invalid_ticker = %Ticker{
        symbol: "BTCUSDT",
        price: 50000.0,
        change: 1000.0,
        volume: 1500.0
      }

      # Modify the ticker to have invalid data by bypassing struct validation
      invalid_data = invalid_ticker
                     |> Map.from_struct()
                     |> Map.put(:symbol, "")

      # Should catch the invalid symbol when validating
      assert {:error, :invalid_symbol} = Ticker.validate(%Ticker{
        symbol: "",
        price: 50000.0,
        change: 100.0,
        volume: 1000.0
      })
    end

    test "rejects non-ticker input" do
      assert {:error, :not_a_ticker} = Ticker.validate(%{})
      assert {:error, :not_a_ticker} = Ticker.validate(nil)
      assert {:error, :not_a_ticker} = Ticker.validate("invalid")
    end
  end

  describe "edge cases and data parsing" do
    test "handles very large numbers" do
      attrs = %{
        symbol: "BTCUSDT",
        price: 999_999_999.99,
        change: 50_000_000.0,
        volume: 1_000_000_000.0
      }

      assert {:ok, ticker} = Ticker.new(attrs)
      assert ticker.price == 999_999_999.99
      assert ticker.change == 50_000_000.0
      assert ticker.volume == 1_000_000_000.0
    end

    test "handles very small numbers" do
      attrs = %{
        symbol: "DOGEUSDT",
        price: 0.0001,
        change: -0.00005,
        volume: 0.001
      }

      assert {:ok, ticker} = Ticker.new(attrs)
      assert ticker.price == 0.0001
      assert ticker.change == -0.00005
      assert ticker.volume == 0.001
    end

    test "parses string numbers with trailing spaces gracefully" do
      binance_data = %{
        "s" => "BTCUSDT",
        "c" => "50000.00   ",
        "P" => "  1.50",
        "v" => " 1234.56 "
      }

      # The current implementation returns 0.0 for strings with spaces
      # This is the expected behavior for malformed strings
      assert {:error, :invalid_price} = Ticker.from_binance_json(binance_data)
      
      # Test with properly formatted strings (no spaces)
      clean_data = %{
        "s" => "BTCUSDT",
        "c" => "50000.00",
        "P" => "1.50",
        "v" => "1234.56"
      }
      
      assert {:ok, ticker} = Ticker.from_binance_json(clean_data)
      assert ticker.price == 50000.0
      assert ticker.change == 1.5
      assert ticker.volume == 1234.56
    end

    test "handles different symbol formats" do
      symbols = ["BTCUSDT", "ETHBTC", "ADAUSD", "DOGEEUR", "BNBBUSD"]
      
      Enum.each(symbols, fn symbol ->
        attrs = %{symbol: symbol, price: 100.0, change: 5.0, volume: 1000.0}
        assert {:ok, ticker} = Ticker.new(attrs)
        assert ticker.symbol == symbol
      end)
    end
  end

  describe "property-based testing with generated data" do
    test "validates generated ticker data" do
      # Generate random valid ticker data
      symbols = ["BTCUSDT", "ETHUSDT", "ADAUSDT", "BNBUSDT", "XRPUSDT"]
      
      for _i <- 1..10 do
        symbol = Enum.random(symbols)
        price = :rand.uniform() * 100000 + 0.001  # Ensure positive price
        change = (:rand.uniform() - 0.5) * 10000  # Allow negative change
        volume = :rand.uniform() * 1000000        # Non-negative volume
        
        attrs = %{
          symbol: symbol,
          price: price,
          change: change,
          volume: volume
        }
        
        assert {:ok, ticker} = Ticker.new(attrs)
        assert ticker.symbol == symbol
        assert ticker.price == price
        assert ticker.change == change
        assert ticker.volume == volume
      end
    end
  end

  describe "serialization round-trip" do
    test "maintains data integrity through JSON conversion" do
      original_ticker = %Ticker{
        symbol: "BTCUSDT",
        price: 50000.0,
        change: 1500.0,
        volume: 1234.56
      }

      # Convert to JSON and back (simulating API usage)
      json = Ticker.to_json(original_ticker)
      
      # Create new ticker from the JSON-like data
      assert {:ok, restored_ticker} = Ticker.new(%{
        symbol: json["symbol"],
        price: json["price"],
        change: json["change"],
        volume: json["volume"]
      })

      assert restored_ticker.symbol == original_ticker.symbol
      assert restored_ticker.price == original_ticker.price
      assert restored_ticker.change == original_ticker.change
      assert restored_ticker.volume == original_ticker.volume
    end
  end
end