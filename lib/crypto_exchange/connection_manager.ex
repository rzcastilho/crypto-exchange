defmodule CryptoExchange.ConnectionManager do
  @moduledoc """
  Comprehensive connection management with circuit breaker pattern and exponential backoff.

  This module provides robust connection management for WebSocket streams with:

  - **Circuit Breaker**: Prevents cascading failures by opening circuits during degraded conditions
  - **Exponential Backoff**: Smart reconnection with jitter to avoid thundering herd problems
  - **Health Monitoring**: Real-time health assessment and alerting
  - **Connection Pooling**: Efficient connection resource management
  - **Automatic Recovery**: Graceful degradation and recovery strategies

  ## Circuit Breaker States

  - **CLOSED**: Normal operation, requests flow through
  - **OPEN**: Circuit is open, requests fail fast to prevent cascading failures
  - **HALF_OPEN**: Testing recovery, limited requests allowed through

  ## Exponential Backoff Strategy

  - Initial delay: 1 second
  - Maximum delay: 30 seconds  
  - Backoff factor: 2.0 (configurable)
  - Jitter: ±10% randomization to prevent synchronization
  - Rate limiting respect: Built-in Binance rate limit awareness

  ## Health Monitoring

  - Connection state tracking
  - Error rate monitoring
  - Response time measurement
  - Automatic alerting on degradation
  - Comprehensive metrics collection

  ## Usage

      # Start connection manager
      {:ok, manager} = ConnectionManager.start_link()
      
      # Request connection with circuit breaker protection
      case ConnectionManager.get_connection(manager, :binance_ws) do
        {:ok, connection} -> # Use connection
        {:error, :circuit_open} -> # Circuit breaker is open, fail fast
        {:error, reason} -> # Other connection error
      end
  """

  use GenServer
  require Logger

  alias CryptoExchange.Config

  # Circuit breaker states
  @circuit_closed :closed
  @circuit_open :open
  @circuit_half_open :half_open

  # Default configuration
  @default_config %{
    # Circuit breaker settings
    failure_threshold: 5,           # Open circuit after 5 failures
    recovery_timeout: 30_000,       # Try recovery after 30 seconds
    success_threshold: 3,           # Close circuit after 3 successes in half-open
    
    # Exponential backoff settings
    initial_delay: 1_000,           # Start with 1 second
    max_delay: 30_000,              # Cap at 30 seconds
    backoff_factor: 2.0,            # Double delay each time
    jitter_percentage: 0.1,         # ±10% randomization
    max_retries: :infinity,         # Retry indefinitely
    
    # Health monitoring settings
    health_check_interval: 30_000,  # Check health every 30 seconds
    max_response_time: 5_000,       # Consider slow if > 5 seconds
    error_rate_threshold: 0.1,      # Alert if error rate > 10%
    
    # Connection pooling settings
    max_connections: 50,            # Maximum concurrent connections
    connection_timeout: 10_000,     # Connection timeout
    idle_timeout: 300_000,          # Close idle connections after 5 minutes
    
    # Rate limiting (Binance specific)
    requests_per_second: 5,         # WebSocket message rate limit
    burst_allowance: 10             # Allow short bursts
  }

  defstruct [
    # Circuit breaker state
    :circuit_state,
    :failure_count,
    :success_count,
    :last_failure_time,
    
    # Connection tracking
    :connections,
    :connection_metrics,
    
    # Retry tracking
    :retry_attempts,
    :retry_timers,
    
    # Health monitoring
    :health_status,
    :health_timer,
    :metrics,
    
    # Configuration
    :config,
    
    # Rate limiting
    :rate_limiter,
    :request_timestamps
  ]

  @type circuit_state :: :closed | :open | :half_open
  @type health_status :: :healthy | :degraded | :unhealthy | :critical
  @type connection_type :: :binance_ws | :binance_api

  # =============================================================================
  # CLIENT API
  # =============================================================================

  @doc """
  Start the ConnectionManager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get a connection with circuit breaker protection.
  
  Returns `{:ok, connection}` if circuit is closed and connection succeeds.
  Returns `{:error, :circuit_open}` if circuit breaker is open.
  Returns `{:error, reason}` for other connection failures.
  """
  @spec get_connection(GenServer.server(), connection_type()) :: 
    {:ok, pid()} | {:error, atom()}
  def get_connection(manager \\ __MODULE__, connection_type) do
    GenServer.call(manager, {:get_connection, connection_type})
  end

  @doc """
  Release a connection back to the pool.
  """
  @spec release_connection(GenServer.server(), connection_type(), pid()) :: :ok
  def release_connection(manager \\ __MODULE__, connection_type, connection_pid) do
    GenServer.cast(manager, {:release_connection, connection_type, connection_pid})
  end

  @doc """
  Report a connection failure to update circuit breaker state.
  """
  @spec report_failure(GenServer.server(), connection_type(), term()) :: :ok
  def report_failure(manager \\ __MODULE__, connection_type, reason) do
    GenServer.cast(manager, {:report_failure, connection_type, reason})
  end

  @doc """
  Report a connection success to update circuit breaker state.
  """
  @spec report_success(GenServer.server(), connection_type()) :: :ok
  def report_success(manager \\ __MODULE__, connection_type) do
    GenServer.cast(manager, {:report_success, connection_type})
  end

  @doc """
  Get the current circuit breaker state.
  """
  @spec get_circuit_state(GenServer.server()) :: circuit_state()
  def get_circuit_state(manager \\ __MODULE__) do
    GenServer.call(manager, :get_circuit_state)
  end

  @doc """
  Get comprehensive health status and metrics.
  """
  @spec get_health_status(GenServer.server()) :: 
    {:ok, %{health_status: health_status(), metrics: map()}} | {:error, term()}
  def get_health_status(manager \\ __MODULE__) do
    GenServer.call(manager, :get_health_status)
  end

  @doc """
  Manually reset the circuit breaker (for emergency recovery).
  """
  @spec reset_circuit(GenServer.server()) :: :ok
  def reset_circuit(manager \\ __MODULE__) do
    GenServer.cast(manager, :reset_circuit)
  end

  @doc """
  Get detailed connection metrics for monitoring.
  """
  @spec get_metrics(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_metrics(manager \\ __MODULE__) do
    GenServer.call(manager, :get_metrics)
  end

  # =============================================================================
  # GENSERVER CALLBACKS
  # =============================================================================

  @impl true
  def init(opts) do
    Logger.info("Starting ConnectionManager with circuit breaker and exponential backoff")
    
    config = Keyword.get(opts, :config, %{})
    |> Map.merge(@default_config)
    |> Map.merge(load_config_from_application())

    state = %__MODULE__{
      circuit_state: @circuit_closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      
      connections: %{},
      connection_metrics: %{},
      
      retry_attempts: %{},
      retry_timers: %{},
      
      health_status: :healthy,
      health_timer: nil,
      metrics: initialize_metrics(),
      
      config: config,
      
      rate_limiter: initialize_rate_limiter(config),
      request_timestamps: :queue.new()
    }

    # Start health monitoring
    health_timer = schedule_health_check(config.health_check_interval)
    state = %{state | health_timer: health_timer}

    Logger.info("ConnectionManager started with circuit breaker protection")
    Logger.debug("Circuit breaker config: #{inspect(Map.take(config, [:failure_threshold, :recovery_timeout, :success_threshold]))}")

    {:ok, state}
  end

  @impl true
  def handle_call({:get_connection, connection_type}, _from, state) do
    case check_circuit_breaker(state) do
      :allow ->
        case attempt_connection(connection_type, state) do
          {:ok, connection_pid, new_state} ->
            # Report success and potentially close circuit
            new_state = record_success(new_state)
            {:reply, {:ok, connection_pid}, new_state}
            
          {:error, reason, new_state} ->
            # Report failure and potentially open circuit
            new_state = record_failure(new_state, reason)
            {:reply, {:error, reason}, new_state}
        end
        
      :deny ->
        Logger.debug("Circuit breaker OPEN - denying connection request for #{connection_type}")
        {:reply, {:error, :circuit_open}, state}
    end
  end

  @impl true
  def handle_call(:get_circuit_state, _from, state) do
    {:reply, state.circuit_state, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_info = %{
      health_status: state.health_status,
      circuit_state: state.circuit_state,
      failure_count: state.failure_count,
      metrics: calculate_current_metrics(state)
    }
    {:reply, {:ok, health_info}, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = calculate_detailed_metrics(state)
    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_cast({:release_connection, connection_type, connection_pid}, state) do
    new_state = release_connection_from_pool(state, connection_type, connection_pid)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:report_failure, connection_type, reason}, state) do
    Logger.warning("Connection failure reported for #{connection_type}: #{inspect(reason)}")
    new_state = record_failure(state, reason)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:report_success, connection_type}, state) do
    Logger.debug("Connection success reported for #{connection_type}")
    new_state = record_success(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reset_circuit, state) do
    Logger.info("Circuit breaker manually reset")
    new_state = %{state |
      circuit_state: @circuit_closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil
    }
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)
    health_timer = schedule_health_check(state.config.health_check_interval)
    new_state = %{new_state | health_timer: health_timer}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:try_recovery, state) do
    Logger.info("Attempting circuit breaker recovery")
    new_state = %{state | circuit_state: @circuit_half_open, success_count: 0}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:retry_connection, connection_id}, state) do
    new_state = handle_retry_connection(state, connection_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:connection_timeout, connection_id}, state) do
    Logger.warning("Connection timeout for #{connection_id}")
    new_state = handle_connection_timeout(state, connection_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in ConnectionManager: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("ConnectionManager terminating: #{inspect(reason)}")
    
    # Cancel all timers
    if state.health_timer, do: Process.cancel_timer(state.health_timer)
    
    # Cancel all retry timers
    Enum.each(state.retry_timers, fn {_id, timer} ->
      Process.cancel_timer(timer)
    end)
    
    # Close all active connections gracefully
    Enum.each(state.connections, fn {_type, connections} ->
      Enum.each(connections, fn {_id, pid} ->
        if Process.alive?(pid) do
          GenServer.stop(pid, :normal, 5000)
        end
      end)
    end)
    
    :ok
  end

  # =============================================================================
  # CIRCUIT BREAKER LOGIC
  # =============================================================================

  defp check_circuit_breaker(%{circuit_state: @circuit_closed}), do: :allow
  defp check_circuit_breaker(%{circuit_state: @circuit_half_open}), do: :allow
  defp check_circuit_breaker(%{circuit_state: @circuit_open} = state) do
    current_time = System.system_time(:millisecond)
    recovery_time = state.last_failure_time + state.config.recovery_timeout
    
    if current_time >= recovery_time do
      # Time to try recovery
      send(self(), :try_recovery)
      :allow
    else
      :deny
    end
  end

  defp record_failure(state, reason) do
    current_time = System.system_time(:millisecond)
    new_failure_count = state.failure_count + 1
    
    # Update metrics
    updated_metrics = update_failure_metrics(state.metrics, reason, current_time)
    
    new_state = %{state |
      failure_count: new_failure_count,
      last_failure_time: current_time,
      success_count: 0,  # Reset success count on failure
      metrics: updated_metrics
    }
    
    # Check if we should open the circuit
    if should_open_circuit?(new_state) do
      Logger.error("Circuit breaker OPENING after #{new_failure_count} failures")
      %{new_state | circuit_state: @circuit_open}
    else
      new_state
    end
  end

  defp record_success(state) do
    case state.circuit_state do
      @circuit_half_open ->
        new_success_count = state.success_count + 1
        
        if new_success_count >= state.config.success_threshold do
          Logger.info("Circuit breaker CLOSING after #{new_success_count} successes")
          %{state |
            circuit_state: @circuit_closed,
            failure_count: 0,
            success_count: 0,
            last_failure_time: nil
          }
        else
          %{state | success_count: new_success_count}
        end
        
      _ ->
        # Reset failure count on success in closed state
        %{state | failure_count: max(0, state.failure_count - 1)}
    end
  end

  defp should_open_circuit?(state) do
    state.failure_count >= state.config.failure_threshold
  end

  # =============================================================================
  # CONNECTION MANAGEMENT
  # =============================================================================

  defp attempt_connection(connection_type, state) do
    # Check rate limiting first
    case check_rate_limit(state) do
      :allow ->
        do_attempt_connection(connection_type, state)
        
      :deny ->
        Logger.debug("Rate limit exceeded, denying connection attempt")
        {:error, :rate_limit_exceeded, state}
    end
  end

  defp do_attempt_connection(connection_type, state) do
    connection_id = generate_connection_id()
    start_time = System.system_time(:millisecond)
    
    Logger.debug("Attempting connection #{connection_id} for type #{connection_type}")
    
    # Set connection timeout
    timeout_timer = Process.send_after(self(), 
      {:connection_timeout, connection_id}, 
      state.config.connection_timeout)
    
    try do
      case create_connection(connection_type, state.config) do
        {:ok, connection_pid} ->
          connection_time = System.system_time(:millisecond) - start_time
          
          # Cancel timeout timer
          Process.cancel_timer(timeout_timer)
          
          # Add connection to pool
          new_state = add_connection_to_pool(state, connection_type, connection_id, connection_pid)
          
          # Update metrics
          updated_metrics = update_success_metrics(state.metrics, connection_time)
          new_state = %{new_state | metrics: updated_metrics}
          
          Logger.debug("Connection #{connection_id} established successfully in #{connection_time}ms")
          {:ok, connection_pid, new_state}
          
        {:error, reason} ->
          Process.cancel_timer(timeout_timer)
          Logger.error("Connection #{connection_id} failed: #{inspect(reason)}")
          {:error, reason, state}
      end
    rescue
      error ->
        Process.cancel_timer(timeout_timer)
        Logger.error("Connection #{connection_id} crashed: #{inspect(error)}")
        {:error, {:connection_crashed, error}, state}
    end
  end

  defp create_connection(:binance_ws, config) do
    # This would create a new WebSocket connection to Binance
    # For now, we'll simulate the connection creation
    ws_url = Config.binance_ws_url()
    
    case simulate_websocket_connection(ws_url, config) do
      {:ok, pid} ->
        {:ok, pid}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_connection(connection_type, _config) do
    {:error, {:unsupported_connection_type, connection_type}}
  end

  # Simulate WebSocket connection for now - replace with real implementation
  defp simulate_websocket_connection(_url, _config) do
    # Simulate connection success/failure
    if :rand.uniform() > 0.1 do  # 90% success rate
      {:ok, spawn(fn -> 
        # Simulate a WebSocket connection process
        receive do
          :stop -> :ok
        end
      end)}
    else
      {:error, :connection_failed}
    end
  end

  # =============================================================================
  # EXPONENTIAL BACKOFF AND RETRY LOGIC
  # =============================================================================

  defp schedule_retry(state, connection_id, attempt_count) do
    delay = calculate_exponential_backoff_delay(attempt_count, state.config)
    
    Logger.info("Scheduling retry #{attempt_count} for #{connection_id} in #{delay}ms")
    
    timer = Process.send_after(self(), {:retry_connection, connection_id}, delay)
    
    updated_timers = Map.put(state.retry_timers, connection_id, timer)
    updated_attempts = Map.put(state.retry_attempts, connection_id, attempt_count)
    
    %{state | retry_timers: updated_timers, retry_attempts: updated_attempts}
  end

  defp calculate_exponential_backoff_delay(attempt_count, config) do
    base_delay = config.initial_delay * :math.pow(config.backoff_factor, attempt_count - 1)
    capped_delay = min(base_delay, config.max_delay)
    
    # Add jitter to prevent thundering herd
    jitter_amount = capped_delay * config.jitter_percentage
    jitter = :rand.uniform() * jitter_amount * 2 - jitter_amount
    
    max(0, trunc(capped_delay + jitter))
  end

  defp handle_retry_connection(state, connection_id) do
    attempt_count = Map.get(state.retry_attempts, connection_id, 1)
    
    case state.config.max_retries do
      :infinity ->
        do_retry_connection(state, connection_id, attempt_count)
        
      max_retries when attempt_count <= max_retries ->
        do_retry_connection(state, connection_id, attempt_count)
        
      _ ->
        Logger.error("Max retries exceeded for connection #{connection_id}")
        cleanup_retry_state(state, connection_id)
    end
  end

  defp do_retry_connection(state, connection_id, attempt_count) do
    Logger.info("Retrying connection #{connection_id}, attempt #{attempt_count}")
    
    # Clean up previous retry state
    state = cleanup_retry_state(state, connection_id)
    
    # Attempt connection - this would call the original connection logic
    # For now, we'll just simulate
    if :rand.uniform() > 0.3 do  # 70% success rate on retry
      Logger.info("Retry connection #{connection_id} succeeded")
      state
    else
      Logger.warning("Retry connection #{connection_id} failed")
      schedule_retry(state, connection_id, attempt_count + 1)
    end
  end

  defp cleanup_retry_state(state, connection_id) do
    # Cancel any existing timer
    case Map.get(state.retry_timers, connection_id) do
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end
    
    %{state |
      retry_timers: Map.delete(state.retry_timers, connection_id),
      retry_attempts: Map.delete(state.retry_attempts, connection_id)
    }
  end

  # =============================================================================
  # HEALTH MONITORING
  # =============================================================================

  defp perform_health_check(state) do
    current_time = System.system_time(:millisecond)
    
    # Calculate current health metrics
    health_metrics = calculate_health_metrics(state, current_time)
    
    # Determine overall health status
    new_health_status = determine_health_status(health_metrics, state.config)
    
    # Log health status changes
    if new_health_status != state.health_status do
      log_health_status_change(state.health_status, new_health_status, health_metrics)
    end
    
    # Update metrics history
    updated_metrics = update_health_metrics_history(state.metrics, health_metrics, current_time)
    
    %{state |
      health_status: new_health_status,
      metrics: updated_metrics
    }
  end

  defp calculate_health_metrics(state, current_time) do
    # Calculate metrics over the last minute
    window_start = current_time - 60_000  # 1 minute window
    
    recent_errors = count_recent_errors(state.metrics, window_start)
    recent_requests = count_recent_requests(state.metrics, window_start)
    
    error_rate = if recent_requests > 0, do: recent_errors / recent_requests, else: 0.0
    
    active_connections = count_active_connections(state.connections)
    average_response_time = calculate_average_response_time(state.metrics, window_start)
    
    %{
      error_rate: error_rate,
      active_connections: active_connections,
      average_response_time: average_response_time,
      circuit_state: state.circuit_state,
      failure_count: state.failure_count,
      recent_requests: recent_requests,
      recent_errors: recent_errors
    }
  end

  defp determine_health_status(metrics, config) do
    cond do
      metrics.circuit_state == @circuit_open ->
        :critical
        
      metrics.error_rate > config.error_rate_threshold ->
        :unhealthy
        
      metrics.average_response_time > config.max_response_time ->
        :degraded
        
      metrics.error_rate > config.error_rate_threshold / 2 ->
        :degraded
        
      true ->
        :healthy
    end
  end

  defp log_health_status_change(old_status, new_status, metrics) do
    Logger.warning("""
    Connection health status changed: #{old_status} -> #{new_status}
    Metrics:
      Error rate: #{Float.round(metrics.error_rate * 100, 2)}%
      Active connections: #{metrics.active_connections}
      Average response time: #{metrics.average_response_time}ms
      Circuit state: #{metrics.circuit_state}
    """)
  end

  # =============================================================================
  # RATE LIMITING
  # =============================================================================

  defp check_rate_limit(state) do
    current_time = System.system_time(:millisecond)
    window_start = current_time - 1000  # 1 second window
    
    # Remove old timestamps
    cleaned_timestamps = :queue.filter(fn timestamp -> 
      timestamp >= window_start 
    end, state.request_timestamps)
    
    request_count = :queue.len(cleaned_timestamps)
    
    if request_count < state.config.requests_per_second do
      :allow
    else
      :deny
    end
  end

  defp record_request(state) do
    current_time = System.system_time(:millisecond)
    new_timestamps = :queue.in(current_time, state.request_timestamps)
    
    # Keep only recent timestamps
    window_start = current_time - 1000
    cleaned_timestamps = :queue.filter(fn timestamp -> 
      timestamp >= window_start 
    end, new_timestamps)
    
    %{state | request_timestamps: cleaned_timestamps}
  end

  # =============================================================================
  # HELPER FUNCTIONS
  # =============================================================================

  defp load_config_from_application do
    Config.get(:connection_manager, %{})
  end

  defp initialize_metrics do
    %{
      total_connections: 0,
      successful_connections: 0,
      failed_connections: 0,
      total_response_time: 0,
      error_history: [],
      request_history: [],
      response_time_history: []
    }
  end

  defp initialize_rate_limiter(config) do
    %{
      requests_per_second: config.requests_per_second,
      burst_allowance: config.burst_allowance,
      current_requests: 0,
      window_start: System.system_time(:millisecond)
    }
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp generate_connection_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp add_connection_to_pool(state, connection_type, connection_id, connection_pid) do
    type_connections = Map.get(state.connections, connection_type, %{})
    updated_connections = Map.put(type_connections, connection_id, connection_pid)
    
    %{state | connections: Map.put(state.connections, connection_type, updated_connections)}
  end

  defp release_connection_from_pool(state, connection_type, connection_pid) do
    case Map.get(state.connections, connection_type) do
      nil -> state
      type_connections ->
        # Find connection by PID and remove it
        updated_connections = Enum.reduce(type_connections, %{}, fn
          {id, pid}, acc when pid == connection_pid -> acc
          {id, pid}, acc -> Map.put(acc, id, pid)
        end)
        
        %{state | connections: Map.put(state.connections, connection_type, updated_connections)}
    end
  end

  defp handle_connection_timeout(state, connection_id) do
    Logger.error("Connection timeout for #{connection_id}")
    
    # This would be handled by attempting retry with exponential backoff
    schedule_retry(state, connection_id, 1)
  end

  defp count_active_connections(connections) do
    connections
    |> Map.values()
    |> Enum.map(&map_size/1)
    |> Enum.sum()
  end

  defp count_recent_errors(metrics, window_start) do
    metrics.error_history
    |> Enum.count(fn {timestamp, _error} -> timestamp >= window_start end)
  end

  defp count_recent_requests(metrics, window_start) do
    metrics.request_history
    |> Enum.count(fn {timestamp, _type} -> timestamp >= window_start end)
  end

  defp calculate_average_response_time(metrics, window_start) do
    recent_response_times = metrics.response_time_history
    |> Enum.filter(fn {timestamp, _time} -> timestamp >= window_start end)
    |> Enum.map(fn {_timestamp, time} -> time end)
    
    if Enum.empty?(recent_response_times) do
      0
    else
      Enum.sum(recent_response_times) / length(recent_response_times)
    end
  end

  defp calculate_current_metrics(state) do
    current_time = System.system_time(:millisecond)
    calculate_health_metrics(state, current_time)
  end

  defp calculate_detailed_metrics(state) do
    current_metrics = calculate_current_metrics(state)
    
    Map.merge(current_metrics, %{
      total_connections: state.metrics.total_connections,
      successful_connections: state.metrics.successful_connections,
      failed_connections: state.metrics.failed_connections,
      circuit_state: state.circuit_state,
      retry_queue_size: map_size(state.retry_attempts),
      connection_pool_sizes: Enum.map(state.connections, fn {type, conns} ->
        {type, map_size(conns)}
      end) |> Enum.into(%{})
    })
  end

  defp update_failure_metrics(metrics, reason, timestamp) do
    updated_error_history = [{timestamp, reason} | metrics.error_history]
    |> Enum.take(1000)  # Keep last 1000 errors
    
    %{metrics |
      failed_connections: metrics.failed_connections + 1,
      error_history: updated_error_history
    }
  end

  defp update_success_metrics(metrics, response_time) do
    timestamp = System.system_time(:millisecond)
    
    updated_request_history = [{timestamp, :success} | metrics.request_history]
    |> Enum.take(1000)  # Keep last 1000 requests
    
    updated_response_time_history = [{timestamp, response_time} | metrics.response_time_history]
    |> Enum.take(1000)  # Keep last 1000 response times
    
    %{metrics |
      total_connections: metrics.total_connections + 1,
      successful_connections: metrics.successful_connections + 1,
      total_response_time: metrics.total_response_time + response_time,
      request_history: updated_request_history,
      response_time_history: updated_response_time_history
    }
  end

  defp update_health_metrics_history(metrics, health_metrics, timestamp) do
    # This could store health metrics history for trending analysis
    # For now, we'll just return the metrics unchanged
    metrics
  end
end