defmodule CryptoExchange.Application do
  @moduledoc """
  The CryptoExchange OTP application.

  This application starts the core supervision tree with the following components:
  
  1. **Registry** - Process registration and discovery for user connections and streams
  2. **Phoenix.PubSub** - Message distribution system for market data and user events
  3. **PublicStreams.StreamManager** - Manages public market data stream subscriptions
  4. **Trading.UserManager** - Dynamic supervisor for isolated user trading sessions

  ## Supervision Strategy

  The application uses `:one_for_one` supervision strategy at the top level.
  This ensures that if any core service fails, only that specific service
  is restarted, not the entire application.

  ## Process Hierarchy

  ```
  CryptoExchange.Application (Supervisor)
  ├── Registry (keys: :unique)
  ├── Phoenix.PubSub  
  ├── PublicStreams.StreamManager (GenServer, restart: :permanent)
  └── Trading.UserManager (DynamicSupervisor, restart: :permanent)
      └── UserConnection processes (restart: :temporary)
  ```

  ## Fault Tolerance Design

  - **Registry**: Core infrastructure - permanent restart
  - **Phoenix.PubSub**: Core infrastructure - permanent restart  
  - **StreamManager**: Core service - permanent restart
  - **UserManager**: Core service - permanent restart
  - **UserConnection**: User sessions - temporary restart (no auto-restart)

  ## Error Isolation

  The supervision tree is designed to isolate failures:

  - Public streams are isolated from user trading operations
  - Each user has their own isolated process that can fail independently
  - Core infrastructure services have permanent restart to ensure availability
  - Failed user sessions require explicit reconnection with valid credentials
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting CryptoExchange application")
    
    # Validate configuration before starting any processes
    try do
      CryptoExchange.Config.validate()
    rescue
      error ->
        Logger.error("Configuration validation failed: #{Exception.message(error)}")
        {:error, {:config_validation_failed, error}}
    end

    children = [
      # Core infrastructure - these services must always be available
      # Registry for process registration and discovery
      {Registry, keys: :unique, name: CryptoExchange.Registry},

      # Phoenix PubSub for message distribution across the system
      {Phoenix.PubSub, name: CryptoExchange.PubSub},

      # Connection Manager with circuit breaker and exponential backoff
      # Critical infrastructure for managing all external connections with fault tolerance
      %{
        id: CryptoExchange.ConnectionManager,
        start: {CryptoExchange.ConnectionManager, :start_link, [[]]},
        restart: :permanent,
        shutdown: 10_000,  # Allow time for graceful connection cleanup
        type: :worker
      },

      # Health Monitor for comprehensive system monitoring and alerting
      # Monitors connection health and system reliability
      %{
        id: CryptoExchange.HealthMonitor,
        start: {CryptoExchange.HealthMonitor, :start_link, [[]]},
        restart: :permanent,
        shutdown: 5_000,
        type: :worker
      },

      # Connection State Manager with automatic fallback strategies
      # Manages connection states and orchestrates fallback mechanisms
      %{
        id: CryptoExchange.ConnectionStateManager,
        start: {CryptoExchange.ConnectionStateManager, :start_link, [[]]},
        restart: :permanent,
        shutdown: 10_000,
        type: :worker
      },

      # Error Recovery Supervisor for stream interruption handling
      # Provides intelligent error recovery strategies for different failure types
      %{
        id: CryptoExchange.ErrorRecoverySupervisor,
        start: {CryptoExchange.ErrorRecoverySupervisor, :start_link, [[]]},
        restart: :permanent,
        shutdown: 15_000,  # Allow time for recovery operations to complete
        type: :supervisor
      },

      # Public market data streaming manager (Enhanced)
      # Now integrates with ConnectionManager for robust fault tolerance
      %{
        id: CryptoExchange.PublicStreams.StreamManager,
        start: {CryptoExchange.PublicStreams.StreamManager, :start_link, [[]]},
        restart: :permanent,
        shutdown: 10_000,  # Allow time for stream cleanup and reconnection
        type: :worker
      },

      # Enhanced User Management Infrastructure
      # UserRegistry for fast user session lookups
      %{
        id: CryptoExchange.Trading.UserRegistry,
        start: {CryptoExchange.Trading.UserRegistry, :start_link, [[]]},
        restart: :permanent,
        shutdown: 5_000,
        type: :worker
      },

      # UserSecurityAuditor for comprehensive security logging
      %{
        id: CryptoExchange.Trading.UserSecurityAuditor,
        start: {CryptoExchange.Trading.UserSecurityAuditor, :start_link, [[]]},
        restart: :permanent,
        shutdown: 10_000,
        type: :worker
      },

      # UserMetrics for performance monitoring and analytics
      %{
        id: CryptoExchange.Trading.UserMetrics,
        start: {CryptoExchange.Trading.UserMetrics, :start_link, [[]]},
        restart: :permanent,
        shutdown: 10_000,
        type: :worker
      },

      # Dynamic supervisor for user trading connections (Enhanced)  
      # Integrated with health monitoring and connection management
      %{
        id: CryptoExchange.Trading.UserManager,
        start: {CryptoExchange.Trading.UserManager, :start_link, [[]]},
        restart: :permanent,
        shutdown: :infinity,
        type: :supervisor
      }
    ]

    # Enhanced supervision strategy configuration
    # Uses :one_for_one with more conservative restart limits to prevent cascading failures
    opts = [
      strategy: :one_for_one,
      name: CryptoExchange.Supervisor,
      max_restarts: 5,     # Allow more restarts for resilience
      max_seconds: 10      # Over a longer period to handle temporary issues
    ]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("CryptoExchange application started successfully")
        log_supervision_tree()
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start CryptoExchange application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping CryptoExchange application")
    :ok
  end

  @impl true
  def prep_stop(state) do
    Logger.info("Preparing to stop CryptoExchange application")
    
    # Gracefully disconnect all users before shutdown
    try do
      users = CryptoExchange.Trading.UserManager.list_connected_users()
      Logger.info("Disconnecting #{length(users)} users before shutdown")
      
      Enum.each(users, fn user_id ->
        case CryptoExchange.Trading.UserManager.disconnect_user(user_id) do
          :ok -> 
            Logger.debug("Disconnected user: #{user_id}")
          {:error, reason} -> 
            Logger.warning("Failed to disconnect user #{user_id}: #{inspect(reason)}")
        end
      end)
    rescue
      error ->
        Logger.error("Error during graceful shutdown: #{inspect(error)}")
    end
    
    state
  end

  # Private Functions

  defp log_supervision_tree do
    Logger.info("CryptoExchange enhanced supervision tree:")
    Logger.info("├── Registry (CryptoExchange.Registry)")
    Logger.info("├── Phoenix.PubSub (CryptoExchange.PubSub)")
    Logger.info("├── ConnectionManager (Circuit Breaker & Exponential Backoff)")
    Logger.info("├── HealthMonitor (System Health & Alerting)")
    Logger.info("├── ConnectionStateManager (Automatic Fallback Strategies)")
    Logger.info("├── ErrorRecoverySupervisor (Stream Interruption Recovery)")
    Logger.info("│   └── RecoveryWorker processes (created on-demand)")
    Logger.info("├── PublicStreams.StreamManager (Enhanced with Fault Tolerance)")
    Logger.info("└── Trading.UserManager (DynamicSupervisor)")
    Logger.info("    └── UserConnection processes (created dynamically)")
    Logger.info("")
    Logger.info("Comprehensive Fault Tolerance Features:")
    Logger.info("• Circuit Breaker Pattern for cascading failure prevention")
    Logger.info("• Exponential backoff with jitter (1s → 30s max, per SPECIFICATION.md)")  
    Logger.info("• Comprehensive health monitoring and real-time alerting")
    Logger.info("• Intelligent error recovery for stream interruptions")
    Logger.info("• Automatic fallback strategies with endpoint switching")
    Logger.info("• Connection state management with graceful degradation")
    Logger.info("• Rate limit awareness and Binance API compliance")
  end

  defp safe_count_connected_users do
    try do
      length(CryptoExchange.Trading.UserManager.list_connected_users())
    rescue
      _ -> 0
    end
  end

  defp safe_count_active_streams do
    try do
      length(CryptoExchange.PublicStreams.StreamManager.list_streams())
    rescue
      _ -> 0
    end
  end

  @doc """
  Get the current status of all supervised processes.
  Useful for health checks and monitoring.
  """
  def health_check do
    supervisor_pid = Process.whereis(CryptoExchange.Supervisor)
    
    if supervisor_pid && Process.alive?(supervisor_pid) do
      children = Supervisor.which_children(CryptoExchange.Supervisor)
      
      status = %{
        supervisor: :ok,
        children: Enum.map(children, fn {id, pid, type, _modules} ->
          %{
            id: id,
            pid: pid,
            type: type,
            status: if(pid && Process.alive?(pid), do: :ok, else: :error)
          }
        end),
        connected_users: safe_count_connected_users(),
        active_streams: safe_count_active_streams()
      }
      
      {:ok, status}
    else
      {:error, :supervisor_not_running}
    end
  end

  @doc """
  Get detailed information about the supervision tree.
  """
  def supervision_info do
    case health_check() do
      {:ok, status} ->
        info = %{
          application: :crypto_exchange,
          supervisor: CryptoExchange.Supervisor,
          strategy: :one_for_one,
          children: status.children,
          metrics: %{
            connected_users: status.connected_users,
            active_streams: status.active_streams,
            uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
          }
        }
        
        {:ok, info}
        
      error ->
        error
    end
  end
end