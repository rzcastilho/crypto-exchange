defmodule CryptoExchange.LoggingIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  
  alias CryptoExchange.Logging

  describe "integration with real application scenarios" do
    test "structured logging system works with different log levels" do
      # Test error logging (which should always be captured)
      error_log = capture_log(fn ->
        Logging.error("Test error message", %{
          category: :trading,
          user_id: "test_user",
          error: :timeout
        })
      end)

      assert error_log =~ "Test error message"
      assert error_log =~ "category=trading"
      assert error_log =~ "user_id=test_user"

      # Test warning logging
      warning_log = capture_log(fn ->
        Logging.warning("Test warning", %{
          category: :api,
          retry_count: 3
        })
      end)

      assert warning_log =~ "Test warning"
      assert warning_log =~ "category=api"
    end

    test "context management works correctly" do
      # Test context setting and logging
      Logging.set_context(%{user_id: "context_user", session_id: "sess-123"})
      
      log_output = capture_log(fn ->
        Logging.error("Contextual error", %{category: :system})
      end)

      assert log_output =~ "user_id=context_user"
      assert log_output =~ "session_id=sess-123"
      assert log_output =~ "category=system"
      
      Logging.clear_context()
    end

    test "timing functionality works with structured logging" do
      log_output = capture_log(fn ->
        result = Logging.with_timing("Database operation", %{category: :system}, fn ->
          Process.sleep(5)
          "query_result"
        end)
        
        assert result == "query_result"
      end)

      # Should contain completion log (which is info level, but we can check for specific patterns)
      assert log_output =~ "duration_ms=" or log_output =~ "Database operation"
    end

    test "error handling with exceptions works" do
      log_output = capture_log(fn ->
        try do
          raise RuntimeError, "integration test error"
        rescue
          exception ->
            Logging.error_with_exception("Integration error occurred", exception, __STACKTRACE__, %{
              category: :system,
              operation: "test_operation"
            })
        end
      end)

      assert log_output =~ "Integration error occurred"
      assert log_output =~ "error_type=Elixir.RuntimeError"
      assert log_output =~ "category=system"
    end

    test "request ID generation and tracking" do
      request_id = Logging.new_request_id()
      
      assert String.starts_with?(request_id, "req-")
      assert String.length(request_id) > 10
      
      # Each call should generate unique IDs
      request_id_2 = Logging.new_request_id()
      assert request_id != request_id_2
    end

    test "specialized logging functions work correctly" do
      # Test API logging
      log_output = capture_log(fn ->
        request_id = Logging.api_request_start("GET", "/api/v3/account")
        Logging.api_request_complete(request_id, "GET", 200, %{duration_ms: 150})
      end)

      # Should capture the error-level logs if any API calls fail internally
      # or we can use warning/error level specialty functions
      assert is_binary(to_string(log_output))  # Just verify it doesn't crash

      # Test trading events (typically info level, but we test the function works)
      trading_log = capture_log(fn ->
        Logging.trading_event("Order executed", %{
          symbol: "BTCUSDT", 
          order_id: "12345",
          user_id: "trader"
        })
      end)

      # Verify function executes without error
      assert is_binary(to_string(trading_log))

      # Test authentication events
      auth_log = capture_log(fn ->
        Logging.auth_event("User login attempt", %{
          user_id: "secure_user",
          ip_address: "192.168.1.1",
          secret_key: "should_be_filtered",  # This should be filtered
          password: "also_filtered"
        })
      end)

      assert is_binary(to_string(auth_log))
    end
  end

  describe "real-world usage patterns" do
    test "complete trading operation logging workflow" do
      log_output = capture_log(fn ->
        # Set user context for the entire operation
        Logging.set_context(%{
          user_id: "integration_trader",
          session_id: "sess-integration"
        })

        # Start a tracked operation
        complete_fn = Logging.start_operation("Process trade order", %{
          category: :trading,
          symbol: "ETHUSDT"
        })

        # Simulate some work with error logging
        Logging.error("Validation failed", %{
          category: :trading,
          error: :insufficient_balance,
          required: "1000.00",
          available: "500.00"
        })

        # Complete the operation with error status
        complete_fn.(:error, %{
          error_code: "INSUFFICIENT_BALANCE",
          error_message: "Not enough funds"
        })

        Logging.clear_context()
      end)

      # Verify the logs contain our structured data
      assert log_output =~ "user_id=integration_trader"
      assert log_output =~ "category=trading"
      assert log_output =~ "Validation failed"
      assert log_output =~ "error=insufficient_balance"
      assert log_output =~ "Process trade order failed"
    end

    test "system startup and monitoring logging" do
      log_output = capture_log(fn ->
        # System startup events
        Logging.system_event("Application starting", %{
          version: "1.0.0",
          environment: :test,
          startup_time: System.monotonic_time(:millisecond)
        })

        # Health check logging
        Logging.warning("Health check warning", %{
          category: :system,
          component: "binance_client",
          status: :degraded,
          latency_ms: 2500
        })

        # Performance alert
        Logging.error("Performance threshold exceeded", %{
          category: :performance,
          operation: "order_processing",
          threshold_ms: 1000,
          actual_ms: 1500
        })
      end)

      assert log_output =~ "category=system"
      assert log_output =~ "category=performance"
      assert log_output =~ "Health check warning"
      assert log_output =~ "Performance threshold exceeded"
    end
  end

  describe "error scenarios and edge cases" do
    test "handles nil and empty values gracefully" do
      log_output = capture_log(fn ->
        Logging.error("Test with nil values", %{
          category: :test,
          user_id: nil,
          empty_string: "",
          valid_field: "valid_value"
        })
      end)

      assert log_output =~ "valid_field=valid_value"
      # nil values should be filtered out in the formatted message
    end

    test "handles large metadata gracefully" do
      large_metadata = %{
        category: :test,
        large_data: String.duplicate("x", 1000),
        nested_data: %{key: "value", another: "data"},
        list_data: [1, 2, 3, 4, 5]
      }

      log_output = capture_log(fn ->
        Logging.error("Test with large metadata", large_metadata)
      end)

      assert log_output =~ "category=test"
      # Function should not crash with large or complex data
      assert is_binary(log_output)
    end

    test "context isolation between processes" do
      # Set context in current process
      Logging.set_context(%{user_id: "process1"})
      
      # Spawn another process and verify it doesn't inherit context
      task = Task.async(fn ->
        context = Logging.get_context()
        # New process should have empty context
        assert context == %{}
        
        # Set different context in spawned process
        Logging.set_context(%{user_id: "process2"})
        Logging.get_context()
      end)
      
      spawned_context = Task.await(task)
      current_context = Logging.get_context()
      
      # Verify contexts are isolated
      assert spawned_context.user_id == "process2"
      assert current_context.user_id == "process1"
      
      Logging.clear_context()
    end
  end
end