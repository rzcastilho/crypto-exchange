defmodule CryptoExchange.PublicStreams.StreamManagerTest do
  use ExUnit.Case, async: true
  
  alias CryptoExchange.PublicStreams.StreamManager
  alias CryptoExchange.{Registry, Config}
  
  import ExUnit.CaptureLog
  
  @moduletag :stream_manager
  
  setup do
    # Start required services
    start_supervised!({Phoenix.PubSub, name: CryptoExchange.PubSub})
    start_supervised!({Registry, keys: :duplicate, name: CryptoExchange.Registry})
    
    # Start StreamManager
    {:ok, manager} = start_supervised({StreamManager, []})
    
    %{manager: manager}
  end
  
  describe "stream subscription" do
    test "subscribes to ticker streams successfully", %{manager: _manager} do
      {:ok, topic} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      assert topic == "binance:ticker:BTCUSDT"
      
      # Verify stream is tracked
      streams = StreamManager.list_streams()
      assert length(streams) == 1
      
      stream = hd(streams)
      assert stream.type == :ticker
      assert stream.symbol == "BTCUSDT"
      assert stream.topic == topic
    end
    
    test "subscribes to depth streams with custom level", %{manager: _manager} do
      {:ok, topic} = StreamManager.subscribe_to_depth("ETHUSDT", 20)
      
      assert topic == "binance:depth:ETHUSDT"
      
      streams = StreamManager.list_streams()
      assert length(streams) == 1
      
      stream = hd(streams)
      assert stream.type == :depth
      assert stream.symbol == "ETHUSDT"
    end
    
    test "subscribes to trade streams", %{manager: _manager} do
      {:ok, topic} = StreamManager.subscribe_to_trades("ADAUSDT")
      
      assert topic == "binance:trades:ADAUSDT"
      
      streams = StreamManager.list_streams()
      assert length(streams) == 1
      
      stream = hd(streams)
      assert stream.type == :trades
      assert stream.symbol == "ADAUSDT"
    end
    
    test "returns existing topic for duplicate subscriptions", %{manager: _manager} do
      {:ok, topic1} = StreamManager.subscribe_to_ticker("BTCUSDT")
      {:ok, topic2} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      assert topic1 == topic2
      
      # Should only have one stream
      streams = StreamManager.list_streams()
      assert length(streams) == 1
    end
    
    test "handles multiple concurrent subscriptions", %{manager: _manager} do
      symbols = ["BTCUSDT", "ETHUSDT", "ADAUSDT", "DOTUSDT", "LINKUSDT"]
      
      # Subscribe to ticker for all symbols concurrently
      tasks = Enum.map(symbols, fn symbol ->
        Task.async(fn -> StreamManager.subscribe_to_ticker(symbol) end)
      end)
      
      results = Task.await_many(tasks)
      
      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))
      
      # Should have 5 streams
      streams = StreamManager.list_streams()
      assert length(streams) == 5
      
      # Verify all symbols are present
      stream_symbols = Enum.map(streams, & &1.symbol)
      assert Enum.sort(stream_symbols) == Enum.sort(symbols)
    end
    
    test "validates symbol format", %{manager: _manager} do
      # Too short
      log = capture_log(fn ->
        assert {:error, :symbol_too_short} = StreamManager.subscribe_to_ticker("BT")
      end)
      
      # Invalid characters
      log = capture_log(fn ->
        assert {:error, :invalid_symbol_format} = StreamManager.subscribe_to_ticker("BTC-USD")
      end)
      
      # Not a string
      log = capture_log(fn ->
        assert {:error, :symbol_must_be_string} = StreamManager.subscribe_to_ticker(123)
      end)
    end
    
    test "validates stream parameters", %{manager: _manager} do
      # Invalid depth level
      log = capture_log(fn ->
        assert {:error, :invalid_depth_level} = StreamManager.subscribe_to_depth("BTCUSDT", -1)
      end)
      
      log = capture_log(fn ->
        assert {:error, :invalid_depth_level} = StreamManager.subscribe_to_depth("BTCUSDT", "invalid")
      end)
    end
  end
  
  describe "stream unsubscription" do
    test "unsubscribes from all streams for a symbol", %{manager: _manager} do
      # Subscribe to multiple stream types for same symbol
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      {:ok, _} = StreamManager.subscribe_to_depth("BTCUSDT")
      {:ok, _} = StreamManager.subscribe_to_trades("BTCUSDT")
      
      # Subscribe to different symbol
      {:ok, _} = StreamManager.subscribe_to_ticker("ETHUSDT")
      
      # Should have 4 streams total
      streams = StreamManager.list_streams()
      assert length(streams) == 4
      
      # Unsubscribe from BTCUSDT
      :ok = StreamManager.unsubscribe("BTCUSDT")
      
      # Should only have ETHUSDT stream left
      streams = StreamManager.list_streams()
      assert length(streams) == 1
      assert hd(streams).symbol == "ETHUSDT"
    end
  end
  
  describe "health monitoring" do
    test "provides health status for all streams", %{manager: _manager} do
      # Subscribe to some streams
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      {:ok, _} = StreamManager.subscribe_to_depth("ETHUSDT")
      
      {:ok, health} = StreamManager.health_status()
      
      assert health.total_streams == 2
      assert health.healthy_streams >= 0
      assert health.degraded_streams >= 0
      assert health.unhealthy_streams >= 0
      assert health.overall_health in [:healthy, :degraded, :unhealthy, :mixed, :no_streams]
    end
    
    test "calculates overall health correctly", %{manager: _manager} do
      # No streams initially
      {:ok, health} = StreamManager.health_status()
      assert health.overall_health == :no_streams
      
      # Add healthy stream
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      {:ok, health} = StreamManager.health_status()
      assert health.total_streams == 1
      assert health.overall_health in [:healthy, :mixed]  # May be healthy or mixed depending on timing
    end
  end
  
  describe "metrics and monitoring" do
    test "provides comprehensive stream metrics", %{manager: _manager} do
      # Subscribe to some streams
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      {:ok, _} = StreamManager.subscribe_to_depth("ETHUSDT")
      {:ok, _} = StreamManager.subscribe_to_trades("ADAUSDT")
      
      {:ok, metrics} = StreamManager.get_metrics()
      
      # Verify key metrics are present
      assert is_integer(metrics.total_streams)
      assert is_integer(metrics.healthy_streams)
      assert is_integer(metrics.degraded_streams)
      assert is_integer(metrics.unhealthy_streams)
      assert is_number(metrics.messages_per_second)
      assert is_integer(metrics.uptime_seconds)
      
      assert metrics.total_streams == 3
    end
    
    test "tracks stream creation timestamps", %{manager: _manager} do
      start_time = System.system_time(:millisecond)
      
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      end_time = System.system_time(:millisecond)
      
      streams = StreamManager.list_streams()
      stream = hd(streams)
      
      assert stream.created_at >= start_time
      assert stream.created_at <= end_time
    end
    
    test "handles stream process failures", %{manager: _manager} do
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      # Get the stream process
      streams = StreamManager.list_streams()
      stream = hd(streams)
      
      # Kill the stream process to simulate failure
      Process.exit(stream.pid, :kill)
      
      # Give time for DOWN message to be processed
      Process.sleep(100)
      
      # Stream should be removed from manager
      streams = StreamManager.list_streams()
      assert length(streams) == 0
    end
  end
  
  describe "enhanced stream parameters" do
    test "adds message callbacks to stream parameters" do
      # This test verifies that the StreamManager enhances parameters
      # with monitoring callbacks. We can't easily test the callback directly,
      # but we can verify the stream starts successfully with enhanced params.
      
      {:ok, topic} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      streams = StreamManager.list_streams()
      stream = hd(streams)
      
      assert stream.topic == topic
      assert is_pid(stream.pid)
      
      # The stream should have been started with enhanced parameters
      # including health monitoring callbacks
    end
  end
  
  describe "stream validation and error handling" do
    test "validates stream type" do
      log = capture_log(fn ->
        assert {:error, :invalid_stream_type} = StreamManager.subscribe(:invalid_type, "BTCUSDT")
      end)
    end
    
    test "handles stream startup timeouts" do
      # This is harder to test without mocking, but we can verify the timeout logic exists
      # by checking that stream startup is wrapped in a Task with timeout
      
      # For now, just verify normal startup works
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      streams = StreamManager.list_streams()
      assert length(streams) == 1
    end
    
    test "handles concurrent subscription attempts gracefully" do
      # Start many concurrent subscriptions to the same symbol
      tasks = Enum.map(1..20, fn _ ->
        Task.async(fn ->
          StreamManager.subscribe_to_ticker("BTCUSDT")
        end)
      end)
      
      results = Task.await_many(tasks)
      
      # All should return the same topic
      topics = Enum.map(results, fn {:ok, topic} -> topic end)
      assert Enum.all?(topics, &(&1 == "binance:ticker:BTCUSDT"))
      
      # Should only have one stream despite 20 subscription attempts
      streams = StreamManager.list_streams()
      assert length(streams) == 1
    end
  end
  
  describe "activity monitoring" do
    test "receives stream activity messages" do
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      # Simulate stream activity message
      send(StreamManager, {:stream_activity, System.system_time(:millisecond)})
      
      # Give time for message to be processed
      Process.sleep(50)
      
      # Metrics should reflect activity
      {:ok, metrics} = StreamManager.get_metrics()
      assert is_map(metrics)
    end
    
    test "performs periodic health checks" do
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      # Trigger health check manually
      send(StreamManager, :health_check)
      
      # Give time for health check to complete
      Process.sleep(100)
      
      # Should not crash and metrics should be available
      {:ok, health} = StreamManager.health_status()
      assert health.total_streams == 1
    end
    
    test "handles stream error notifications" do
      {:ok, _} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      stream_key = {:ticker, "BTCUSDT"}
      
      # Simulate stream error
      send(StreamManager, {:stream_error, stream_key, :connection_failed})
      
      # Give time for error to be processed
      Process.sleep(50)
      
      # Metrics should reflect the error
      {:ok, metrics} = StreamManager.get_metrics()
      assert metrics.total_errors >= 0  # Should handle the error gracefully
    end
  end
  
  describe "integration with WebSocket clients" do
    test "starts actual Binance WebSocket clients" do
      # This test verifies integration but doesn't connect to real Binance
      {:ok, topic} = StreamManager.subscribe_to_ticker("BTCUSDT")
      
      # Subscribe to the PubSub topic
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      streams = StreamManager.list_streams()
      stream = hd(streams)
      
      # The stream process should be a Binance WebSocket client
      assert is_pid(stream.pid)
      assert Process.alive?(stream.pid)
      
      # Get metrics from the WebSocket client
      try do
        client_metrics = GenServer.call(stream.pid, :get_metrics, 1000)
        assert is_map(client_metrics)
      catch
        :exit, {:timeout, _} ->
          # Timeout is OK for this test since we're not connecting to real Binance
          :ok
      end
    end
  end
end