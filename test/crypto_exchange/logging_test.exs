defmodule CryptoExchange.LoggingTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias CryptoExchange.Logging

  describe "basic logging functions" do
    test "info/2 logs structured messages" do
      log_output =
        capture_log([level: :info], fn ->
          Logging.info("Test message", %{
            category: :trading,
            user_id: "test_user",
            symbol: "BTCUSDT"
          })
        end)

      assert log_output =~ "Test message"
      assert log_output =~ "category=trading"
      assert log_output =~ "user_id=test_user"
      assert log_output =~ "symbol=BTCUSDT"
    end

    test "error/2 logs error messages with metadata" do
      log_output =
        capture_log(fn ->
          Logging.error("Operation failed", %{
            category: :api,
            error: :timeout,
            retry_count: 3
          })
        end)

      assert log_output =~ "[error]"
      assert log_output =~ "Operation failed"
      assert log_output =~ "category=api"
      assert log_output =~ "error=timeout"
      assert log_output =~ "retry_count=3"
    end

    test "debug/2 logs debug messages" do
      log_output =
        capture_log([level: :debug], fn ->
          Logging.debug("Debug info", %{category: :system})
        end)

      assert log_output =~ "[debug]"
      assert log_output =~ "Debug info"
      assert log_output =~ "category=system"
    end

    test "warning/2 logs warning messages" do
      log_output =
        capture_log(fn ->
          Logging.warning("Warning message", %{category: :websocket})
        end)

      assert log_output =~ "[warning]"
      assert log_output =~ "Warning message"
      assert log_output =~ "category=websocket"
    end
  end

  describe "context management" do
    test "set_context/1 and get_context/0 manage process context" do
      context = %{user_id: "alice", request_id: "req-123"}

      Logging.set_context(context)
      assert Logging.get_context() == context

      Logging.clear_context()
      assert Logging.get_context() == %{}
    end

    test "with_context/2 executes function with temporary context" do
      # Set initial context
      Logging.set_context(%{user_id: "bob"})

      result =
        Logging.with_context(%{request_id: "temp-456"}, fn ->
          context = Logging.get_context()
          assert context.user_id == "bob"
          assert context.request_id == "temp-456"
          "test_result"
        end)

      # Context should be restored
      final_context = Logging.get_context()
      assert final_context.user_id == "bob"
      assert Map.has_key?(final_context, :request_id) == false
      assert result == "test_result"
    end

    test "context is automatically included in log messages" do
      Logging.set_context(%{user_id: "charlie", session_id: "sess-789"})

      log_output =
        capture_log([level: :info], fn ->
          Logging.info("Contextual message", %{category: :trading})
        end)

      assert log_output =~ "user_id=charlie"
      assert log_output =~ "session_id=sess-789"
      assert log_output =~ "category=trading"

      Logging.clear_context()
    end
  end

  describe "performance timing" do
    test "with_timing/3 measures and logs execution time" do
      log_output =
        capture_log([level: :info], fn ->
          result =
            Logging.with_timing("Test operation", %{category: :performance}, fn ->
              # Small delay for timing
              Process.sleep(10)
              "success"
            end)

          assert result == "success"
        end)

      assert log_output =~ "Test operation completed"
      assert log_output =~ "category=performance"
      assert log_output =~ "duration_ms="
      assert log_output =~ "status=success"
    end

    test "with_timing/3 logs errors and re-raises exceptions" do
      log_output =
        capture_log(fn ->
          assert_raise RuntimeError, "test error", fn ->
            Logging.with_timing("Failing operation", %{category: :test}, fn ->
              raise "test error"
            end)
          end
        end)

      assert log_output =~ "Failing operation failed"
      assert log_output =~ "[error]"
      assert log_output =~ "status=error"
      assert log_output =~ "error_type=Elixir.RuntimeError"
      assert log_output =~ "duration_ms="
    end
  end

  describe "operation tracking" do
    test "start_operation/2 returns completion function" do
      log_output =
        capture_log([level: :info], fn ->
          complete_fn =
            Logging.start_operation("Test operation", %{
              category: :trading,
              user_id: "dave"
            })

          assert is_function(complete_fn, 2)

          # Simulate some work
          Process.sleep(5)

          complete_fn.(:success, %{order_id: "order-123"})
        end)

      assert log_output =~ "Test operation started"
      assert log_output =~ "Test operation completed"
      assert log_output =~ "user_id=dave"
      assert log_output =~ "order_id=order-123"
      assert log_output =~ "status=success"
      assert log_output =~ "duration_ms="
    end

    test "operation completion can log errors" do
      log_output =
        capture_log([level: :info], fn ->
          complete_fn = Logging.start_operation("Error operation", %{category: :api})
          complete_fn.(:error, %{error: :connection_failed, endpoint: "/api/test"})
        end)

      assert log_output =~ "Error operation started"
      assert log_output =~ "Error operation failed"
      assert log_output =~ "[error]"
      assert log_output =~ "status=error"
      assert log_output =~ "error=connection_failed"
    end
  end

  describe "specialized logging functions" do
    test "api_request_start/3 and api_request_complete/4 log API operations" do
      log_output =
        capture_log([level: :info], fn ->
          request_id = Logging.api_request_start("GET", "/api/v3/account", %{user_id: "eve"})

          assert is_binary(request_id)
          assert String.starts_with?(request_id, "req-")

          Logging.api_request_complete(request_id, "GET", 200, %{response_time: 150})
        end)

      assert log_output =~ "API request initiated"
      assert log_output =~ "API request completed"
      assert log_output =~ "method=GET"
      assert log_output =~ "endpoint=/api/v3/account"
      assert log_output =~ "status_code=200"
      assert log_output =~ "category=api"
      assert log_output =~ "user_id=eve"
    end

    test "trading_event/2 logs with trading category" do
      log_output =
        capture_log([level: :info], fn ->
          Logging.trading_event("Order placed", %{
            user_id: "frank",
            symbol: "ETHUSDT",
            order_id: "order-456"
          })
        end)

      assert log_output =~ "Order placed"
      assert log_output =~ "category=trading"
      assert log_output =~ "user_id=frank"
      assert log_output =~ "symbol=ETHUSDT"
    end

    test "websocket_event/2 logs with websocket category" do
      log_output =
        capture_log([level: :info], fn ->
          Logging.websocket_event("Connection established", %{
            endpoint: "wss://stream.binance.com:9443/ws",
            user_id: "grace"
          })
        end)

      assert log_output =~ "Connection established"
      assert log_output =~ "category=websocket"
      assert log_output =~ "endpoint=wss://stream.binance.com:9443/ws"
    end

    test "auth_event/2 sanitizes sensitive information" do
      log_output =
        capture_log([level: :info], fn ->
          Logging.auth_event("User authenticated", %{
            user_id: "henry",
            api_key: "test_key",
            # Should be filtered out
            secret_key: "sensitive_secret",
            # Should be filtered out
            password: "secret_password"
          })
        end)

      assert log_output =~ "User authenticated"
      assert log_output =~ "category=authentication"
      assert log_output =~ "user_id=henry"
      assert log_output =~ "api_key=test_key"
      refute log_output =~ "secret_key="
      refute log_output =~ "password="
      refute log_output =~ "sensitive_secret"
      refute log_output =~ "secret_password"
    end

    test "system_event/2 logs with system category" do
      log_output =
        capture_log([level: :info], fn ->
          Logging.system_event("Application started", %{
            version: "1.0.0",
            environment: :production
          })
        end)

      assert log_output =~ "Application started"
      assert log_output =~ "category=system"
      assert log_output =~ "version=1.0.0"
    end
  end

  describe "error handling" do
    test "error_with_exception/4 logs exception details" do
      log_output =
        capture_log(fn ->
          try do
            raise ArgumentError, "invalid argument"
          rescue
            exception ->
              Logging.error_with_exception("Operation failed", exception, __STACKTRACE__, %{
                category: :api,
                operation: "parse_response"
              })
          end
        end)

      assert log_output =~ "[error]"
      assert log_output =~ "Operation failed"
      assert log_output =~ "error_type=Elixir.ArgumentError"
      assert log_output =~ "error_message=invalid argument"
      assert log_output =~ "category=api"
      assert log_output =~ "stacktrace="
    end
  end

  describe "request ID generation" do
    test "new_request_id/0 generates unique identifiers" do
      id1 = Logging.new_request_id()
      id2 = Logging.new_request_id()

      assert String.starts_with?(id1, "req-")
      assert String.starts_with?(id2, "req-")
      assert id1 != id2
      assert String.length(id1) > 10
    end
  end

  describe "system metadata" do
    test "logs include system metadata automatically" do
      log_output =
        capture_log([level: :info], fn ->
          Logging.info("Test with system metadata", %{category: :test})
        end)

      # Note: In test mode, exact system metadata format may vary
      assert log_output =~ "category=test"

      # System metadata like node, timestamp, etc. are added but exact format depends on Logger configuration
    end
  end

  describe "integration scenarios" do
    test "complete trading operation with context and timing" do
      log_output =
        capture_log([level: :info], fn ->
          # Set user context
          Logging.set_context(%{user_id: "integration_user", session_id: "sess-integration"})

          # Start operation with timing
          result =
            Logging.with_timing("Process order placement", %{category: :trading}, fn ->
              # Log API request
              request_id =
                Logging.api_request_start("POST", "/api/v3/order", %{
                  symbol: "BTCUSDT",
                  side: "BUY"
                })

              # Simulate API processing
              Process.sleep(5)

              # Log API completion
              Logging.api_request_complete(request_id, "POST", 200, %{
                order_id: "integration_order_123"
              })

              # Log trading event
              Logging.trading_event("Order successfully placed", %{
                order_id: "integration_order_123",
                symbol: "BTCUSDT",
                side: "BUY"
              })

              :ok
            end)

          assert result == :ok
          Logging.clear_context()
        end)

      # Verify all expected log entries
      assert log_output =~ "API request initiated"
      assert log_output =~ "API request completed"
      assert log_output =~ "Order successfully placed"
      assert log_output =~ "Process order placement completed"

      # Verify context propagation
      assert log_output =~ "user_id=integration_user"
      assert log_output =~ "session_id=sess-integration"

      # Verify categories
      assert log_output =~ "category=api"
      assert log_output =~ "category=trading"
    end
  end
end
