defmodule CryptoExchange.Models.OrderBookTest do
  @moduledoc """
  Comprehensive unit tests for the CryptoExchange.Models.OrderBook module.
  Tests validation, parsing, utility functions, and edge cases.
  """

  use CryptoExchange.TestSupport.TestCaseTemplate, async: true

  alias CryptoExchange.Models.OrderBook

  describe "OrderBook.new/1" do
    test "creates order book with valid attributes" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5], [49999.0, 2.0], [49998.0, 0.5]],
        asks: [[50001.0, 0.8], [50002.0, 1.2], [50003.0, 2.5]]
      }

      assert {:ok, order_book} = OrderBook.new(attrs)
      assert order_book.symbol == "BTCUSDT"
      assert length(order_book.bids) == 3
      assert length(order_book.asks) == 3
      assert order_book.bids == [[50000.0, 1.5], [49999.0, 2.0], [49998.0, 0.5]]
      assert order_book.asks == [[50001.0, 0.8], [50002.0, 1.2], [50003.0, 2.5]]
    end

    test "accepts empty bids and asks lists" do
      attrs = %{
        symbol: "ETHUSDT",
        bids: [],
        asks: []
      }

      assert {:ok, order_book} = OrderBook.new(attrs)
      assert order_book.bids == []
      assert order_book.asks == []
    end

    test "accepts mixed numeric types in price levels" do
      attrs = %{
        symbol: "ADAUSDT",
        bids: [[1.25, 1000], [1.24, 500.5]],
        asks: [[1.26, 750.0], [1.27, 250]]
      }

      assert {:ok, order_book} = OrderBook.new(attrs)
      assert order_book.bids == [[1.25, 1000], [1.24, 500.5]]
      assert order_book.asks == [[1.26, 750.0], [1.27, 250]]
    end

    test "rejects invalid symbol - nil" do
      attrs = %{
        symbol: nil,
        bids: [[50000.0, 1.0]],
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_symbol} = OrderBook.new(attrs)
    end

    test "rejects invalid symbol - empty string" do
      attrs = %{
        symbol: "",
        bids: [[50000.0, 1.0]],
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_symbol} = OrderBook.new(attrs)
    end

    test "rejects invalid bids - not a list" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: "not a list",
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_bids} = OrderBook.new(attrs)
    end

    test "rejects invalid asks - not a list" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.0]],
        asks: %{invalid: "structure"}
      }
      assert {:error, :invalid_asks} = OrderBook.new(attrs)
    end

    test "rejects invalid price level - wrong structure" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.0], ["invalid", "level"]],
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_price_levels} = OrderBook.new(attrs)
    end

    test "rejects price level with negative price" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[-50000.0, 1.0]],
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_price_levels} = OrderBook.new(attrs)
    end

    test "rejects price level with zero price" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[0.0, 1.0]],
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_price_levels} = OrderBook.new(attrs)
    end

    test "rejects price level with negative quantity" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0, -1.0]],
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_price_levels} = OrderBook.new(attrs)
    end

    test "rejects price level with zero quantity" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0, 0.0]],
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_price_levels} = OrderBook.new(attrs)
    end

    test "rejects incomplete price level" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0]],  # Missing quantity
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_price_levels} = OrderBook.new(attrs)
    end

    test "rejects price level with extra elements" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.0, "extra"]],
        asks: [[50001.0, 1.0]]
      }
      assert {:error, :invalid_price_levels} = OrderBook.new(attrs)
    end

    test "rejects invalid input type" do
      assert {:error, :invalid_input} = OrderBook.new("not a map")
      assert {:error, :invalid_input} = OrderBook.new(nil)
      assert {:error, :invalid_input} = OrderBook.new([])
    end
  end

  describe "OrderBook.from_binance_json/1" do
    test "parses WebSocket format correctly" do
      binance_data = %{
        "s" => "BTCUSDT",
        "b" => [["50000.00", "1.50"], ["49999.00", "2.00"]],
        "a" => [["50001.00", "0.80"], ["50002.00", "1.20"]]
      }

      assert {:ok, order_book} = OrderBook.from_binance_json(binance_data)
      assert order_book.symbol == "BTCUSDT"
      assert order_book.bids == [[50000.0, 1.5], [49999.0, 2.0]]
      assert order_book.asks == [[50001.0, 0.8], [50002.0, 1.2]]
    end

    test "parses REST API format correctly" do
      binance_data = %{
        "symbol" => "ETHUSDT",
        "bids" => [["3000.50", "5.25"], ["3000.00", "10.00"]],
        "asks" => [["3001.00", "3.75"], ["3001.50", "7.50"]]
      }

      assert {:ok, order_book} = OrderBook.from_binance_json(binance_data)
      assert order_book.symbol == "ETHUSDT"
      assert order_book.bids == [[3000.5, 5.25], [3000.0, 10.0]]
      assert order_book.asks == [[3001.0, 3.75], [3001.5, 7.5]]
    end

    test "handles numeric values in JSON" do
      binance_data = %{
        "s" => "ADAUSDT",
        "b" => [[1.25, 1000.0], [1.24, 500.0]],
        "a" => [[1.26, 750.0], [1.27, 250.0]]
      }

      assert {:ok, order_book} = OrderBook.from_binance_json(binance_data)
      assert order_book.bids == [[1.25, 1000.0], [1.24, 500.0]]
      assert order_book.asks == [[1.26, 750.0], [1.27, 250.0]]
    end

    test "handles empty bids and asks" do
      binance_data = %{
        "s" => "BTCUSDT",
        "b" => [],
        "a" => []
      }

      assert {:ok, order_book} = OrderBook.from_binance_json(binance_data)
      assert order_book.bids == []
      assert order_book.asks == []
    end

    test "handles malformed number strings gracefully" do
      binance_data = %{
        "s" => "BTCUSDT",
        "b" => [["invalid_price", "bad_quantity"]],
        "a" => [["50001.00", "not_a_number"]]
      }

      assert {:ok, order_book} = OrderBook.from_binance_json(binance_data)
      assert order_book.bids == [[0.0, 0.0]]
      assert order_book.asks == [[50001.0, 0.0]]
    end

    test "handles nil price levels" do
      binance_data = %{
        "s" => "BTCUSDT",
        "b" => nil,
        "a" => nil
      }

      assert {:ok, order_book} = OrderBook.from_binance_json(binance_data)
      assert order_book.bids == []
      assert order_book.asks == []
    end

    test "rejects invalid format - missing fields" do
      incomplete_data = %{
        "s" => "BTCUSDT",
        "b" => [["50000.00", "1.0"]]
        # Missing "a" field
      }

      assert {:error, :invalid_binance_format} = OrderBook.from_binance_json(incomplete_data)
    end

    test "rejects completely invalid input" do
      assert {:error, :invalid_binance_format} = OrderBook.from_binance_json(%{})
      assert {:error, :invalid_binance_format} = OrderBook.from_binance_json(nil)
      assert {:error, :invalid_binance_format} = OrderBook.from_binance_json("invalid")
    end
  end

  describe "OrderBook.to_json/1" do
    test "converts order book to JSON representation" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5], [49999.0, 2.0]],
        asks: [[50001.0, 0.8], [50002.0, 1.2]]
      }

      json = OrderBook.to_json(order_book)

      assert json["symbol"] == "BTCUSDT"
      assert json["bids"] == [[50000.0, 1.5], [49999.0, 2.0]]
      assert json["asks"] == [[50001.0, 0.8], [50002.0, 1.2]]
    end

    test "handles empty order book" do
      order_book = %OrderBook{
        symbol: "ETHUSDT",
        bids: [],
        asks: []
      }

      json = OrderBook.to_json(order_book)
      assert json["bids"] == []
      assert json["asks"] == []
    end
  end

  describe "OrderBook.best_bid/1" do
    test "returns best bid price from non-empty bids" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5], [49999.0, 2.0], [49998.0, 0.5]],
        asks: [[50001.0, 0.8]]
      }

      assert OrderBook.best_bid(order_book) == 50000.0
    end

    test "returns nil for empty bids" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [],
        asks: [[50001.0, 0.8]]
      }

      assert OrderBook.best_bid(order_book) == nil
    end

    test "returns first bid price even with single element" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[49500.0, 3.0]],
        asks: [[50001.0, 0.8]]
      }

      assert OrderBook.best_bid(order_book) == 49500.0
    end
  end

  describe "OrderBook.best_ask/1" do
    test "returns best ask price from non-empty asks" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5]],
        asks: [[50001.0, 0.8], [50002.0, 1.2], [50003.0, 2.5]]
      }

      assert OrderBook.best_ask(order_book) == 50001.0
    end

    test "returns nil for empty asks" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5]],
        asks: []
      }

      assert OrderBook.best_ask(order_book) == nil
    end

    test "returns first ask price even with single element" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5]],
        asks: [[50500.0, 1.0]]
      }

      assert OrderBook.best_ask(order_book) == 50500.0
    end
  end

  describe "OrderBook.spread/1" do
    test "calculates spread correctly with valid bid and ask" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5], [49999.0, 2.0]],
        asks: [[50001.0, 0.8], [50002.0, 1.2]]
      }

      spread = OrderBook.spread(order_book)
      assert spread == 1.0
    end

    test "calculates spread with fractional difference" do
      order_book = %OrderBook{
        symbol: "ETHUSDT",
        bids: [[3000.25, 5.0]],
        asks: [[3000.75, 3.0]]
      }

      spread = OrderBook.spread(order_book)
      assert spread == 0.5
    end

    test "returns nil when bids are empty" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [],
        asks: [[50001.0, 0.8]]
      }

      assert OrderBook.spread(order_book) == nil
    end

    test "returns nil when asks are empty" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5]],
        asks: []
      }

      assert OrderBook.spread(order_book) == nil
    end

    test "returns nil when both bids and asks are empty" do
      order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [],
        asks: []
      }

      assert OrderBook.spread(order_book) == nil
    end
  end

  describe "edge cases and data validation" do
    test "handles very small price differences" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0001, 1.0]],
        asks: [[50000.0002, 1.0]]
      }

      assert {:ok, order_book} = OrderBook.new(attrs)
      spread = OrderBook.spread(order_book)
      assert_in_delta spread, 0.0001, 0.0001
    end

    test "handles very large quantities" do
      attrs = %{
        symbol: "DOGEUSDT",
        bids: [[0.08, 1_000_000.0]],
        asks: [[0.081, 5_000_000.0]]
      }

      assert {:ok, order_book} = OrderBook.new(attrs)
      assert order_book.bids == [[0.08, 1_000_000.0]]
      assert order_book.asks == [[0.081, 5_000_000.0]]
    end

    test "handles many price levels" do
      # Generate 100 bid levels and 100 ask levels
      bids = for i <- 1..100, do: [50000.0 - i, :rand.uniform() * 10]
      asks = for i <- 1..100, do: [50001.0 + i, :rand.uniform() * 10]

      attrs = %{
        symbol: "BTCUSDT",
        bids: bids,
        asks: asks
      }

      assert {:ok, order_book} = OrderBook.new(attrs)
      assert length(order_book.bids) == 100
      assert length(order_book.asks) == 100
      assert OrderBook.best_bid(order_book) == 49999.0
      assert OrderBook.best_ask(order_book) == 50002.0
    end

    test "maintains order of price levels" do
      # Price levels should maintain the order provided
      bids = [[50000.0, 1.0], [49995.0, 2.0], [49990.0, 3.0]]
      asks = [[50005.0, 0.5], [50010.0, 1.5], [50015.0, 2.5]]

      attrs = %{symbol: "BTCUSDT", bids: bids, asks: asks}
      assert {:ok, order_book} = OrderBook.new(attrs)
      
      assert order_book.bids == bids
      assert order_book.asks == asks
    end
  end

  describe "serialization round-trip" do
    test "maintains data integrity through JSON conversion" do
      original_order_book = %OrderBook{
        symbol: "BTCUSDT",
        bids: [[50000.0, 1.5], [49999.0, 2.0]],
        asks: [[50001.0, 0.8], [50002.0, 1.2]]
      }

      # Convert to JSON and back
      json = OrderBook.to_json(original_order_book)
      
      assert {:ok, restored_order_book} = OrderBook.new(%{
        symbol: json["symbol"],
        bids: json["bids"],
        asks: json["asks"]
      })

      assert restored_order_book.symbol == original_order_book.symbol
      assert restored_order_book.bids == original_order_book.bids
      assert restored_order_book.asks == original_order_book.asks
    end
  end
end