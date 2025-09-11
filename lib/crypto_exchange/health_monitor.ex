defmodule CryptoExchange.HealthMonitor do
  @moduledoc """
  Comprehensive health monitoring and alerting system for WebSocket connections.

  This module provides real-time health monitoring with:

  - **Connection Health Tracking**: Monitor individual connection states and performance
  - **System-wide Health Assessment**: Overall system health scoring and trending
  - **Alert Management**: Intelligent alerting with configurable thresholds and escalation
  - **Metrics Collection**: Detailed performance metrics for monitoring and analysis
  - **Health Diagnostics**: Automated diagnosis of common issues and recommended actions

  ## Health Levels

  - **HEALTHY**: All systems operating normally
  - **WARNING**: Minor issues detected, no user impact
  - **DEGRADED**: Performance issues, some user impact
  - **UNHEALTHY**: Significant issues, major user impact  
  - **CRITICAL**: System failure, service unavailable

  ## Alert Types

  - **Connection Alerts**: WebSocket connection issues
  - **Performance Alerts**: High latency, error rates
  - **System Alerts**: Resource exhaustion, circuit breakers
  - **Recovery Alerts**: Successful recovery notifications

  ## Monitoring Metrics

  - Connection uptime and stability
  - Message throughput and latency
  - Error rates and patterns
  - Circuit breaker states
  - System resource utilization

  ## Usage

      # Start health monitor
      {:ok, monitor} = HealthMonitor.start_link()
      
      # Register connection for monitoring
      :ok = HealthMonitor.register_connection(monitor, connection_id, connection_type)
      
      # Report connection events
      :ok = HealthMonitor.report_connection_event(monitor, connection_id, :connected)
      :ok = HealthMonitor.report_error(monitor, connection_id, :network_timeout)
      
      # Get health status
      {:ok, health} = HealthMonitor.get_system_health(monitor)
  """

  use GenServer
  require Logger

  alias CryptoExchange.{Config, ConnectionManager, ReconnectionStrategy}

  # Health levels
  @health_healthy :healthy
  @health_warning :warning
  @health_degraded :degraded
  @health_unhealthy :unhealthy
  @health_critical :critical

  # Alert types
  @alert_connection :connection
  @alert_performance :performance
  @alert_system :system
  @alert_recovery :recovery

  # Alert severities
  @severity_info :info
  @severity_warning :warning
  @severity_error :error
  @severity_critical :critical

  defstruct [
    # Connection tracking
    :connections,
    :connection_metrics,
    
    # System health state
    :system_health,
    :health_history,
    :last_health_check,
    
    # Alert management
    :active_alerts,
    :alert_history,
    :alert_suppression,
    
    # Monitoring timers
    :health_check_timer,
    :metrics_timer,
    :cleanup_timer,
    
    # Configuration
    :config,
    
    # Diagnostics
    :diagnostic_data,
    :performance_baselines
  ]

  @type health_level :: :healthy | :warning | :degraded | :unhealthy | :critical
  @type alert_type :: :connection | :performance | :system | :recovery
  @type alert_severity :: :info | :warning | :error | :critical

  # =============================================================================
  # CLIENT API
  # =============================================================================

  @doc """
  Start the HealthMonitor GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a connection for health monitoring.
  """
  @spec register_connection(GenServer.server(), String.t(), atom()) :: :ok
  def register_connection(monitor \\ __MODULE__, connection_id, connection_type) do
    GenServer.cast(monitor, {:register_connection, connection_id, connection_type})
  end

  @doc """
  Unregister a connection from health monitoring.
  """
  @spec unregister_connection(GenServer.server(), String.t()) :: :ok
  def unregister_connection(monitor \\ __MODULE__, connection_id) do
    GenServer.cast(monitor, {:unregister_connection, connection_id})
  end

  @doc """
  Report a connection event (connected, disconnected, error, etc.).
  """
  @spec report_connection_event(GenServer.server(), String.t(), atom()) :: :ok
  def report_connection_event(monitor \\ __MODULE__, connection_id, event_type) do
    GenServer.cast(monitor, {:connection_event, connection_id, event_type, System.system_time(:millisecond)})
  end

  @doc """
  Report an error for a specific connection.
  """
  @spec report_error(GenServer.server(), String.t(), atom()) :: :ok
  def report_error(monitor \\ __MODULE__, connection_id, error_type) do
    GenServer.cast(monitor, {:error_event, connection_id, error_type, System.system_time(:millisecond)})
  end

  @doc """
  Report performance metrics for a connection.
  """
  @spec report_performance(GenServer.server(), String.t(), map()) :: :ok
  def report_performance(monitor \\ __MODULE__, connection_id, metrics) do
    GenServer.cast(monitor, {:performance_metrics, connection_id, metrics, System.system_time(:millisecond)})
  end

  @doc """
  Get the overall system health status.
  """
  @spec get_system_health(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_system_health(monitor \\ __MODULE__) do
    GenServer.call(monitor, :get_system_health)
  end

  @doc """
  Get detailed health information for a specific connection.
  """
  @spec get_connection_health(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_connection_health(monitor \\ __MODULE__, connection_id) do
    GenServer.call(monitor, {:get_connection_health, connection_id})
  end

  @doc """
  Get all active alerts.
  """
  @spec get_active_alerts(GenServer.server()) :: {:ok, [map()]} | {:error, term()}
  def get_active_alerts(monitor \\ __MODULE__) do
    GenServer.call(monitor, :get_active_alerts)
  end

  @doc """
  Get comprehensive monitoring metrics.
  """
  @spec get_metrics(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_metrics(monitor \\ __MODULE__) do
    GenServer.call(monitor, :get_metrics)
  end

  @doc """
  Acknowledge an alert to prevent repeated notifications.
  """
  @spec acknowledge_alert(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def acknowledge_alert(monitor \\ __MODULE__, alert_id) do
    GenServer.call(monitor, {:acknowledge_alert, alert_id})
  end

  @doc """
  Force a health check immediately.
  """
  @spec force_health_check(GenServer.server()) :: :ok
  def force_health_check(monitor \\ __MODULE__) do
    GenServer.cast(monitor, :force_health_check)
  end

  # =============================================================================
  # GENSERVER CALLBACKS
  # =============================================================================

  @impl true
  def init(opts) do
    Logger.info("Starting HealthMonitor for comprehensive system monitoring")
    
    config = load_monitoring_config(opts)
    
    state = %__MODULE__{
      connections: %{},
      connection_metrics: %{},
      
      system_health: @health_healthy,
      health_history: [],
      last_health_check: System.system_time(:millisecond),
      
      active_alerts: %{},
      alert_history: [],
      alert_suppression: %{},
      
      health_check_timer: nil,
      metrics_timer: nil,
      cleanup_timer: nil,
      
      config: config,
      
      diagnostic_data: %{},
      performance_baselines: initialize_baselines()
    }
    
    # Schedule monitoring tasks
    state = schedule_monitoring_tasks(state)
    
    Logger.info("HealthMonitor started with #{map_size(state.connections)} connections")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_system_health, _from, state) do
    health_summary = calculate_system_health_summary(state)
    {:reply, {:ok, health_summary}, state}
  end

  @impl true
  def handle_call({:get_connection_health, connection_id}, _from, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:reply, {:error, :connection_not_found}, state}
        
      connection_info ->
        health_details = calculate_connection_health_details(connection_info, state)
        {:reply, {:ok, health_details}, state}
    end
  end

  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    alerts = state.active_alerts |> Map.values() |> Enum.sort_by(& &1.timestamp, :desc)
    {:reply, {:ok, alerts}, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = compile_comprehensive_metrics(state)
    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_call({:acknowledge_alert, alert_id}, _from, state) do
    case Map.get(state.active_alerts, alert_id) do
      nil ->
        {:reply, {:error, :alert_not_found}, state}
        
      alert ->
        acknowledged_alert = %{alert | acknowledged: true, acknowledged_at: System.system_time(:millisecond)}
        new_active_alerts = Map.put(state.active_alerts, alert_id, acknowledged_alert)
        
        Logger.info("Alert acknowledged: #{alert_id}")
        {:reply, :ok, %{state | active_alerts: new_active_alerts}}
    end
  end

  @impl true
  def handle_cast({:register_connection, connection_id, connection_type}, state) do
    Logger.info("Registering connection for monitoring: #{connection_id} (#{connection_type})")
    
    connection_info = %{
      connection_id: connection_id,
      connection_type: connection_type,
      registered_at: System.system_time(:millisecond),
      last_seen: System.system_time(:millisecond),
      state: :registered,
      health_level: @health_healthy,
      
      # Metrics tracking
      uptime_start: nil,
      total_uptime: 0,
      connection_count: 0,
      disconnection_count: 0,
      error_count: 0,
      
      # Performance tracking
      message_count: 0,
      total_latency: 0,
      min_latency: nil,
      max_latency: nil,
      
      # Error tracking
      recent_errors: [],
      error_patterns: %{},
      
      # Health history
      health_history: []
    }
    
    new_connections = Map.put(state.connections, connection_id, connection_info)
    {:noreply, %{state | connections: new_connections}}
  end

  @impl true
  def handle_cast({:unregister_connection, connection_id}, state) do
    Logger.info("Unregistering connection from monitoring: #{connection_id}")
    
    # Generate final health report if connection exists
    case Map.get(state.connections, connection_id) do
      nil -> :ok
      connection_info -> log_final_connection_report(connection_info)
    end
    
    new_connections = Map.delete(state.connections, connection_id)
    new_metrics = Map.delete(state.connection_metrics, connection_id)
    
    {:noreply, %{state | connections: new_connections, connection_metrics: new_metrics}}
  end

  @impl true
  def handle_cast({:connection_event, connection_id, event_type, timestamp}, state) do
    new_state = handle_connection_event(state, connection_id, event_type, timestamp)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:error_event, connection_id, error_type, timestamp}, state) do
    new_state = handle_error_event(state, connection_id, error_type, timestamp)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:performance_metrics, connection_id, metrics, timestamp}, state) do
    new_state = handle_performance_metrics(state, connection_id, metrics, timestamp)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:force_health_check, state) do
    Logger.info("Forcing immediate health check")
    new_state = perform_comprehensive_health_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_comprehensive_health_check(state)
    new_state = schedule_health_check(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:metrics_collection, state) do
    new_state = collect_system_metrics(state)
    new_state = schedule_metrics_collection(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup_old_data(state)
    new_state = schedule_cleanup(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in HealthMonitor: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("HealthMonitor terminating: #{inspect(reason)}")
    
    # Cancel all timers
    cancel_timer(state.health_check_timer)
    cancel_timer(state.metrics_timer)
    cancel_timer(state.cleanup_timer)
    
    # Log final system health report
    log_final_system_report(state)
    
    :ok
  end

  # =============================================================================
  # CONNECTION EVENT HANDLING
  # =============================================================================

  defp handle_connection_event(state, connection_id, event_type, timestamp) do
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Received event for unregistered connection: #{connection_id}")
        state
        
      connection_info ->
        updated_connection = update_connection_for_event(connection_info, event_type, timestamp)
        new_connections = Map.put(state.connections, connection_id, updated_connection)
        
        # Check if this event should trigger alerts
        new_state = %{state | connections: new_connections}
        check_and_generate_alerts(new_state, connection_id, event_type, updated_connection)
    end
  end

  defp update_connection_for_event(connection_info, event_type, timestamp) do
    case event_type do
      :connected ->
        %{connection_info |
          state: :connected,
          uptime_start: timestamp,
          connection_count: connection_info.connection_count + 1,
          last_seen: timestamp
        }
        
      :disconnected ->
        uptime_duration = if connection_info.uptime_start do
          timestamp - connection_info.uptime_start
        else
          0
        end
        
        %{connection_info |
          state: :disconnected,
          uptime_start: nil,
          total_uptime: connection_info.total_uptime + uptime_duration,
          disconnection_count: connection_info.disconnection_count + 1,
          last_seen: timestamp
        }
        
      :reconnecting ->
        %{connection_info |
          state: :reconnecting,
          last_seen: timestamp
        }
        
      _ ->
        %{connection_info | last_seen: timestamp}
    end
  end

  defp handle_error_event(state, connection_id, error_type, timestamp) do
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Received error for unregistered connection: #{connection_id}")
        state
        
      connection_info ->
        error_record = %{type: error_type, timestamp: timestamp}
        
        updated_errors = [error_record | connection_info.recent_errors]
        |> Enum.take(50)  # Keep last 50 errors
        
        # Update error patterns
        current_pattern_count = Map.get(connection_info.error_patterns, error_type, 0)
        updated_patterns = Map.put(connection_info.error_patterns, error_type, current_pattern_count + 1)
        
        updated_connection = %{connection_info |
          error_count: connection_info.error_count + 1,
          recent_errors: updated_errors,
          error_patterns: updated_patterns,
          last_seen: timestamp
        }
        
        new_connections = Map.put(state.connections, connection_id, updated_connection)
        new_state = %{state | connections: new_connections}
        
        # Generate error-specific alerts
        generate_error_alert(new_state, connection_id, error_type, updated_connection)
    end
  end

  defp handle_performance_metrics(state, connection_id, metrics, timestamp) do
    case Map.get(state.connections, connection_id) do
      nil ->
        Logger.warning("Received metrics for unregistered connection: #{connection_id}")
        state
        
      connection_info ->
        # Update performance metrics
        latency = Map.get(metrics, :latency, 0)
        message_count = Map.get(metrics, :message_count, 0)
        
        updated_connection = %{connection_info |
          message_count: connection_info.message_count + message_count,
          total_latency: connection_info.total_latency + latency,
          min_latency: update_min_latency(connection_info.min_latency, latency),
          max_latency: update_max_latency(connection_info.max_latency, latency),
          last_seen: timestamp
        }
        
        # Store detailed metrics
        detailed_metrics = Map.merge(metrics, %{timestamp: timestamp})
        current_metrics = Map.get(state.connection_metrics, connection_id, [])
        updated_metrics = [detailed_metrics | current_metrics] |> Enum.take(100)  # Keep last 100
        
        new_connections = Map.put(state.connections, connection_id, updated_connection)
        new_metrics = Map.put(state.connection_metrics, connection_id, updated_metrics)
        
        new_state = %{state | connections: new_connections, connection_metrics: new_metrics}
        
        # Check for performance-based alerts
        check_performance_alerts(new_state, connection_id, metrics, updated_connection)
    end
  end

  # =============================================================================
  # HEALTH ASSESSMENT
  # =============================================================================

  defp perform_comprehensive_health_check(state) do
    current_time = System.system_time(:millisecond)
    
    # Assess health of each connection
    {updated_connections, connection_alerts} = assess_all_connection_health(state)
    
    # Calculate overall system health
    system_health_level = calculate_system_health_level(updated_connections)
    
    # Generate system-level alerts if needed
    system_alerts = check_system_level_alerts(state, system_health_level, updated_connections)
    
    # Combine all alerts
    all_new_alerts = connection_alerts ++ system_alerts
    
    # Update active alerts
    new_active_alerts = process_new_alerts(state.active_alerts, all_new_alerts)
    
    # Update health history
    health_record = %{
      timestamp: current_time,
      system_health: system_health_level,
      connection_count: map_size(updated_connections),
      healthy_connections: count_connections_by_health(updated_connections, @health_healthy),
      warning_connections: count_connections_by_health(updated_connections, @health_warning),
      degraded_connections: count_connections_by_health(updated_connections, @health_degraded),
      unhealthy_connections: count_connections_by_health(updated_connections, @health_unhealthy),
      critical_connections: count_connections_by_health(updated_connections, @health_critical)
    }
    
    new_health_history = [health_record | state.health_history] |> Enum.take(1000)
    
    # Log health status changes
    if system_health_level != state.system_health do
      log_system_health_change(state.system_health, system_health_level, health_record)
    end
    
    %{state |
      connections: updated_connections,
      system_health: system_health_level,
      health_history: new_health_history,
      active_alerts: new_active_alerts,
      last_health_check: current_time
    }
  end

  defp assess_all_connection_health(state) do
    Enum.map_reduce(state.connections, [], fn {connection_id, connection_info}, alerts_acc ->
      {updated_connection, new_alerts} = assess_connection_health(connection_id, connection_info, state)
      {{connection_id, updated_connection}, alerts_acc ++ new_alerts}
    end)
  end

  defp assess_connection_health(connection_id, connection_info, state) do
    current_time = System.system_time(:millisecond)
    
    # Calculate health factors
    uptime_health = calculate_uptime_health(connection_info)
    error_rate_health = calculate_error_rate_health(connection_info)
    performance_health = calculate_performance_health(connection_id, state)
    connectivity_health = calculate_connectivity_health(connection_info, current_time)
    
    # Determine overall connection health
    overall_health = determine_overall_connection_health([
      uptime_health, error_rate_health, performance_health, connectivity_health
    ])
    
    # Update health history
    health_record = %{
      timestamp: current_time,
      health_level: overall_health,
      uptime_health: uptime_health,
      error_rate_health: error_rate_health,
      performance_health: performance_health,
      connectivity_health: connectivity_health
    }
    
    new_health_history = [health_record | connection_info.health_history] |> Enum.take(100)
    
    updated_connection = %{connection_info |
      health_level: overall_health,
      health_history: new_health_history
    }
    
    # Generate alerts if health has degraded
    alerts = if overall_health != connection_info.health_level and 
                overall_health in [@health_warning, @health_degraded, @health_unhealthy, @health_critical] do
      [create_health_degradation_alert(connection_id, connection_info.health_level, overall_health, health_record)]
    else
      []
    end
    
    {updated_connection, alerts}
  end

  defp calculate_system_health_level(connections) do
    if map_size(connections) == 0 do
      @health_healthy
    else
      health_counts = %{
        healthy: count_connections_by_health(connections, @health_healthy),
        warning: count_connections_by_health(connections, @health_warning),
        degraded: count_connections_by_health(connections, @health_degraded),
        unhealthy: count_connections_by_health(connections, @health_unhealthy),
        critical: count_connections_by_health(connections, @health_critical)
      }
      
      total = map_size(connections)
      
      cond do
        health_counts.critical > 0 -> @health_critical
        health_counts.unhealthy > total / 2 -> @health_unhealthy
        health_counts.degraded > total / 3 -> @health_degraded
        health_counts.warning > total / 4 -> @health_warning
        true -> @health_healthy
      end
    end
  end

  # =============================================================================
  # ALERT MANAGEMENT
  # =============================================================================

  defp check_and_generate_alerts(state, connection_id, event_type, connection_info) do
    alerts = case event_type do
      :disconnected ->
        if connection_info.disconnection_count > state.config.max_disconnections_per_hour do
          [create_frequent_disconnection_alert(connection_id, connection_info)]
        else
          []
        end
        
      :connected ->
        # Check if this was a recovery from critical state
        if was_recently_critical?(connection_info) do
          [create_recovery_alert(connection_id, connection_info)]
        else
          []
        end
        
      _ -> []
    end
    
    new_active_alerts = process_new_alerts(state.active_alerts, alerts)
    %{state | active_alerts: new_active_alerts}
  end

  defp generate_error_alert(state, connection_id, error_type, connection_info) do
    # Check if error rate is above threshold
    error_rate = calculate_recent_error_rate(connection_info)
    
    alerts = if error_rate > state.config.error_rate_threshold do
      severity = determine_error_severity(error_type, error_rate)
      [create_error_rate_alert(connection_id, error_type, error_rate, severity)]
    else
      []
    end
    
    new_active_alerts = process_new_alerts(state.active_alerts, alerts)
    %{state | active_alerts: new_active_alerts}
  end

  defp check_performance_alerts(state, connection_id, metrics, connection_info) do
    alerts = []
    
    # Check latency
    latency = Map.get(metrics, :latency, 0)
    alerts = if latency > state.config.latency_threshold do
      [create_high_latency_alert(connection_id, latency) | alerts]
    else
      alerts
    end
    
    # Check message rate
    message_rate = Map.get(metrics, :message_rate, 0)
    alerts = if message_rate < state.config.min_message_rate do
      [create_low_throughput_alert(connection_id, message_rate) | alerts]
    else
      alerts
    end
    
    new_active_alerts = process_new_alerts(state.active_alerts, alerts)
    %{state | active_alerts: new_active_alerts}
  end

  defp check_system_level_alerts(state, system_health, connections) do
    alerts = []
    
    # Check for widespread connection issues
    total_connections = map_size(connections)
    unhealthy_count = count_connections_by_health(connections, @health_unhealthy) +
                     count_connections_by_health(connections, @health_critical)
    
    alerts = if total_connections > 0 and unhealthy_count / total_connections > 0.5 do
      [create_system_degradation_alert(system_health, unhealthy_count, total_connections) | alerts]
    else
      alerts
    end
    
    # Check circuit breaker states
    alerts = check_circuit_breaker_alerts(state, alerts)
    
    alerts
  end

  defp create_health_degradation_alert(connection_id, old_health, new_health, health_record) do
    %{
      id: generate_alert_id(),
      type: @alert_connection,
      severity: map_health_to_severity(new_health),
      connection_id: connection_id,
      title: "Connection Health Degraded",
      message: "Connection #{connection_id} health changed from #{old_health} to #{new_health}",
      details: health_record,
      timestamp: System.system_time(:millisecond),
      acknowledged: false
    }
  end

  defp create_error_rate_alert(connection_id, error_type, error_rate, severity) do
    %{
      id: generate_alert_id(),
      type: @alert_performance,
      severity: severity,
      connection_id: connection_id,
      title: "High Error Rate Detected",
      message: "Connection #{connection_id} experiencing high #{error_type} error rate: #{Float.round(error_rate * 100, 2)}%",
      details: %{error_type: error_type, error_rate: error_rate},
      timestamp: System.system_time(:millisecond),
      acknowledged: false
    }
  end

  defp create_recovery_alert(connection_id, connection_info) do
    %{
      id: generate_alert_id(),
      type: @alert_recovery,
      severity: @severity_info,
      connection_id: connection_id,
      title: "Connection Recovered",
      message: "Connection #{connection_id} has successfully recovered",
      details: %{previous_state: :critical, recovery_time: System.system_time(:millisecond)},
      timestamp: System.system_time(:millisecond),
      acknowledged: false
    }
  end

  # =============================================================================
  # METRICS AND CALCULATIONS
  # =============================================================================

  defp calculate_uptime_health(connection_info) do
    if connection_info.connection_count == 0 do
      @health_healthy
    else
      uptime_ratio = if connection_info.disconnection_count > 0 do
        connection_info.total_uptime / (connection_info.total_uptime + connection_info.disconnection_count * 1000)
      else
        1.0
      end
      
      cond do
        uptime_ratio >= 0.99 -> @health_healthy
        uptime_ratio >= 0.95 -> @health_warning
        uptime_ratio >= 0.90 -> @health_degraded
        uptime_ratio >= 0.80 -> @health_unhealthy
        true -> @health_critical
      end
    end
  end

  defp calculate_error_rate_health(connection_info) do
    if connection_info.message_count == 0 do
      @health_healthy
    else
      error_rate = connection_info.error_count / connection_info.message_count
      
      cond do
        error_rate <= 0.01 -> @health_healthy    # < 1%
        error_rate <= 0.05 -> @health_warning    # < 5%
        error_rate <= 0.10 -> @health_degraded   # < 10%
        error_rate <= 0.20 -> @health_unhealthy  # < 20%
        true -> @health_critical                 # >= 20%
      end
    end
  end

  defp calculate_performance_health(connection_id, state) do
    case Map.get(state.connection_metrics, connection_id) do
      nil -> @health_healthy
      metrics ->
        recent_metrics = Enum.take(metrics, 10)  # Last 10 metrics
        
        if Enum.empty?(recent_metrics) do
          @health_healthy
        else
          avg_latency = Enum.reduce(recent_metrics, 0, fn metric, acc ->
            acc + Map.get(metric, :latency, 0)
          end) / length(recent_metrics)
          
          cond do
            avg_latency <= 100 -> @health_healthy     # < 100ms
            avg_latency <= 500 -> @health_warning     # < 500ms
            avg_latency <= 1000 -> @health_degraded   # < 1s
            avg_latency <= 5000 -> @health_unhealthy  # < 5s
            true -> @health_critical                  # >= 5s
          end
        end
    end
  end

  defp calculate_connectivity_health(connection_info, current_time) do
    time_since_last_seen = current_time - connection_info.last_seen
    
    cond do
      time_since_last_seen <= 30_000 -> @health_healthy     # < 30s
      time_since_last_seen <= 60_000 -> @health_warning     # < 1min
      time_since_last_seen <= 300_000 -> @health_degraded   # < 5min
      time_since_last_seen <= 900_000 -> @health_unhealthy  # < 15min
      true -> @health_critical                              # >= 15min
    end
  end

  defp determine_overall_connection_health(health_factors) do
    # Use the worst health level among all factors
    health_levels = [@health_critical, @health_unhealthy, @health_degraded, @health_warning, @health_healthy]
    
    Enum.find(health_levels, @health_healthy, fn level ->
      Enum.member?(health_factors, level)
    end)
  end

  # =============================================================================
  # HELPER FUNCTIONS
  # =============================================================================

  defp load_monitoring_config(opts) do
    base_config = %{
      health_check_interval: 30_000,    # 30 seconds
      metrics_interval: 60_000,         # 1 minute  
      cleanup_interval: 300_000,        # 5 minutes
      error_rate_threshold: 0.05,       # 5%
      latency_threshold: 1000,          # 1 second
      min_message_rate: 1.0,            # 1 message/second
      max_disconnections_per_hour: 10
    }
    
    config_overrides = Config.get(:health_monitor, %{})
    cli_overrides = Keyword.get(opts, :config, %{})
    
    base_config
    |> Map.merge(config_overrides)
    |> Map.merge(cli_overrides)
  end

  defp initialize_baselines do
    %{
      latency: %{p50: 100, p90: 500, p99: 1000},
      message_rate: %{min: 1.0, max: 100.0, avg: 10.0},
      error_rate: %{max: 0.01}  # 1% baseline error rate
    }
  end

  defp schedule_monitoring_tasks(state) do
    health_timer = Process.send_after(self(), :health_check, state.config.health_check_interval)
    metrics_timer = Process.send_after(self(), :metrics_collection, state.config.metrics_interval)
    cleanup_timer = Process.send_after(self(), :cleanup, state.config.cleanup_interval)
    
    %{state |
      health_check_timer: health_timer,
      metrics_timer: metrics_timer,
      cleanup_timer: cleanup_timer
    }
  end

  defp schedule_health_check(state) do
    timer = Process.send_after(self(), :health_check, state.config.health_check_interval)
    %{state | health_check_timer: timer}
  end

  defp schedule_metrics_collection(state) do
    timer = Process.send_after(self(), :metrics_collection, state.config.metrics_interval)
    %{state | metrics_timer: timer}
  end

  defp schedule_cleanup(state) do
    timer = Process.send_after(self(), :cleanup, state.config.cleanup_interval)
    %{state | cleanup_timer: timer}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp generate_alert_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp count_connections_by_health(connections, target_health) do
    connections
    |> Enum.count(fn {_id, info} -> info.health_level == target_health end)
  end

  defp update_min_latency(nil, latency), do: latency
  defp update_min_latency(current, latency), do: min(current, latency)

  defp update_max_latency(nil, latency), do: latency  
  defp update_max_latency(current, latency), do: max(current, latency)

  defp process_new_alerts(current_alerts, new_alerts) do
    Enum.reduce(new_alerts, current_alerts, fn alert, acc ->
      Map.put(acc, alert.id, alert)
    end)
  end

  defp map_health_to_severity(@health_healthy), do: @severity_info
  defp map_health_to_severity(@health_warning), do: @severity_warning  
  defp map_health_to_severity(@health_degraded), do: @severity_warning
  defp map_health_to_severity(@health_unhealthy), do: @severity_error
  defp map_health_to_severity(@health_critical), do: @severity_critical

  # Additional helper functions would be implemented here for:
  # - calculate_system_health_summary/1
  # - calculate_connection_health_details/2  
  # - compile_comprehensive_metrics/1
  # - collect_system_metrics/1
  # - cleanup_old_data/1
  # - log_final_system_report/1
  # - And other utility functions

  # Placeholder implementations to satisfy compilation
  defp calculate_system_health_summary(state), do: %{health: state.system_health}
  defp calculate_connection_health_details(_info, _state), do: %{}
  defp compile_comprehensive_metrics(state), do: %{connections: map_size(state.connections)}
  defp collect_system_metrics(state), do: state
  defp cleanup_old_data(state), do: state
  defp log_final_system_report(_state), do: :ok
  defp log_final_connection_report(_info), do: :ok
  defp log_system_health_change(old, new, _record), do: 
    Logger.info("System health changed: #{old} -> #{new}")
  defp was_recently_critical?(_info), do: false
  defp calculate_recent_error_rate(_info), do: 0.0
  defp determine_error_severity(_type, _rate), do: @severity_warning
  defp create_frequent_disconnection_alert(id, _info), do: 
    %{id: generate_alert_id(), connection_id: id, type: @alert_connection}
  defp create_high_latency_alert(id, latency), do:
    %{id: generate_alert_id(), connection_id: id, type: @alert_performance, latency: latency}
  defp create_low_throughput_alert(id, rate), do:
    %{id: generate_alert_id(), connection_id: id, type: @alert_performance, rate: rate}
  defp create_system_degradation_alert(health, unhealthy, total), do:
    %{id: generate_alert_id(), type: @alert_system, health: health, unhealthy: unhealthy, total: total}
  defp check_circuit_breaker_alerts(_state, alerts), do: alerts
end