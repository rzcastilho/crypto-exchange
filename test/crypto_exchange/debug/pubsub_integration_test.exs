defmodule CryptoExchange.Debug.PubSubIntegrationTest do
  @moduledoc """
  Integration tests to verify end-to-end PubSub data flow.

  These tests verify that data flows correctly from WebSocket messages
  through parsing and into PubSub topics.
  """

  use ExUnit.Case, async: false
  require Logger

  alias CryptoExchange.Debug.PubSubSubscriber
  alias CryptoExchange.Binance.PublicStreams

  @moduletag :pubsub_debug

  describe "PubSub data flow verification" do
    setup do
      # Ensure PubSub is started for the test
      if !Process.whereis(CryptoExchange.PubSub) do
        {:ok, _} =
          start_supervised(
            {Phoenix.PubSub, name: CryptoExchange.PubSub, adapter: Phoenix.PubSub.PG2}
          )
      end

      # Start the debug subscriber
      {:ok, subscriber_pid} = start_supervised(PubSubSubscriber)

      # Clear any previous messages
      PubSubSubscriber.clear_messages()

      {:ok, %{subscriber: subscriber_pid}}
    end

    test "ticker data flows from WebSocket to PubSub", %{subscriber: _subscriber} do
      # Subscribe to ticker topic
      symbol = "BTCUSDT"
      topic = "binance:ticker:#{symbol}"
      assert :ok = PubSubSubscriber.subscribe(topic)

      # Simulate what PublicStreams receives from WebSocket
      binance_message = %{
        "stream" => "btcusdt@ticker",
        "data" => %{
          "e" => "24hrTicker",
          "E" => 123_456_789,
          "s" => "BTCUSDT",
          "p" => "1500.00",
          "P" => "3.21",
          "w" => "47850.12",
          "x" => "46700.00",
          "c" => "48200.50",
          "Q" => "0.125",
          "b" => "48200.00",
          "B" => "1.50",
          "a" => "48201.00",
          "A" => "2.30",
          "o" => "46700.50",
          "h" => "49000.00",
          "l" => "46500.00",
          "v" => "12345.67",
          "q" => "590123456.78",
          "O" => 123_456_000,
          "C" => 123_456_789,
          "F" => 1_234_567,
          "L" => 1_234_890,
          "n" => 324
        }
      }

      # Send the message directly to PublicStreams process
      # This simulates what WebSocketHandler would send
      send(PublicStreams, {:websocket_message, Jason.encode!(binance_message)})

      # Wait for message to be processed
      Process.sleep(100)

      # Check if message was received by subscriber
      messages = PubSubSubscriber.get_messages(1)
      count = PubSubSubscriber.message_count()

      Logger.info("""
      [INTEGRATION TEST] Ticker Flow Results:
      Messages received: #{count}
      Last message: #{inspect(messages, pretty: true)}
      """)

      assert count >= 1, "Expected at least 1 message, got #{count}"

      # Verify message structure
      [message | _] = messages
      assert message.type == :ticker
      assert message.symbol == symbol
      assert is_struct(message.data, CryptoExchange.Models.Ticker)
    end

    test "depth data flows from WebSocket to PubSub", %{subscriber: _subscriber} do
      # Subscribe to depth topic
      symbol = "BTCUSDT"
      topic = "binance:depth:#{symbol}"
      assert :ok = PubSubSubscriber.subscribe(topic)

      # Simulate depth update message
      binance_message = %{
        "stream" => "btcusdt@depth5",
        "data" => %{
          "e" => "depthUpdate",
          "E" => 123_456_789,
          "s" => "BTCUSDT",
          "U" => 157,
          "u" => 160,
          "b" => [["48200.00", "1.5"], ["48199.00", "2.3"]],
          "a" => [["48201.00", "0.8"], ["48202.00", "1.2"]]
        }
      }

      send(PublicStreams, {:websocket_message, Jason.encode!(binance_message)})
      Process.sleep(100)

      messages = PubSubSubscriber.get_messages(1)
      count = PubSubSubscriber.message_count()

      Logger.info("""
      [INTEGRATION TEST] Depth Flow Results:
      Messages received: #{count}
      Last message: #{inspect(messages, pretty: true)}
      """)

      assert count >= 1, "Expected at least 1 message, got #{count}"

      [message | _] = messages
      assert message.type == :depth
      assert message.symbol == symbol
      assert is_struct(message.data, CryptoExchange.Models.OrderBook)
    end

    test "trade data flows from WebSocket to PubSub", %{subscriber: _subscriber} do
      # Subscribe to trades topic
      symbol = "BTCUSDT"
      topic = "binance:trades:#{symbol}"
      assert :ok = PubSubSubscriber.subscribe(topic)

      # Simulate trade message
      binance_message = %{
        "stream" => "btcusdt@trade",
        "data" => %{
          "e" => "trade",
          "E" => 123_456_789,
          "s" => "BTCUSDT",
          "t" => 12345,
          "p" => "48200.50",
          "q" => "0.125",
          "b" => 88,
          "a" => 50,
          "T" => 123_456_785,
          "m" => true,
          "M" => true
        }
      }

      send(PublicStreams, {:websocket_message, Jason.encode!(binance_message)})
      Process.sleep(100)

      messages = PubSubSubscriber.get_messages(1)
      count = PubSubSubscriber.message_count()

      Logger.info("""
      [INTEGRATION TEST] Trade Flow Results:
      Messages received: #{count}
      Last message: #{inspect(messages, pretty: true)}
      """)

      assert count >= 1, "Expected at least 1 message, got #{count}"

      [message | _] = messages
      assert message.type == :trades
      assert message.symbol == symbol
      assert is_struct(message.data, CryptoExchange.Models.Trade)
    end

    test "kline data flows from WebSocket to PubSub", %{subscriber: _subscriber} do
      # Subscribe to klines topic with interval
      symbol = "BTCUSDT"
      interval = "1m"
      topic = "binance:klines:#{symbol}:#{interval}"
      assert :ok = PubSubSubscriber.subscribe(topic)

      # Simulate kline message
      binance_message = %{
        "stream" => "btcusdt@kline_1m",
        "data" => %{
          "e" => "kline",
          "E" => 123_456_789,
          "s" => "BTCUSDT",
          "k" => %{
            "t" => 123_456_000,
            "T" => 123_459_999,
            "s" => "BTCUSDT",
            "i" => "1m",
            "f" => 100,
            "L" => 200,
            "o" => "48000.00",
            "c" => "48200.50",
            "h" => "48250.00",
            "l" => "47950.00",
            "v" => "1000.00",
            "n" => 100,
            "x" => false,
            "q" => "48100000.00",
            "V" => "500.00",
            "Q" => "24050000.00"
          }
        }
      }

      send(PublicStreams, {:websocket_message, Jason.encode!(binance_message)})
      Process.sleep(100)

      messages = PubSubSubscriber.get_messages(1)
      count = PubSubSubscriber.message_count()

      Logger.info("""
      [INTEGRATION TEST] Kline Flow Results:
      Messages received: #{count}
      Last message: #{inspect(messages, pretty: true)}
      """)

      assert count >= 1, "Expected at least 1 message, got #{count}"

      [message | _] = messages
      assert message.type == :klines
      assert message.symbol == symbol
      assert is_struct(message.data, CryptoExchange.Models.Kline)
    end

    test "verifies topic naming consistency", %{subscriber: _subscriber} do
      # This test verifies that topic names match between broadcaster and subscriber

      test_cases = [
        %{
          stream: "btcusdt@ticker",
          expected_topic: "binance:ticker:BTCUSDT",
          type: :ticker
        },
        %{
          stream: "ethusdt@depth5",
          expected_topic: "binance:depth:ETHUSDT",
          type: :depth
        },
        %{
          stream: "bnbusdt@trade",
          expected_topic: "binance:trades:BNBUSDT",
          type: :trades
        },
        %{
          stream: "adausdt@kline_1m",
          expected_topic: "binance:klines:ADAUSDT:1m",
          type: :klines
        }
      ]

      for test_case <- test_cases do
        # Clear previous messages
        PubSubSubscriber.clear_messages()

        # Subscribe to expected topic
        assert :ok = PubSubSubscriber.subscribe(test_case.expected_topic)

        # Send a minimal valid message for this stream type
        data =
          case test_case.type do
            :ticker ->
              %{
                "e" => "24hrTicker",
                "E" => 123_456_789,
                "s" => extract_symbol(test_case.stream),
                "c" => "100.00",
                "p" => "1.00",
                "P" => "1.0"
              }

            :depth ->
              %{
                "e" => "depthUpdate",
                "E" => 123_456_789,
                "s" => extract_symbol(test_case.stream),
                "b" => [["100.00", "1.0"]],
                "a" => [["101.00", "1.0"]]
              }

            :trades ->
              %{
                "e" => "trade",
                "E" => 123_456_789,
                "s" => extract_symbol(test_case.stream),
                "t" => 123,
                "p" => "100.00",
                "q" => "1.0"
              }

            :klines ->
              %{
                "e" => "kline",
                "E" => 123_456_789,
                "s" => extract_symbol(test_case.stream),
                "k" => %{
                  "t" => 123_456_000,
                  "T" => 123_459_999,
                  "i" => extract_interval(test_case.stream),
                  "o" => "100.00",
                  "c" => "101.00",
                  "h" => "102.00",
                  "l" => "99.00"
                }
              }
          end

        binance_message = %{"stream" => test_case.stream, "data" => data}
        send(PublicStreams, {:websocket_message, Jason.encode!(binance_message)})
        Process.sleep(50)

        count = PubSubSubscriber.message_count()

        assert count == 1,
               "Topic mismatch for #{test_case.stream}. Expected topic: #{test_case.expected_topic}, Messages received: #{count}"

        # Unsubscribe for next iteration
        PubSubSubscriber.unsubscribe(test_case.expected_topic)
      end
    end
  end

  # Helper functions

  defp extract_symbol(stream) do
    stream
    |> String.split("@")
    |> List.first()
    |> String.upcase()
  end

  defp extract_interval(stream) do
    case String.split(stream, "@kline_") do
      [_, interval] -> interval
      _ -> "1m"
    end
  end
end
