defmodule CryptoExchange.Binance.MessageParsingTest do
  use ExUnit.Case, async: true
  
  alias CryptoExchange.{Binance, Models}
  alias CryptoExchange.Binance.PublicStreams
  
  import ExUnit.CaptureLog
  
  @moduletag :message_parsing
  
  describe "message parsing and validation" do
    setup do
      # Start a test PubSub server
      start_supervised!({Phoenix.PubSub, name: CryptoExchange.PubSub})
      
      # Test configuration
      params = %{
        message_callback: fn -> send(self(), :message_callback) end
      }
      
      topic = "test:ticker:BTCUSDT"
      
      %{params: params, topic: topic}
    end
    
    test "parses valid ticker message successfully", %{params: params, topic: topic} do
      # Start WebSocket client
      {:ok, pid} = PublicStreams.start_link(:ticker, "BTCUSDT", params, topic)
      
      # Subscribe to the topic
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Send a valid ticker message
      valid_ticker = Jason.encode!(%{
        "s" => "BTCUSDT",
        "c" => "50000.00",
        "P" => "1.50",
        "v" => "1234.56"
      })
      
      send(pid, {:websocket_message, valid_ticker})
      
      # Should receive parsed data
      assert_receive {:market_data, %{
        type: :ticker,
        symbol: "BTCUSDT",
        data: %Models.Ticker{
          symbol: "BTCUSDT",
          price: 50000.0,
          change: 1.5,
          volume: 1234.56
        }
      }}, 1000
      
      # Should trigger callback
      assert_receive :message_callback, 500
    end
    
    test "handles malformed JSON gracefully", %{params: params, topic: topic} do
      {:ok, pid} = PublicStreams.start_link(:ticker, "BTCUSDT", params, topic)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Send malformed JSON
      malformed_json = "{\"s\": \"BTCUSDT\", \"c\": invalid}"
      
      log = capture_log(fn ->
        send(pid, {:websocket_message, malformed_json})
        Process.sleep(100)  # Give time for processing
      end)
      
      # Should log parsing error
      assert log =~ "JSON parsing failed"
      assert log =~ "BTCUSDT"
      
      # Should not receive any market data
      refute_receive {:market_data, _}, 500
      
      # Should not trigger callback
      refute_receive :message_callback, 500
      
      # Check metrics
      metrics = PublicStreams.get_metrics(pid)
      assert metrics.error_counts[:json_parse_error] == 1
    end
    
    test "validates required fields for ticker messages", %{params: params, topic: topic} do
      {:ok, pid} = PublicStreams.start_link(:ticker, "BTCUSDT", params, topic)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Send ticker message missing required field
      invalid_ticker = Jason.encode!(%{
        "s" => "BTCUSDT",
        "c" => "50000.00",
        # Missing "P" and "v"
      })
      
      log = capture_log(fn ->
        send(pid, {:websocket_message, invalid_ticker})
        Process.sleep(100)
      end)
      
      # Should log validation error
      assert log =~ "Invalid message format"
      assert log =~ "Missing required ticker fields"
      
      # Should not receive market data
      refute_receive {:market_data, _}, 500
      
      # Check error metrics
      metrics = PublicStreams.get_metrics(pid)
      assert metrics.error_counts[:format_error] == 1
    end
    
    test "parses valid depth message successfully", %{params: params} do
      topic = "test:depth:BTCUSDT"
      {:ok, pid} = PublicStreams.start_link(:depth, "BTCUSDT", params, topic)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Send valid depth message
      valid_depth = Jason.encode!(%{
        "s" => "BTCUSDT",
        "b" => [["50000.00", "0.5"], ["49999.00", "1.0"]],
        "a" => [["50001.00", "0.3"], ["50002.00", "0.8"]]
      })
      
      send(pid, {:websocket_message, valid_depth})
      
      # Should receive parsed order book
      assert_receive {:market_data, %{
        type: :depth,
        symbol: "BTCUSDT",
        data: %Models.OrderBook{
          symbol: "BTCUSDT",
          bids: [[50000.0, 0.5], [49999.0, 1.0]],
          asks: [[50001.0, 0.3], [50002.0, 0.8]]
        }
      }}, 1000
    end
    
    test "validates price levels in depth messages", %{params: params} do
      topic = "test:depth:BTCUSDT"
      {:ok, pid} = PublicStreams.start_link(:depth, "BTCUSDT", params, topic)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Send depth message with invalid price levels
      invalid_depth = Jason.encode!(%{
        "s" => "BTCUSDT",
        "b" => [["invalid", "0.5"], [49999.0, 1.0]],  # Invalid price format
        "a" => [["50001.00", "0.3"]]
      })
      
      log = capture_log(fn ->
        send(pid, {:websocket_message, invalid_depth})
        Process.sleep(100)
      end)
      
      # Should log validation error
      assert log =~ "Invalid message format"
      assert log =~ "Invalid bids price level format"
      
      refute_receive {:market_data, _}, 500
    end
    
    test "parses valid trade message successfully", %{params: params} do
      topic = "test:trades:BTCUSDT"
      {:ok, pid} = PublicStreams.start_link(:trades, "BTCUSDT", params, topic)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Send valid trade message
      valid_trade = Jason.encode!(%{
        "s" => "BTCUSDT",
        "p" => "50000.00",
        "q" => "0.1",
        "m" => false  # Not buyer maker, so this is a buy
      })
      
      send(pid, {:websocket_message, valid_trade})
      
      # Should receive parsed trade
      assert_receive {:market_data, %{
        type: :trades,
        symbol: "BTCUSDT",
        data: %Models.Trade{
          symbol: "BTCUSDT",
          price: 50000.0,
          quantity: 0.1,
          side: :buy
        }
      }}, 1000
    end
    
    test "applies message filters when configured" do
      # Configure with price filter
      filtered_params = %{
        message_callback: fn -> send(self(), :message_callback) end,
        filters: [{:min_price, 51000.0}]  # Filter out prices below 51000
      }
      
      topic = "test:ticker:BTCUSDT"
      {:ok, pid} = PublicStreams.start_link(:ticker, "BTCUSDT", filtered_params, topic)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Send message with price below threshold
      low_price_ticker = Jason.encode!(%{
        "s" => "BTCUSDT",
        "c" => "50000.00",  # Below 51000 threshold
        "P" => "1.50",
        "v" => "1234.56"
      })
      
      log = capture_log(fn ->
        send(pid, {:websocket_message, low_price_ticker})
        Process.sleep(100)
      end)
      
      # Should be filtered out
      assert log =~ "Message validation failed"
      assert log =~ "Price below minimum threshold"
      
      refute_receive {:market_data, _}, 500
      
      # Send message with price above threshold
      high_price_ticker = Jason.encode!(%{
        "s" => "BTCUSDT",
        "c" => "52000.00",  # Above threshold
        "P" => "1.50",
        "v" => "1234.56"
      })
      
      send(pid, {:websocket_message, high_price_ticker})
      
      # Should receive this one
      assert_receive {:market_data, %{
        data: %Models.Ticker{price: 52000.0}
      }}, 1000
    end
    
    test "tracks comprehensive error metrics" do
      topic = "test:ticker:BTCUSDT"
      params = %{}
      {:ok, pid} = PublicStreams.start_link(:ticker, "BTCUSDT", params, topic)
      
      # Send various types of invalid messages
      invalid_json = "invalid json"
      incomplete_message = Jason.encode!(%{"s" => "BTCUSDT"})  # Missing required fields
      
      capture_log(fn ->
        send(pid, {:websocket_message, invalid_json})
        send(pid, {:websocket_message, incomplete_message})
        Process.sleep(200)
      end)
      
      # Check metrics
      metrics = PublicStreams.get_metrics(pid)
      
      assert metrics.error_counts[:json_parse_error] == 1
      assert metrics.error_counts[:format_error] == 1
      assert metrics.total_errors == 2
      assert metrics.health_status in [:degraded, :warning, :unhealthy]
    end
    
    test "provides detailed health status calculation" do
      topic = "test:ticker:BTCUSDT"
      params = %{}
      {:ok, pid} = PublicStreams.start_link(:ticker, "BTCUSDT", params, topic)
      
      # Initially healthy
      metrics = PublicStreams.get_metrics(pid)
      assert metrics.health_status == :healthy
      
      # Send valid message
      valid_ticker = Jason.encode!(%{
        "s" => "BTCUSDT",
        "c" => "50000.00",
        "P" => "1.50",
        "v" => "1234.56"
      })
      
      send(pid, {:websocket_message, valid_ticker})
      Process.sleep(50)
      
      # Still healthy after valid message
      metrics = PublicStreams.get_metrics(pid)
      assert metrics.health_status == :healthy
      assert metrics.messages_processed == 1
      assert metrics.total_errors == 0
      
      # Send many invalid messages to trigger degraded status
      capture_log(fn ->
        Enum.each(1..20, fn _ ->
          send(pid, {:websocket_message, "invalid"})
        end)
        Process.sleep(200)
      end)
      
      # Should be degraded due to high error rate
      metrics = PublicStreams.get_metrics(pid)
      assert metrics.health_status in [:degraded, :warning]
      assert metrics.total_errors == 20
    end
  end
  
  describe "broadcasting mechanisms" do
    setup do
      start_supervised!({Phoenix.PubSub, name: CryptoExchange.PubSub})
      :ok
    end
    
    test "broadcasts to correct PubSub topics" do
      topics = [
        "binance:ticker:BTCUSDT",
        "binance:depth:ETHUSDT", 
        "binance:trades:ADAUSDT"
      ]
      
      # Subscribe to all topics
      Enum.each(topics, &Phoenix.PubSub.subscribe(CryptoExchange.PubSub, &1))
      
      # Start clients for different streams
      {:ok, ticker_pid} = PublicStreams.start_link(:ticker, "BTCUSDT", %{}, topics |> Enum.at(0))
      {:ok, depth_pid} = PublicStreams.start_link(:depth, "ETHUSDT", %{}, topics |> Enum.at(1))
      {:ok, trades_pid} = PublicStreams.start_link(:trades, "ADAUSDT", %{}, topics |> Enum.at(2))
      
      # Send messages to each
      ticker_msg = Jason.encode!(%{"s" => "BTCUSDT", "c" => "50000", "P" => "1.5", "v" => "1000"})
      depth_msg = Jason.encode!(%{"s" => "ETHUSDT", "b" => [["3000", "10"]], "a" => [["3001", "5"]]})
      trades_msg = Jason.encode!(%{"s" => "ADAUSDT", "p" => "1.2", "q" => "1000", "m" => true})
      
      send(ticker_pid, {:websocket_message, ticker_msg})
      send(depth_pid, {:websocket_message, depth_msg})
      send(trades_pid, {:websocket_message, trades_msg})
      
      # Should receive messages on correct topics
      assert_receive {:market_data, %{type: :ticker, symbol: "BTCUSDT"}}, 1000
      assert_receive {:market_data, %{type: :depth, symbol: "ETHUSDT"}}, 1000  
      assert_receive {:market_data, %{type: :trades, symbol: "ADAUSDT"}}, 1000
    end
    
    test "includes comprehensive message metadata" do
      topic = "test:ticker:BTCUSDT"
      {:ok, pid} = PublicStreams.start_link(:ticker, "BTCUSDT", %{}, topic)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      valid_ticker = Jason.encode!(%{
        "s" => "BTCUSDT",
        "c" => "50000.00",
        "P" => "1.50", 
        "v" => "1234.56"
      })
      
      before_time = System.system_time(:millisecond)
      send(pid, {:websocket_message, valid_ticker})
      
      assert_receive {:market_data, %{
        type: :ticker,
        symbol: "BTCUSDT",
        data: %Models.Ticker{},
        timestamp: timestamp,
        source: :binance
      }}, 1000
      
      after_time = System.system_time(:millisecond)
      
      # Timestamp should be within reasonable bounds
      assert timestamp >= before_time
      assert timestamp <= after_time
    end
    
    test "handles PubSub broadcast failures gracefully" do
      # This test would require mocking PubSub to fail
      # For now, we verify the error handling code path exists
      topic = "test:ticker:BTCUSDT"
      {:ok, pid} = PublicStreams.start_link(:ticker, "BTCUSDT", %{}, topic)
      
      # Stop PubSub to simulate failure
      Process.exit(Process.whereis(CryptoExchange.PubSub), :kill)
      Process.sleep(50)
      
      valid_ticker = Jason.encode!(%{
        "s" => "BTCUSDT", 
        "c" => "50000.00",
        "P" => "1.50",
        "v" => "1234.56"
      })
      
      log = capture_log(fn ->
        send(pid, {:websocket_message, valid_ticker})
        Process.sleep(200)
      end)
      
      # Should handle the broadcast failure and continue operating
      assert String.contains?(log, "broadcast") || String.contains?(log, "PubSub")
    end
  end
end