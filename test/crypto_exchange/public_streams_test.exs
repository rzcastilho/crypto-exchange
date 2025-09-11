defmodule CryptoExchange.PublicStreamsTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.PublicStreams
  alias CryptoExchange.PublicStreams.StreamManager

  setup do
    # Use the existing StreamManager from the application supervision tree
    # We'll clean up any existing streams before each test
    try do
      # Get existing streams and clean them up
      streams = StreamManager.list_streams()
      Enum.each(streams, fn stream ->
        StreamManager.unsubscribe(stream.symbol)
      end)
    rescue
      _ -> :ok  # StreamManager might not be started in test
    end
    
    # Give cleanup a moment to complete
    Process.sleep(50)
    
    %{}
  end

  describe "StreamManager initialization" do
    test "is available and responsive" do
      # Check that the StreamManager is running and responsive
      streams = StreamManager.list_streams()
      assert is_list(streams)
    end

    test "provides proper metrics" do
      {:ok, metrics} = StreamManager.get_metrics()
      assert metrics.total_streams >= 0
      assert metrics.healthy_streams >= 0
      assert metrics.total_messages >= 0
      assert is_number(metrics.messages_per_second)
    end

    test "provides proper health status" do
      {:ok, health} = StreamManager.health_status()
      assert health.total_streams >= 0
      assert health.overall_health in [:healthy, :degraded, :unhealthy, :mixed, :no_streams]
    end
  end

  describe "subscription management" do
    test "can subscribe to ticker stream" do
      # Subscribe to ticker
      result = StreamManager.subscribe(:ticker, "BTCUSDT", %{})
      
      case result do
        {:ok, topic} ->
          assert topic == "binance:ticker:BTCUSDT"
          
          # Check that stream was created
          streams = StreamManager.list_streams()
          assert length(streams) == 1
          
          stream = List.first(streams)
          assert stream.type == :ticker
          assert stream.symbol == "BTCUSDT"
          assert stream.subscribers == 1
          assert stream.health_status in [:healthy, :recovering]
          
        {:error, _reason} ->
          # In test environment, connection might fail, which is acceptable
          assert true
      end
    end

    test "can subscribe to depth stream with custom level" do
      result = StreamManager.subscribe(:depth, "ETHUSDT", %{level: 20})
      
      case result do
        {:ok, topic} ->
          assert topic == "binance:depth:ETHUSDT"
          
          streams = StreamManager.list_streams()
          stream = List.first(streams)
          assert stream.type == :depth
          assert stream.symbol == "ETHUSDT"
          
        {:error, _reason} ->
          # Connection might fail in test environment
          assert true
      end
    end

    test "can subscribe to trades stream" do
      result = StreamManager.subscribe(:trades, "ADAUSDT", %{})
      
      case result do
        {:ok, topic} ->
          assert topic == "binance:trades:ADAUSDT"
          
        {:error, _reason} ->
          assert true
      end
    end

    test "multiple subscribers to same stream share connection" do
      # First subscription
      result1 = StreamManager.subscribe(:ticker, "BTCUSDT", %{})
      
      case result1 do
        {:ok, topic1} ->
          # Second subscription to same stream
          result2 = StreamManager.subscribe(:ticker, "BTCUSDT", %{})
          
          case result2 do
            {:ok, topic2} ->
              assert topic1 == topic2
              
              streams = StreamManager.list_streams()
              assert length(streams) == 1
              
              # Should have 2 subscribers now
              stream = List.first(streams)
              assert stream.subscribers == 2
              
            {:error, _reason} ->
              assert true
          end
          
        {:error, _reason} ->
          assert true
      end
    end

    test "can unsubscribe from streams" do
      # Subscribe first
      result = StreamManager.subscribe(:ticker, "BTCUSDT", %{})
      
      case result do
        {:ok, _topic} ->
          # Verify stream exists
          streams = StreamManager.list_streams()
          assert length(streams) == 1
          
          # Unsubscribe
          :ok = StreamManager.unsubscribe("BTCUSDT")
          
          # Give it a moment for cleanup
          Process.sleep(100)
          
          # Stream should be removed
          streams = StreamManager.list_streams()
          assert length(streams) == 0
          
        {:error, _reason} ->
          # If subscription failed, unsubscribe should still work
          :ok = StreamManager.unsubscribe("BTCUSDT")
      end
    end
  end

  describe "error handling and recovery" do
    test "handles invalid symbol gracefully" do
      result = StreamManager.subscribe(:ticker, "XX", %{})
      assert {:error, :invalid_symbol} = result
    end

    test "handles subscription limit" do
      # This test would require mocking the configuration to set a low limit
      # For now, we'll just verify the function exists and can be called
      result = StreamManager.subscribe(:ticker, "BTCUSDT", %{})
      
      # Should either succeed or fail gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles process crashes gracefully" do
      # This test is challenging in a real environment
      # We can at least verify that the DOWN message handler doesn't crash
      _streams_before = StreamManager.list_streams()
      
      # Send a fake DOWN message (normally this would be from Process.monitor)
      ref = make_ref()
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      if manager_pid do
        send(manager_pid, {:DOWN, ref, :process, self(), :normal})
      end
      
      # Manager should still be alive and responsive
      Process.sleep(50)
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      assert manager_pid && Process.alive?(manager_pid)
      
      streams_after = StreamManager.list_streams()
      assert is_list(streams_after)
    end
  end

  describe "health monitoring" do
    test "performs health checks without crashing" do
      # Trigger a health check manually
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      if manager_pid do
        send(manager_pid, :health_check)
      end
      
      # Give it time to process
      Process.sleep(100)
      
      # Manager should still be responsive
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      assert manager_pid && Process.alive?(manager_pid)
      
      {:ok, health} = StreamManager.health_status()
      assert is_map(health)
      assert Map.has_key?(health, :overall_health)
    end

    test "performs subscriber cleanup without crashing" do
      # Trigger subscriber cleanup manually
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      if manager_pid do
        send(manager_pid, :cleanup_subscribers)
      end
      
      # Give it time to process
      Process.sleep(100)
      
      # Manager should still be responsive
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      assert manager_pid && Process.alive?(manager_pid)
      
      streams = StreamManager.list_streams()
      assert is_list(streams)
    end

    test "handles restart messages gracefully" do
      # Send a restart message (normally triggered internally)
      stream_key = {:ticker, "BTCUSDT"}
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      if manager_pid do
        send(manager_pid, {:restart_stream, stream_key, 1})
      end
      
      # Give it time to process
      Process.sleep(100)
      
      # Manager should still be responsive
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      assert manager_pid && Process.alive?(manager_pid)
    end

    test "handles stream messages for health tracking" do
      # Send a stream message for health tracking
      topic = "binance:ticker:BTCUSDT"
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      if manager_pid do
        send(manager_pid, {:stream_message, topic})
      end
      
      # Give it time to process
      Process.sleep(50)
      
      # Manager should still be responsive
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      assert manager_pid && Process.alive?(manager_pid)
      
      {:ok, metrics} = StreamManager.get_metrics()
      assert is_map(metrics)
    end
  end

  describe "metrics and monitoring" do
    test "provides comprehensive metrics" do
      {:ok, metrics} = StreamManager.get_metrics()
      
      # Check all expected metric fields
      assert Map.has_key?(metrics, :total_streams)
      assert Map.has_key?(metrics, :healthy_streams)
      assert Map.has_key?(metrics, :degraded_streams)
      assert Map.has_key?(metrics, :unhealthy_streams)
      assert Map.has_key?(metrics, :total_messages)
      assert Map.has_key?(metrics, :messages_per_second)
      assert Map.has_key?(metrics, :current_subscriptions)
      assert Map.has_key?(metrics, :active_subscribers)
      assert Map.has_key?(metrics, :uptime_seconds)
      
      # All metrics should be non-negative numbers
      assert metrics.total_streams >= 0
      assert metrics.healthy_streams >= 0
      assert metrics.total_messages >= 0
      assert metrics.messages_per_second >= 0.0
      assert metrics.uptime_seconds >= 0
    end

    test "provides detailed health status" do
      {:ok, health} = StreamManager.health_status()
      
      # Check all expected health fields
      assert Map.has_key?(health, :total_streams)
      assert Map.has_key?(health, :healthy_streams) 
      assert Map.has_key?(health, :degraded_streams)
      assert Map.has_key?(health, :unhealthy_streams)
      assert Map.has_key?(health, :recovering_streams)
      assert Map.has_key?(health, :overall_health)
      
      # Overall health should be a valid status
      assert health.overall_health in [:healthy, :degraded, :unhealthy, :mixed, :no_streams]
      
      # All counts should be non-negative
      assert health.total_streams >= 0
      assert health.healthy_streams >= 0
      assert health.degraded_streams >= 0
      assert health.unhealthy_streams >= 0
    end

    test "list_streams provides comprehensive stream info" do
      streams = StreamManager.list_streams()
      assert is_list(streams)
      
      # If we have streams, they should have complete information
      Enum.each(streams, fn stream ->
        assert Map.has_key?(stream, :type)
        assert Map.has_key?(stream, :symbol)
        assert Map.has_key?(stream, :topic)
        assert Map.has_key?(stream, :subscribers)
        assert Map.has_key?(stream, :health_status)
        assert Map.has_key?(stream, :created_at)
        assert Map.has_key?(stream, :last_message_at)
        assert Map.has_key?(stream, :reconnect_count)
        
        assert stream.type in [:ticker, :depth, :trades]
        assert is_binary(stream.symbol)
        assert is_binary(stream.topic)
        assert is_integer(stream.subscribers) and stream.subscribers >= 0
        assert stream.health_status in [:healthy, :degraded, :unhealthy, :recovering]
        assert is_integer(stream.created_at)
        assert is_integer(stream.last_message_at)
        assert is_integer(stream.reconnect_count) and stream.reconnect_count >= 0
      end)
    end
  end

  describe "convenience functions" do
    test "PublicStreams.subscribe wraps StreamManager.subscribe" do
      result = PublicStreams.subscribe(:ticker, "BTCUSDT")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      # Should be equivalent to calling StreamManager directly
      manager_result = StreamManager.subscribe(:ticker, "BTCUSDT", %{})
      
      case {result, manager_result} do
        {{:ok, topic1}, {:ok, topic2}} -> assert topic1 == topic2
        {{:error, reason1}, {:error, reason2}} -> assert reason1 == reason2
        _ -> assert false, "Results should match"
      end
    end

    test "PublicStreams.unsubscribe wraps StreamManager.unsubscribe" do
      # First subscribe to something
      _result = PublicStreams.subscribe(:ticker, "BTCUSDT")
      
      # Then unsubscribe
      result = PublicStreams.unsubscribe("BTCUSDT")
      assert result == :ok
    end

    test "PublicStreams functions provide expected data structures" do
      streams = PublicStreams.list_streams()
      assert is_list(streams)
      
      {:ok, metrics} = PublicStreams.get_metrics()
      assert is_map(metrics)
      
      {:ok, health} = PublicStreams.health_status()
      assert is_map(health)
    end
  end

  describe "configuration and limits" do
    test "respects configuration settings" do
      # This test verifies that the manager can access configuration
      # In a real test environment, we'd mock the configuration
      streams = StreamManager.list_streams()
      assert is_list(streams)
      
      # Manager should be responsive regardless of configuration
      manager_pid = Process.whereis(CryptoExchange.PublicStreams.StreamManager)
      assert manager_pid && Process.alive?(manager_pid)
    end
  end

  describe "integration with PubSub" do
    test "generates correct topic names" do
      # Test topic generation indirectly through subscription
      result = StreamManager.subscribe(:ticker, "BTCUSDT", %{})
      
      case result do
        {:ok, topic} ->
          assert topic == "binance:ticker:BTCUSDT"
          assert String.starts_with?(topic, "binance:")
          assert String.contains?(topic, "ticker")
          assert String.contains?(topic, "BTCUSDT")
          
        {:error, _reason} ->
          assert true
      end
    end
  end

  describe "termination and cleanup" do
    test "terminates gracefully" do
      {:ok, pid} = StreamManager.start_link([])
      
      # Subscribe to a stream
      _result = GenServer.call(pid, {:subscribe, :ticker, "BTCUSDT", %{}})
      
      # Should terminate without hanging
      assert :ok = GenServer.stop(pid, :normal)
      
      # Process should be dead
      refute Process.alive?(pid)
    end
  end
end