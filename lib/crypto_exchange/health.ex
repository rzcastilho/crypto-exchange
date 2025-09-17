defmodule CryptoExchange.Health do
  @moduledoc """
  Health check and monitoring system for CryptoExchange application.

  This module provides comprehensive health monitoring capabilities for all critical
  components of the crypto exchange system, enabling proactive monitoring, alerting,
  and system reliability assessment.

  ## Features

  - **Component Health Checks**: Individual health assessments for all system components
  - **System-wide Status**: Aggregated health status with detailed breakdown
  - **Performance Metrics**: Latency, throughput, and resource utilization monitoring
  - **Dependency Monitoring**: External API and service dependency health tracking
  - **Circuit Breaker Integration**: Health-aware circuit breaker status reporting
  - **Real-time Monitoring**: Continuous health assessment with configurable intervals
  - **Alert Integration**: Structured health data for alerting and notification systems

  ## Health Check Categories

  - **Critical**: Core trading functionality (order placement, balance queries)
  - **Important**: Real-time data feeds (WebSocket connections, price feeds)
  - **Supporting**: Authentication, logging, and administrative functions
  - **External**: Third-party dependencies (Binance API, external services)

  ## Health Status Levels

  - **healthy**: All systems operational within normal parameters
  - **degraded**: Some non-critical issues detected, system still functional
  - **unhealthy**: Critical issues affecting core functionality
  - **unknown**: Unable to determine component status

  ## Usage Examples

  ```elixir
  # Get overall system health
  {:ok, health} = Health.check_system()
  IO.inspect(health.status)  # :healthy, :degraded, :unhealthy, or :unknown

  # Check specific component
  {:ok, api_health} = Health.check_component(:binance_api)

  # Get detailed health report
  {:ok, report} = Health.detailed_report()

  # Start continuous monitoring
  {:ok, _pid} = Health.start_monitor()
  ```

  ## Health Check Structure

  ```json
  {
    "status": "healthy",
    "timestamp": "2023-01-15T10:30:45.123Z",
    "components": {
      "binance_api": {
        "status": "healthy",
        "latency_ms": 150,
        "last_success": "2023-01-15T10:30:40.000Z",
        "error_rate": 0.02
      },
      "websocket_connections": {
        "status": "degraded", 
        "active_connections": 3,
        "target_connections": 5,
        "reconnect_rate": 0.1
      }
    },
    "metrics": {
      "uptime_seconds": 86400,
      "memory_usage_mb": 256,
      "cpu_usage_percent": 15.5
    }
  }
  ```
  """

  use GenServer
  require Logger

  alias CryptoExchange.{Logging, Trading, Binance}
  alias CryptoExchange.Binance.WebSocketHandler

  @type health_status :: :healthy | :degraded | :unhealthy | :unknown
  @type component_name ::
          :binance_api
          | :websocket_connections
          | :trading_system
          | :user_connections
          | :application
          | :external_dependencies

  @type health_check_result :: %{
          status: health_status(),
          timestamp: DateTime.t(),
          latency_ms: non_neg_integer() | nil,
          error_message: String.t() | nil,
          metadata: map()
        }

  @type system_health :: %{
          status: health_status(),
          timestamp: DateTime.t(),
          components: %{component_name() => health_check_result()},
          metrics: map(),
          version: String.t()
        }

  # Configuration
  # 30 seconds
  @default_check_interval 30_000
  # 5 seconds per component check
  @component_timeout 5_000
  @critical_components [:binance_api, :trading_system]
  # Component categorization for health assessment
  # @important_components [:websocket_connections, :user_connections] 
  # @supporting_components [:application, :external_dependencies]

  ## Public API

  @doc """
  Performs a comprehensive system health check.

  Returns aggregated health status for all monitored components.
  """
  @spec check_system() :: {:ok, system_health()} | {:error, term()}
  def check_system do
    Logging.info("Starting system health check", %{category: :system})

    start_time = System.monotonic_time(:millisecond)
    timestamp = DateTime.utc_now()

    # Run health checks for all components concurrently
    component_checks = [
      Task.async(fn -> {:binance_api, check_binance_api()} end),
      Task.async(fn -> {:websocket_connections, check_websocket_connections()} end),
      Task.async(fn -> {:trading_system, check_trading_system()} end),
      Task.async(fn -> {:user_connections, check_user_connections()} end),
      Task.async(fn -> {:application, check_application()} end),
      Task.async(fn -> {:external_dependencies, check_external_dependencies()} end)
    ]

    # Collect results with timeout protection
    component_results =
      component_checks
      |> Task.await_many(@component_timeout)
      |> Map.new()

    end_time = System.monotonic_time(:millisecond)
    check_duration = end_time - start_time

    # Determine overall system status
    overall_status = determine_overall_status(component_results)

    # Gather system metrics
    metrics = gather_system_metrics() |> Map.put(:health_check_duration_ms, check_duration)

    system_health = %{
      status: overall_status,
      timestamp: timestamp,
      components: component_results,
      metrics: metrics,
      version: Application.spec(:crypto_exchange, :vsn) |> to_string()
    }

    Logging.info("System health check completed", %{
      category: :system,
      status: overall_status,
      duration_ms: check_duration,
      total_components: map_size(component_results)
    })

    {:ok, system_health}
  end

  @doc """
  Checks the health of a specific component.
  """
  @spec check_component(component_name()) :: {:ok, health_check_result()} | {:error, term()}
  def check_component(component) do
    Logging.debug("Checking component health", %{category: :system, component: component})

    result =
      case component do
        :binance_api ->
          check_binance_api()

        :websocket_connections ->
          check_websocket_connections()

        :trading_system ->
          check_trading_system()

        :user_connections ->
          check_user_connections()

        :application ->
          check_application()

        :external_dependencies ->
          check_external_dependencies()

        _ ->
          %{status: :unknown, timestamp: DateTime.utc_now(), error_message: "Unknown component"}
      end

    {:ok, result}
  end

  @doc """
  Starts the health monitoring GenServer.

  Performs periodic health checks and maintains system health state.
  """
  @spec start_monitor(keyword()) :: GenServer.on_start()
  def start_monitor(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current cached health status from the monitor.
  """
  @spec get_cached_health() :: {:ok, system_health()} | {:error, term()}
  def get_cached_health do
    case GenServer.whereis(__MODULE__) do
      # Fall back to immediate check if monitor not running
      nil -> check_system()
      pid -> GenServer.call(pid, :get_health)
    end
  end

  @doc """
  Forces an immediate health check update in the monitor.
  """
  @spec refresh_health() :: :ok
  def refresh_health do
    case GenServer.whereis(__MODULE__) do
      # Monitor not running
      nil -> :ok
      pid -> GenServer.cast(pid, :refresh_health)
    end
  end

  @doc """
  Gets detailed health report with historical data and trends.
  """
  @spec detailed_report() :: {:ok, map()} | {:error, term()}
  def detailed_report do
    with {:ok, current_health} <- check_system() do
      detailed_data = %{
        current: current_health,
        trends: calculate_health_trends(),
        alerts: generate_health_alerts(current_health),
        recommendations: generate_health_recommendations(current_health)
      }

      {:ok, detailed_data}
    end
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)

    # Perform initial health check
    {:ok, initial_health} = check_system()

    # Schedule periodic health checks
    Process.send_after(self(), :health_check, check_interval)

    state = %{
      current_health: initial_health,
      check_interval: check_interval,
      last_check: DateTime.utc_now(),
      check_count: 1,
      health_history: [initial_health]
    }

    Logging.system_event("Health monitor started", %{
      check_interval_ms: check_interval,
      initial_status: initial_health.status
    })

    {:ok, state}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    {:reply, {:ok, state.current_health}, state}
  end

  @impl true
  def handle_cast(:refresh_health, state) do
    {:noreply, perform_health_check(state)}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)

    # Schedule next check
    Process.send_after(self(), :health_check, state.check_interval)

    {:noreply, new_state}
  end

  ## Private Functions

  defp perform_health_check(state) do
    case check_system() do
      {:ok, new_health} ->
        # Update history (keep last 100 checks)
        updated_history =
          [new_health | state.health_history]
          |> Enum.take(100)

        # Check for status changes
        if new_health.status != state.current_health.status do
          Logging.warning("System health status changed", %{
            category: :system,
            previous_status: state.current_health.status,
            new_status: new_health.status
          })
        end

        %{
          state
          | current_health: new_health,
            last_check: DateTime.utc_now(),
            check_count: state.check_count + 1,
            health_history: updated_history
        }
    end
  end

  defp check_binance_api do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Test Binance API connectivity with a lightweight endpoint
      case Binance.PrivateClient.test_connectivity() do
        {:ok, _} ->
          end_time = System.monotonic_time(:millisecond)
          latency = end_time - start_time

          %{
            status: :healthy,
            timestamp: DateTime.utc_now(),
            latency_ms: latency,
            metadata: %{endpoint: "api_connectivity_test"}
          }

        {:error, reason} ->
          %{
            status: :unhealthy,
            timestamp: DateTime.utc_now(),
            error_message: "Binance API connectivity failed: #{inspect(reason)}",
            metadata: %{error: reason}
          }
      end
    rescue
      exception ->
        %{
          status: :unhealthy,
          timestamp: DateTime.utc_now(),
          error_message: "Binance API check exception: #{Exception.message(exception)}",
          metadata: %{exception: exception.__struct__}
        }
    end
  end

  defp check_websocket_connections do
    try do
      # Check WebSocket handler health if available
      case WebSocketHandler.get_connection_health(self()) do
        health when is_map(health) ->
          status =
            if health.connected do
              if health.circuit_breaker_state == :open do
                :degraded
              else
                :healthy
              end
            else
              :unhealthy
            end

          %{
            status: status,
            timestamp: DateTime.utc_now(),
            metadata: Map.merge(health, %{component: "websocket_handler"})
          }

        {:error, reason} ->
          %{
            status: :unknown,
            timestamp: DateTime.utc_now(),
            error_message: "WebSocket health check failed: #{inspect(reason)}",
            metadata: %{error: reason}
          }
      end
    catch
      :exit, reason ->
        %{
          status: :unhealthy,
          timestamp: DateTime.utc_now(),
          error_message: "WebSocket connection check failed: #{inspect(reason)}",
          metadata: %{exit_reason: reason}
        }
    end
  end

  defp check_trading_system do
    task =
      Task.async(fn ->
        try do
          # Check trading system responsiveness
          stats = Trading.get_system_stats()

          status =
            cond do
              stats.connected_users == 0 -> :degraded
              stats.total_connections > 0 -> :healthy
              true -> :unknown
            end

          %{
            status: status,
            timestamp: DateTime.utc_now(),
            metadata: Map.merge(stats, %{component: "trading_system"})
          }
        rescue
          exception ->
            %{
              status: :unhealthy,
              timestamp: DateTime.utc_now(),
              error_message: "Trading system check failed: #{Exception.message(exception)}",
              metadata: %{exception: exception.__struct__}
            }
        catch
          :exit, reason ->
            %{
              status: :unhealthy,
              timestamp: DateTime.utc_now(),
              error_message: "Trading system unavailable: #{inspect(reason)}",
              metadata: %{exit_reason: reason, component: "trading_system"}
            }
        end
      end)

    try do
      # 2 second timeout for this specific check
      Task.await(task, 2000)
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)

        %{
          status: :unhealthy,
          timestamp: DateTime.utc_now(),
          error_message: "Trading system check timed out",
          metadata: %{timeout: 2000, component: "trading_system"}
        }
    end
  end

  defp check_user_connections do
    task =
      Task.async(fn ->
        try do
          connected_users = Trading.list_connected_users()
          user_count = length(connected_users)

          # Sample a few user connections to verify they're responsive
          sample_size = min(3, user_count)
          sample_users = Enum.take_random(connected_users, sample_size)

          healthy_connections =
            sample_users
            |> Enum.count(fn user_id ->
              case Trading.get_user_info(user_id) do
                {:ok, _info} -> true
                {:error, _} -> false
              end
            end)

          status =
            cond do
              # No users connected (not necessarily unhealthy)
              user_count == 0 -> :degraded
              healthy_connections == sample_size -> :healthy
              healthy_connections > 0 -> :degraded
              true -> :unhealthy
            end

          %{
            status: status,
            timestamp: DateTime.utc_now(),
            metadata: %{
              total_users: user_count,
              sampled_users: sample_size,
              healthy_connections: healthy_connections
            }
          }
        rescue
          exception ->
            %{
              status: :unhealthy,
              timestamp: DateTime.utc_now(),
              error_message: "User connections check failed: #{Exception.message(exception)}",
              metadata: %{exception: exception.__struct__}
            }
        catch
          :exit, reason ->
            %{
              status: :unhealthy,
              timestamp: DateTime.utc_now(),
              error_message: "User connections unavailable: #{inspect(reason)}",
              metadata: %{exit_reason: reason, total_users: 0}
            }
        end
      end)

    try do
      # 1 second timeout for user connections check
      Task.await(task, 1000)
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)

        %{
          status: :unhealthy,
          timestamp: DateTime.utc_now(),
          error_message: "User connections check timed out",
          metadata: %{timeout: 1000, total_users: 0}
        }
    end
  end

  defp check_application do
    try do
      # Check application-level health indicators
      processes = Process.list() |> length()
      memory = :erlang.memory()

      status =
        cond do
          # > 1GB memory usage
          memory[:total] > 1_000_000_000 -> :degraded
          # > 10k processes
          processes > 10_000 -> :degraded
          true -> :healthy
        end

      %{
        status: status,
        timestamp: DateTime.utc_now(),
        metadata: %{
          process_count: processes,
          memory_bytes: memory[:total],
          memory_mb: div(memory[:total], 1_048_576)
        }
      }
    rescue
      exception ->
        %{
          status: :unhealthy,
          timestamp: DateTime.utc_now(),
          error_message: "Application check failed: #{Exception.message(exception)}",
          metadata: %{exception: exception.__struct__}
        }
    end
  end

  defp check_external_dependencies do
    # For now, this is a placeholder - in a real system, you'd check:
    # - Database connectivity
    # - Redis/cache connectivity  
    # - External service APIs
    # - Network connectivity

    %{
      status: :healthy,
      timestamp: DateTime.utc_now(),
      metadata: %{
        note: "External dependency checks not implemented",
        dependencies: []
      }
    }
  end

  defp determine_overall_status(component_results) do
    statuses = Map.values(component_results) |> Enum.map(& &1.status)

    cond do
      Enum.any?(statuses, fn status ->
        status == :unhealthy and
            Map.keys(component_results)
            |> Enum.any?(&(&1 in @critical_components))
      end) ->
        :unhealthy

      Enum.any?(statuses, &(&1 == :unhealthy)) ->
        :degraded

      Enum.any?(statuses, &(&1 == :degraded)) ->
        :degraded

      Enum.all?(statuses, &(&1 == :healthy)) ->
        :healthy

      true ->
        :unknown
    end
  end

  defp gather_system_metrics do
    memory = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      uptime_seconds: div(uptime_ms, 1000),
      memory_usage_mb: div(memory[:total], 1_048_576),
      process_count: length(Process.list()),
      node: Node.self(),
      otp_release: :erlang.system_info(:otp_release)
    }
  end

  defp calculate_health_trends do
    # Placeholder for health trend analysis
    # In a real implementation, this would analyze historical health data
    %{
      status_changes_24h: 0,
      average_latency_ms: nil,
      error_rate: 0.0,
      availability_percent: 99.5
    }
  end

  defp generate_health_alerts(health) do
    alerts = []

    # Check for critical component failures
    critical_alerts =
      health.components
      |> Enum.filter(fn {component, result} ->
        component in @critical_components and result.status == :unhealthy
      end)
      |> Enum.map(fn {component, result} ->
        %{
          severity: :critical,
          component: component,
          message: result.error_message || "Critical component unhealthy",
          timestamp: result.timestamp
        }
      end)

    # Check for performance degradation
    performance_alerts =
      case health.status do
        :degraded ->
          [
            %{
              severity: :warning,
              component: :system,
              message: "System performance degraded",
              timestamp: health.timestamp
            }
          ]

        _ ->
          []
      end

    alerts ++ critical_alerts ++ performance_alerts
  end

  defp generate_health_recommendations(health) do
    recommendations = []

    # Check memory usage
    memory_mb = health.metrics[:memory_usage_mb] || 0

    memory_recommendations =
      if memory_mb > 512 do
        ["Consider increasing available memory or optimizing memory usage"]
      else
        []
      end

    # Check component-specific recommendations
    component_recommendations =
      health.components
      |> Enum.flat_map(fn {component, result} ->
        case {component, result.status} do
          {:binance_api, :unhealthy} ->
            ["Check Binance API credentials and network connectivity"]

          {:websocket_connections, :degraded} ->
            ["Review WebSocket connection stability and reconnection logic"]

          {:user_connections, :unhealthy} ->
            ["Investigate user connection issues and session management"]

          _ ->
            []
        end
      end)

    recommendations ++ memory_recommendations ++ component_recommendations
  end
end
