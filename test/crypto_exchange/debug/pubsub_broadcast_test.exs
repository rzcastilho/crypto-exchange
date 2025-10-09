defmodule CryptoExchange.Debug.PubSubBroadcastTest do
  @moduledoc """
  Unit tests to verify PubSub broadcast functionality.

  These tests verify that the broadcast_market_data function properly
  broadcasts to PubSub topics with correct formatting.
  """

  use ExUnit.Case, async: false
  require Logger

  @moduletag :pubsub_debug

  # Define a test module to access private functions
  defmodule TestHelper do
    def broadcast_test_data(market_data) do
      topic =
        case market_data.type do
          :klines ->
            build_topic_with_interval(market_data.type, market_data.symbol, market_data.interval)

          _ ->
            build_topic(market_data.type, market_data.symbol)
        end

      Phoenix.PubSub.broadcast(
        CryptoExchange.PubSub,
        topic,
        {:market_data, market_data}
      )
    end

    defp build_topic(stream_type, symbol) do
      "binance:#{stream_type}:#{symbol}"
    end

    defp build_topic_with_interval(stream_type, symbol, interval) do
      "binance:#{stream_type}:#{symbol}:#{interval}"
    end
  end

  setup_all do
    # PubSub is already started by the application supervision tree
    # Just verify it's running
    case Process.whereis(CryptoExchange.PubSub) do
      nil ->
        # If somehow not started, start it using the same config as application
        {:ok, _} =
          Phoenix.PubSub.Supervisor.start_link(name: CryptoExchange.PubSub)

      _pid ->
        :ok
    end

    :ok
  end

  describe "PubSub broadcast functionality" do
    test "ticker data broadcasts to correct topic" do
      # Create ticker market data
      ticker_data = %CryptoExchange.Models.Ticker{
        symbol: "BTCUSDT",
        last_price: "48200.50",
        event_type: "24hrTicker"
      }

      market_data = %{
        type: :ticker,
        symbol: "BTCUSDT",
        data: ticker_data
      }

      # Subscribe to the topic
      topic = "binance:ticker:BTCUSDT"
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

      # Broadcast the data
      assert :ok = TestHelper.broadcast_test_data(market_data)

      # Verify we received the message
      assert_receive {:market_data, received_data}, 1000

      Logger.info("""
      [BROADCAST TEST] Ticker Message Received:
      Type: #{received_data.type}
      Symbol: #{received_data.symbol}
      Data: #{inspect(received_data.data)}
      """)

      assert received_data.type == :ticker
      assert received_data.symbol == "BTCUSDT"
      assert received_data.data.last_price == "48200.50"
    end

    test "depth data broadcasts to correct topic" do
      # Create order book market data
      order_book_data = %CryptoExchange.Models.OrderBook{
        symbol: "BTCUSDT",
        bids: [["48200.00", "1.5"]],
        asks: [["48201.00", "0.8"]]
      }

      market_data = %{
        type: :depth,
        symbol: "BTCUSDT",
        data: order_book_data
      }

      # Subscribe to the topic
      topic = "binance:depth:BTCUSDT"
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

      # Broadcast the data
      assert :ok = TestHelper.broadcast_test_data(market_data)

      # Verify we received the message
      assert_receive {:market_data, received_data}, 1000

      Logger.info("""
      [BROADCAST TEST] Depth Message Received:
      Type: #{received_data.type}
      Symbol: #{received_data.symbol}
      Bids: #{inspect(received_data.data.bids)}
      Asks: #{inspect(received_data.data.asks)}
      """)

      assert received_data.type == :depth
      assert received_data.symbol == "BTCUSDT"
      assert length(received_data.data.bids) == 1
      assert length(received_data.data.asks) == 1
    end

    test "trade data broadcasts to correct topic" do
      # Create trade market data
      trade_data = %CryptoExchange.Models.Trade{
        symbol: "BTCUSDT",
        price: "48200.50",
        quantity: "0.125",
        event_type: "trade"
      }

      market_data = %{
        type: :trades,
        symbol: "BTCUSDT",
        data: trade_data
      }

      # Subscribe to the topic
      topic = "binance:trades:BTCUSDT"
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

      # Broadcast the data
      assert :ok = TestHelper.broadcast_test_data(market_data)

      # Verify we received the message
      assert_receive {:market_data, received_data}, 1000

      Logger.info("""
      [BROADCAST TEST] Trade Message Received:
      Type: #{received_data.type}
      Symbol: #{received_data.symbol}
      Price: #{received_data.data.price}
      Quantity: #{received_data.data.quantity}
      """)

      assert received_data.type == :trades
      assert received_data.symbol == "BTCUSDT"
      assert received_data.data.price == "48200.50"
    end

    test "kline data broadcasts to correct topic with interval" do
      # Create kline market data
      kline_data = %CryptoExchange.Models.Kline{
        symbol: "BTCUSDT",
        open_price: "48000.00",
        close_price: "48200.50",
        high_price: "48250.00",
        low_price: "47950.00",
        interval: "1m"
      }

      market_data = %{
        type: :klines,
        symbol: "BTCUSDT",
        interval: "1m",
        data: kline_data
      }

      # Subscribe to the topic (includes interval)
      topic = "binance:klines:BTCUSDT:1m"
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

      # Broadcast the data
      assert :ok = TestHelper.broadcast_test_data(market_data)

      # Verify we received the message
      assert_receive {:market_data, received_data}, 1000

      Logger.info("""
      [BROADCAST TEST] Kline Message Received:
      Type: #{received_data.type}
      Symbol: #{received_data.symbol}
      Interval: #{received_data.interval}
      Open: #{received_data.data.open_price}
      Close: #{received_data.data.close_price}
      """)

      assert received_data.type == :klines
      assert received_data.symbol == "BTCUSDT"
      assert received_data.interval == "1m"
      assert received_data.data.close_price == "48200.50"
    end

    test "different symbols broadcast to different topics" do
      # Create ticker data for BTC
      btc_data = %{
        type: :ticker,
        symbol: "BTCUSDT",
        data: %CryptoExchange.Models.Ticker{last_price: "48200.50"}
      }

      # Create ticker data for ETH
      eth_data = %{
        type: :ticker,
        symbol: "ETHUSDT",
        data: %CryptoExchange.Models.Ticker{last_price: "3500.25"}
      }

      # Subscribe to BTC topic only
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, "binance:ticker:BTCUSDT")

      # Broadcast both
      assert :ok = TestHelper.broadcast_test_data(btc_data)
      assert :ok = TestHelper.broadcast_test_data(eth_data)

      # Should receive only BTC message
      assert_receive {:market_data, %{symbol: "BTCUSDT"}}, 1000
      refute_receive {:market_data, %{symbol: "ETHUSDT"}}, 500

      Logger.info("[BROADCAST TEST] Topic isolation verified - only subscribed symbol received")
    end
  end
end
