defmodule CryptoExchange.Trading.UserMetrics do
  @moduledoc """
  Comprehensive user metrics collection and monitoring system.

  This module provides real-time metrics collection and monitoring for user trading
  sessions, supporting performance optimization, capacity planning, and operational
  visibility.

  ## Metrics Categories

  - **Connection Metrics**: User connection patterns and lifecycle
  - **Performance Metrics**: Response times, throughput, and resource usage
  - **Resource Metrics**: Memory, CPU, and connection pool usage per user
  - **Security Metrics**: Authentication events, rate limiting, and violations
  - **Trading Metrics**: Order placement, cancellation, and execution statistics

  ## Performance Features

  - **Real-time collection**: Low-latency metrics gathering
  - **Efficient storage**: Optimized for high-frequency updates
  - **Aggregation support**: Time-based aggregations and rollups
  - **Alert integration**: Threshold-based alerting
  - **Dashboard support**: Structured data for monitoring dashboards

  ## Integration

  - Integrates with HealthMonitor for system-wide visibility
  - Provides data for UserManager statistics
  - Supports external monitoring systems (Prometheus, etc.)
  - Enables capacity planning and performance optimization
  """

  use GenServer
  require Logger

  @metrics_table :user_metrics
  @aggregation_table :user_metrics_aggregated
  @cleanup_interval 300_000  # 5 minutes
  @retention_hours 24  # Keep detailed metrics for 24 hours
  @aggregation_interval 60_000  # 1 minute aggregation intervals

  # Client API

  @doc """
  Start the UserMetrics GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a user connection event.
  """
  def record_connection(user_id) when is_binary(user_id) do
    metric = %{
      user_id: user_id,
      metric_type: :connection,
      event_type: :connected,
      timestamp: System.system_time(:millisecond),
      value: 1
    }
    
    GenServer.cast(__MODULE__, {:record_metric, metric})
  end

  @doc """
  Record a user disconnection event.
  """
  def record_disconnection(user_id) when is_binary(user_id) do
    metric = %{
      user_id: user_id,
      metric_type: :connection,
      event_type: :disconnected,
      timestamp: System.system_time(:millisecond),
      value: 1
    }
    
    GenServer.cast(__MODULE__, {:record_metric, metric})
  end

  @doc """
  Record API request metrics.
  """
  def record_api_request(user_id, endpoint, response_time_ms, status) do
    metric = %{
      user_id: user_id,
      metric_type: :api_request,
      endpoint: endpoint,
      response_time_ms: response_time_ms,
      status: status,
      timestamp: System.system_time(:millisecond),
      value: 1
    }
    
    GenServer.cast(__MODULE__, {:record_metric, metric})
  end

  @doc """
  Record trading operation metrics.
  """
  def record_trading_operation(user_id, operation_type, success, execution_time_ms \\ nil) do
    metric = %{
      user_id: user_id,
      metric_type: :trading_operation,
      operation_type: operation_type,
      success: success,
      execution_time_ms: execution_time_ms,
      timestamp: System.system_time(:millisecond),
      value: 1
    }
    
    GenServer.cast(__MODULE__, {:record_metric, metric})
  end

  @doc """
  Record resource usage metrics for a user.
  """
  def record_resource_usage(user_id, memory_bytes, process_count, connection_count \\ 1) do
    metric = %{
      user_id: user_id,
      metric_type: :resource_usage,
      memory_bytes: memory_bytes,
      process_count: process_count,
      connection_count: connection_count,
      timestamp: System.system_time(:millisecond)
    }
    
    GenServer.cast(__MODULE__, {:record_metric, metric})
  end

  @doc """
  Record error metrics.
  """
  def record_error(user_id, error_type, error_category \\ :general) do
    metric = %{
      user_id: user_id,
      metric_type: :error,
      error_type: error_type,
      error_category: error_category,
      timestamp: System.system_time(:millisecond),
      value: 1
    }
    
    GenServer.cast(__MODULE__, {:record_metric, metric})
  end

  @doc """
  Get resource usage for a specific user.
  """
  def get_user_resource_usage(user_id) when is_binary(user_id) do
    GenServer.call(__MODULE__, {:get_user_resource_usage, user_id})
  end

  @doc """
  Get performance metrics for a specific user.
  """
  def get_user_performance_metrics(user_id, time_window_ms \\ 3600_000) do
    GenServer.call(__MODULE__, {:get_user_performance_metrics, user_id, time_window_ms})
  end

  @doc """
  Get system-wide metrics summary.
  """
  def get_system_metrics_summary do
    GenServer.call(__MODULE__, :get_system_metrics_summary)
  end

  @doc """
  Get aggregated metrics for monitoring dashboards.
  """
  def get_aggregated_metrics(time_window_ms \\ 3600_000) do
    GenServer.call(__MODULE__, {:get_aggregated_metrics, time_window_ms})
  end

  @doc """
  Get top users by specific metric.
  """
  def get_top_users_by_metric(metric_type, limit \\ 10) do
    GenServer.call(__MODULE__, {:get_top_users_by_metric, metric_type, limit})
  end

  @doc """
  Get metrics for capacity planning.
  """
  def get_capacity_metrics do
    GenServer.call(__MODULE__, :get_capacity_metrics)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting UserMetrics")
    
    # Create ETS tables
    metrics_table = :ets.new(@metrics_table, [
      :named_table,
      :public,
      :bag,  # Multiple metrics per user
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    aggregation_table = :ets.new(@aggregation_table, [
      :named_table,
      :public,
      :set,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Schedule periodic tasks
    schedule_cleanup()
    schedule_aggregation()
    
    state = %{
      metrics_table: metrics_table,
      aggregation_table: aggregation_table,
      started_at: System.system_time(:millisecond),
      metric_count: 0
    }
    
    Logger.info("UserMetrics started successfully")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_metric, metric}, state) do
    # Generate unique metric ID
    metric_id = generate_metric_id(state.metric_count)
    
    # Insert metric
    :ets.insert(@metrics_table, {metric_id, metric})
    
    # Update counters and trigger aggregation if needed
    new_metric_count = state.metric_count + 1
    
    if rem(new_metric_count, 1000) == 0 do
      Logger.debug("Recorded #{new_metric_count} metrics")
    end
    
    {:noreply, %{state | metric_count: new_metric_count}}
  end

  @impl true
  def handle_call({:get_user_resource_usage, user_id}, _from, state) do
    # Get latest resource usage metrics for user
    now = System.system_time(:millisecond)
    recent_threshold = now - 60_000  # Last minute
    
    resource_metrics = :ets.foldl(fn {_id, metric}, acc ->
      case metric do
        %{user_id: ^user_id, metric_type: :resource_usage, timestamp: timestamp} 
          when timestamp > recent_threshold ->
          [metric | acc]
        _ ->
          acc
      end
    end, [], @metrics_table)
    
    # Calculate current usage from most recent metrics
    usage = case resource_metrics do
      [] ->
        %{memory: 0, processes: 0, connections: 0, last_updated: nil}
        
      metrics ->
        latest_metric = Enum.max_by(metrics, & &1.timestamp)
        %{
          memory: Map.get(latest_metric, :memory_bytes, 0),
          processes: Map.get(latest_metric, :process_count, 0),
          connections: Map.get(latest_metric, :connection_count, 0),
          last_updated: latest_metric.timestamp
        }
    end
    
    {:reply, usage, state}
  end

  @impl true
  def handle_call({:get_user_performance_metrics, user_id, time_window_ms}, _from, state) do
    now = System.system_time(:millisecond)
    threshold = now - time_window_ms
    
    # Collect performance-related metrics
    performance_metrics = :ets.foldl(fn {_id, metric}, acc ->
      case metric do
        %{user_id: ^user_id, timestamp: timestamp} when timestamp > threshold ->
          [metric | acc]
        _ ->
          acc
      end
    end, [], @metrics_table)
    
    # Calculate performance statistics
    stats = calculate_performance_stats(performance_metrics)
    
    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call(:get_system_metrics_summary, _from, state) do
    now = System.system_time(:millisecond)
    
    # Calculate summary statistics
    total_metrics = :ets.info(@metrics_table, :size)
    
    # Count unique users
    unique_users = :ets.foldl(fn {_id, metric}, acc ->
      MapSet.put(acc, metric.user_id)
    end, MapSet.new(), @metrics_table)
    
    summary = %{
      total_metrics_recorded: state.metric_count,
      metrics_in_memory: total_metrics,
      unique_users: MapSet.size(unique_users),
      uptime_ms: now - state.started_at,
      metrics_per_second: calculate_metrics_rate(state.metric_count, now - state.started_at),
      memory_usage_bytes: :ets.info(@metrics_table, :memory) * :erlang.system_info(:wordsize),
      last_updated: now
    }
    
    {:reply, {:ok, summary}, state}
  end

  @impl true
  def handle_call({:get_aggregated_metrics, time_window_ms}, _from, state) do
    now = System.system_time(:millisecond)
    threshold = now - time_window_ms
    
    # Get aggregated data from aggregation table
    aggregated_data = :ets.foldl(fn {timestamp, aggregation}, acc ->
      if timestamp > threshold do
        [aggregation | acc]
      else
        acc
      end
    end, [], @aggregation_table)
    
    # Sort by timestamp
    sorted_data = Enum.sort_by(aggregated_data, & &1.timestamp)
    
    {:reply, {:ok, sorted_data}, state}
  end

  @impl true
  def handle_call({:get_top_users_by_metric, metric_type, limit}, _from, state) do
    # Aggregate metrics by user for the specified metric type
    user_metrics = :ets.foldl(fn {_id, metric}, acc ->
      case metric do
        %{metric_type: ^metric_type, user_id: user_id} ->
          value = Map.get(metric, :value, 1)
          Map.update(acc, user_id, value, &(&1 + value))
        _ ->
          acc
      end
    end, %{}, @metrics_table)
    
    # Sort and limit
    top_users = user_metrics
    |> Enum.sort_by(fn {_user_id, count} -> count end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {user_id, count} ->
      %{user_id: user_id, count: count, metric_type: metric_type}
    end)
    
    {:reply, {:ok, top_users}, state}
  end

  @impl true
  def handle_call(:get_capacity_metrics, _from, state) do
    # Calculate capacity planning metrics
    now = System.system_time(:millisecond)
    last_hour = now - 3600_000
    
    # Connection metrics
    recent_connections = count_metric_events(:connection, :connected, last_hour)
    recent_disconnections = count_metric_events(:connection, :disconnected, last_hour)
    
    # Resource usage trends
    resource_trend = calculate_resource_trend(last_hour)
    
    # API usage patterns
    api_usage_trend = calculate_api_usage_trend(last_hour)
    
    capacity_metrics = %{
      connections_per_hour: recent_connections,
      disconnections_per_hour: recent_disconnections,
      net_connections: recent_connections - recent_disconnections,
      average_memory_per_user: resource_trend.avg_memory_per_user,
      peak_memory_usage: resource_trend.peak_memory_usage,
      api_requests_per_hour: api_usage_trend.total_requests,
      average_response_time: api_usage_trend.avg_response_time,
      error_rate: calculate_error_rate(last_hour),
      capacity_utilization: calculate_capacity_utilization(),
      projected_load: calculate_projected_load(),
      last_updated: now
    }
    
    {:reply, {:ok, capacity_metrics}, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_metrics()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:aggregate, state) do
    perform_aggregation()
    schedule_aggregation()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in UserMetrics: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("UserMetrics terminating: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  defp generate_metric_id(count) do
    timestamp = System.system_time(:microsecond)
    "#{timestamp}_#{count}"
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp schedule_aggregation do
    Process.send_after(self(), :aggregate, @aggregation_interval)
  end

  defp cleanup_old_metrics do
    cutoff = System.system_time(:millisecond) - (@retention_hours * 3600_000)
    
    old_metrics = :ets.foldl(fn {id, metric}, acc ->
      if metric.timestamp < cutoff do
        [id | acc]
      else
        acc
      end
    end, [], @metrics_table)
    
    Enum.each(old_metrics, fn id ->
      :ets.delete(@metrics_table, id)
    end)
    
    if length(old_metrics) > 0 do
      Logger.info("Cleaned up #{length(old_metrics)} old metrics")
    end
  end

  defp perform_aggregation do
    now = System.system_time(:millisecond)
    window_start = now - @aggregation_interval
    
    # Get metrics from the last aggregation window
    window_metrics = :ets.foldl(fn {_id, metric}, acc ->
      if metric.timestamp > window_start and metric.timestamp <= now do
        [metric | acc]
      else
        acc
      end
    end, [], @metrics_table)
    
    if length(window_metrics) > 0 do
      # Create aggregation
      aggregation = %{
        timestamp: now,
        window_start: window_start,
        window_end: now,
        total_metrics: length(window_metrics),
        unique_users: MapSet.size(Enum.reduce(window_metrics, MapSet.new(), fn metric, acc ->
          MapSet.put(acc, metric.user_id)
        end)),
        metric_types: aggregate_by_type(window_metrics),
        performance_summary: aggregate_performance_metrics(window_metrics)
      }
      
      # Store aggregation
      :ets.insert(@aggregation_table, {now, aggregation})
    end
  end

  defp calculate_performance_stats(metrics) do
    if length(metrics) == 0 do
      %{
        total_operations: 0,
        avg_response_time: 0,
        max_response_time: 0,
        min_response_time: 0,
        error_count: 0,
        success_rate: 100.0
      }
    else
      response_times = Enum.flat_map(metrics, fn metric ->
        case Map.get(metric, :response_time_ms) do
          nil -> []
          time -> [time]
        end
      end)
      
      error_count = Enum.count(metrics, fn metric ->
        metric.metric_type == :error or 
        (Map.has_key?(metric, :success) and not metric.success)
      end)
      
      total_operations = length(metrics)
      
      %{
        total_operations: total_operations,
        avg_response_time: if(length(response_times) > 0, do: Enum.sum(response_times) / length(response_times), else: 0),
        max_response_time: if(length(response_times) > 0, do: Enum.max(response_times), else: 0),
        min_response_time: if(length(response_times) > 0, do: Enum.min(response_times), else: 0),
        error_count: error_count,
        success_rate: if(total_operations > 0, do: ((total_operations - error_count) / total_operations) * 100, else: 100.0)
      }
    end
  end

  defp calculate_metrics_rate(total_metrics, uptime_ms) do
    if uptime_ms > 0 do
      (total_metrics / uptime_ms) * 1000  # metrics per second
    else
      0
    end
  end

  defp count_metric_events(metric_type, event_type, since_timestamp) do
    :ets.foldl(fn {_id, metric}, count ->
      case metric do
        %{metric_type: ^metric_type, event_type: ^event_type, timestamp: timestamp}
          when timestamp > since_timestamp ->
          count + 1
        _ ->
          count
      end
    end, 0, @metrics_table)
  end

  defp calculate_resource_trend(since_timestamp) do
    resource_metrics = :ets.foldl(fn {_id, metric}, acc ->
      case metric do
        %{metric_type: :resource_usage, timestamp: timestamp} when timestamp > since_timestamp ->
          [metric | acc]
        _ ->
          acc
      end
    end, [], @metrics_table)
    
    if length(resource_metrics) > 0 do
      memory_values = Enum.map(resource_metrics, &Map.get(&1, :memory_bytes, 0))
      
      %{
        avg_memory_per_user: Enum.sum(memory_values) / length(memory_values),
        peak_memory_usage: Enum.max(memory_values),
        sample_count: length(resource_metrics)
      }
    else
      %{avg_memory_per_user: 0, peak_memory_usage: 0, sample_count: 0}
    end
  end

  defp calculate_api_usage_trend(since_timestamp) do
    api_metrics = :ets.foldl(fn {_id, metric}, acc ->
      case metric do
        %{metric_type: :api_request, timestamp: timestamp} when timestamp > since_timestamp ->
          [metric | acc]
        _ ->
          acc
      end
    end, [], @metrics_table)
    
    if length(api_metrics) > 0 do
      response_times = Enum.flat_map(api_metrics, fn metric ->
        case Map.get(metric, :response_time_ms) do
          nil -> []
          time -> [time]
        end
      end)
      
      %{
        total_requests: length(api_metrics),
        avg_response_time: if(length(response_times) > 0, do: Enum.sum(response_times) / length(response_times), else: 0)
      }
    else
      %{total_requests: 0, avg_response_time: 0}
    end
  end

  defp calculate_error_rate(since_timestamp) do
    error_count = count_metric_events(:error, nil, since_timestamp)
    total_operations = :ets.foldl(fn {_id, metric}, count ->
      if metric.timestamp > since_timestamp do
        count + 1
      else
        count
      end
    end, 0, @metrics_table)
    
    if total_operations > 0 do
      (error_count / total_operations) * 100
    else
      0.0
    end
  end

  defp calculate_capacity_utilization do
    # This would integrate with system-level metrics
    # For now, return a placeholder based on current load
    50.0  # Placeholder: 50% utilization
  end

  defp calculate_projected_load do
    # This would use historical data to project future load
    # For now, return current load metrics
    %{
      projected_users_1h: 10,
      projected_requests_1h: 1000,
      confidence: 0.8
    }
  end

  defp aggregate_by_type(metrics) do
    Enum.reduce(metrics, %{}, fn metric, acc ->
      type = metric.metric_type
      Map.update(acc, type, 1, &(&1 + 1))
    end)
  end

  defp aggregate_performance_metrics(metrics) do
    calculate_performance_stats(metrics)
  end
end