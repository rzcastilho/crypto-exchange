defmodule CryptoExchange.Trading.UserHealthMonitor do
  @moduledoc """
  User-specific health monitoring for individual trading sessions.

  This GenServer monitors the health and performance of a specific user's
  trading session, providing real-time health assessment and alerting.

  ## Features

  - **Process monitoring**: Tracks health of user's processes
  - **Performance tracking**: Monitors response times and throughput
  - **Resource monitoring**: Tracks memory and CPU usage
  - **Alert generation**: Sends alerts for health issues
  - **Health scoring**: Provides numeric health assessment

  ## Integration

  - Reports to system-wide HealthMonitor
  - Integrates with UserMetrics for performance data
  - Participates in UserSecurityAuditor for health-related events
  - Provides data for UserRegistry statistics
  """

  use GenServer
  require Logger

  alias CryptoExchange.{HealthMonitor, Trading.UserMetrics, Trading.UserSecurityAuditor}

  @health_check_interval 30_000  # 30 seconds
  @performance_window 300_000    # 5 minutes for performance metrics
  @memory_threshold 50 * 1024 * 1024  # 50MB memory warning threshold
  @response_time_threshold 5_000       # 5 second response time warning

  # Client API

  @doc """
  Start the UserHealthMonitor for a specific user.
  """
  def start_link({:user_id, user_id, :timeout, timeout}) do
    GenServer.start_link(__MODULE__, {user_id, timeout}, name: via_tuple(user_id))
  end

  @doc """
  Get current health status for the user.
  """
  def get_health_status(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :get_health_status)
  end

  @doc """
  Force a health check for the user.
  """
  def force_health_check(user_id) when is_binary(user_id) do
    GenServer.cast(via_tuple(user_id), :force_health_check)
  end

  @doc """
  Update activity timestamp for the user.
  """
  def record_activity(user_id) when is_binary(user_id) do
    GenServer.cast(via_tuple(user_id), :record_activity)
  end

  @doc """
  Record a performance metric for the user.
  """
  def record_performance_metric(user_id, operation, duration_ms) when is_binary(user_id) do
    GenServer.cast(via_tuple(user_id), {:record_performance, operation, duration_ms})
  end

  # Server Callbacks

  @impl true
  def init({user_id, timeout}) do
    Logger.info("Starting UserHealthMonitor for user: #{user_id}", user_id: user_id)
    
    # Schedule first health check
    schedule_health_check()
    
    state = %{
      user_id: user_id,
      timeout: timeout,
      started_at: System.system_time(:millisecond),
      last_activity: System.system_time(:millisecond),
      last_health_check: nil,
      health_status: :healthy,
      health_score: 100.0,
      performance_metrics: [],
      alerts: [],
      process_monitors: setup_process_monitors(user_id)
    }
    
    # Register with system health monitor (if available)
    try do
      HealthMonitor.register_connection({:user_health_monitor, user_id}, self())
    catch
      _, _ -> Logger.debug("HealthMonitor integration not available for user: #{user_id}")
    end
    
    Logger.info("UserHealthMonitor initialized for user: #{user_id}", user_id: user_id)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_info = %{
      user_id: state.user_id,
      health_status: state.health_status,
      health_score: state.health_score,
      last_activity: state.last_activity,
      last_health_check: state.last_health_check,
      uptime_ms: System.system_time(:millisecond) - state.started_at,
      active_alerts: state.alerts,
      process_status: get_process_status(state.process_monitors)
    }
    
    {:reply, health_info, state}
  end

  @impl true
  def handle_cast(:force_health_check, state) do
    new_state = perform_health_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:record_activity, state) do
    now = System.system_time(:millisecond)
    new_state = %{state | last_activity: now}
    
    # Update metrics
    UserMetrics.record_api_request(state.user_id, "activity", 0, :ok)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_performance, operation, duration_ms}, state) do
    now = System.system_time(:millisecond)
    
    performance_metric = %{
      operation: operation,
      duration_ms: duration_ms,
      timestamp: now
    }
    
    # Keep only recent performance metrics
    cutoff = now - @performance_window
    recent_metrics = Enum.filter([performance_metric | state.performance_metrics], fn metric ->
      metric.timestamp > cutoff
    end)
    
    new_state = %{state | 
      performance_metrics: recent_metrics,
      last_activity: now
    }
    
    # Record in system metrics
    UserMetrics.record_api_request(
      state.user_id, 
      Atom.to_string(operation), 
      duration_ms, 
      if(duration_ms < @response_time_threshold, do: :ok, else: :slow)
    )
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)
    schedule_health_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.warning("User process died", user_id: state.user_id, reason: inspect(reason))
    
    # Record process failure
    UserSecurityAuditor.log_suspicious_activity(
      state.user_id, 
      :process_death, 
      %{reason: reason}
    )
    
    # Update health status
    new_state = %{state | 
      health_status: :degraded,
      health_score: max(state.health_score - 20.0, 0.0)
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in UserHealthMonitor: #{inspect(msg)}", user_id: state.user_id)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("UserHealthMonitor terminating for user: #{state.user_id}", 
      user_id: state.user_id, reason: inspect(reason))
    
    # Unregister from system health monitor (if available)
    try do
      HealthMonitor.unregister_connection({:user_health_monitor, state.user_id})
    catch
      _, _ -> Logger.debug("HealthMonitor integration not available for user: #{state.user_id}")
    end
    
    :ok
  end

  # Private Functions

  defp via_tuple(user_id) do
    {:via, Registry, {CryptoExchange.Registry, {:user_health_monitor, user_id}}}
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp setup_process_monitors(user_id) do
    monitors = %{}
    
    # Monitor user connection process
    case Registry.lookup(CryptoExchange.Registry, {:user_connection, user_id}) do
      [{pid, _}] when is_pid(pid) ->
        ref = Process.monitor(pid)
        Map.put(monitors, :user_connection, {pid, ref})
      _ ->
        monitors
    end
  end

  defp perform_health_check(state) do
    now = System.system_time(:millisecond)
    
    # Check various health indicators
    activity_health = check_activity_health(state, now)
    performance_health = check_performance_health(state)
    resource_health = check_resource_health(state)
    process_health = check_process_health(state)
    
    # Calculate overall health score
    health_score = calculate_health_score([
      activity_health,
      performance_health,
      resource_health,
      process_health
    ])
    
    # Determine health status
    health_status = determine_health_status(health_score)
    
    # Generate alerts if needed
    new_alerts = generate_health_alerts(state, health_score, health_status)
    
    # Update state
    new_state = %{state |
      last_health_check: now,
      health_score: health_score,
      health_status: health_status,
      alerts: new_alerts
    }
    
    # Report to system health monitor (if available)
    try do
      HealthMonitor.report_connection_event(state.user_id, :health_check_completed)
    catch
      _, _ -> Logger.debug("HealthMonitor integration not available for user: #{state.user_id}")
    end
    
    # Record metrics
    UserMetrics.record_resource_usage(
      state.user_id,
      get_process_memory_usage(),
      count_user_processes(state.user_id),
      1
    )
    
    new_state
  end

  defp check_activity_health(state, now) do
    activity_age = now - state.last_activity
    
    cond do
      activity_age < 60_000 -> 100.0      # Active within 1 minute
      activity_age < 300_000 -> 80.0      # Active within 5 minutes  
      activity_age < 900_000 -> 60.0      # Active within 15 minutes
      activity_age < state.timeout -> 40.0 # Within timeout period
      true -> 0.0                         # Inactive beyond timeout
    end
  end

  defp check_performance_health(state) do
    if length(state.performance_metrics) == 0 do
      100.0  # No performance issues if no recent activity
    else
      # Calculate average response time
      avg_response_time = state.performance_metrics
      |> Enum.map(& &1.duration_ms)
      |> Enum.sum()
      |> div(length(state.performance_metrics))
      
      # Calculate slow request percentage
      slow_requests = Enum.count(state.performance_metrics, fn metric ->
        metric.duration_ms > @response_time_threshold
      end)
      
      slow_percentage = slow_requests / length(state.performance_metrics)
      
      # Score based on performance
      cond do
        avg_response_time < 1000 and slow_percentage < 0.1 -> 100.0
        avg_response_time < 2000 and slow_percentage < 0.2 -> 80.0
        avg_response_time < 5000 and slow_percentage < 0.5 -> 60.0
        true -> 30.0
      end
    end
  end

  defp check_resource_health(_state) do
    memory_usage = get_process_memory_usage()
    
    cond do
      memory_usage < @memory_threshold * 0.5 -> 100.0
      memory_usage < @memory_threshold -> 80.0
      memory_usage < @memory_threshold * 2 -> 60.0
      true -> 30.0
    end
  end

  defp check_process_health(state) do
    process_status = get_process_status(state.process_monitors)
    
    alive_count = Enum.count(process_status, fn {_name, status} -> status == :alive end)
    total_count = map_size(process_status)
    
    if total_count == 0 do
      50.0  # No processes to monitor
    else
      (alive_count / total_count) * 100.0
    end
  end

  defp calculate_health_score(scores) do
    if length(scores) == 0 do
      0.0
    else
      Enum.sum(scores) / length(scores)
    end
  end

  defp determine_health_status(score) do
    cond do
      score >= 80.0 -> :healthy
      score >= 60.0 -> :degraded
      score >= 30.0 -> :unhealthy
      true -> :critical
    end
  end

  defp generate_health_alerts(state, health_score, health_status) do
    alerts = []
    
    # Generate alert if health score drops significantly
    alerts = if health_score < 50.0 and state.health_score >= 50.0 do
      alert = %{
        type: :health_degradation,
        severity: :warning,
        message: "User health score dropped to #{health_score}",
        timestamp: System.system_time(:millisecond)
      }
      [alert | alerts]
    else
      alerts
    end
    
    # Generate alert if user becomes inactive
    now = System.system_time(:millisecond)
    inactive_time = now - state.last_activity
    
    alerts = if inactive_time > state.timeout and length(state.alerts) == 0 do
      alert = %{
        type: :user_inactive,
        severity: :info,
        message: "User inactive for #{inactive_time}ms",
        timestamp: now
      }
      [alert | alerts]
    else
      alerts
    end
    
    # Keep only recent alerts (last hour)
    cutoff = now - 3_600_000
    Enum.filter([alerts | state.alerts], fn alert ->
      alert.timestamp > cutoff
    end) |> List.flatten()
  end

  defp get_process_status(monitors) do
    Enum.reduce(monitors, %{}, fn {name, {pid, _ref}}, acc ->
      status = if Process.alive?(pid), do: :alive, else: :dead
      Map.put(acc, name, status)
    end)
  end

  defp get_process_memory_usage do
    case Process.info(self(), :memory) do
      {:memory, bytes} -> bytes
      nil -> 0
    end
  end

  defp count_user_processes(user_id) do
    # Count processes related to this user
    base_count = 3  # UserSupervisor + UserConnection + CredentialManager
    
    # Add any additional processes discovered in registry
    additional = CryptoExchange.Registry
    |> Registry.select([
      {{{:_, user_id}, :_, :_}, [], [true]}
    ])
    |> length()
    
    base_count + additional
  end
end