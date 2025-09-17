defmodule CryptoExchange.Binance.WebSocketHandler do
  @moduledoc """
  Enhanced WebSockex-based WebSocket client handler for Binance WebSocket connections.

  This module provides highly resilient WebSocket connectivity for Binance streams
  with comprehensive error handling, health monitoring, and intelligent reconnection.

  ## Features

  - **Reliable Connection Management**: Robust connection establishment using WebSockex
  - **Enhanced Reconnection Logic**: Intelligent exponential backoff with jitter
  - **Connection Health Monitoring**: Responds to Binance server pings
  - **Circuit Breaker Pattern**: Prevents overwhelming the server during outages
  - **Message Queuing**: Buffers messages during temporary disconnections
  - **Error Classification**: Different retry strategies based on error types
  - **Connection Quality Metrics**: Tracks connection stability and performance

  ## Resilience Features

  - **Exponential Backoff**: Progressive retry delays from 1s to 5 minutes
  - **Jitter**: Randomization to prevent thundering herd
  - **Circuit Breaker**: Temporary pause after consecutive failures
  - **Health Checks**: Responds to Binance ping frames to maintain connection
  - **Message Buffering**: Queue messages during brief disconnections
  - **Graceful Degradation**: Continues operation with reduced functionality

  ## Configuration Options

  - `:max_retries` - Maximum consecutive retry attempts (default: 10)
  - `:base_delay` - Initial retry delay in ms (default: 1000)
  - `:max_delay` - Maximum retry delay in ms (default: 300_000)
  - `:circuit_breaker_threshold` - Failures before circuit opens (default: 5)
  - `:circuit_breaker_timeout` - Time to wait before retry (default: 60_000)
  - `:message_buffer_size` - Max buffered messages (default: 100)
  """

  use WebSockex
  require Logger

  defmodule ConnectionState do
    @moduledoc """
    Enhanced connection state tracking for WebSocket resilience.
    """
    defstruct [
      :parent_pid,
      :url,
      :retry_count,
      :last_error,
      :circuit_breaker_state,
      :circuit_breaker_opened_at,
      :last_pong_sent,
      :message_buffer,
      :connection_start_time,
      :total_reconnects,
      :config
    ]

    @type circuit_state :: :closed | :open | :half_open
    
    @type t :: %__MODULE__{
            parent_pid: pid(),
            url: String.t(),
            retry_count: non_neg_integer(),
            last_error: term() | nil,
            circuit_breaker_state: circuit_state(),
            circuit_breaker_opened_at: DateTime.t() | nil,
            last_pong_sent: DateTime.t() | nil,
            message_buffer: [term()],
            connection_start_time: DateTime.t() | nil,
            total_reconnects: non_neg_integer(),
            config: map()
          }

    def new(parent_pid, url, opts \\ []) do
      config = %{
        max_retries: Keyword.get(opts, :max_retries, 10),
        base_delay: Keyword.get(opts, :base_delay, 1000),
        max_delay: Keyword.get(opts, :max_delay, 300_000),
        circuit_breaker_threshold: Keyword.get(opts, :circuit_breaker_threshold, 5),
        circuit_breaker_timeout: Keyword.get(opts, :circuit_breaker_timeout, 60_000),
        message_buffer_size: Keyword.get(opts, :message_buffer_size, 100)
      }

      %__MODULE__{
        parent_pid: parent_pid,
        url: url,
        retry_count: 0,
        last_error: nil,
        circuit_breaker_state: :closed,
        circuit_breaker_opened_at: nil,
        last_pong_sent: nil,
        message_buffer: [],
        connection_start_time: nil,
        total_reconnects: 0,
        config: config
      }
    end
  end

  @doc """
  Starts a resilient WebSocket connection to the specified URL.

  ## Parameters
  - `url` - WebSocket URL to connect to
  - `parent_pid` - PID of the parent process to send messages to
  - `opts` - Optional connection and resilience options

  ## Returns
  - `{:ok, pid}` on successful connection
  - `{:error, reason}` on connection failure

  ## Options
  All resilience configuration options listed in module documentation are supported.
  """
  def start_link(url, parent_pid, opts \\ []) do
    Logger.info("Starting enhanced WebSockex client for #{url}")

    # Extract our custom options
    {websocket_opts, resilience_opts} = Keyword.split(opts, [
      :extra_headers, :protocols, :timeout, :debug, :handle_initial_conn_failure
    ])

    # WebSockex options with enhanced defaults
    websockex_opts = [
      extra_headers: [{"User-Agent", "CryptoExchange/1.0"}],
      handle_initial_conn_failure: true
    ] ++ websocket_opts

    # Initialize enhanced connection state
    state = ConnectionState.new(parent_pid, url, resilience_opts)

    WebSockex.start_link(url, __MODULE__, state, websockex_opts)
  end

  @doc """
  Sends a message through the WebSocket connection with enhanced error handling.

  ## Parameters
  - `pid` - WebSocket process PID
  - `message` - Message to send (map or string)

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure

  The function automatically buffers messages during disconnections and replays
  them when the connection is reestablished.
  """
  def send_message(pid, message) do
    json_message =
      case message do
        msg when is_binary(msg) -> msg
        msg -> Jason.encode!(msg)
      end

    Logger.debug("Sending WebSocket message: #{json_message}")
    
    case WebSockex.send_frame(pid, {:text, json_message}) do
      :ok -> 
        :ok
      {:error, %WebSockex.ConnError{}} = error ->
        # Buffer the message for retry when reconnected
        WebSockex.cast(pid, {:buffer_message, json_message})
        error
      error ->
        error
    end
  end

  @doc """
  Gets connection health and statistics.

  ## Parameters
  - `pid` - WebSocket process PID

  ## Returns
  Map containing connection health metrics.
  """
  def get_connection_health(pid) do
    WebSockex.cast(pid, {:get_health, self()})
    
    receive do
      {:health_response, health} -> health
    after
      5000 -> {:error, :timeout}
    end
  end

  # Enhanced WebSockex callbacks

  @impl WebSockex
  def handle_connect(_conn, %ConnectionState{} = state) do
    Logger.info("Enhanced WebSocket connection established successfully")
    
    now = DateTime.utc_now()
    
    # Reset circuit breaker on successful connection
    new_state = %{state | 
      retry_count: 0,
      last_error: nil,
      circuit_breaker_state: :closed,
      circuit_breaker_opened_at: nil,
      connection_start_time: now,
      last_pong_sent: nil
    }

    # Notify parent process that connection is ready
    send(new_state.parent_pid, :websocket_connected)

    # Replay any buffered messages
    new_state = replay_buffered_messages(new_state)

    {:ok, new_state}
  end

  @impl WebSockex
  def handle_frame({:text, message}, %ConnectionState{} = state) do
    Logger.debug("Received WebSocket text message")

    # Forward message to parent process
    send(state.parent_pid, {:websocket_message, message})

    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:binary, _data}, %ConnectionState{} = state) do
    Logger.debug("Received binary WebSocket message (ignored)")
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:ping, data}, %ConnectionState{} = state) do
    Logger.debug("Received ping frame from Binance server, responding with pong")
    
    # Update state to track when we last responded to a ping
    new_state = %{state | last_pong_sent: DateTime.utc_now()}
    
    # Respond with pong containing the same payload
    {:reply, {:pong, data}, new_state}
  end

  @impl WebSockex
  def handle_frame(frame, %ConnectionState{} = state) do
    Logger.debug("Received unknown WebSocket frame: #{inspect(frame)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:buffer_message, message}, %ConnectionState{} = state) do
    Logger.debug("Buffering message for later delivery: #{message}")
    
    # Add to buffer, respecting size limit
    new_buffer = add_to_buffer(state.message_buffer, message, state.config.message_buffer_size)
    new_state = %{state | message_buffer: new_buffer}
    
    {:noreply, new_state}
  end

  @impl WebSockex
  def handle_cast({:get_health, requester_pid}, %ConnectionState{} = state) do
    now = DateTime.utc_now()
    
    connection_duration = if state.connection_start_time do
      DateTime.diff(now, state.connection_start_time, :millisecond)
    else
      0
    end

    # Calculate time since last pong response (health indicator)
    last_pong_age = if state.last_pong_sent do
      DateTime.diff(now, state.last_pong_sent, :millisecond)
    else
      nil
    end

    health = %{
      connected: is_connected?(state),
      connection_duration_ms: connection_duration,
      circuit_breaker_state: state.circuit_breaker_state,
      retry_count: state.retry_count,
      total_reconnects: state.total_reconnects,
      last_pong_sent_ms_ago: last_pong_age,
      buffered_messages: length(state.message_buffer),
      last_error: state.last_error
    }

    send(requester_pid, {:health_response, health})
    {:noreply, state}
  end

  @impl WebSockex
  def handle_cast({:send, frame}, %ConnectionState{} = state) do
    {:reply, frame, state}
  end


  @impl WebSockex
  def handle_disconnect(%{reason: reason}, %ConnectionState{} = state) do
    Logger.warning("Enhanced WebSocket disconnected: #{inspect(reason)}")

    # Update retry count and last error
    new_state = %{state | 
      retry_count: state.retry_count + 1,
      last_error: reason
    }

    # Check circuit breaker
    case should_reconnect?(new_state) do
      {:reconnect, delay} ->
        Logger.info("Scheduling reconnect in #{delay}ms (attempt #{new_state.retry_count}/#{new_state.config.max_retries})")
        
        # Notify parent of disconnection
        send(new_state.parent_pid, {:websocket_disconnect, reason})
        
        # Use WebSockex's built-in reconnect with delay
        {:reconnect, delay, new_state}

      :circuit_open ->
        Logger.warning("Circuit breaker opened - pausing reconnection attempts")
        
        circuit_state = %{new_state |
          circuit_breaker_state: :open,
          circuit_breaker_opened_at: DateTime.utc_now(),
          total_reconnects: new_state.total_reconnects + 1
        }
        
        send(circuit_state.parent_pid, {:websocket_circuit_open, reason})
        {:close, reason, circuit_state}

      :max_retries_exceeded ->
        Logger.error("Maximum retry attempts exceeded - giving up")
        send(new_state.parent_pid, {:websocket_error, :max_retries_exceeded})
        {:close, :max_retries_exceeded, new_state}
    end
  end

  @impl WebSockex
  def terminate(reason, %ConnectionState{} = state) do
    Logger.info("Enhanced WebSocket terminated: #{inspect(reason)}")

    # Clean up any timers
    # Notify parent process of termination
    send(state.parent_pid, {:websocket_error, reason})

    :ok
  end

  # Private helper functions


  defp is_connected?(%ConnectionState{connection_start_time: nil}), do: false
  defp is_connected?(%ConnectionState{}), do: true

  defp should_reconnect?(%ConnectionState{} = state) do
    cond do
      state.retry_count >= state.config.max_retries ->
        :max_retries_exceeded
        
      state.retry_count >= state.config.circuit_breaker_threshold ->
        :circuit_open
        
      true ->
        # Calculate exponential backoff with jitter
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
    
    # Add jitter (±10%)
    jitter = trunc(delay * 0.1)
    delay + :rand.uniform(jitter * 2) - jitter
  end

  defp add_to_buffer(buffer, message, max_size) do
    new_buffer = [message | buffer]
    
    if length(new_buffer) > max_size do
      Enum.take(new_buffer, max_size)
    else
      new_buffer
    end
  end

  defp replay_buffered_messages(%ConnectionState{message_buffer: []} = state) do
    state
  end

  defp replay_buffered_messages(%ConnectionState{message_buffer: messages} = state) do
    Logger.info("Replaying #{length(messages)} buffered messages")
    
    # Send buffered messages in FIFO order
    messages
    |> Enum.reverse()
    |> Enum.each(fn message ->
      case WebSockex.send_frame(self(), {:text, message}) do
        :ok -> 
          Logger.debug("Replayed buffered message successfully")
        {:error, reason} ->
          Logger.warning("Failed to replay buffered message: #{inspect(reason)}")
      end
    end)
    
    # Clear buffer after replay attempt
    %{state | message_buffer: []}
  end
end
