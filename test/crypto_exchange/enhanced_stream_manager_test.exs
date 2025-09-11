defmodule CryptoExchange.EnhancedStreamManagerTest do
  use ExUnit.Case, async: false

  alias CryptoExchange.PublicStreams.StreamManager

  setup do
    # Start a dedicated test StreamManager to avoid conflicts
    {:ok, test_manager} = GenServer.start_link(StreamManager, [])
    
    on_exit(fn ->
      if Process.alive?(test_manager) do
        GenServer.stop(test_manager, :normal)
      end
    end)
    
    %{manager: test_manager}
  end

  describe "enhanced StreamManager functionality" do
    test "initializes with proper metrics structure", %{manager: manager} do
      # Get initial metrics from our test manager
      result = GenServer.call(manager, :get_metrics)
      
      assert {:ok, metrics} = result
      assert is_map(metrics)
      
      # Check core metric fields
      assert Map.has_key?(metrics, :total_streams)
      assert Map.has_key?(metrics, :current_subscriptions)
      assert Map.has_key?(metrics, :active_subscribers)
      assert metrics.total_streams == 0
      assert metrics.current_subscriptions == 0
      assert metrics.active_subscribers == 0
    end

    test "provides proper health status", %{manager: manager} do
      result = GenServer.call(manager, :health_status)
      
      assert {:ok, health} = result
      assert is_map(health)
      
      # Check health fields
      assert Map.has_key?(health, :total_streams)
      assert Map.has_key?(health, :overall_health)
      assert health.total_streams == 0
      assert health.overall_health == :no_streams
    end

    test "handles subscription attempts gracefully", %{manager: manager} do
      # Try to subscribe using our test manager
      # This will likely fail in test environment, but should not crash
      result = GenServer.call(manager, {:subscribe, :ticker, "TESTUSDT", %{}})
      
      # Should either succeed or fail gracefully
      case result do
        {:ok, topic} ->
          assert is_binary(topic)
          assert String.contains?(topic, "TESTUSDT")
          
        {:error, reason} ->
          # Expected in test environment where external connections fail
          assert reason in [:invalid_symbol, :connection_failed]
      end
    end

    test "list_streams returns empty list initially", %{manager: manager} do
      streams = GenServer.call(manager, :list_streams)
      assert is_list(streams)
      assert length(streams) == 0
    end

    test "handles unsubscribe gracefully even with no streams", %{manager: manager} do
      result = GenServer.call(manager, {:unsubscribe, "NONEXISTENT"})
      assert result == :ok
    end

    test "processes health check messages without crashing", %{manager: manager} do
      # Send health check message
      send(manager, :health_check)
      
      # Give it time to process
      Process.sleep(100)
      
      # Should still be responsive
      assert Process.alive?(manager)
      
      # Should still be able to get metrics
      result = GenServer.call(manager, :get_metrics)
      assert {:ok, _metrics} = result
    end

    test "processes cleanup messages without crashing", %{manager: manager} do
      # Send cleanup message
      send(manager, :cleanup_subscribers)
      
      # Give it time to process
      Process.sleep(100)
      
      # Should still be responsive
      assert Process.alive?(manager)
      
      # Should still be able to get health status
      result = GenServer.call(manager, :health_status)
      assert {:ok, _health} = result
    end

    test "handles stream restart messages gracefully", %{manager: manager} do
      # Send a restart message for non-existent stream
      stream_key = {:ticker, "TESTUSDT"}
      send(manager, {:restart_stream, stream_key, 1})
      
      # Give it time to process
      Process.sleep(100)
      
      # Should still be responsive
      assert Process.alive?(manager)
    end

    test "handles stream message notifications", %{manager: manager} do
      # Send stream message notification
      topic = "binance:ticker:TESTUSDT"
      send(manager, {:stream_message, topic})
      
      # Give it time to process
      Process.sleep(50)
      
      # Should still be responsive
      assert Process.alive?(manager)
      
      # Metrics should be updated
      {:ok, metrics} = GenServer.call(manager, :get_metrics)
      assert is_map(metrics)
    end

    test "terminates gracefully", %{manager: manager} do
      # Should be able to stop gracefully
      result = GenServer.stop(manager, :normal)
      assert result == :ok
      
      # Should no longer be alive
      refute Process.alive?(manager)
    end
  end

  describe "helper functions work correctly" do
    test "count_streams_by_status works with empty streams", %{manager: manager} do
      # Test the internal helper by checking health status
      {:ok, health} = GenServer.call(manager, :health_status)
      
      assert health.healthy_streams == 0
      assert health.degraded_streams == 0
      assert health.unhealthy_streams == 0
      assert health.recovering_streams == 0
    end

    test "calculate_overall_health returns :no_streams for empty state", %{manager: manager} do
      {:ok, health} = GenServer.call(manager, :health_status)
      assert health.overall_health == :no_streams
    end

    test "calculate_current_metrics provides comprehensive data", %{manager: manager} do
      {:ok, metrics} = GenServer.call(manager, :get_metrics)
      
      # Should have all expected fields
      expected_fields = [
        :total_streams, :current_subscriptions, :active_subscribers,
        :total_messages, :messages_per_second, :uptime_seconds
      ]
      
      Enum.each(expected_fields, fn field ->
        assert Map.has_key?(metrics, field), "Missing field: #{field}"
        assert is_number(metrics[field]) or metrics[field] == 0
      end)
    end
  end
end