defmodule CryptoExchange.Models.IntegrationTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Models.{Ticker, OrderBook, Trade, Kline}

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

    test "parses real Binance kline message" do
      # Real Binance kline stream message format
      stream_data = %{
        "stream" => "btcusdt@kline_1m",
        "data" => %{
          "e" => "kline",
          "E" => 123_456_789,
          "s" => "BTCUSDT",
          "k" => %{
            "t" => 123_400_000,
            "T" => 123_459_999,
            "s" => "BTCUSDT",
            "i" => "1m",
            "f" => 100,
            "L" => 200,
            "o" => "48000.00000000",
            "c" => "48200.50000000",
            "h" => "48300.00000000",
            "l" => "47980.00000000",
            "v" => "1000.50000000",
            "n" => 150,
            "x" => false,
            "q" => "48100000.00000000",
            "V" => "500.25000000",
            "Q" => "24050000.00000000"
          }
        }
      }

      {:ok, kline} = Kline.parse(stream_data["data"])

      assert kline.symbol == "BTCUSDT"
      assert kline.interval == "1m"
      assert kline.open_price == "48000.00000000"
      assert kline.close_price == "48200.50000000"
      assert kline.high_price == "48300.00000000"
      assert kline.low_price == "47980.00000000"
      assert kline.is_kline_closed == false

      # Test utility functions
      assert Kline.is_bullish?(kline) == true
      {:ok, change} = Kline.price_change(kline)
      assert change == "200.5"
    end

    test "demonstrates complete market data integration workflow" do
      # Simulate data as it would be received from different streams
      ticker_data = %{
        "e" => "24hrTicker",
        "s" => "BTCUSDT",
        "c" => "48200.00000000",
        "p" => "200.00000000",
        "P" => "0.42"
      }

      depth_data = %{
        "e" => "depthUpdate",
        "s" => "BTCUSDT",
        "b" => [["48199.00", "1.5"]],
        "a" => [["48201.00", "0.8"]]
      }

      trade_data = %{
        "e" => "trade",
        "s" => "BTCUSDT",
        "p" => "48200.50000000",
        "q" => "0.12500000",
        # Buy order
        "m" => false
      }

      kline_data = %{
        "e" => "kline",
        "s" => "BTCUSDT",
        "k" => %{
          "i" => "1m",
          "o" => "48000.00000000",
          "c" => "48200.50000000",
          "h" => "48250.00000000",
          "l" => "47980.00000000",
          # Closed kline
          "x" => true
        }
      }

      # Parse all data types
      {:ok, ticker} = Ticker.parse(ticker_data)
      {:ok, order_book} = OrderBook.parse(depth_data)
      {:ok, trade} = Trade.parse(trade_data)
      {:ok, kline} = Kline.parse(kline_data)

      # Create message format as would be broadcast
      ticker_parsed = %{
        type: :ticker,
        symbol: "BTCUSDT",
        data: ticker
      }

      depth_parsed = %{
        type: :depth,
        symbol: "BTCUSDT",
        data: order_book
      }

      trade_parsed = %{
        type: :trades,
        symbol: "BTCUSDT",
        data: trade
      }

      kline_parsed = %{
        type: :klines,
        symbol: "BTCUSDT",
        interval: "1m",
        data: kline
      }

      # Verify all data is properly structured and cross-consistent
      assert ticker_parsed.data.last_price == "48200.00000000"
      assert depth_parsed.data.bids == [["48199.00", "1.5"]]
      assert trade_parsed.data.price == "48200.50000000"
      assert kline_parsed.data.close_price == "48200.50000000"
      assert kline_parsed.data.is_kline_closed == true
      assert Kline.is_bullish?(kline_parsed.data) == true

      # Test cross-model consistency
      assert Trade.trade_side(trade_parsed.data) == :buy
      {:ok, kline_change} = Kline.price_change(kline_parsed.data)
      assert kline_change == "200.5"
    end
  end
end
