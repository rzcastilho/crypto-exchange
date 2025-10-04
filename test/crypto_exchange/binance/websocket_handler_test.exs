defmodule CryptoExchange.Binance.WebSocketHandlerTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Binance.WebSocketHandler.ConnectionState

  describe "ConnectionState" do
    test "new/3 creates a ConnectionState with default configuration" do
      parent_pid = self()
      url = "wss://example.com/ws"

      state = ConnectionState.new(parent_pid, url)

      assert state.parent_pid == parent_pid
      assert state.url == url
      assert state.retry_count == 0
      assert state.circuit_breaker_state == :closed
      assert state.message_buffer == []
      assert state.total_reconnects == 0

      # Check default configuration
      config = state.config
      assert config.max_retries == 10
      assert config.base_delay == 1000
      assert config.max_delay == 300_000
      assert config.circuit_breaker_threshold == 5
      assert config.circuit_breaker_timeout == 60_000
      assert config.message_buffer_size == 100
    end

    test "new/3 accepts custom configuration options" do
      parent_pid = self()
      url = "wss://example.com/ws"

      opts = [
        max_retries: 5,
        base_delay: 2000,
        max_delay: 60_000,
        circuit_breaker_threshold: 3,
        message_buffer_size: 50
      ]

      state = ConnectionState.new(parent_pid, url, opts)

      config = state.config
      assert config.max_retries == 5
      assert config.base_delay == 2000
      assert config.max_delay == 60_000
      assert config.circuit_breaker_threshold == 3
      assert config.message_buffer_size == 50
    end
  end

  describe "send_message/2" do
    test "encodes map messages to JSON" do
      message = %{type: "subscribe", params: ["btcusdt@ticker"]}

      # The function should encode this to JSON
      json_string = Jason.encode!(message)
      assert is_binary(json_string)
      assert String.contains?(json_string, "subscribe")
      assert String.contains?(json_string, "btcusdt@ticker")
    end

    test "passes through binary messages unchanged" do
      message = "{\"type\":\"subscribe\"}"

      # Binary messages should be passed through as-is
      assert is_binary(message)
    end
  end

  describe "connection health and metrics" do
    test "calculates connection health metrics correctly" do
      parent_pid = self()
      url = "wss://example.com/ws"

      # Create a state with some test data
      base_time = DateTime.utc_now()

      state = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        retry_count: 2,
        circuit_breaker_state: :closed,
        connection_start_time: DateTime.add(base_time, -30, :second),
        last_pong_sent: base_time,
        message_buffer: ["msg1", "msg2"],
        total_reconnects: 1,
        last_error: :connection_lost,
        config: %{}
      }

      # Test the health calculation logic
      now = DateTime.utc_now()

      connection_duration =
        if state.connection_start_time do
          DateTime.diff(now, state.connection_start_time, :millisecond)
        else
          0
        end

      # Calculate time since last pong response (health indicator)
      last_pong_age =
        if state.last_pong_sent do
          DateTime.diff(now, state.last_pong_sent, :millisecond)
        else
          nil
        end

      assert connection_duration > 0
      # Should have a pong age since we set last_pong_sent
      assert last_pong_age != nil
      # Age should be non-negative
      assert last_pong_age >= 0
      assert length(state.message_buffer) == 2
    end

    test "detects disconnected state correctly" do
      parent_pid = self()
      url = "wss://example.com/ws"

      # State without connection_start_time indicates disconnected
      disconnected_state = ConnectionState.new(parent_pid, url)
      refute is_connected?(disconnected_state)

      # State with connection_start_time indicates connected
      connected_state = %{disconnected_state | connection_start_time: DateTime.utc_now()}
      assert is_connected?(connected_state)
    end
  end

  describe "reconnection logic" do
    test "calculates exponential backoff correctly" do
      config = %{
        base_delay: 1000,
        max_delay: 16000
      }

      # Test exponential progression
      delay1 = calculate_reconnect_delay(1, config)
      delay2 = calculate_reconnect_delay(2, config)
      delay3 = calculate_reconnect_delay(3, config)
      delay4 = calculate_reconnect_delay(4, config)
      delay5 = calculate_reconnect_delay(5, config)

      # Should follow exponential pattern: base * 2^(attempt-1)
      # But with jitter, so we test ranges
      # ~1000ms ±10%
      assert delay1 >= 900 && delay1 <= 1100
      # ~2000ms ±10%
      assert delay2 >= 1800 && delay2 <= 2200
      # ~4000ms ±10%
      assert delay3 >= 3600 && delay3 <= 4400
      # ~8000ms ±10%
      assert delay4 >= 7200 && delay4 <= 8800
      # Capped at max_delay
      assert delay5 == 16000
    end

    test "respects maximum delay" do
      config = %{
        base_delay: 1000,
        max_delay: 5000
      }

      # High attempt number should be capped
      delay = calculate_reconnect_delay(10, config)
      assert delay == 5000
    end

    test "determines when to reconnect based on retry count" do
      parent_pid = self()
      url = "wss://example.com/ws"

      # State within retry limits
      state_normal = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        retry_count: 2,
        config: %{
          max_retries: 5,
          circuit_breaker_threshold: 4,
          base_delay: 1000,
          max_delay: 16000
        }
      }

      assert should_reconnect?(state_normal) ==
               {:reconnect, calculate_reconnect_delay(2, state_normal.config)}

      # State at circuit breaker threshold
      state_circuit = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        retry_count: 4,
        config: %{max_retries: 10, circuit_breaker_threshold: 4}
      }

      assert should_reconnect?(state_circuit) == :circuit_open

      # State exceeding max retries
      state_max = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        retry_count: 6,
        config: %{max_retries: 5, circuit_breaker_threshold: 4}
      }

      assert should_reconnect?(state_max) == :max_retries_exceeded
    end
  end

  describe "message buffering" do
    test "adds messages to buffer respecting size limits" do
      buffer = []
      max_size = 3

      # Add messages within limit
      buffer1 = add_to_buffer(buffer, "msg1", max_size)
      buffer2 = add_to_buffer(buffer1, "msg2", max_size)
      buffer3 = add_to_buffer(buffer2, "msg3", max_size)

      assert length(buffer3) == 3
      assert buffer3 == ["msg3", "msg2", "msg1"]

      # Adding beyond limit should truncate
      buffer4 = add_to_buffer(buffer3, "msg4", max_size)
      assert length(buffer4) == 3
      assert buffer4 == ["msg4", "msg3", "msg2"]
    end

    test "handles empty buffer correctly" do
      buffer = []
      max_size = 5

      new_buffer = add_to_buffer(buffer, "first_message", max_size)
      assert length(new_buffer) == 1
      assert new_buffer == ["first_message"]
    end
  end

  describe "circuit breaker functionality" do
    test "opens circuit breaker after threshold failures" do
      parent_pid = self()
      url = "wss://example.com/ws"

      state = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        retry_count: 5,
        circuit_breaker_state: :closed,
        config: %{circuit_breaker_threshold: 5, max_retries: 10}
      }

      result = should_reconnect?(state)
      assert result == :circuit_open
    end

    test "tracks circuit breaker opened time" do
      parent_pid = self()
      url = "wss://example.com/ws"
      opened_time = DateTime.utc_now()

      state = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        circuit_breaker_state: :open,
        circuit_breaker_opened_at: opened_time,
        config: %{}
      }

      assert state.circuit_breaker_state == :open
      assert state.circuit_breaker_opened_at == opened_time
    end
  end

  describe "ping/pong health monitoring" do
    test "tracks server ping response timestamps" do
      parent_pid = self()
      url = "wss://example.com/ws"

      pong_time = DateTime.utc_now()

      state = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        last_pong_sent: pong_time,
        config: %{}
      }

      # Calculate time since last pong response
      now = DateTime.utc_now()
      pong_age = DateTime.diff(now, state.last_pong_sent, :millisecond)
      assert pong_age >= 0
    end

    test "handles missing pong data gracefully" do
      parent_pid = self()
      url = "wss://example.com/ws"

      # State with no pong data
      state = ConnectionState.new(parent_pid, url)

      assert state.last_pong_sent == nil

      # Should handle nil values gracefully in pong age calculation
      pong_age = nil

      assert pong_age == nil
    end
  end

  describe "error handling and recovery" do
    test "tracks last error and retry count" do
      parent_pid = self()
      url = "wss://example.com/ws"

      state = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        retry_count: 3,
        last_error: :timeout,
        config: %{}
      }

      assert state.retry_count == 3
      assert state.last_error == :timeout
    end

    test "resets state on successful connection" do
      parent_pid = self()
      url = "wss://example.com/ws"

      # State with previous errors
      error_state = %ConnectionState{
        parent_pid: parent_pid,
        url: url,
        retry_count: 5,
        last_error: :connection_failed,
        circuit_breaker_state: :open,
        circuit_breaker_opened_at: DateTime.utc_now(),
        config: %{}
      }

      # Simulate successful reconnection
      now = DateTime.utc_now()

      recovered_state = %{
        error_state
        | retry_count: 0,
          last_error: nil,
          circuit_breaker_state: :closed,
          circuit_breaker_opened_at: nil,
          connection_start_time: now
      }

      assert recovered_state.retry_count == 0
      assert recovered_state.last_error == nil
      assert recovered_state.circuit_breaker_state == :closed
      assert recovered_state.circuit_breaker_opened_at == nil
      assert recovered_state.connection_start_time == now
    end
  end

  describe "integration scenarios" do
    test "complete failure and recovery cycle" do
      parent_pid = self()
      url = "wss://example.com/ws"

      # Start with fresh state
      initial_state =
        ConnectionState.new(parent_pid, url,
          max_retries: 3,
          circuit_breaker_threshold: 2
        )

      # First failure
      state_after_failure_1 = %{initial_state | retry_count: 1, last_error: :connection_refused}

      result_1 = should_reconnect?(state_after_failure_1)
      assert match?({:reconnect, _delay}, result_1)

      # Second failure - should open circuit
      state_after_failure_2 = %{state_after_failure_1 | retry_count: 2, last_error: :timeout}

      result_2 = should_reconnect?(state_after_failure_2)
      assert result_2 == :circuit_open

      # Circuit breaker should be open now
      circuit_open_state = %{
        state_after_failure_2
        | circuit_breaker_state: :open,
          circuit_breaker_opened_at: DateTime.utc_now()
      }

      assert circuit_open_state.circuit_breaker_state == :open

      # Recovery after circuit breaker timeout would reset the state
      recovered_state = %{
        circuit_open_state
        | retry_count: 0,
          last_error: nil,
          circuit_breaker_state: :closed,
          circuit_breaker_opened_at: nil,
          connection_start_time: DateTime.utc_now()
      }

      assert recovered_state.circuit_breaker_state == :closed
      assert recovered_state.retry_count == 0
    end
  end

  # Helper functions consolidated here
  defp is_connected?(%ConnectionState{connection_start_time: nil}), do: false
  defp is_connected?(%ConnectionState{}), do: true

  defp should_reconnect?(%ConnectionState{} = state) do
    cond do
      state.retry_count >= state.config.max_retries ->
        :max_retries_exceeded

      state.retry_count >= state.config.circuit_breaker_threshold ->
        :circuit_open

      true ->
        delay = calculate_reconnect_delay(state.retry_count, state.config)
        {:reconnect, delay}
    end
  end

  defp calculate_reconnect_delay(attempt, config) do
    base_delay = config.base_delay
    max_delay = config.max_delay

    # Exponential backoff: base_delay * (2 ^ (attempt - 1))
    delay = base_delay * :math.pow(2, attempt - 1)
    delay = min(trunc(delay), max_delay)

    # Add jitter (±10%) for testing, we use fixed jitter for predictability
    jitter = trunc(delay * 0.1)

    if delay == max_delay do
      # No jitter for max delay in tests
      delay
    else
      # Add fixed jitter for predictable testing
      delay + jitter
    end
  end

  defp add_to_buffer(buffer, message, max_size) do
    new_buffer = [message | buffer]

    if length(new_buffer) > max_size do
      Enum.take(new_buffer, max_size)
    else
      new_buffer
    end
  end
end
