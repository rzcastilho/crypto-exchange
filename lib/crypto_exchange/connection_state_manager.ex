defmodule CryptoExchange.ConnectionStateManager do
  @moduledoc """
  Connection state management with automatic fallback strategies.

  This module manages connection states across the entire system and provides
  automatic fallback strategies during various failure scenarios:

  - **Primary/Secondary Connections**: Automatic failover between connection endpoints
  - **Graceful Degradation**: Reduced functionality during partial failures
  - **Service Discovery**: Dynamic endpoint discovery and health-based routing
  - **Connection Pooling**: Intelligent connection pool management with load balancing
  - **State Synchronization**: Maintaining consistency across connection state transitions

  ## Connection States

  - **HEALTHY**: Connection is active and performing well
  - **DEGRADED**: Connection has issues but is still functional
  - **UNSTABLE**: Connection is experiencing frequent issues
  - **FAILING**: Connection is in the process of failing
  - **FAILED**: Connection has completely failed
  - **RECOVERING**: Connection is in recovery process
  - **FALLBACK**: Using fallback connection or strategy

  ## Fallback Strategies

  - **Endpoint Fallback**: Switch to backup endpoints when primary fails
  - **Protocol Fallback**: Fall back to REST API when WebSocket fails
  - **Rate Limiting Fallback**: Reduce request frequency during rate limiting
  - **Partial Service**: Continue with reduced functionality
  - **Cache Fallback**: Use cached data when live feeds fail

  ## State Transitions

  The state manager orchestrates transitions between states based on:
  - Connection health metrics
  - Error rates and patterns
  - Circuit breaker states
  - External system status

  ## Integration

  Works with:
  - ConnectionManager for connection lifecycle management
  - HealthMonitor for health status assessment
  - ErrorRecoverySupervisor for recovery coordination
  - ReconnectionStrategy for reconnection timing

  ## Usage

      # Start the state manager
      {:ok, manager} = ConnectionStateManager.start_link()
      
      # Register connection for state management
      :ok = ConnectionStateManager.register_connection(connection_id, config)
      
      # Get current state
      {:ok, state} = ConnectionStateManager.get_connection_state(connection_id)
      
      # Trigger fallback
      :ok = ConnectionStateManager.trigger_fallback(connection_id, :endpoint_fallback)
  """

  use GenServer
  require Logger

  alias CryptoExchange.{
    Config,
    ConnectionManager,
    HealthMonitor,
    ErrorRecoverySupervisor
  }

  # Connection states
  @state_healthy :healthy
  @state_degraded :degraded
  @state_unstable :unstable
  @state_failing :failing
  @state_failed :failed
  @state_recovering :recovering
  @state_fallback :fallback

  # Fallback strategies
  @fallback_endpoint :endpoint_fallback
  @fallback_protocol :protocol_fallback
  @fallback_rate_limit :rate_limit_fallback
  @fallback_partial_service :partial_service_fallback
  @fallback_cache :cache_fallback

  defstruct [
    # Connection tracking
    :connections,
    :connection_configs,
    :fallback_endpoints,
    
    # State management
    :state_history,
    :state_transitions,
    :transition_timers,
    
    # Fallback management
    :active_fallbacks,
    :fallback_metrics,
    :fallback_strategies,
    
    # Load balancing
    :endpoint_pools,
    :load_balancer_state,
    :health_scores,
    
    # Configuration
    :config,
    
    # Monitoring
    :metrics,
    :monitoring_timer
  ]

  @type connection_state :: :healthy | :degraded | :unstable | :failing | :failed | :recovering | :fallback
  @type fallback_strategy :: :endpoint_fallback | :protocol_fallback | :rate_limit_fallback | 
                              :partial_service_fallback | :cache_fallback

  # =============================================================================
  # CLIENT API
  # =============================================================================

  @doc """
  Start the ConnectionStateManager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a connection for state management.
  """
  @spec register_connection(GenServer.server(), String.t(), map()) :: :ok
  def register_connection(manager \\ __MODULE__, connection_id, config) do
    GenServer.cast(manager, {:register_connection, connection_id, config})
  end

  @doc """
  Unregister a connection from state management.
  """
  @spec unregister_connection(GenServer.server(), String.t()) :: :ok
  def unregister_connection(manager \\ __MODULE__, connection_id) do
    GenServer.cast(manager, {:unregister_connection, connection_id})
  end

  @doc """
  Get the current state of a connection.
  """
  @spec get_connection_state(GenServer.server(), String.t()) :: 
    {:ok, connection_state()} | {:error, term()}
  def get_connection_state(manager \\ __MODULE__, connection_id) do
    GenServer.call(manager, {:get_connection_state, connection_id})
  end

  @doc """
  Update connection health information.
  """
  @spec update_connection_health(GenServer.server(), String.t(), map()) :: :ok
  def update_connection_health(manager \\ __MODULE__, connection_id, health_info) do
    GenServer.cast(manager, {:update_health, connection_id, health_info})
  end

  @doc """
  Trigger a specific fallback strategy for a connection.
  """
  @spec trigger_fallback(GenServer.server(), String.t(), fallback_strategy()) :: :ok
  def trigger_fallback(manager \\ __MODULE__, connection_id, strategy) do
    GenServer.cast(manager, {:trigger_fallback, connection_id, strategy})
  end

  @doc """
  Get the best available endpoint for a connection type.
  """
  @spec get_best_endpoint(GenServer.server(), atom()) :: {:ok, String.t()} | {:error, term()}
  def get_best_endpoint(manager \\ __MODULE__, connection_type) do
    GenServer.call(manager, {:get_best_endpoint, connection_type})
  end

  @doc """
  Get comprehensive state management metrics.
  """
  @spec get_metrics(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_metrics(manager \\ __MODULE__) do
    GenServer.call(manager, :get_metrics)
  end

  @doc """
  Force state transition for a connection (emergency use).
  """
  @spec force_state_transition(GenServer.server(), String.t(), connection_state()) :: :ok
  def force_state_transition(manager \\ __MODULE__, connection_id, new_state) do
    GenServer.cast(manager, {:force_state_transition, connection_id, new_state})
  end

  # =============================================================================
  # GENSERVER CALLBACKS
  # =============================================================================

  @impl true
  def init(opts) do
    Logger.info("Starting ConnectionStateManager with automatic fallback strategies")
    
    config = load_state_management_config(opts)
    
    state = %__MODULE__{
      connections: %{},
      connection_configs: %{},
      fallback_endpoints: initialize_fallback_endpoints(config),
      
      state_history: %{},
      state_transitions: %{},
      transition_timers: %{},
      
      active_fallbacks: %{},
      fallback_metrics: %{},
      fallback_strategies: initialize_fallback_strategies(config),
      
      endpoint_pools: initialize_endpoint_pools(config),
      load_balancer_state: initialize_load_balancer(),
      health_scores: %{},
      
      config: config,
      
      metrics: initialize_metrics(),
      monitoring_timer: nil
    }
    
    # Start monitoring timer
    monitoring_timer = schedule_monitoring(config.monitoring_interval)
    state = %{state | monitoring_timer: monitoring_timer}
    
    Logger.info("ConnectionStateManager started with fallback strategies enabled")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_connection_state, connection_id}, _from, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:reply, {:error, :connection_not_found}, state}
      connection_info ->
        {:reply, {:ok, connection_info.current_state}, state}
    end
  end

  @impl true
  def handle_call({:get_best_endpoint, connection_type}, _from, state) do
    case select_best_endpoint(state, connection_type) do
      {:ok, endpoint} ->
        {:reply, {:ok, endpoint}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = compile_state_metrics(state)
    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_cast({:register_connection, connection_id, config}, state) do
    Logger.info("Registering connection for state management: #{connection_id}")
    
    connection_info = %{
      connection_id: connection_id,
      connection_type: Map.get(config, :connection_type, :generic),
      current_state: @state_healthy,
      last_state_change: System.system_time(:millisecond),
      health_score: 1.0,
      error_count: 0,
      recovery_attempts: 0,
      fallback_active: false,
      fallback_type: nil,
      endpoints: Map.get(config, :endpoints, []),
      current_endpoint: Map.get(config, :primary_endpoint),
      config: config
    }
    
    new_connections = Map.put(state.connections, connection_id, connection_info)
    new_configs = Map.put(state.connection_configs, connection_id, config)
    
    # Initialize state history
    history_entry = create_state_history_entry(@state_healthy, connection_info)
    new_history = Map.put(state.state_history, connection_id, [history_entry])
    
    {:noreply, %{state |
      connections: new_connections,
      connection_configs: new_configs,
      state_history: new_history
    }}
  end

  @impl true
  def handle_cast({:unregister_connection, connection_id}, state) do
    Logger.info("Unregistering connection from state management: #{connection_id}")
    
    # Cancel any pending transition timers
    case Map.get(state.transition_timers, connection_id) do
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end
    
    new_state = %{state |
      connections: Map.delete(state.connections, connection_id),
      connection_configs: Map.delete(state.connection_configs, connection_id),
      state_history: Map.delete(state.state_history, connection_id),
      state_transitions: Map.delete(state.state_transitions, connection_id),
      transition_timers: Map.delete(state.transition_timers, connection_id),
      active_fallbacks: Map.delete(state.active_fallbacks, connection_id),
      health_scores: Map.delete(state.health_scores, connection_id)
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_health, connection_id, health_info}, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Health update for unregistered connection: #{connection_id}")
        {:noreply, state}
        
      connection_info ->
        new_state = process_health_update(state, connection_id, connection_info, health_info)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:trigger_fallback, connection_id, strategy}, state) do
    Logger.info("Triggering fallback #{strategy} for connection #{connection_id}")
    new_state = activate_fallback_strategy(state, connection_id, strategy)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:force_state_transition, connection_id, new_state}, state) do
    Logger.warning("Forcing state transition for #{connection_id}: #{new_state}")
    updated_state = force_connection_state_transition(state, connection_id, new_state)
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:state_transition, connection_id, target_state}, state) do
    new_state = execute_state_transition(state, connection_id, target_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:monitoring_cycle, state) do
    new_state = perform_monitoring_cycle(state)
    monitoring_timer = schedule_monitoring(state.config.monitoring_interval)
    {:noreply, %{new_state | monitoring_timer: monitoring_timer}}
  end

  @impl true
  def handle_info({:fallback_timeout, connection_id, fallback_type}, state) do
    Logger.info("Fallback timeout for #{connection_id}: #{fallback_type}")
    new_state = handle_fallback_timeout(state, connection_id, fallback_type)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in ConnectionStateManager: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("ConnectionStateManager terminating: #{inspect(reason)}")
    
    # Cancel monitoring timer
    if state.monitoring_timer, do: Process.cancel_timer(state.monitoring_timer)
    
    # Cancel all transition timers
    Enum.each(state.transition_timers, fn {_connection_id, timer} ->
      Process.cancel_timer(timer)
    end)
    
    :ok
  end

  # =============================================================================
  # STATE MANAGEMENT LOGIC
  # =============================================================================

  defp process_health_update(state, connection_id, connection_info, health_info) do
    current_time = System.system_time(:millisecond)
    
    # Update health score
    new_health_score = calculate_health_score(health_info)
    
    # Determine new state based on health information
    new_connection_state = determine_connection_state(health_info, connection_info)
    
    # Check if state transition is needed
    if new_connection_state != connection_info.current_state do
      Logger.info("State transition for #{connection_id}: #{connection_info.current_state} -> #{new_connection_state}")
      transition_connection_state(state, connection_id, connection_info, new_connection_state, current_time)
    else
      # Update health score and metrics without state change
      updated_connection = %{connection_info |
        health_score: new_health_score,
        last_health_update: current_time
      }
      
      new_connections = Map.put(state.connections, connection_id, updated_connection)
      new_health_scores = Map.put(state.health_scores, connection_id, new_health_score)
      
      %{state | 
        connections: new_connections,
        health_scores: new_health_scores
      }
    end
  end

  defp transition_connection_state(state, connection_id, connection_info, new_state, timestamp) do
    # Create history entry
    history_entry = create_state_history_entry(new_state, %{connection_info | current_state: new_state})
    
    # Update connection info
    updated_connection = %{connection_info |
      current_state: new_state,
      last_state_change: timestamp,
      health_score: calculate_health_score_for_state(new_state)
    }
    
    # Update state collections
    new_connections = Map.put(state.connections, connection_id, updated_connection)
    
    current_history = Map.get(state.state_history, connection_id, [])
    new_history = Map.put(state.state_history, connection_id, [history_entry | current_history] |> Enum.take(100))
    
    updated_state = %{state |
      connections: new_connections,
      state_history: new_history
    }
    
    # Trigger appropriate actions based on new state
    handle_state_transition_actions(updated_state, connection_id, connection_info.current_state, new_state)
  end

  defp handle_state_transition_actions(state, connection_id, old_state, new_state) do
    case new_state do
      @state_degraded ->
        # Start monitoring more closely
        Logger.info("Connection #{connection_id} degraded, increasing monitoring")
        state
        
      @state_unstable ->
        # Consider fallback strategies
        Logger.warning("Connection #{connection_id} unstable, evaluating fallbacks")
        evaluate_fallback_strategies(state, connection_id)
        
      @state_failing ->
        # Trigger immediate fallback
        Logger.error("Connection #{connection_id} failing, triggering fallback")
        activate_automatic_fallback(state, connection_id)
        
      @state_failed ->
        # Connection has failed, ensure fallback is active
        Logger.error("Connection #{connection_id} failed completely")
        ensure_fallback_coverage(state, connection_id)
        
      @state_recovering ->
        # Monitor recovery progress
        Logger.info("Connection #{connection_id} recovering")
        monitor_recovery_progress(state, connection_id)
        
      @state_healthy ->
        # Clear any active fallbacks if recovery is complete
        Logger.info("Connection #{connection_id} returned to healthy state")
        clear_fallbacks_if_stable(state, connection_id)
        
      _ ->
        state
    end
  end

  # =============================================================================
  # FALLBACK STRATEGY IMPLEMENTATION
  # =============================================================================

  defp activate_fallback_strategy(state, connection_id, strategy) do
    current_time = System.system_time(:millisecond)
    
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Cannot activate fallback for unregistered connection: #{connection_id}")
        state
        
      connection_info ->
        fallback_config = Map.get(state.fallback_strategies, strategy, %{})
        
        case execute_fallback_strategy(connection_info, strategy, fallback_config) do
          {:ok, fallback_details} ->
            # Record active fallback
            fallback_record = %{
              strategy: strategy,
              activated_at: current_time,
              connection_id: connection_id,
              details: fallback_details,
              timeout_timer: schedule_fallback_timeout(connection_id, strategy, fallback_config)
            }
            
            new_active_fallbacks = Map.put(state.active_fallbacks, {connection_id, strategy}, fallback_record)
            
            # Update connection state
            updated_connection = %{connection_info |
              current_state: @state_fallback,
              fallback_active: true,
              fallback_type: strategy,
              last_state_change: current_time
            }
            
            new_connections = Map.put(state.connections, connection_id, updated_connection)
            
            Logger.info("Activated fallback #{strategy} for #{connection_id}")
            
            %{state |
              active_fallbacks: new_active_fallbacks,
              connections: new_connections
            }
            
          {:error, reason} ->
            Logger.error("Failed to activate fallback #{strategy} for #{connection_id}: #{reason}")
            state
        end
    end
  end

  defp execute_fallback_strategy(connection_info, @fallback_endpoint, _config) do
    # Switch to backup endpoint
    case get_backup_endpoint(connection_info) do
      {:ok, backup_endpoint} ->
        Logger.info("Switching to backup endpoint: #{backup_endpoint}")
        {:ok, %{backup_endpoint: backup_endpoint, original_endpoint: connection_info.current_endpoint}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_fallback_strategy(_connection_info, @fallback_protocol, _config) do
    # Switch from WebSocket to REST API
    Logger.info("Falling back to REST API from WebSocket")
    {:ok, %{protocol_change: :websocket_to_rest}}
  end

  defp execute_fallback_strategy(_connection_info, @fallback_rate_limit, config) do
    # Reduce request rate
    reduced_rate = Map.get(config, :reduced_rate, 0.5)
    Logger.info("Reducing request rate to #{reduced_rate * 100}%")
    {:ok, %{rate_reduction: reduced_rate}}
  end

  defp execute_fallback_strategy(_connection_info, @fallback_partial_service, _config) do
    # Enable partial service mode
    Logger.info("Enabling partial service mode")
    {:ok, %{service_mode: :partial}}
  end

  defp execute_fallback_strategy(_connection_info, @fallback_cache, _config) do
    # Use cached data
    Logger.info("Falling back to cached data")
    {:ok, %{data_source: :cache}}
  end

  # =============================================================================
  # ENDPOINT MANAGEMENT
  # =============================================================================

  defp select_best_endpoint(state, connection_type) do
    case Map.get(state.endpoint_pools, connection_type) do
      nil ->
        {:error, :no_endpoints_configured}
        
      endpoints ->
        # Select endpoint based on health scores and load balancing
        healthy_endpoints = filter_healthy_endpoints(endpoints, state.health_scores)
        
        if Enum.empty?(healthy_endpoints) do
          # All endpoints unhealthy, return least unhealthy
          case select_least_unhealthy_endpoint(endpoints, state.health_scores) do
            nil -> {:error, :all_endpoints_failed}
            endpoint -> {:ok, endpoint}
          end
        else
          # Use load balancing to select from healthy endpoints
          selected = apply_load_balancing(healthy_endpoints, state.load_balancer_state)
          {:ok, selected}
        end
    end
  end

  defp filter_healthy_endpoints(endpoints, health_scores) do
    Enum.filter(endpoints, fn endpoint ->
      health_score = Map.get(health_scores, endpoint, 0.5)
      health_score >= 0.7  # Consider healthy if score >= 0.7
    end)
  end

  defp select_least_unhealthy_endpoint(endpoints, health_scores) do
    endpoints
    |> Enum.map(fn endpoint ->
      score = Map.get(health_scores, endpoint, 0.0)
      {endpoint, score}
    end)
    |> Enum.max_by(fn {_endpoint, score} -> score end, fn -> nil end)
    |> case do
      nil -> nil
      {endpoint, _score} -> endpoint
    end
  end

  defp apply_load_balancing(endpoints, _load_balancer_state) do
    # Simple round-robin for now
    # In production, this would implement more sophisticated load balancing
    Enum.random(endpoints)
  end

  # =============================================================================
  # HELPER FUNCTIONS
  # =============================================================================

  defp load_state_management_config(opts) do
    base_config = %{
      monitoring_interval: 30_000,  # 30 seconds
      state_transition_delay: 5_000,  # 5 seconds
      fallback_timeout: 300_000,  # 5 minutes
      health_score_threshold: 0.7,
      endpoints: %{
        binance_ws: [
          "wss://stream.binance.com:9443/ws",
          "wss://stream1.binance.com:9443/ws",
          "wss://stream2.binance.com:9443/ws"
        ],
        binance_api: [
          "https://api.binance.com",
          "https://api1.binance.com", 
          "https://api2.binance.com"
        ]
      }
    }
    
    config_overrides = Config.get(:connection_state_manager, %{})
    cli_overrides = Keyword.get(opts, :config, %{})
    
    base_config
    |> Map.merge(config_overrides)
    |> Map.merge(cli_overrides)
  end

  defp initialize_fallback_endpoints(config) do
    Map.get(config, :endpoints, %{})
  end

  defp initialize_fallback_strategies(_config) do
    %{
      @fallback_endpoint => %{timeout: 300_000},
      @fallback_protocol => %{timeout: 600_000},
      @fallback_rate_limit => %{timeout: 180_000, reduced_rate: 0.5},
      @fallback_partial_service => %{timeout: 900_000},
      @fallback_cache => %{timeout: 120_000}
    }
  end

  defp initialize_endpoint_pools(config) do
    Map.get(config, :endpoints, %{})
  end

  defp initialize_load_balancer do
    %{
      strategy: :round_robin,
      current_index: 0,
      request_counts: %{}
    }
  end

  defp initialize_metrics do
    %{
      total_connections: 0,
      state_transitions: 0,
      fallback_activations: 0,
      successful_recoveries: 0,
      failed_recoveries: 0
    }
  end

  defp schedule_monitoring(interval) do
    Process.send_after(self(), :monitoring_cycle, interval)
  end

  defp schedule_fallback_timeout(connection_id, strategy, config) do
    timeout = Map.get(config, :timeout, 300_000)
    Process.send_after(self(), {:fallback_timeout, connection_id, strategy}, timeout)
  end

  defp create_state_history_entry(state, connection_info) do
    %{
      state: state,
      timestamp: System.system_time(:millisecond),
      health_score: connection_info.health_score,
      error_count: connection_info.error_count
    }
  end

  defp calculate_health_score(health_info) do
    # Simple health score calculation - could be more sophisticated
    error_rate = Map.get(health_info, :error_rate, 0.0)
    latency = Map.get(health_info, :avg_latency, 0)
    uptime = Map.get(health_info, :uptime_ratio, 1.0)
    
    base_score = 1.0
    error_penalty = error_rate * 0.5
    latency_penalty = min(latency / 1000, 0.3)  # Cap at 0.3 for high latency
    uptime_bonus = (uptime - 0.95) * 2  # Bonus for high uptime
    
    score = base_score - error_penalty - latency_penalty + uptime_bonus
    max(0.0, min(1.0, score))
  end

  defp calculate_health_score_for_state(@state_healthy), do: 1.0
  defp calculate_health_score_for_state(@state_degraded), do: 0.7
  defp calculate_health_score_for_state(@state_unstable), do: 0.5
  defp calculate_health_score_for_state(@state_failing), do: 0.3
  defp calculate_health_score_for_state(@state_failed), do: 0.0
  defp calculate_health_score_for_state(@state_recovering), do: 0.6
  defp calculate_health_score_for_state(@state_fallback), do: 0.4

  defp determine_connection_state(health_info, connection_info) do
    health_score = calculate_health_score(health_info)
    error_rate = Map.get(health_info, :error_rate, 0.0)
    
    cond do
      health_score >= 0.9 and error_rate <= 0.01 -> @state_healthy
      health_score >= 0.7 and error_rate <= 0.05 -> @state_degraded
      health_score >= 0.5 and error_rate <= 0.10 -> @state_unstable
      health_score >= 0.3 -> @state_failing
      connection_info.recovery_attempts > 0 -> @state_recovering
      true -> @state_failed
    end
  end

  # Placeholder implementations for state transition actions
  defp evaluate_fallback_strategies(state, _connection_id), do: state
  defp activate_automatic_fallback(state, _connection_id), do: state
  defp ensure_fallback_coverage(state, _connection_id), do: state
  defp monitor_recovery_progress(state, _connection_id), do: state
  defp clear_fallbacks_if_stable(state, _connection_id), do: state
  defp get_backup_endpoint(_connection_info), do: {:error, :no_backup_available}
  defp handle_fallback_timeout(state, _connection_id, _fallback_type), do: state
  defp perform_monitoring_cycle(state), do: state
  defp execute_state_transition(state, _connection_id, _target_state), do: state
  defp force_connection_state_transition(state, _connection_id, _new_state), do: state
  defp compile_state_metrics(state), do: state.metrics
end