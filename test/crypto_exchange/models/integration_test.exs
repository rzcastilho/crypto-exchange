defmodule CryptoExchange.Models.IntegrationTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Models.{Ticker, OrderBook, Trade}

  describe "integration with PublicStreams parsing" do
    test "parses real Binance ticker message" do
      # Real Binance ticker stream message format
      stream_data = %{
        "stream" => "btcusdt@ticker",
        "data" => %{
          "e" => "24hrTicker",
          "E" => 123_456_789,
          "s" => "BTCUSDT",
          "p" => "1500.00000000",
          "P" => "3.210",
          "w" => "47850.12345678",
          "x" => "46700.00000000",
          "c" => "48200.50000000",
          "Q" => "0.12500000",
          "b" => "48200.00000000",
          "B" => "1.50000000",
          "a" => "48201.00000000",
          "A" => "2.30000000",
          "o" => "46700.50000000",
          "h" => "49000.00000000",
          "l" => "46500.00000000",
          "v" => "12345.67890000",
          "q" => "590123456.78900000",
          "O" => 1_640_908_800_000,
          "C" => 1_640_995_200_000,
          "F" => 1_234_567,
          "L" => 1_234_890,
          "n" => 324
        }
      }

      {:ok, ticker} = Ticker.parse(stream_data["data"])

      assert ticker.symbol == "BTCUSDT"
      assert ticker.last_price == "48200.50000000"
      assert ticker.price_change == "1500.00000000"
      assert ticker.best_bid_price == "48200.00000000"
      assert ticker.best_ask_price == "48201.00000000"
      assert ticker.total_number_of_trades == 324
    end

    test "parses real Binance order book message" do
      # Real Binance depth stream message format
      stream_data = %{
        "stream" => "btcusdt@depth5",
        "data" => %{
          "e" => "depthUpdate",
          "E" => 123_456_789,
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
      }

      {:ok, order_book} = OrderBook.parse(stream_data["data"])

      assert order_book.symbol == "BTCUSDT"
      assert length(order_book.bids) == 3
      assert length(order_book.asks) == 2

      {:ok, best_bid} = OrderBook.best_bid(order_book)
      {:ok, best_ask} = OrderBook.best_ask(order_book)
      {:ok, spread} = OrderBook.spread(order_book)

      assert best_bid == ["48200.00000000", "1.50000000"]
      assert best_ask == ["48201.00000000", "0.80000000"]
      assert spread == "1.0"
    end

    test "parses real Binance trade message" do
      # Real Binance trade stream message format
      stream_data = %{
        "stream" => "btcusdt@trade",
        "data" => %{
          "e" => "trade",
          "E" => 123_456_789,
          "s" => "BTCUSDT",
          "t" => 12345,
          "p" => "48200.50000000",
          "q" => "0.12500000",
          "b" => 88,
          "a" => 50,
          "T" => 123_456_785,
          "m" => true,
          "M" => true
        }
      }

      {:ok, trade} = Trade.parse(stream_data["data"])

      assert trade.symbol == "BTCUSDT"
      assert trade.price == "48200.50000000"
      assert trade.quantity == "0.12500000"
      assert trade.is_buyer_market_maker == true
      assert Trade.trade_side(trade) == :sell

      {:ok, value} = Trade.trade_value(trade)
      assert String.starts_with?(value, "6025.0625")

      {:ok, is_large} = Trade.is_large_trade?(trade, "1000")
      assert is_large == true
    end

    test "demonstrates the parsing flow as used in PublicStreams" do
      # This demonstrates how the models integrate with PublicStreams
      ticker_data = %{
        "e" => "24hrTicker",
        "s" => "ETHUSDT",
        "c" => "4000.00000000",
        "p" => "150.00000000",
        "P" => "3.75"
      }

      depth_data = %{
        "e" => "depthUpdate",
        "s" => "ETHUSDT",
        "b" => [["3999.00", "1.5"]],
        "a" => [["4001.00", "0.8"]]
      }

      trade_data = %{
        "e" => "trade",
        "s" => "ETHUSDT",
        "p" => "4000.50000000",
        "q" => "2.00000000",
        "m" => false
      }

      # Parse using the model functions
      {:ok, ticker} = Ticker.parse(ticker_data)
      {:ok, order_book} = OrderBook.parse(depth_data)
      {:ok, trade} = Trade.parse(trade_data)

      # Verify parsed structures match expected PublicStreams format
      ticker_parsed = %{
        type: :ticker,
        symbol: "ETHUSDT",
        data: ticker
      }

      depth_parsed = %{
        type: :depth,
        symbol: "ETHUSDT",
        data: order_book
      }

      trade_parsed = %{
        type: :trades,
        symbol: "ETHUSDT",
        data: trade
      }

      # Verify the data is properly structured
      assert ticker_parsed.data.last_price == "4000.00000000"
      assert depth_parsed.data.bids == [["3999.00", "1.5"]]
      assert trade_parsed.data.price == "4000.50000000"
      assert Trade.trade_side(trade_parsed.data) == :buy
    end
  end
end
