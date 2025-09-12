defmodule CryptoExchange.Models.OrderBookTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Models.OrderBook

  describe "parse/1" do
    test "successfully parses a complete Binance order book message" do
      data = %{
        "e" => "depthUpdate",
        "E" => 1_640_995_200_000,
        "s" => "BTCUSDT",
        "U" => 157,
        "u" => 160,
        "b" => [
          ["48200.00000000", "1.50000000"],
          ["48199.00000000", "2.30000000"],
          ["48198.00000000", "0.00000000"]
        ],
        "a" => [
          ["48201.00000000", "0.80000000"],
          ["48202.00000000", "1.20000000"]
        ]
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.event_type == "depthUpdate"
      assert order_book.event_time == 1_640_995_200_000
      assert order_book.symbol == "BTCUSDT"
      assert order_book.first_update_id == 157
      assert order_book.final_update_id == 160

      assert length(order_book.bids) == 3
      assert hd(order_book.bids) == ["48200.00000000", "1.50000000"]
      assert Enum.at(order_book.bids, 2) == ["48198.00000000", "0.00000000"]

      assert length(order_book.asks) == 2
      assert hd(order_book.asks) == ["48201.00000000", "0.80000000"]
      assert Enum.at(order_book.asks, 1) == ["48202.00000000", "1.20000000"]
    end

    test "parses with minimal required fields" do
      data = %{
        "e" => "depthUpdate",
        "s" => "ETHUSDT"
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.event_type == "depthUpdate"
      assert order_book.symbol == "ETHUSDT"
      assert order_book.event_time == nil
      assert order_book.first_update_id == nil
      assert order_book.final_update_id == nil
      assert order_book.bids == []
      assert order_book.asks == []
    end

    test "handles empty bid and ask arrays" do
      data = %{
        "e" => "depthUpdate",
        "E" => 1_640_995_200_000,
        "s" => "BTCUSDT",
        "U" => 157,
        "u" => 160,
        "b" => [],
        "a" => []
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.bids == []
      assert order_book.asks == []
    end

    test "handles missing bid and ask fields" do
      data = %{
        "e" => "depthUpdate",
        "E" => 1_640_995_200_000,
        "s" => "BTCUSDT",
        "U" => 157,
        "u" => 160
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.bids == []
      assert order_book.asks == []
    end

    test "handles integer update IDs correctly" do
      data = %{
        "e" => "depthUpdate",
        "E" => 1_640_995_200_000,
        "s" => "BTCUSDT",
        "U" => 157,
        "u" => 160
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.first_update_id == 157
      assert order_book.final_update_id == 160
    end

    test "handles string update IDs correctly" do
      data = %{
        "e" => "depthUpdate",
        "E" => "1640995200000",
        "s" => "BTCUSDT",
        "U" => "157",
        "u" => "160"
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.event_time == 1_640_995_200_000
      assert order_book.first_update_id == 157
      assert order_book.final_update_id == 160
    end

    test "handles invalid integer values gracefully" do
      data = %{
        "e" => "depthUpdate",
        "E" => "invalid_timestamp",
        "s" => "BTCUSDT",
        "U" => "not_a_number",
        "u" => nil
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.event_time == nil
      assert order_book.first_update_id == nil
      assert order_book.final_update_id == nil
    end

    test "handles malformed price levels gracefully" do
      data = %{
        "e" => "depthUpdate",
        "s" => "BTCUSDT",
        "b" => [
          # Valid
          ["48200.00", "1.50"],
          # Missing quantity
          ["48199.00"],
          # Numeric values
          [48198.00, 2.30],
          # String entry
          "invalid_entry",
          # Nil entry
          nil
        ],
        "a" => [
          # Extra field
          ["48201.00", "0.80", "extra"],
          # Empty array
          []
        ]
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert length(order_book.bids) == 5
      assert Enum.at(order_book.bids, 0) == ["48200.00", "1.50"]
      # Malformed
      assert Enum.at(order_book.bids, 1) == ["0.00000000", "0.00000000"]
      # Converted from numbers
      assert Enum.at(order_book.bids, 2) == ["48198.0", "2.3"]

      assert length(order_book.asks) == 2
    end

    test "returns error for non-map input" do
      assert {:error, _reason} = OrderBook.parse("not a map")
      assert {:error, _reason} = OrderBook.parse(nil)
      assert {:error, _reason} = OrderBook.parse(42)
      assert {:error, _reason} = OrderBook.parse([])
    end
  end

  describe "best_bid/1" do
    test "returns the first bid when bids are available" do
      order_book = %OrderBook{
        bids: [["48200.00", "1.5"], ["48199.00", "2.3"]]
      }

      {:ok, best} = OrderBook.best_bid(order_book)
      assert best == ["48200.00", "1.5"]
    end

    test "returns error when no bids are available" do
      order_book = %OrderBook{bids: []}

      assert {:error, :no_bids} = OrderBook.best_bid(order_book)
    end
  end

  describe "best_ask/1" do
    test "returns the first ask when asks are available" do
      order_book = %OrderBook{
        asks: [["48201.00", "0.8"], ["48202.00", "1.2"]]
      }

      {:ok, best} = OrderBook.best_ask(order_book)
      assert best == ["48201.00", "0.8"]
    end

    test "returns error when no asks are available" do
      order_book = %OrderBook{asks: []}

      assert {:error, :no_asks} = OrderBook.best_ask(order_book)
    end
  end

  describe "spread/1" do
    test "calculates spread when both bids and asks are available" do
      order_book = %OrderBook{
        bids: [["48200.00", "1.5"]],
        asks: [["48201.00", "0.8"]]
      }

      {:ok, spread} = OrderBook.spread(order_book)
      assert spread == "1.0"
    end

    test "calculates spread with decimal precision" do
      order_book = %OrderBook{
        bids: [["48200.12345678", "1.5"]],
        asks: [["48201.87654321", "0.8"]]
      }

      {:ok, spread} = OrderBook.spread(order_book)
      assert String.starts_with?(spread, "1.75308643")
    end

    test "returns error when no bids" do
      order_book = %OrderBook{
        bids: [],
        asks: [["48201.00", "0.8"]]
      }

      assert {:error, :no_bids} = OrderBook.spread(order_book)
    end

    test "returns error when no asks" do
      order_book = %OrderBook{
        bids: [["48200.00", "1.5"]],
        asks: []
      }

      assert {:error, :no_asks} = OrderBook.spread(order_book)
    end

    test "returns error when prices are invalid" do
      order_book = %OrderBook{
        bids: [["invalid_price", "1.5"]],
        asks: [["48201.00", "0.8"]]
      }

      assert {:error, "Invalid price format"} = OrderBook.spread(order_book)
    end
  end

  describe "real Binance data examples" do
    test "parses actual Binance BNBBTC depth data" do
      # Real example from Binance documentation
      data = %{
        "e" => "depthUpdate",
        "E" => 123_456_789,
        "s" => "BNBBTC",
        "U" => 157,
        "u" => 160,
        "b" => [["0.0024", "10"]],
        "a" => [["0.0026", "100"]]
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.event_type == "depthUpdate"
      assert order_book.event_time == 123_456_789
      assert order_book.symbol == "BNBBTC"
      assert order_book.first_update_id == 157
      assert order_book.final_update_id == 160
      assert order_book.bids == [["0.0024", "10"]]
      assert order_book.asks == [["0.0026", "100"]]

      # Test utility functions with real data
      {:ok, best_bid} = OrderBook.best_bid(order_book)
      assert best_bid == ["0.0024", "10"]

      {:ok, best_ask} = OrderBook.best_ask(order_book)
      assert best_ask == ["0.0026", "100"]

      {:ok, spread} = OrderBook.spread(order_book)
      assert spread == "0.0002"
    end

    test "parses order book with quantity updates (including zero quantities)" do
      data = %{
        "e" => "depthUpdate",
        "E" => 123_456_789,
        "s" => "BTCUSDT",
        "U" => 157,
        "u" => 160,
        "b" => [
          # Add/update bid
          ["48200.00", "1.50"],
          # Remove bid (zero quantity)
          ["48199.00", "0.00000000"]
        ],
        "a" => [
          # Add/update ask
          ["48201.00", "0.80"],
          # Remove ask (zero quantity)
          ["48202.00", "0.00000000"]
        ]
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert length(order_book.bids) == 2
      assert length(order_book.asks) == 2

      # Zero quantities are preserved to indicate removal
      assert Enum.at(order_book.bids, 1) == ["48199.00", "0.00000000"]
      assert Enum.at(order_book.asks, 1) == ["48202.00", "0.00000000"]
    end
  end

  describe "edge cases" do
    test "handles very large update IDs" do
      data = %{
        "e" => "depthUpdate",
        "E" => 9_999_999_999_999,
        "s" => "BTCUSDT",
        "U" => 9_999_999_999,
        "u" => 9_999_999_999
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.event_time == 9_999_999_999_999
      assert order_book.first_update_id == 9_999_999_999
      assert order_book.final_update_id == 9_999_999_999
    end

    test "handles nil values gracefully" do
      data = %{
        "e" => "depthUpdate",
        "s" => "BTCUSDT",
        "E" => nil,
        "U" => nil,
        "u" => nil,
        "b" => nil,
        "a" => nil
      }

      {:ok, order_book} = OrderBook.parse(data)

      assert order_book.event_time == nil
      assert order_book.first_update_id == nil
      assert order_book.final_update_id == nil
      assert order_book.bids == []
      assert order_book.asks == []
    end
  end
end
