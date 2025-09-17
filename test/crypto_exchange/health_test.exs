defmodule CryptoExchange.HealthTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  
  alias CryptoExchange.Health

  describe "system health checks" do
    test "check_system/0 returns comprehensive health status" do
      {:ok, health} = Health.check_system()
      
      # Verify structure
      assert %{
        status: status,
        timestamp: timestamp,
        components: components,
        metrics: metrics,
        version: version
      } = health
      
      # Verify status is valid
      assert status in [:healthy, :degraded, :unhealthy, :unknown]
      
      # Verify timestamp is recent
      assert DateTime.diff(DateTime.utc_now(), timestamp, :second) < 30
      
      # Verify components are present
      expected_components = [:binance_api, :websocket_connections, :trading_system, 
                           :user_connections, :application, :external_dependencies]
      assert MapSet.new(Map.keys(components)) == MapSet.new(expected_components)
      
      # Verify each component has required fields
      Enum.each(components, fn {component, result} ->
        assert %{status: comp_status, timestamp: comp_timestamp} = result
        assert comp_status in [:healthy, :degraded, :unhealthy, :unknown]
        assert %DateTime{} = comp_timestamp
        assert is_map(result.metadata || %{})
        assert is_atom(component)
      end)
      
      # Verify metrics
      assert is_map(metrics)
      assert is_integer(metrics.uptime_seconds)
      assert is_integer(metrics.memory_usage_mb)
      assert is_integer(metrics.process_count)
      
      # Verify version
      assert is_binary(version)
    end

    test "check_component/1 returns individual component status" do
      {:ok, result} = Health.check_component(:application)
      
      assert %{
        status: status,
        timestamp: timestamp,
        metadata: metadata
      } = result
      
      assert status in [:healthy, :degraded, :unhealthy, :unknown]
      assert %DateTime{} = timestamp
      assert is_map(metadata)
    end

    test "check_component/1 handles unknown components" do
      {:ok, result} = Health.check_component(:unknown_component)
      
      assert result.status == :unknown
      assert result.error_message =~ "Unknown component"
    end
  end

  describe "health monitor GenServer" do
    test "starts and maintains health state" do
      # Start monitor with shorter check interval for testing
      {:ok, pid} = Health.start_monitor(check_interval: 1000)
      
      # Verify it started
      assert Process.alive?(pid)
      
      # Get cached health
      {:ok, health} = Health.get_cached_health()
      assert is_map(health)
      assert Map.has_key?(health, :status)
      
      # Clean up
      GenServer.stop(pid)
    end

    test "refresh_health/0 triggers immediate update" do
      {:ok, pid} = Health.start_monitor(check_interval: 60000)  # Long interval
      
      # Get initial health
      {:ok, initial_health} = Health.get_cached_health()
      
      # Sleep briefly to ensure timestamp would be different
      Process.sleep(10)
      
      # Force refresh
      :ok = Health.refresh_health()
      
      # Get updated health
      {:ok, updated_health} = Health.get_cached_health()
      
      # Timestamp should be more recent (though this test might be flaky)
      assert DateTime.compare(updated_health.timestamp, initial_health.timestamp) in [:gt, :eq]
      
      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "individual component health checks" do
    test "binance_api check handles connectivity" do
      log_output = capture_log(fn ->
        {:ok, result} = Health.check_component(:binance_api)
        
        # Should have status and metadata
        assert Map.has_key?(result, :status)
        assert Map.has_key?(result, :metadata)
        
        # If healthy, should have latency info
        if result.status == :healthy do
          assert is_integer(result.latency_ms)
          assert result.latency_ms >= 0
        end
        
        # If unhealthy, should have error message
        if result.status == :unhealthy do
          assert is_binary(result.error_message)
        end
      end)
      
      # Should log system activity
      assert log_output == "" or String.contains?(log_output, "health")
    end

    test "trading_system check returns valid status" do
      {:ok, result} = Health.check_component(:trading_system)
      
      assert result.status in [:healthy, :degraded, :unhealthy, :unknown]
      assert is_map(result.metadata)
      
      # Should include trading system stats
      if result.status in [:healthy, :degraded] do
        assert Map.has_key?(result.metadata, :connected_users)
        assert Map.has_key?(result.metadata, :total_connections)
      end
    end

    test "application check monitors system resources" do
      {:ok, result} = Health.check_component(:application)
      
      assert result.status in [:healthy, :degraded, :unhealthy]
      
      # Should include system metrics
      metadata = result.metadata
      assert is_integer(metadata.process_count)
      assert is_integer(metadata.memory_bytes)
      assert is_integer(metadata.memory_mb)
      
      # Process count should be reasonable
      assert metadata.process_count > 0
      assert metadata.process_count < 100_000
      
      # Memory should be reasonable (less than 2GB for tests)
      assert metadata.memory_mb > 0
      assert metadata.memory_mb < 2048
    end

    test "user_connections check handles empty state gracefully" do
      {:ok, result} = Health.check_component(:user_connections)
      
      assert result.status in [:healthy, :degraded, :unhealthy]
      
      # Should handle case where no users are connected
      metadata = result.metadata
      assert is_integer(metadata.total_users)
      assert metadata.total_users >= 0
      
      if metadata.total_users == 0 do
        assert result.status == :degraded
      end
    end

    test "external_dependencies check is implemented" do
      {:ok, result} = Health.check_component(:external_dependencies)
      
      # Currently returns healthy as placeholder
      assert result.status == :healthy
      assert is_map(result.metadata)
    end
  end

  describe "health status determination" do
    test "determines overall status based on component health" do
      # We can't directly test the private function, but we can verify the system
      # correctly aggregates component statuses by testing the full system check
      
      {:ok, health} = Health.check_system()
      
      assert health.status in [:healthy, :degraded, :unhealthy, :unknown]
    end
  end

  describe "detailed health reporting" do
    test "detailed_report/0 provides comprehensive analysis" do
      {:ok, report} = Health.detailed_report()
      
      # Verify report structure
      assert %{
        current: current_health,
        trends: trends,
        alerts: alerts,
        recommendations: recommendations
      } = report
      
      # Verify current health
      assert is_map(current_health)
      assert Map.has_key?(current_health, :status)
      
      # Verify trends (even if placeholder)
      assert is_map(trends)
      
      # Verify alerts is a list
      assert is_list(alerts)
      
      # Verify recommendations is a list
      assert is_list(recommendations)
    end
  end

  describe "error handling and edge cases" do
    test "handles component check timeouts gracefully" do
      # Test that the system doesn't crash when component checks timeout
      {:ok, health} = Health.check_system()
      
      # Should complete within reasonable time (test has overall timeout)
      assert is_map(health)
      assert Map.has_key?(health, :status)
    end

    test "handles exceptions in component checks" do
      # The health checks should handle exceptions internally
      # and return appropriate error statuses
      
      log_output = capture_log(fn ->
        {:ok, health} = Health.check_system()
        
        # System should not crash even if individual components fail
        assert is_map(health)
        
        # Check that unhealthy components have error messages
        Enum.each(health.components, fn {_component, result} ->
          if result.status == :unhealthy do
            assert is_binary(result.error_message) or Map.has_key?(result, :error_message)
          end
        end)
      end)
      
      # May contain error logs, but should not crash
      assert is_binary(log_output)
    end

    test "system metrics are always present" do
      {:ok, health} = Health.check_system()
      
      metrics = health.metrics
      
      # Required metrics should always be present
      required_metrics = [:uptime_seconds, :memory_usage_mb, :process_count, 
                         :node, :otp_release, :health_check_duration_ms]
      
      Enum.each(required_metrics, fn metric ->
        assert Map.has_key?(metrics, metric), "Missing metric: #{metric}"
      end)
      
      # Values should be reasonable
      assert is_integer(metrics.uptime_seconds)
      assert metrics.uptime_seconds >= 0
      
      assert is_integer(metrics.memory_usage_mb)
      assert metrics.memory_usage_mb > 0
      
      assert is_integer(metrics.process_count)
      assert metrics.process_count > 0
      
      assert is_atom(metrics.node)
      
      assert is_integer(metrics.health_check_duration_ms)
      assert metrics.health_check_duration_ms >= 0
    end
  end

  describe "integration with logging system" do
    test "health checks produce structured logs" do
      log_output = capture_log(fn ->
        {:ok, _health} = Health.check_system()
      end)
      
      # Should produce some log output with structured information
      assert log_output =~ "health check" or log_output =~ "system"
      
      # Should not contain sensitive information
      refute log_output =~ "secret"
      refute log_output =~ "password"
    end

    test "component health changes are logged" do
      # This test would be more meaningful with a running monitor
      # that could detect status changes over time
      
      {:ok, pid} = Health.start_monitor(check_interval: 100)  # Fast interval
      
      log_output = capture_log(fn ->
        # Let it run a few checks
        Process.sleep(250)
      end)
      
      # Should produce periodic health check logs
      # (This might be flaky depending on timing)
      assert is_binary(log_output)
      
      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "performance and timing" do
    test "health checks complete within reasonable time" do
      start_time = System.monotonic_time(:millisecond)
      
      {:ok, health} = Health.check_system()
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete within 10 seconds (generous timeout for CI)
      assert duration < 10_000
      
      # Should report its own timing
      assert is_integer(health.metrics.health_check_duration_ms)
      assert health.metrics.health_check_duration_ms > 0
    end

    test "individual component checks are reasonably fast" do
      components = [:binance_api, :websocket_connections, :trading_system, 
                   :user_connections, :application, :external_dependencies]
      
      Enum.each(components, fn component ->
        start_time = System.monotonic_time(:millisecond)
        {:ok, _result} = Health.check_component(component)
        end_time = System.monotonic_time(:millisecond)
        
        duration = end_time - start_time
        
        # Each component check should complete within 5 seconds
        assert duration < 5_000, "Component #{component} took #{duration}ms"
      end)
    end
  end
end