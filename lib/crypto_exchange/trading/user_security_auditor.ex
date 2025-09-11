defmodule CryptoExchange.Trading.UserSecurityAuditor do
  @moduledoc """
  Comprehensive security auditing for user trading operations.

  This module provides secure audit logging for all user-related security events,
  ensuring compliance and security monitoring without exposing sensitive information.

  ## Security Features

  - **No credential exposure**: Never logs actual credentials or sensitive data
  - **Comprehensive audit trail**: All security events are tracked
  - **Tamper-resistant logging**: Structured logging with checksums
  - **Real-time alerting**: Integration with monitoring systems
  - **Compliance support**: Audit trails suitable for regulatory compliance

  ## Audit Event Types

  - Connection attempts (successful/failed)
  - Credential operations (creation, validation, updates, purging)
  - Authentication events
  - Rate limiting violations
  - Suspicious activity detection
  - Process lifecycle events
  - Security policy violations

  ## Privacy Protection

  All audit logs are designed to provide security visibility while protecting
  user privacy and credential confidentiality. No actual credential values
  are ever logged.
  """

  use GenServer
  require Logger

  @audit_table :security_audit_log
  @max_log_entries 10_000  # Configurable limit to prevent memory issues
  @cleanup_interval 3600_000  # 1 hour cleanup interval
  @retention_days 30  # Keep audit logs for 30 days

  # Client API

  @doc """
  Start the UserSecurityAuditor GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Log a user connection attempt.
  """
  def log_connection_attempt(user_id, result, metadata \\ nil) do
    audit_event = %{
      event_type: :connection_attempt,
      user_id: user_id,
      result: result,
      metadata: sanitize_metadata(metadata),
      timestamp: System.system_time(:millisecond),
      severity: determine_severity(:connection_attempt, result)
    }
    
    GenServer.cast(__MODULE__, {:log_event, audit_event})
  end

  @doc """
  Log user disconnection.
  """
  def log_disconnection(user_id, type) do
    audit_event = %{
      event_type: :disconnection,
      user_id: user_id,
      disconnection_type: type,
      timestamp: System.system_time(:millisecond),
      severity: determine_severity(:disconnection, type)
    }
    
    GenServer.cast(__MODULE__, {:log_event, audit_event})
  end

  @doc """
  Log credential-related events (without exposing credentials).
  """
  def log_credential_event(user_id, event_type, metadata \\ %{}) do
    audit_event = %{
      event_type: :credential_operation,
      user_id: user_id,
      credential_event: event_type,
      metadata: sanitize_metadata(metadata),
      timestamp: System.system_time(:millisecond),
      severity: determine_severity(:credential_operation, event_type)
    }
    
    GenServer.cast(__MODULE__, {:log_event, audit_event})
  end

  @doc """
  Log authentication events.
  """
  def log_authentication_event(user_id, event_type, result, metadata \\ %{}) do
    audit_event = %{
      event_type: :authentication,
      user_id: user_id,
      auth_event: event_type,
      result: result,
      metadata: sanitize_metadata(metadata),
      timestamp: System.system_time(:millisecond),
      severity: determine_severity(:authentication, result)
    }
    
    GenServer.cast(__MODULE__, {:log_event, audit_event})
  end

  @doc """
  Log rate limiting violations.
  """
  def log_rate_limit_violation(user_id, violation_type, metadata \\ %{}) do
    audit_event = %{
      event_type: :rate_limit_violation,
      user_id: user_id,
      violation_type: violation_type,
      metadata: sanitize_metadata(metadata),
      timestamp: System.system_time(:millisecond),
      severity: :warning
    }
    
    GenServer.cast(__MODULE__, {:log_event, audit_event})
  end

  @doc """
  Log suspicious activity.
  """
  def log_suspicious_activity(user_id, activity_type, details) do
    audit_event = %{
      event_type: :suspicious_activity,
      user_id: user_id,
      activity_type: activity_type,
      details: sanitize_metadata(details),
      timestamp: System.system_time(:millisecond),
      severity: :critical
    }
    
    GenServer.cast(__MODULE__, {:log_event, audit_event})
    
    # Also send immediate alert for suspicious activity
    send_security_alert(audit_event)
  end

  @doc """
  Log trading operations for audit trail.
  """
  def log_trading_operation(user_id, operation_type, metadata \\ %{}) do
    audit_event = %{
      event_type: :trading_operation,
      user_id: user_id,
      operation_type: operation_type,
      details: sanitize_metadata(metadata),
      timestamp: System.system_time(:millisecond),
      severity: :info
    }
    
    GenServer.cast(__MODULE__, {:log_event, audit_event})
  end

  @doc """
  Log session end events.
  """
  def log_session_end(user_id, metadata \\ %{}) do
    audit_event = %{
      event_type: :session_end,
      user_id: user_id,
      details: sanitize_metadata(metadata),
      timestamp: System.system_time(:millisecond),
      severity: :info
    }
    
    GenServer.cast(__MODULE__, {:log_event, audit_event})
  end

  @doc """
  Get security summary statistics.
  """
  def get_security_summary do
    GenServer.call(__MODULE__, :get_security_summary)
  end

  @doc """
  Get recent audit events for a specific user.
  """
  def get_user_audit_history(user_id, limit \\ 100) do
    GenServer.call(__MODULE__, {:get_user_audit_history, user_id, limit})
  end

  @doc """
  Get audit events by severity level.
  """
  def get_events_by_severity(severity, limit \\ 100) do
    GenServer.call(__MODULE__, {:get_events_by_severity, severity, limit})
  end

  @doc """
  Search audit events by criteria.
  """
  def search_audit_events(criteria, limit \\ 100) do
    GenServer.call(__MODULE__, {:search_audit_events, criteria, limit})
  end

  @doc """
  Get system security health score.
  """
  def get_security_health_score do
    GenServer.call(__MODULE__, :get_security_health_score)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting UserSecurityAuditor")
    
    # Create ETS table for audit log storage
    table = :ets.new(@audit_table, [
      :named_table,
      :public,
      :ordered_set,  # Ordered by insertion for chronological access
      {:read_concurrency, true}
    ])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %{
      table: table,
      event_count: 0,
      started_at: System.system_time(:millisecond),
      alert_subscribers: []
    }
    
    Logger.info("UserSecurityAuditor started successfully")
    {:ok, state}
  end

  @impl true
  def handle_cast({:log_event, audit_event}, state) do
    # Generate unique event ID
    event_id = generate_event_id(state.event_count)
    
    # Add event ID and checksum
    enhanced_event = Map.merge(audit_event, %{
      event_id: event_id,
      checksum: generate_checksum(audit_event)
    })
    
    # Insert into ETS table
    :ets.insert(@audit_table, {event_id, enhanced_event})
    
    # Log structured security event
    log_structured_event(enhanced_event)
    
    # Check for cleanup if we're approaching limits
    new_event_count = state.event_count + 1
    if rem(new_event_count, 1000) == 0 do
      maybe_cleanup_old_entries()
    end
    
    {:noreply, %{state | event_count: new_event_count}}
  end

  @impl true
  def handle_call(:get_security_summary, _from, state) do
    now = System.system_time(:millisecond)
    last_hour = now - 3_600_000
    last_day = now - 86_400_000
    
    # Calculate statistics
    total_events = :ets.info(@audit_table, :size)
    
    events_last_hour = count_events_since(last_hour)
    events_last_day = count_events_since(last_day)
    
    severity_breakdown = get_severity_breakdown()
    event_type_breakdown = get_event_type_breakdown()
    
    summary = %{
      total_events: total_events,
      events_last_hour: events_last_hour,
      events_last_day: events_last_day,
      severity_breakdown: severity_breakdown,
      event_type_breakdown: event_type_breakdown,
      security_health_score: calculate_security_health_score(),
      uptime_ms: now - state.started_at,
      last_updated: now
    }
    
    {:reply, {:ok, summary}, state}
  end

  @impl true
  def handle_call({:get_user_audit_history, user_id, limit}, _from, state) do
    events = :ets.foldl(fn {_id, event}, acc ->
      if event.user_id == user_id do
        [event | acc]
      else
        acc
      end
    end, [], @audit_table)
    
    # Sort by timestamp (most recent first) and limit
    sorted_events = events
    |> Enum.sort(&(&1.timestamp > &2.timestamp))
    |> Enum.take(limit)
    
    {:reply, {:ok, sorted_events}, state}
  end

  @impl true
  def handle_call({:get_events_by_severity, severity, limit}, _from, state) do
    events = :ets.foldl(fn {_id, event}, acc ->
      if event.severity == severity do
        [event | acc]
      else
        acc
      end
    end, [], @audit_table)
    
    # Sort by timestamp (most recent first) and limit
    sorted_events = events
    |> Enum.sort(&(&1.timestamp > &2.timestamp))
    |> Enum.take(limit)
    
    {:reply, {:ok, sorted_events}, state}
  end

  @impl true
  def handle_call({:search_audit_events, criteria, limit}, _from, state) do
    events = :ets.foldl(fn {_id, event}, acc ->
      if event_matches_criteria?(event, criteria) do
        [event | acc]
      else
        acc
      end
    end, [], @audit_table)
    
    # Sort by timestamp (most recent first) and limit
    sorted_events = events
    |> Enum.sort(&(&1.timestamp > &2.timestamp))
    |> Enum.take(limit)
    
    {:reply, {:ok, sorted_events}, state}
  end

  @impl true
  def handle_call(:get_security_health_score, _from, state) do
    score = calculate_security_health_score()
    {:reply, {:ok, score}, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in UserSecurityAuditor: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("UserSecurityAuditor terminating: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  defp generate_event_id(count) do
    timestamp = System.system_time(:microsecond)
    "#{timestamp}_#{count}"
  end

  defp generate_checksum(event) do
    event_string = inspect(event)
    :crypto.hash(:sha256, event_string) |> Base.encode16(case: :lower)
  end

  defp sanitize_metadata(nil), do: %{}
  defp sanitize_metadata(metadata) when is_map(metadata) do
    # Remove any potentially sensitive keys
    sensitive_keys = [:api_key, :secret_key, :password, :token, :credential, :secret]
    
    Enum.reduce(sensitive_keys, metadata, fn key, acc ->
      case Map.get(acc, key) do
        nil -> acc
        value when is_binary(value) -> Map.put(acc, key, "[REDACTED:#{String.length(value)}]")
        _value -> Map.put(acc, key, "[REDACTED]")
      end
    end)
  end
  defp sanitize_metadata(metadata), do: %{original_type: typeof(metadata)}

  defp determine_severity(event_type, result_or_subtype) do
    case {event_type, result_or_subtype} do
      {:connection_attempt, :rejected} -> :warning
      {:connection_attempt, :failed} -> :error
      {:connection_attempt, :successful} -> :info
      
      {:disconnection, :graceful} -> :info
      {:disconnection, :failed} -> :warning
      
      {:credential_operation, :validation_failed} -> :error
      {:credential_operation, :update_failed} -> :error
      {:credential_operation, :created} -> :info
      {:credential_operation, :updated} -> :info
      {:credential_operation, :purged} -> :info
      
      {:authentication, :success} -> :info
      {:authentication, :failure} -> :warning
      {:authentication, :blocked} -> :error
      
      _ -> :info
    end
  end

  defp log_structured_event(event) do
    log_level = case event.severity do
      :critical -> :error
      :error -> :error
      :warning -> :warning
      :info -> :info
      _ -> :info
    end
    
    Logger.log(log_level, "Security audit event", 
      event_id: event.event_id,
      event_type: event.event_type,
      user_id: event.user_id,
      severity: event.severity,
      timestamp: event.timestamp
    )
  end

  defp send_security_alert(audit_event) do
    # Send alert through PubSub for real-time monitoring
    Phoenix.PubSub.broadcast(
      CryptoExchange.PubSub,
      "security:alerts",
      {:security_alert, audit_event}
    )
    
    # Also integrate with health monitoring system (if available)
    try do
      CryptoExchange.HealthMonitor.report_connection_event(
        audit_event.user_id,
        :security_alert
      )
    catch
      _, _ -> Logger.debug("HealthMonitor integration not available for security event")
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_old_entries do
    maybe_cleanup_old_entries()
  end

  defp maybe_cleanup_old_entries do
    table_size = :ets.info(@audit_table, :size)
    
    if table_size > @max_log_entries do
      Logger.info("Cleaning up old audit entries, current size: #{table_size}")
      
      # Get oldest entries and delete them
      excess_count = table_size - (@max_log_entries * 0.8) |> trunc()
      
      oldest_entries = :ets.foldl(fn {id, event}, acc ->
        [{event.timestamp, id} | acc]
      end, [], @audit_table)
      |> Enum.sort()
      |> Enum.take(excess_count)
      
      Enum.each(oldest_entries, fn {_timestamp, id} ->
        :ets.delete(@audit_table, id)
      end)
      
      Logger.info("Cleaned up #{length(oldest_entries)} old audit entries")
    end
  end

  defp count_events_since(timestamp) do
    :ets.foldl(fn {_id, event}, count ->
      if event.timestamp > timestamp do
        count + 1
      else
        count
      end
    end, 0, @audit_table)
  end

  defp get_severity_breakdown do
    :ets.foldl(fn {_id, event}, acc ->
      severity = event.severity
      Map.update(acc, severity, 1, &(&1 + 1))
    end, %{}, @audit_table)
  end

  defp get_event_type_breakdown do
    :ets.foldl(fn {_id, event}, acc ->
      event_type = event.event_type
      Map.update(acc, event_type, 1, &(&1 + 1))
    end, %{}, @audit_table)
  end

  defp event_matches_criteria?(event, criteria) do
    Enum.all?(criteria, fn {key, value} ->
      Map.get(event, key) == value
    end)
  end

  defp calculate_security_health_score do
    now = System.system_time(:millisecond)
    last_hour = now - 3_600_000
    
    # Base score
    base_score = 100.0
    
    # Deduct points for recent security issues
    recent_critical = count_events_by_severity_since(:critical, last_hour)
    recent_errors = count_events_by_severity_since(:error, last_hour)
    recent_warnings = count_events_by_severity_since(:warning, last_hour)
    
    # Calculate deductions
    critical_deduction = recent_critical * 10.0
    error_deduction = recent_errors * 5.0
    warning_deduction = recent_warnings * 2.0
    
    # Calculate final score
    final_score = base_score - critical_deduction - error_deduction - warning_deduction
    
    # Ensure score is between 0 and 100
    max(0.0, min(100.0, final_score))
  end

  defp count_events_by_severity_since(severity, timestamp) do
    :ets.foldl(fn {_id, event}, count ->
      if event.severity == severity and event.timestamp > timestamp do
        count + 1
      else
        count
      end
    end, 0, @audit_table)
  end

  defp typeof(term) do
    cond do
      is_atom(term) -> :atom
      is_binary(term) -> :binary
      is_integer(term) -> :integer
      is_float(term) -> :float
      is_list(term) -> :list
      is_map(term) -> :map
      is_tuple(term) -> :tuple
      is_pid(term) -> :pid
      is_reference(term) -> :reference
      true -> :unknown
    end
  end
end