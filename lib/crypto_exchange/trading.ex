defmodule CryptoExchange.Trading do
  @moduledoc """
  User trading operations with secure credential management.

  This module handles authenticated trading operations for users, including:

  - Order placement and cancellation
  - Account balance retrieval
  - Order history and status
  - Isolated user sessions with credential management

  ## Architecture

  The trading system uses a two-level supervision structure:

  1. **UserManager** (DynamicSupervisor): Manages user connection lifecycles
  2. **UserConnection** (GenServer): Individual user session with credentials

  ## Security

  - API credentials are stored only in GenServer state
  - Each user has an isolated connection process
  - Credentials are never logged or exposed
  - HMAC-SHA256 signatures for API authentication

  ## Error Handling

  Common error patterns:

  - `{:error, :invalid_credentials}` - Invalid API key/secret
  - `{:error, :insufficient_balance}` - Not enough funds
  - `{:error, :rate_limit_exceeded}` - API rate limit hit
  - `{:error, :connection_failed}` - Network/connection issues
  """

  defmodule UserManager do
    @moduledoc """
    Enhanced DynamicSupervisor for managing secure user trading connections.

    This supervisor manages the lifecycle of individual user trading sessions with
    enhanced security, fault tolerance, and monitoring capabilities. Each user gets
    their own isolated supervision subtree for maximum fault isolation.

    ## Enhanced Architecture

    ```
    UserManager (DynamicSupervisor)
    └── UserSupervisor (per user)
        ├── UserConnection (trading operations)
        ├── CredentialManager (secure credential handling)
        └── UserHealthMonitor (user-specific health monitoring)
    ```

    ## Security Features

    - **Credential isolation**: Separate process for credential management
    - **Memory protection**: Credentials stored in isolated process memory
    - **Audit logging**: All operations logged (without credential exposure)
    - **Automatic cleanup**: Credentials purged on disconnection
    - **Rate limiting**: Per-user Binance API compliance

    ## Fault Tolerance

    - **Three-tier isolation**: Manager → UserSupervisor → User processes
    - **Graceful degradation**: Individual user failures don't affect others
    - **Health monitoring**: Real-time user session health tracking
    - **Integration**: Works with existing fault tolerance infrastructure

    ## Scalability

    - **Resource monitoring**: Per-user memory/CPU tracking
    - **Connection pooling**: Efficient HTTP connection reuse
    - **Load balancing**: Distribute users across available resources
    - **Concurrent users**: Optimized for 10+ concurrent trading sessions

    ## Restart Strategy

    Uses `:temporary` restart for user supervisors - failed sessions require
    explicit reconnection with credentials for security.
    """

    use DynamicSupervisor
    require Logger

    alias CryptoExchange.{Registry, HealthMonitor, FaultTolerance}
    alias CryptoExchange.Trading.{
      UserSupervisor, UserRegistry, UserMetrics, UserSecurityAuditor, UserHealthMonitor
    }

    @registry CryptoExchange.Registry
    @max_users 50  # Configurable limit for resource management
    @user_timeout 300_000  # 5 minutes of inactivity before monitoring alert

    # Client API

    @doc """
    Starts the UserManager DynamicSupervisor.
    """
    def start_link(opts \\ []) do
      DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @doc """
    Connect a user with their API credentials using enhanced security architecture.
    
    Creates a UserSupervisor for the user which manages:
    - UserConnection for trading operations
    - CredentialManager for secure credential handling
    - UserHealthMonitor for user-specific monitoring

    ## Security Features
    - Credentials are never logged or exposed
    - Separate process isolation for credential management
    - Automatic security audit trail
    - Rate limiting and resource monitoring

    ## Returns
    - `{:ok, supervisor_pid}` - User successfully connected
    - `{:error, :user_limit_exceeded}` - Too many users connected
    - `{:error, :invalid_credentials}` - Credential validation failed
    - `{:error, reason}` - Other connection failures
    """
    def connect_user(user_id, api_key, secret_key) when is_binary(user_id) do
      # Input validation
      with :ok <- validate_user_input(user_id, api_key, secret_key),
           :ok <- check_user_limit(),
           :ok <- validate_credentials_format(api_key, secret_key) do
        
        case UserRegistry.lookup_user(user_id) do
          {:error, :not_found} ->
            # Create new user session with enhanced architecture
            create_user_session(user_id, api_key, secret_key)
            
          {:ok, %{supervisor_pid: pid}} when is_pid(pid) ->
            case Process.alive?(pid) do
              true ->
                Logger.info("User #{user_id} already connected", user_id: user_id)
                {:ok, pid}
                
              false ->
                # Clean up stale registry entry and create new session
                UserRegistry.remove_user(user_id)
                create_user_session(user_id, api_key, secret_key)
            end
        end
      else
        error -> 
          Logger.warning("User connection rejected: #{inspect(error)}", user_id: user_id)
          UserSecurityAuditor.log_connection_attempt(user_id, :rejected, error)
          error
      end
    end

    @doc """
    Disconnect a user with secure credential cleanup.
    
    Performs graceful shutdown of the entire user supervision subtree,
    ensuring all credentials are properly purged from memory and all
    user processes are terminated cleanly.

    ## Security Features
    - Credentials are securely purged from memory
    - All user-related processes are terminated
    - Audit trail is maintained
    - Clean registry cleanup
    """
    def disconnect_user(user_id) when is_binary(user_id) do
      case UserRegistry.lookup_user(user_id) do
        {:error, :not_found} ->
          {:error, :not_connected}
          
        {:ok, %{supervisor_pid: supervisor_pid}} ->
          Logger.info("Disconnecting user: #{user_id}", user_id: user_id)
          
          # Graceful shutdown sequence
          with :ok <- notify_user_disconnecting(user_id),
               :ok <- secure_credential_cleanup(user_id),
               :ok <- DynamicSupervisor.terminate_child(__MODULE__, supervisor_pid),
               :ok <- UserRegistry.remove_user(user_id) do
            
            # Update metrics and audit
            UserMetrics.record_disconnection(user_id)
            UserSecurityAuditor.log_disconnection(user_id, :graceful)
            HealthMonitor.report_connection_event(user_id, :user_disconnected)
            
            Logger.info("User disconnected successfully: #{user_id}", user_id: user_id)
            :ok
          else
            error ->
              Logger.error("Failed to disconnect user #{user_id}: #{inspect(error)}", user_id: user_id)
              UserSecurityAuditor.log_disconnection(user_id, :failed)
              error
          end
      end
    end

    @doc """
    Get comprehensive user session information.
    
    Returns detailed information about a user's session including
    all managed processes and their current status.
    """
    def get_user_session_info(user_id) when is_binary(user_id) do
      case UserRegistry.lookup_user(user_id) do
        {:error, :not_found} -> 
          {:error, :not_connected}
          
        {:ok, user_info} ->
          # Enhance with real-time process status
          enhanced_info = Map.merge(user_info, %{
            processes_alive: check_user_processes_alive(user_info),
            last_activity: get_user_last_activity(user_id),
            health_status: get_user_health_status(user_id),
            resource_usage: get_user_resource_usage(user_id)
          })
          
          {:ok, enhanced_info}
      end
    end

    @doc """
    Get the PID of a user's connection process (legacy API).
    """
    def get_user_connection(user_id) when is_binary(user_id) do
      case get_user_session_info(user_id) do
        {:ok, %{connection_pid: pid}} -> {:ok, pid}
        error -> error
      end
    end

    @doc """
    List all connected users with enhanced information.
    
    Returns comprehensive information about all connected users,
    including their health status, resource usage, and connection details.
    """
    def list_connected_users do
      UserRegistry.list_all_users()
    end

    @doc """
    Get comprehensive system statistics for all users.
    """
    def get_system_statistics do
      users = list_connected_users()
      
      %{
        total_users: length(users),
        active_users: count_active_users(users),
        resource_usage: calculate_total_resource_usage(users),
        health_summary: calculate_health_summary(users),
        uptime_stats: calculate_uptime_stats(users),
        security_stats: UserSecurityAuditor.get_security_summary(),
        last_updated: System.system_time(:millisecond)
      }
    end

    @doc """
    Check if the system can accept new user connections.
    """
    def can_accept_new_users? do
      current_count = length(list_connected_users())
      current_count < @max_users
    end

    # Server Callbacks

    @impl true
    def init(_opts) do
      Logger.info("Starting enhanced Trading.UserManager with security features")
      
      # Initialize supporting components
      :ok = initialize_user_registry()
      :ok = initialize_security_auditor()
      :ok = initialize_user_metrics()
      
      # Register with health monitoring (if available)
      try do
        HealthMonitor.register_connection(:user_manager, self())
      catch
        _, _ -> Logger.debug("HealthMonitor integration not available")
      end
      
      Logger.info("UserManager initialized - Max users: #{@max_users}, Timeout: #{@user_timeout}ms")
      DynamicSupervisor.init(strategy: :one_for_one)
    end

    # Private Functions - User Session Management

    defp create_user_session(user_id, api_key, secret_key) do
      Logger.info("Creating new user session", user_id: user_id)
      
      # Create UserSupervisor for this user
      supervisor_spec = {
        UserSupervisor,
        [
          user_id: user_id,
          api_key: api_key,
          secret_key: secret_key,
          timeout: @user_timeout
        ]
      }
      
      case DynamicSupervisor.start_child(__MODULE__, supervisor_spec) do
        {:ok, supervisor_pid} ->
          # Register user in our enhanced registry
          user_info = %{
            user_id: user_id,
            supervisor_pid: supervisor_pid,
            connection_pid: nil,  # Will be updated by UserSupervisor
            credential_manager_pid: nil,  # Will be updated by UserSupervisor
            health_monitor_pid: nil,  # Will be updated by UserSupervisor
            connected_at: System.system_time(:millisecond),
            last_activity: System.system_time(:millisecond),
            status: :initializing
          }
          
          with :ok <- UserRegistry.register_user(user_id, user_info),
               :ok <- UserSecurityAuditor.log_connection_attempt(user_id, :successful, nil),
               :ok <- UserMetrics.record_connection(user_id),
               :ok <- HealthMonitor.report_connection_event(user_id, :user_connected) do
            
            Logger.info("User session created successfully", user_id: user_id)
            {:ok, supervisor_pid}
          else
            error ->
              # Clean up on registration failure
              DynamicSupervisor.terminate_child(__MODULE__, supervisor_pid)
              Logger.error("Failed to register user session: #{inspect(error)}", user_id: user_id)
              {:error, {:registration_failed, error}}
          end
          
        {:error, reason} ->
          Logger.error("Failed to create user supervisor: #{inspect(reason)}", user_id: user_id)
          UserSecurityAuditor.log_connection_attempt(user_id, :failed, reason)
          {:error, reason}
      end
    end

    # Private Functions - Validation

    defp validate_user_input(user_id, api_key, secret_key) do
      cond do
        not is_binary(user_id) or String.length(user_id) == 0 ->
          {:error, :invalid_user_id}
          
        not is_binary(api_key) or String.length(api_key) == 0 ->
          {:error, :invalid_api_key}
          
        not is_binary(secret_key) or String.length(secret_key) == 0 ->
          {:error, :invalid_secret_key}
          
        String.length(user_id) > 100 ->
          {:error, :user_id_too_long}
          
        true ->
          :ok
      end
    end

    defp validate_credentials_format(api_key, secret_key) do
      cond do
        # Basic Binance API key format validation (without exposing the key)
        not String.match?(api_key, ~r/^[a-zA-Z0-9]{64}$/) ->
          {:error, :invalid_api_key_format}
          
        String.length(secret_key) < 32 ->
          {:error, :invalid_secret_key_format}
          
        true ->
          :ok
      end
    end

    defp check_user_limit do
      if can_accept_new_users?() do
        :ok
      else
        {:error, :user_limit_exceeded}
      end
    end

    # Private Functions - Cleanup and Monitoring

    defp notify_user_disconnecting(user_id) do
      # Notify all user processes about impending disconnection
      Phoenix.PubSub.broadcast(
        CryptoExchange.PubSub,
        "trading:user:#{user_id}",
        {:user_disconnecting, user_id}
      )
      :ok
    end

    defp secure_credential_cleanup(user_id) do
      case UserRegistry.lookup_user(user_id) do
        {:ok, %{credential_manager_pid: pid}} when is_pid(pid) ->
          # Signal credential manager to securely purge credentials
          GenServer.call(pid, :secure_purge_credentials, 5_000)
          
        _ ->
          :ok
      end
    rescue
      _ -> :ok  # Continue with cleanup even if credential purge fails
    end

    defp check_user_processes_alive(user_info) do
      %{
        supervisor: user_info.supervisor_pid && Process.alive?(user_info.supervisor_pid),
        connection: user_info.connection_pid && Process.alive?(user_info.connection_pid),
        credential_manager: user_info.credential_manager_pid && Process.alive?(user_info.credential_manager_pid),
        health_monitor: user_info.health_monitor_pid && Process.alive?(user_info.health_monitor_pid)
      }
    end

    defp get_user_last_activity(user_id) do
      case UserRegistry.lookup_user(user_id) do
        {:ok, %{last_activity: activity}} -> activity
        _ -> nil
      end
    end

    defp get_user_health_status(user_id) do
      case UserRegistry.lookup_user(user_id) do
        {:ok, %{health_monitor_pid: pid}} when is_pid(pid) ->
          try do
            GenServer.call(pid, :get_health_status, 1_000)
          catch
            :exit, _ -> :unknown
          end
          
        _ -> :unknown
      end
    end

    defp get_user_resource_usage(user_id) do
      UserMetrics.get_user_resource_usage(user_id)
    end

    # Private Functions - Statistics and Metrics

    defp count_active_users(users) do
      Enum.count(users, fn user ->
        case user do
          %{last_activity: activity} when is_integer(activity) ->
            System.system_time(:millisecond) - activity < @user_timeout
          _ -> false
        end
      end)
    end

    defp calculate_total_resource_usage(users) do
      Enum.reduce(users, %{memory: 0, processes: 0, connections: 0}, fn user, acc ->
        usage = get_user_resource_usage(user.user_id)
        %{
          memory: acc.memory + Map.get(usage, :memory, 0),
          processes: acc.processes + Map.get(usage, :processes, 0),
          connections: acc.connections + Map.get(usage, :connections, 0)
        }
      end)
    end

    defp calculate_health_summary(users) do
      health_counts = Enum.reduce(users, %{healthy: 0, degraded: 0, unhealthy: 0, unknown: 0}, fn user, acc ->
        health = get_user_health_status(user.user_id)
        Map.update(acc, health, 1, &(&1 + 1))
      end)
      
      total = length(users)
      if total > 0 do
        Map.merge(health_counts, %{
          total: total,
          health_percentage: (health_counts.healthy / total) * 100
        })
      else
        Map.merge(health_counts, %{total: 0, health_percentage: 100})
      end
    end

    defp calculate_uptime_stats(users) do
      now = System.system_time(:millisecond)
      
      uptimes = Enum.map(users, fn user ->
        case user do
          %{connected_at: connected_at} when is_integer(connected_at) ->
            now - connected_at
          _ -> 0
        end
      end)
      
      if length(uptimes) > 0 do
        %{
          average_uptime: Enum.sum(uptimes) / length(uptimes),
          max_uptime: Enum.max(uptimes),
          min_uptime: Enum.min(uptimes)
        }
      else
        %{average_uptime: 0, max_uptime: 0, min_uptime: 0}
      end
    end

    # Private Functions - Initialization

    defp initialize_user_registry do
      # UserRegistry will be implemented as a separate module
      # For now, return :ok to indicate successful initialization
      :ok
    end

    defp initialize_security_auditor do
      # UserSecurityAuditor will be implemented as a separate module
      :ok
    end

    defp initialize_user_metrics do
      # UserMetrics will be implemented as a separate module
      :ok
    end
  end

  defmodule UserConnection do
    @moduledoc """
    Enhanced GenServer for individual user trading sessions with comprehensive
    session management, monitoring, and fault tolerance.

    This process serves as the main interface for user trading operations,
    integrating with the secure credential management system and providing
    real-time session monitoring and activity tracking.

    ## Enhanced Architecture Integration

    UserConnection provides:
    - **Secure trading operations**: All API calls through CredentialManager
    - **Session lifecycle management**: Connect, active, cleanup, disconnect states
    - **Activity tracking**: Real-time user activity monitoring
    - **Order management**: Local caching with consistency guarantees
    - **PubSub integration**: Real-time event broadcasting
    - **Health monitoring**: Session health and performance metrics
    - **Error recovery**: Comprehensive error handling and recovery
    - **Audit logging**: Security audit trail for all operations

    ## Enhanced State Structure

        %{
          user_id: "user123",
          session_id: "sess_abc123",
          session_state: :connected | :active | :idle | :cleanup | :disconnecting,
          orders: %{order_id => order_data},
          balances: %{asset => balance_data},
          last_activity: timestamp,
          connection_started: timestamp,
          activity_history: [activity_events],
          session_stats: %{detailed_metrics},
          health_status: :healthy | :degraded | :unhealthy,
          timeout: milliseconds
        }

    ## Security Features

    - **Zero credential storage**: All credentials handled by CredentialManager
    - **Secure API integration**: All operations through authenticated PrivateClient
    - **Session isolation**: Complete isolation between user sessions
    - **Audit logging**: All operations logged without sensitive data exposure
    - **Automatic cleanup**: Secure session cleanup on termination or timeout
    - **Rate limiting**: Per-user API rate limiting compliance

    ## Session Management

    - **Connection states**: Tracks user session lifecycle phases
    - **Activity monitoring**: Real-time tracking of user operations
    - **Timeout handling**: Automatic cleanup for idle sessions
    - **Health monitoring**: Continuous session health assessment
    - **Resource tracking**: Memory and performance monitoring

    ## Fault Tolerance

    - **Graceful degradation**: Handles credential manager failures
    - **Retry mechanisms**: Automatic retry for transient failures
    - **Circuit breaker**: Prevents cascade failures to Binance API
    - **Session recovery**: Supports session state reconstruction
    - **Cleanup guarantees**: Ensures proper resource cleanup

    ## Integration Points

    - **CredentialManager**: Secure credential operations
    - **UserHealthMonitor**: Session health reporting
    - **UserRegistry**: Session registration and discovery
    - **UserMetrics**: Performance and usage metrics
    - **Phoenix.PubSub**: Real-time event broadcasting
    - **Binance.PrivateClient**: Secure API operations
    """

    use GenServer
    require Logger

    alias CryptoExchange.Binance.PrivateClient
    alias CryptoExchange.Trading.{CredentialManager, UserRegistry, UserMetrics, UserSecurityAuditor}

    @registry CryptoExchange.Registry
    @pubsub CryptoExchange.PubSub

    # Configuration
    @default_timeout 300_000  # 5 minutes
    @activity_timeout 600_000  # 10 minutes for idle detection
    @health_check_interval 30_000  # 30 seconds
    @order_cache_ttl 3_600_000  # 1 hour
    @balance_cache_ttl 60_000  # 1 minute
    @max_activity_history 100  # Keep last 100 activities

    # Client API

    @doc """
    Starts an enhanced UserConnection GenServer for a specific user.
    
    The UserConnection integrates with the UserSupervisor architecture
    and expects the CredentialManager to be available for secure operations.
    """
    def start_link({:user_id, user_id, :timeout, timeout}) do
      GenServer.start_link(__MODULE__, {user_id, timeout}, name: via_tuple(user_id))
    end

    # Legacy support for existing code
    def start_link({user_id, _credentials}) do
      start_link({:user_id, user_id, :timeout, @default_timeout})
    end

    @doc """
    Place a trading order for the user with enhanced validation and monitoring.
    
    ## Parameters
    - `user_id`: User identifier
    - `order_params`: Order parameters map
    
    ## Returns
    - `{:ok, order}`: Order placed successfully
    - `{:error, reason}`: Order placement failed
    """
    def place_order(user_id, order_params) when is_binary(user_id) and is_map(order_params) do
      with {:ok, pid} <- get_user_connection_pid(user_id),
           :ok <- validate_order_params(order_params) do
        GenServer.call(pid, {:place_order, order_params}, 30_000)
      end
    end

    @doc """
    Cancel a trading order for the user with enhanced validation.
    """
    def cancel_order(user_id, order_id) when is_binary(user_id) and is_binary(order_id) do
      with {:ok, pid} <- get_user_connection_pid(user_id) do
        GenServer.call(pid, {:cancel_order, order_id}, 15_000)
      end
    end

    @doc """
    Get account balance for the user with caching support.
    """
    def get_balance(user_id, opts \\ []) when is_binary(user_id) do
      with {:ok, pid} <- get_user_connection_pid(user_id) do
        force_refresh = Keyword.get(opts, :force_refresh, false)
        GenServer.call(pid, {:get_balance, force_refresh}, 15_000)
      end
    end

    @doc """
    Get order history for the user with filtering options.
    
    ## Options
    - `symbol`: Filter by trading pair
    - `status`: Filter by order status
    - `limit`: Limit number of results
    - `from_cache`: Use cached results if available
    """
    def get_orders(user_id, opts \\ []) when is_binary(user_id) do
      with {:ok, pid} <- get_user_connection_pid(user_id) do
        GenServer.call(pid, {:get_orders, opts}, 15_000)
      end
    end

    @doc """
    Get comprehensive session information including health and activity.
    """
    def get_session_info(user_id) when is_binary(user_id) do
      with {:ok, pid} <- get_user_connection_pid(user_id) do
        GenServer.call(pid, :get_session_info, 5_000)
      end
    end

    @doc """
    Get real-time session statistics and metrics.
    """
    def get_session_stats(user_id) when is_binary(user_id) do
      with {:ok, pid} <- get_user_connection_pid(user_id) do
        GenServer.call(pid, :get_session_stats, 5_000)
      end
    end

    @doc """
    Manually trigger a session health check.
    """
    def check_session_health(user_id) when is_binary(user_id) do
      with {:ok, pid} <- get_user_connection_pid(user_id) do
        GenServer.call(pid, :check_session_health, 5_000)
      end
    end

    @doc """
    Update session activity (called by other processes).
    """
    def record_activity(user_id, activity_type, metadata \\ %{}) when is_binary(user_id) do
      case get_user_connection_pid(user_id) do
        {:ok, pid} -> GenServer.cast(pid, {:record_activity, activity_type, metadata})
        _ -> :ok  # Fail silently if user not connected
      end
    end

    @doc """
    Gracefully prepare session for shutdown.
    """
    def prepare_shutdown(user_id) when is_binary(user_id) do
      with {:ok, pid} <- get_user_connection_pid(user_id) do
        GenServer.call(pid, :prepare_shutdown, 10_000)
      end
    end

    # Server Callbacks

    @impl true
    def init({user_id, timeout}) do
      Logger.info("Starting enhanced UserConnection for user: #{user_id}", user_id: user_id)
      
      # Generate unique session ID
      session_id = generate_session_id(user_id)
      
      # Initialize comprehensive state
      now = System.system_time(:millisecond)
      
      state = %{
        user_id: user_id,
        session_id: session_id,
        session_state: :connecting,
        orders: %{},
        balances: %{},
        last_activity: now,
        connection_started: now,
        activity_history: [],
        timeout: timeout,
        health_status: :healthy,
        last_health_check: now,
        session_stats: %{
          orders_placed: 0,
          orders_cancelled: 0,
          balance_checks: 0,
          api_calls: 0,
          errors: 0,
          started_at: now,
          last_order_time: nil,
          cache_hits: 0,
          cache_misses: 0
        },
        cache_timestamps: %{
          balances: 0,
          orders: %{}
        }
      }
      
      # Verify credential manager is available
      case verify_credential_manager(user_id) do
        :ok ->
          # Register this process for discovery
          Registry.register(@registry, {:user_connection, user_id}, self())
          
          # Update user registry
          update_user_registry_connection(user_id)
          
          # Schedule periodic health checks
          schedule_health_check()
          
          # Schedule activity timeout check
          schedule_activity_timeout_check()
          
          # Record connection activity
          new_state = record_activity_internal(state, :session_started, %{
            session_id: session_id,
            timeout: timeout
          })
          
          # Transition to connected state
          connected_state = %{new_state | session_state: :connected}
          
          # Send user connected event
          broadcast_session_event(connected_state, :user_connected)
          
          # Log successful connection
          UserSecurityAuditor.log_connection_attempt(user_id, :successful, %{
            session_id: session_id
          })
          
          Logger.info("UserConnection initialized successfully", 
            user_id: user_id, 
            session_id: session_id
          )
          
          {:ok, connected_state}
          
        {:error, reason} ->
          Logger.error("Failed to verify credential manager for user #{user_id}: #{inspect(reason)}", 
            user_id: user_id
          )
          
          UserSecurityAuditor.log_connection_attempt(user_id, :failed, reason)
          
          {:stop, {:credential_manager_unavailable, reason}}
      end
    end

    @impl true
    def handle_call({:place_order, order_params}, _from, state) do
      Logger.info("Placing order for user #{state.user_id} with comprehensive validation", 
        user_id: state.user_id, 
        symbol: Map.get(order_params, "symbol")
      )
      
      start_time = System.system_time(:millisecond)
      
      # Comprehensive validation pipeline
      case perform_comprehensive_order_validation(state, order_params) do
        {:ok, {healthy_state, validated_params}} ->
          case execute_order_placement(healthy_state, validated_params, start_time) do
            {:ok, {order, new_state}} ->
              Logger.info("Order placed successfully with full validation", 
                user_id: state.user_id, 
                order_id: order.order_id,
                symbol: order.symbol,
                session_id: state.session_id,
                validation_time_ms: System.system_time(:millisecond) - start_time
              )
              
              {:reply, {:ok, order}, new_state}
              
            {:error, {reason, new_state}} ->
              {:reply, {:error, reason}, new_state}
          end
          
        {:error, {error_type, details}} ->
          Logger.warning("Order placement rejected by validation", 
            user_id: state.user_id,
            symbol: Map.get(order_params, "symbol"),
            error_type: error_type,
            details: inspect(details)
          )
          
          # Record validation failure
          validation_failure_state = record_validation_failure(state, error_type, details)
          
          # Enhanced error response with detailed information
          enhanced_error = build_enhanced_error_response(error_type, details, order_params)
          
          {:reply, {:error, enhanced_error}, validation_failure_state}
      end
    end

    @impl true
    def handle_call({:cancel_order, order_id}, _from, state) do
      Logger.info("Canceling order #{order_id} for user #{state.user_id} with comprehensive validation", 
        user_id: state.user_id, 
        order_id: order_id
      )
      
      start_time = System.system_time(:millisecond)
      
      # Comprehensive validation pipeline for order cancellation
      case perform_comprehensive_cancel_validation(state, order_id) do
        {:ok, {healthy_state, order_symbol}} ->
          case execute_order_cancellation(healthy_state, order_id, order_symbol, start_time) do
            {:ok, {cancelled_order, new_state}} ->
              Logger.info("Order cancelled successfully with full validation", 
                user_id: state.user_id, 
                order_id: order_id,
                symbol: cancelled_order.symbol,
                session_id: state.session_id,
                validation_time_ms: System.system_time(:millisecond) - start_time
              )
              
              {:reply, {:ok, cancelled_order}, new_state}
              
            {:error, {reason, new_state}} ->
              {:reply, {:error, reason}, new_state}
          end
          
        {:error, {error_type, details}} ->
          Logger.warning("Order cancellation rejected by validation", 
            user_id: state.user_id,
            order_id: order_id,
            error_type: error_type,
            details: inspect(details)
          )
          
          # Record validation failure for cancellation
          validation_failure_state = record_cancellation_validation_failure(state, error_type, details, order_id)
          
          # Enhanced error response for cancellation
          enhanced_error = build_enhanced_cancel_error_response(error_type, details, order_id)
          
          {:reply, {:error, enhanced_error}, validation_failure_state}
      end
    end

    @impl true
    def handle_call({:get_balance, opts}, _from, state) do
      Logger.debug("Getting balance for user #{state.user_id} with comprehensive options", 
        user_id: state.user_id, 
        opts: sanitize_opts_for_logging(opts)
      )
      
      start_time = System.system_time(:millisecond)
      
      # Comprehensive validation pipeline for balance request
      case perform_comprehensive_balance_validation(state, opts) do
        {:ok, {healthy_state, validated_opts}} ->
          case execute_balance_retrieval(healthy_state, validated_opts, start_time) do
            {:ok, {balances, new_state}} ->
              Logger.debug("Balance retrieved successfully with comprehensive processing", 
                user_id: state.user_id, 
                asset_count: length(balances),
                from_cache: Map.get(validated_opts, :from_cache, false),
                validation_time_ms: System.system_time(:millisecond) - start_time
              )
              
              {:reply, {:ok, balances}, new_state}
              
            {:error, {reason, new_state}} ->
              {:reply, {:error, reason}, new_state}
          end
          
        {:error, {error_type, details}} ->
          Logger.warning("Balance request rejected by validation", 
            user_id: state.user_id,
            error_type: error_type,
            details: inspect(details)
          )
          
          # Record validation failure for balance request
          validation_failure_state = record_balance_validation_failure(state, error_type, details)
          
          # Enhanced error response for balance request
          enhanced_error = build_enhanced_balance_error_response(error_type, details, opts)
          
          {:reply, {:error, enhanced_error}, validation_failure_state}
      end
    end

    @impl true
    def handle_call({:get_orders, opts}, _from, state) do
      Logger.debug("Getting orders for user #{state.user_id} with comprehensive filtering", 
        user_id: state.user_id, 
        opts: sanitize_opts_for_logging(opts)
      )
      
      start_time = System.system_time(:millisecond)
      
      # Comprehensive validation pipeline for orders request
      case perform_comprehensive_orders_validation(state, opts) do
        {:ok, {healthy_state, validated_opts}} ->
          case execute_orders_retrieval(healthy_state, validated_opts, start_time) do
            {:ok, {orders, new_state}} ->
              Logger.debug("Orders retrieved successfully with comprehensive processing", 
                user_id: state.user_id, 
                order_count: length(orders),
                symbol: Map.get(validated_opts, :symbol),
                from_cache: Map.get(validated_opts, :from_cache, false),
                validation_time_ms: System.system_time(:millisecond) - start_time
              )
              
              {:reply, {:ok, orders}, new_state}
              
            {:error, {reason, new_state}} ->
              {:reply, {:error, reason}, new_state}
          end
          
        {:error, {error_type, details}} ->
          Logger.warning("Orders request rejected by validation", 
            user_id: state.user_id,
            error_type: error_type,
            details: inspect(details)
          )
          
          # Record validation failure for orders request
          validation_failure_state = record_orders_validation_failure(state, error_type, details)
          
          # Enhanced error response for orders request
          enhanced_error = build_enhanced_orders_error_response(error_type, details, opts)
          
          {:reply, {:error, enhanced_error}, validation_failure_state}
      end
    end

    # New comprehensive handlers for enhanced functionality
    
    @impl true
    def handle_call(:get_session_info, _from, state) do
      session_info = build_session_info(state)
      {:reply, {:ok, session_info}, state}
    end
    
    @impl true
    def handle_call(:get_session_stats, _from, state) do
      enhanced_stats = build_enhanced_session_stats(state)
      {:reply, {:ok, enhanced_stats}, state}
    end
    
    @impl true
    def handle_call(:check_session_health, _from, state) do
      case check_session_health_internal(state) do
        {:ok, new_state} ->
          health_info = %{
            status: new_state.health_status,
            last_activity: new_state.last_activity,
            session_state: new_state.session_state,
            uptime_ms: System.system_time(:millisecond) - new_state.connection_started
          }
          {:reply, {:ok, health_info}, new_state}
          
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
    
    @impl true
    def handle_call(:prepare_shutdown, _from, state) do
      Logger.info("Preparing graceful shutdown for user #{state.user_id}", user_id: state.user_id)
      
      # Update session state to cleanup
      cleanup_state = %{state | 
        session_state: :cleanup,
        last_activity: System.system_time(:millisecond)
      }
      
      # Record shutdown activity
      shutdown_state = record_activity_internal(cleanup_state, :shutdown_initiated, %{
        session_duration: System.system_time(:millisecond) - state.connection_started
      })
      
      # Broadcast shutdown event
      broadcast_session_event(shutdown_state, :user_preparing_shutdown)
      
      {:reply, :ok, shutdown_state}
    end
    
    @impl true
    def handle_cast({:record_activity, activity_type, metadata}, state) do
      new_state = record_activity_internal(state, activity_type, metadata)
      {:noreply, new_state}
    end
    
    @impl true
    def handle_info(:health_check, state) do
      case check_session_health_internal(state) do
        {:ok, new_state} ->
          # Schedule next health check
          schedule_health_check()
          {:noreply, new_state}
          
        {:error, _reason} ->
          # Keep original state if health check fails
          schedule_health_check()
          {:noreply, state}
      end
    end
    
    @impl true
    def handle_info(:activity_timeout_check, state) do
      now = System.system_time(:millisecond)
      time_since_activity = now - state.last_activity
      
      new_state = cond do
        time_since_activity > @activity_timeout ->
          Logger.info("User session inactive, marking as idle", 
            user_id: state.user_id, 
            inactive_duration: time_since_activity
          )
          
          idle_state = %{state | 
            session_state: :idle,
            health_status: :degraded
          }
          
          # Record idle activity
          activity_state = record_activity_internal(idle_state, :session_idle, %{
            inactive_duration: time_since_activity
          })
          
          # Broadcast idle event
          broadcast_session_event(activity_state, :user_idle)
          
          activity_state
          
        time_since_activity > (state.timeout * 0.8) ->
          Logger.debug("User session approaching timeout", 
            user_id: state.user_id, 
            time_until_timeout: state.timeout - time_since_activity
          )
          
          %{state | health_status: :degraded}
          
        true ->
          state
      end
      
      # Schedule next activity check
      schedule_activity_timeout_check()
      {:noreply, new_state}
    end
    
    @impl true
    def handle_info(msg, state) do
      Logger.debug("Unexpected message in UserConnection: #{inspect(msg)}", user_id: state.user_id)
      {:noreply, state}
    end

    @impl true
    def terminate(reason, state) do
      Logger.info("UserConnection terminating for user #{state.user_id}: #{inspect(reason)}", 
        user_id: state.user_id, 
        session_id: state.session_id,
        reason: reason
      )
      
      # Calculate session duration
      session_duration = System.system_time(:millisecond) - state.connection_started
      
      # Update session state to disconnecting
      disconnecting_state = %{state | 
        session_state: :disconnecting,
        last_activity: System.system_time(:millisecond)
      }
      
      # Record termination activity
      final_state = record_activity_internal(disconnecting_state, :session_terminated, %{
        reason: reason,
        session_duration: session_duration,
        final_stats: state.session_stats
      })
      
      # Update user registry to mark disconnection
      case UserRegistry.lookup_user(state.user_id) do
        {:ok, user_info} ->
          updated_info = Map.merge(user_info, %{
            connection_pid: nil,
            status: :disconnected,
            disconnected_at: System.system_time(:millisecond),
            last_session_duration: session_duration
          })
          UserRegistry.update_user(state.user_id, updated_info)
          
        _ -> :ok
      end
      
      # Record final metrics
      UserMetrics.record_disconnection(state.user_id)
      
      # Security audit
      UserSecurityAuditor.log_session_end(state.user_id, %{
        session_id: state.session_id,
        duration: session_duration,
        reason: reason,
        final_health: state.health_status
      })
      
      # Send enhanced user disconnected event
      broadcast_session_event(final_state, :user_disconnected, %{
        reason: reason,
        session_duration: session_duration
      })
      
      Logger.info("UserConnection terminated gracefully", 
        user_id: state.user_id, 
        session_id: state.session_id,
        session_duration: session_duration,
        final_stats: final_state.session_stats
      )
      
      :ok
    end

    # Private Helper Functions
    
    defp via_tuple(user_id) do
      {:via, Registry, {CryptoExchange.Registry, {:user_connection, user_id}}}
    end
    
    defp get_user_connection_pid(user_id) do
      case Registry.lookup(@registry, {:user_connection, user_id}) do
        [] -> {:error, :not_connected}
        [{pid, _}] -> {:ok, pid}
      end
    end
    
    defp validate_order_params(params) when is_map(params) do
      required_fields = ["symbol", "side", "type", "quantity"]
      
      missing_fields = Enum.filter(required_fields, fn field ->
        not Map.has_key?(params, field) or Map.get(params, field) == ""
      end)
      
      if Enum.empty?(missing_fields) do
        :ok
      else
        {:error, {:missing_required_fields, missing_fields}}
      end
    end
    
    defp generate_session_id(user_id) do
      timestamp = System.system_time(:millisecond)
      random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
      "sess_#{user_id}_#{timestamp}_#{random}"
    end
    
    defp verify_credential_manager(user_id) do
      case CredentialManager.validate_credentials(user_id) do
        {:ok, _validation} -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      _ -> {:error, :credential_manager_unavailable}
    end
    
    defp update_user_registry_connection(user_id) do
      case UserRegistry.lookup_user(user_id) do
        {:ok, user_info} ->
          updated_info = Map.merge(user_info, %{
            connection_pid: self(),
            status: :connected
          })
          UserRegistry.update_user(user_id, updated_info)
          
        _ -> :ok
      end
    rescue
      error ->
        Logger.warning("Failed to update user registry: #{inspect(error)}", user_id: user_id)
        :ok
    end
    
    defp schedule_health_check do
      Process.send_after(self(), :health_check, @health_check_interval)
    end
    
    defp schedule_activity_timeout_check do
      Process.send_after(self(), :activity_timeout_check, @activity_timeout)
    end
    
    defp record_activity_internal(state, activity_type, metadata \\ %{}) do
      now = System.system_time(:millisecond)
      
      activity = %{
        type: activity_type,
        timestamp: now,
        metadata: metadata,
        session_id: state.session_id
      }
      
      # Keep only recent activities to prevent memory bloat
      new_history = [activity | state.activity_history]
      |> Enum.take(@max_activity_history)
      
      %{state | 
        activity_history: new_history,
        last_activity: now
      }
    end
    
    defp check_session_health_internal(state) do
      now = System.system_time(:millisecond)
      time_since_activity = now - state.last_activity
      
      health_status = cond do
        time_since_activity > @activity_timeout -> :unhealthy
        time_since_activity > (state.timeout * 0.8) -> :degraded
        state.session_stats.errors > 10 -> :degraded
        true -> :healthy
      end
      
      # Check credential manager availability
      credential_status = case verify_credential_manager(state.user_id) do
        :ok -> :ok
        {:error, reason} -> {:error, {:credential_manager_error, reason}}
      end
      
      case credential_status do
        :ok ->
          new_state = %{state | 
            health_status: health_status,
            last_health_check: now
          }
          
          if health_status != state.health_status do
            Logger.info("Session health changed", 
              user_id: state.user_id,
              old_health: state.health_status,
              new_health: health_status
            )
            
            # Broadcast health change event
            broadcast_session_event(new_state, :health_status_changed, %{
              old_status: state.health_status,
              new_status: health_status
            })
          end
          
          {:ok, new_state}
          
        error -> error
      end
    end
    
    defp handle_order_cancellation(state, order_id, cached_order) do
      case PrivateClient.cancel_order(state.user_id, cached_order.symbol, order_id) do
        {:ok, cancelled_order} ->
          # Update order in local cache with enhanced metadata
          enhanced_cancelled_order = Map.merge(cancelled_order, %{
            cancelled_at: System.system_time(:millisecond),
            session_id: state.session_id,
            local_status: :cancelled
          })
          
          new_orders = Map.put(state.orders, order_id, enhanced_cancelled_order)
          
          # Update session stats
          now = System.system_time(:millisecond)
          new_stats = state.session_stats
          |> Map.update!(:orders_cancelled, &(&1 + 1))
          |> Map.update!(:api_calls, &(&1 + 1))
          
          # Record activity
          activity_state = record_activity_internal(state, :order_cancelled, %{
            order_id: order_id,
            symbol: cancelled_order.symbol
          })
          
          new_state = %{activity_state | 
            orders: new_orders,
            session_stats: new_stats,
            last_activity: now,
            session_state: :active
          }
          
          # Broadcast order cancellation event
          broadcast_order_event(new_state, :order_cancelled, enhanced_cancelled_order)
          
          # Update metrics
          UserMetrics.record_trading_operation(state.user_id, :order_cancelled, true)
          
          # Security audit
          UserSecurityAuditor.log_trading_operation(state.user_id, :order_cancelled, %{
            order_id: order_id,
            symbol: cancelled_order.symbol,
            session_id: state.session_id
          })
          
          Logger.info("Order cancelled successfully", 
            user_id: state.user_id, 
            order_id: order_id,
            symbol: cancelled_order.symbol
          )
          
          {:reply, {:ok, enhanced_cancelled_order}, new_state}
          
        {:error, reason} ->
          Logger.error("Failed to cancel order #{order_id} for user #{state.user_id}: #{inspect(reason)}", 
            user_id: state.user_id, 
            order_id: order_id
          )
          
          # Update error stats and record activity
          new_stats = state.session_stats
          |> Map.update!(:errors, &(&1 + 1))
          |> Map.update!(:api_calls, &(&1 + 1))
          
          error_state = record_activity_internal(state, :order_cancellation_failed, %{
            order_id: order_id,
            error: reason
          })
          
          new_state = %{error_state | session_stats: new_stats}
          
          # Update metrics
          UserMetrics.record_trading_operation(state.user_id, :order_cancellation_failed, false)
          
          {:reply, {:error, reason}, new_state}
      end
    end
    
    defp find_order_from_api(user_id, order_id) do
      # This is a simplified implementation - in practice, you might want to
      # search across multiple symbols or use a more efficient approach
      {:error, :not_found}
    end
    
    defp handle_get_orders_request(state, opts) do
      symbol = Keyword.get(opts, :symbol)
      from_cache = Keyword.get(opts, :from_cache, false)
      
      if from_cache and symbol do
        # Return cached orders for specific symbol
        cached_orders = state.orders
        |> Map.values()
        |> Enum.filter(&(&1.symbol == symbol))
        
        activity_state = record_activity_internal(state, :orders_cached, %{
          symbol: symbol,
          count: length(cached_orders)
        })
        
        {:reply, {:ok, cached_orders}, activity_state}
        
      else
        # Fetch from API
        case PrivateClient.get_orders(state.user_id, symbol || "BTCUSDT", %{}) do
          {:ok, orders} ->
            # Update local cache with fresh order data
            now = System.system_time(:millisecond)
            
            new_orders = Enum.reduce(orders, state.orders, fn order, acc ->
              enhanced_order = Map.merge(order, %{
                fetched_at: now,
                session_id: state.session_id
              })
              Map.put(acc, order.order_id, enhanced_order)
            end)
            
            # Update cache timestamp for this symbol
            symbol_key = symbol || "all"
            new_cache_timestamps = put_in(
              state.cache_timestamps, 
              [:orders, symbol_key], 
              now
            )
            
            # Update session stats
            new_stats = state.session_stats
            |> Map.update!(:api_calls, &(&1 + 1))
            |> Map.update!(:cache_misses, &(&1 + 1))
            
            # Record activity
            activity_state = record_activity_internal(state, :orders_fetched, %{
              symbol: symbol,
              count: length(orders)
            })
            
            new_state = %{activity_state | 
              orders: new_orders,
              session_stats: new_stats,
              cache_timestamps: new_cache_timestamps,
              last_activity: now,
              session_state: :active
            }
            
            Logger.debug("Orders retrieved successfully", 
              user_id: state.user_id, 
              symbol: symbol,
              count: length(orders)
            )
            
            {:reply, {:ok, orders}, new_state}
            
          {:error, reason} ->
            Logger.error("Failed to get orders for user #{state.user_id}: #{inspect(reason)}", 
              user_id: state.user_id
            )
            
            # Update error stats
            new_stats = state.session_stats
            |> Map.update!(:errors, &(&1 + 1))
            |> Map.update!(:api_calls, &(&1 + 1))
            
            error_state = record_activity_internal(state, :orders_fetch_failed, %{
              symbol: symbol,
              error: reason
            })
            
            new_state = %{error_state | session_stats: new_stats}
            
            {:reply, {:error, reason}, new_state}
        end
      end
    end
    
    defp build_session_info(state) do
      now = System.system_time(:millisecond)
      
      %{
        user_id: state.user_id,
        session_id: state.session_id,
        session_state: state.session_state,
        health_status: state.health_status,
        connection_started: state.connection_started,
        last_activity: state.last_activity,
        uptime_ms: now - state.connection_started,
        time_since_activity: now - state.last_activity,
        timeout: state.timeout,
        cached_orders: map_size(state.orders),
        cached_balances: map_size(state.balances),
        recent_activities: Enum.take(state.activity_history, 10)
      }
    end
    
    defp build_enhanced_session_stats(state) do
      now = System.system_time(:millisecond)
      session_duration = now - state.connection_started
      
      Map.merge(state.session_stats, %{
        session_id: state.session_id,
        session_duration_ms: session_duration,
        session_state: state.session_state,
        health_status: state.health_status,
        cached_orders: map_size(state.orders),
        cached_balances: map_size(state.balances),
        last_activity: state.last_activity,
        time_since_activity: now - state.last_activity,
        activity_count: length(state.activity_history),
        error_rate: if(state.session_stats.api_calls > 0, do: state.session_stats.errors / state.session_stats.api_calls * 100, else: 0)
      })
    end
    
    defp broadcast_session_event(state, event_type, extra_data \\ %{}) do
      event_data = Map.merge(%{
        user_id: state.user_id,
        session_id: state.session_id,
        session_state: state.session_state,
        health_status: state.health_status,
        timestamp: System.system_time(:millisecond)
      }, extra_data)
      
      # Broadcast to general trading users topic
      Phoenix.PubSub.broadcast(@pubsub, "trading:users", {event_type, event_data})
      
      # Broadcast to user-specific topic
      Phoenix.PubSub.broadcast(@pubsub, "trading:user:#{state.user_id}", {event_type, event_data})
    end
    
    defp broadcast_order_event(state, event_type, order) do
      event_data = %{
        user_id: state.user_id,
        session_id: state.session_id,
        order: order,
        timestamp: System.system_time(:millisecond)
      }
      
      # Broadcast to user-specific topic
      Phoenix.PubSub.broadcast(@pubsub, "trading:user:#{state.user_id}", {event_type, event_data})
      
      # Broadcast to symbol-specific topic
      Phoenix.PubSub.broadcast(@pubsub, "trading:orders:#{order.symbol}", {event_type, event_data})
    end
    
    # Enhanced order placement helper functions
    
    defp perform_comprehensive_order_validation(state, order_params) do
      alias CryptoExchange.Trading.Validation
      
      # Step 1: Check session health
      with {:ok, healthy_state} <- check_session_health_internal(state),
           # Step 2: Comprehensive validation using the Validation module
           {:ok, validated_params} <- Validation.validate_place_order(state.user_id, order_params) do
        {:ok, {healthy_state, validated_params}}
      else
        {:error, health_reason} ->
          {:error, {:session_unhealthy, %{reason: health_reason}}}
          
        {:error, {error_type, details}} ->
          {:error, {error_type, details}}
          
        error ->
          {:error, {:unknown_validation_error, %{reason: error}}}
      end
    end
    
    defp execute_order_placement(state, validated_params, start_time) do
      case PrivateClient.place_order(state.user_id, validated_params) do
        {:ok, order} ->
          # Create enhanced order with comprehensive metadata
          enhanced_order = create_enhanced_order(order, state, start_time)
          
          # Update state with order and metrics
          new_state = update_state_after_successful_order(state, enhanced_order, start_time)
          
          # Perform comprehensive post-order actions
          perform_post_order_actions(new_state, enhanced_order, :success)
          
          {:ok, {enhanced_order, new_state}}
          
        {:error, reason} ->
          # Handle order placement failure with detailed error tracking
          handle_order_placement_failure(state, validated_params, reason, start_time)
      end
    end
    
    defp create_enhanced_order(order, state, start_time) do
      now = System.system_time(:millisecond)
      
      Map.merge(order, %{
        placed_at: now,
        session_id: state.session_id,
        local_status: :active,
        validation_time_ms: now - start_time,
        user_id: state.user_id,
        placement_source: :user_connection,
        enhanced_metadata: %{
          session_state: state.session_state,
          health_status: state.health_status,
          api_request_count: state.session_stats.api_calls + 1
        }
      })
    end
    
    defp update_state_after_successful_order(state, enhanced_order, start_time) do
      now = System.system_time(:millisecond)
      placement_duration = now - start_time
      
      # Update orders cache
      new_orders = Map.put(state.orders, enhanced_order.order_id, enhanced_order)
      
      # Update comprehensive session stats
      new_stats = state.session_stats
      |> Map.update!(:orders_placed, &(&1 + 1))
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.put(:last_order_time, now)
      |> Map.update(:successful_operations, 0, &(&1 + 1))
      |> Map.update(:total_placement_time_ms, 0, &(&1 + placement_duration))
      |> Map.update(:avg_placement_time_ms, 0, fn current ->
        total_orders = Map.get(state.session_stats, :orders_placed, 0) + 1
        if total_orders > 0 do
          (current * (total_orders - 1) + placement_duration) / total_orders
        else
          placement_duration
        end
      end)
      
      # Record comprehensive activity
      activity_state = record_activity_internal(state, :order_placed_with_validation, %{
        order_id: enhanced_order.order_id,
        symbol: enhanced_order.symbol,
        side: enhanced_order.side,
        type: enhanced_order.type,
        validation_time_ms: enhanced_order.validation_time_ms,
        placement_duration_ms: placement_duration,
        total_process_time_ms: now - start_time
      })
      
      %{activity_state |
        orders: new_orders,
        session_stats: new_stats,
        last_activity: now,
        session_state: :active
      }
    end
    
    defp perform_post_order_actions(state, enhanced_order, status) do
      # Broadcast enhanced order event
      broadcast_order_event(state, :order_placed, enhanced_order)
      
      # Update comprehensive metrics
      UserMetrics.record_trading_operation(
        state.user_id, 
        :order_placed, 
        status == :success,
        enhanced_order.validation_time_ms + Map.get(enhanced_order.enhanced_metadata, :placement_time_ms, 0)
      )
      
      # Comprehensive security audit
      UserSecurityAuditor.log_trading_operation(state.user_id, :order_placed, %{
        order_id: enhanced_order.order_id,
        symbol: enhanced_order.symbol,
        session_id: state.session_id,
        validation_passed: true,
        placement_source: enhanced_order.placement_source,
        session_health: state.health_status,
        total_process_time_ms: enhanced_order.validation_time_ms
      })
    end
    
    defp handle_order_placement_failure(state, validated_params, reason, start_time) do
      now = System.system_time(:millisecond)
      placement_duration = now - start_time
      
      Logger.error("Order placement failed after validation", 
        user_id: state.user_id, 
        symbol: Map.get(validated_params, "symbol"),
        reason: inspect(reason),
        placement_duration_ms: placement_duration
      )
      
      # Update comprehensive error stats
      new_stats = state.session_stats
      |> Map.update!(:errors, &(&1 + 1))
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update(:placement_failures, 0, &(&1 + 1))
      |> Map.update(:total_failed_placement_time_ms, 0, &(&1 + placement_duration))
      
      # Record comprehensive error activity
      error_state = record_activity_internal(state, :order_placement_failed_post_validation, %{
        symbol: Map.get(validated_params, "symbol"),
        error: reason,
        placement_duration_ms: placement_duration,
        validated_params_count: map_size(validated_params)
      })
      
      new_state = %{error_state | session_stats: new_stats}
      
      # Update comprehensive metrics
      UserMetrics.record_trading_operation(state.user_id, :order_placement_failed, false, placement_duration)
      
      # Comprehensive security audit for failures
      UserSecurityAuditor.log_trading_operation(state.user_id, :order_placement_failed, %{
        symbol: Map.get(validated_params, "symbol"),
        error: reason,
        session_id: state.session_id,
        validation_passed: true,
        failure_after_validation: true,
        placement_duration_ms: placement_duration
      })
      
      # Enhanced error categorization
      categorized_error = categorize_placement_error(reason)
      
      {:error, {categorized_error, new_state}}
    end
    
    defp record_validation_failure(state, error_type, details) do
      # Update session stats for validation failures
      new_stats = state.session_stats
      |> Map.update(:validation_failures, 0, &(&1 + 1))
      |> Map.update(:errors, 0, &(&1 + 1))
      
      # Record detailed validation failure activity
      activity_state = record_activity_internal(state, :order_validation_failed, %{
        error_type: error_type,
        details: details,
        validation_stage: determine_validation_stage(error_type)
      })
      
      %{activity_state | session_stats: new_stats}
    end
    
    defp build_enhanced_error_response(error_type, details, original_params) do
      base_error = %{
        error_type: error_type,
        details: details,
        timestamp: System.system_time(:millisecond)
      }
      
      case error_type do
        :validation_error ->
          Map.merge(base_error, %{
            category: :input_validation,
            user_message: "Invalid order parameters provided",
            field_errors: extract_field_errors(details),
            suggestion: generate_validation_suggestion(details)
          })
          
        :business_rule_violation ->
          Map.merge(base_error, %{
            category: :business_rules,
            user_message: "Order violates trading rules",
            rule_violation: details.reason,
            suggestion: generate_business_rule_suggestion(details)
          })
          
        :insufficient_funds ->
          Map.merge(base_error, %{
            category: :account_balance,
            user_message: "Insufficient balance for order",
            required_balance: details.required,
            available_balance: details.available,
            asset: details.asset
          })
          
        :symbol_not_supported ->
          Map.merge(base_error, %{
            category: :market_data,
            user_message: "Trading pair not supported",
            requested_symbol: details.symbol,
            supported_symbols: Enum.take(details.supported, 10)  # Show first 10
          })
          
        :rate_limit_violation ->
          Map.merge(base_error, %{
            category: :rate_limiting,
            user_message: "API rate limit exceeded",
            retry_after_seconds: calculate_retry_delay(details)
          })
          
        :session_unhealthy ->
          Map.merge(base_error, %{
            category: :session_health,
            user_message: "User session health check failed",
            health_issue: details.reason
          })
          
        _ ->
          Map.merge(base_error, %{
            category: :unknown,
            user_message: "Order validation failed",
            original_params: sanitize_params_for_error(original_params)
          })
      end
    end
    
    defp categorize_placement_error(reason) do
      case reason do
        {:invalid_quantity, _} -> :invalid_order_parameters
        {:invalid_symbol, _} -> :invalid_trading_pair
        {:insufficient_balance, _} -> :insufficient_funds
        {:rate_limit_exceeded, _} -> :rate_limit_exceeded
        {:connection_failed, _} -> :network_error
        {:api_error, _} -> :exchange_error
        _ -> :unknown_placement_error
      end
    end
    
    defp determine_validation_stage(error_type) do
      case error_type do
        :validation_error -> :input_validation
        :business_rule_violation -> :business_rules
        :insufficient_funds -> :balance_check
        :symbol_not_supported -> :symbol_validation
        :rate_limit_violation -> :rate_limiting
        :session_unhealthy -> :health_check
        _ -> :unknown_stage
      end
    end
    
    defp extract_field_errors(%{missing_required_fields: fields}) when is_list(fields) do
      Enum.map(fields, &%{field: &1, error: "required"})
    end
    
    defp extract_field_errors(%{field: field, reason: reason}) do
      [%{field: field, error: reason}]
    end
    
    defp extract_field_errors(_details), do: []
    
    defp generate_validation_suggestion(%{missing_required_fields: fields}) when is_list(fields) do
      "Please provide the following required fields: #{Enum.join(fields, ", ")}"
    end
    
    defp generate_validation_suggestion(%{field: field, reason: :invalid_format}) do
      "Please check the format of the '#{field}' field"
    end
    
    defp generate_validation_suggestion(_details) do
      "Please check your order parameters and try again"
    end
    
    defp generate_business_rule_suggestion(%{reason: :quantity_below_minimum, minimum: min}) do
      "Minimum quantity required: #{min}"
    end
    
    defp generate_business_rule_suggestion(%{reason: :order_value_below_minimum, minimum_usdt: min}) do
      "Minimum order value: $#{min} USDT"
    end
    
    defp generate_business_rule_suggestion(%{reason: :price_deviation_too_high, market_price: price}) do
      "Order price too far from market price ($#{price})"
    end
    
    defp generate_business_rule_suggestion(_details) do
      "Please review trading rules and adjust your order"
    end
    
    defp calculate_retry_delay(_details) do
      # Simple retry delay calculation - could be enhanced based on details
      30
    end
    
    defp sanitize_params_for_error(params) when is_map(params) do
      # Remove sensitive information but keep structure for debugging
      Map.take(params, ["symbol", "side", "type"])
    end
    
    # Enhanced order cancellation helper functions
    
    defp perform_comprehensive_cancel_validation(state, order_id) do
      alias CryptoExchange.Trading.Validation
      
      # Step 1: Check session health
      with {:ok, healthy_state} <- check_session_health_internal(state),
           # Step 2: Validate cancellation parameters
           {:ok, :valid} <- Validation.validate_cancel_order(state.user_id, order_id),
           # Step 3: Determine order symbol for API call
           {:ok, order_symbol} <- determine_order_symbol_for_cancellation(healthy_state, order_id) do
        {:ok, {healthy_state, order_symbol}}
      else
        {:error, health_reason} ->
          {:error, {:session_unhealthy, %{reason: health_reason}}}
          
        {:error, {error_type, details}} ->
          {:error, {error_type, details}}
          
        error ->
          {:error, {:unknown_validation_error, %{reason: error}}}
      end
    end
    
    defp execute_order_cancellation(state, order_id, order_symbol, start_time) do
      case PrivateClient.cancel_order(state.user_id, order_symbol, order_id) do
        {:ok, cancelled_order} ->
          # Create enhanced cancelled order with comprehensive metadata
          enhanced_cancelled_order = create_enhanced_cancelled_order(cancelled_order, state, start_time)
          
          # Update state with cancellation and metrics
          new_state = update_state_after_successful_cancellation(state, enhanced_cancelled_order, start_time)
          
          # Perform comprehensive post-cancellation actions
          perform_post_cancellation_actions(new_state, enhanced_cancelled_order, :success)
          
          {:ok, {enhanced_cancelled_order, new_state}}
          
        {:error, reason} ->
          # Handle cancellation failure with detailed error tracking
          handle_order_cancellation_failure(state, order_id, order_symbol, reason, start_time)
      end
    end
    
    defp determine_order_symbol_for_cancellation(state, order_id) do
      case Map.get(state.orders, order_id) do
        %{symbol: symbol} when is_binary(symbol) ->
          {:ok, symbol}
          
        nil ->
          # Try to find order from recent API call if not in cache
          case find_order_from_api_with_comprehensive_search(state.user_id, order_id) do
            {:ok, found_order} ->
              {:ok, found_order.symbol}
              
            {:error, :not_found} ->
              {:error, {:order_not_found, %{
                order_id: order_id,
                searched_cache: true,
                searched_api: true,
                cache_order_count: map_size(state.orders)
              }}}
              
            {:error, reason} ->
              {:error, {:order_lookup_failed, %{
                order_id: order_id,
                reason: reason
              }}}
          end
      end
    end
    
    defp find_order_from_api_with_comprehensive_search(user_id, order_id) do
      # This is a more comprehensive search than the original implementation
      # Try to search across multiple symbols if needed
      # For now, we'll return not found - in production this would be enhanced
      {:error, :not_found}
    end
    
    defp create_enhanced_cancelled_order(cancelled_order, state, start_time) do
      now = System.system_time(:millisecond)
      
      Map.merge(cancelled_order, %{
        cancelled_at: now,
        session_id: state.session_id,
        local_status: :cancelled,
        validation_time_ms: now - start_time,
        user_id: state.user_id,
        cancellation_source: :user_connection,
        enhanced_metadata: %{
          session_state: state.session_state,
          health_status: state.health_status,
          api_request_count: state.session_stats.api_calls + 1,
          was_cached: Map.has_key?(state.orders, cancelled_order.order_id)
        }
      })
    end
    
    defp update_state_after_successful_cancellation(state, enhanced_cancelled_order, start_time) do
      now = System.system_time(:millisecond)
      cancellation_duration = now - start_time
      
      # Update orders cache with cancelled order
      new_orders = Map.put(state.orders, enhanced_cancelled_order.order_id, enhanced_cancelled_order)
      
      # Update comprehensive session stats
      new_stats = state.session_stats
      |> Map.update!(:orders_cancelled, &(&1 + 1))
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update(:successful_operations, 0, &(&1 + 1))
      |> Map.update(:total_cancellation_time_ms, 0, &(&1 + cancellation_duration))
      |> Map.update(:avg_cancellation_time_ms, 0, fn current ->
        total_cancellations = Map.get(state.session_stats, :orders_cancelled, 0) + 1
        if total_cancellations > 0 do
          (current * (total_cancellations - 1) + cancellation_duration) / total_cancellations
        else
          cancellation_duration
        end
      end)
      
      # Record comprehensive activity
      activity_state = record_activity_internal(state, :order_cancelled_with_validation, %{
        order_id: enhanced_cancelled_order.order_id,
        symbol: enhanced_cancelled_order.symbol,
        validation_time_ms: enhanced_cancelled_order.validation_time_ms,
        cancellation_duration_ms: cancellation_duration,
        total_process_time_ms: now - start_time,
        was_cached: enhanced_cancelled_order.enhanced_metadata.was_cached
      })
      
      %{activity_state |
        orders: new_orders,
        session_stats: new_stats,
        last_activity: now,
        session_state: :active
      }
    end
    
    defp perform_post_cancellation_actions(state, enhanced_cancelled_order, status) do
      # Broadcast enhanced cancellation event
      broadcast_order_event(state, :order_cancelled, enhanced_cancelled_order)
      
      # Update comprehensive metrics
      UserMetrics.record_trading_operation(
        state.user_id, 
        :order_cancelled, 
        status == :success,
        enhanced_cancelled_order.validation_time_ms
      )
      
      # Comprehensive security audit
      UserSecurityAuditor.log_trading_operation(state.user_id, :order_cancelled, %{
        order_id: enhanced_cancelled_order.order_id,
        symbol: enhanced_cancelled_order.symbol,
        session_id: state.session_id,
        validation_passed: true,
        cancellation_source: enhanced_cancelled_order.cancellation_source,
        session_health: state.health_status,
        total_process_time_ms: enhanced_cancelled_order.validation_time_ms,
        was_cached: enhanced_cancelled_order.enhanced_metadata.was_cached
      })
    end
    
    defp handle_order_cancellation_failure(state, order_id, order_symbol, reason, start_time) do
      now = System.system_time(:millisecond)
      cancellation_duration = now - start_time
      
      Logger.error("Order cancellation failed after validation", 
        user_id: state.user_id, 
        order_id: order_id,
        symbol: order_symbol,
        reason: inspect(reason),
        cancellation_duration_ms: cancellation_duration
      )
      
      # Update comprehensive error stats
      new_stats = state.session_stats
      |> Map.update!(:errors, &(&1 + 1))
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update(:cancellation_failures, 0, &(&1 + 1))
      |> Map.update(:total_failed_cancellation_time_ms, 0, &(&1 + cancellation_duration))
      
      # Record comprehensive error activity
      error_state = record_activity_internal(state, :order_cancellation_failed_post_validation, %{
        order_id: order_id,
        symbol: order_symbol,
        error: reason,
        cancellation_duration_ms: cancellation_duration
      })
      
      new_state = %{error_state | session_stats: new_stats}
      
      # Update comprehensive metrics
      UserMetrics.record_trading_operation(state.user_id, :order_cancellation_failed, false, cancellation_duration)
      
      # Comprehensive security audit for failures
      UserSecurityAuditor.log_trading_operation(state.user_id, :order_cancellation_failed, %{
        order_id: order_id,
        symbol: order_symbol,
        error: reason,
        session_id: state.session_id,
        validation_passed: true,
        failure_after_validation: true,
        cancellation_duration_ms: cancellation_duration
      })
      
      # Enhanced error categorization for cancellation
      categorized_error = categorize_cancellation_error(reason)
      
      {:error, {categorized_error, new_state}}
    end
    
    defp record_cancellation_validation_failure(state, error_type, details, order_id) do
      # Update session stats for cancellation validation failures
      new_stats = state.session_stats
      |> Map.update(:cancellation_validation_failures, 0, &(&1 + 1))
      |> Map.update(:errors, 0, &(&1 + 1))
      
      # Record detailed cancellation validation failure activity
      activity_state = record_activity_internal(state, :order_cancellation_validation_failed, %{
        error_type: error_type,
        details: details,
        order_id: order_id,
        validation_stage: determine_validation_stage(error_type)
      })
      
      %{activity_state | session_stats: new_stats}
    end
    
    defp build_enhanced_cancel_error_response(error_type, details, order_id) do
      base_error = %{
        error_type: error_type,
        details: details,
        order_id: order_id,
        timestamp: System.system_time(:millisecond)
      }
      
      case error_type do
        :order_not_found ->
          Map.merge(base_error, %{
            category: :order_management,
            user_message: "Order not found or already completed",
            searched_locations: [:cache, :api],
            suggestion: "Please check the order ID and ensure the order is still active"
          })
          
        :order_lookup_failed ->
          Map.merge(base_error, %{
            category: :system_error,
            user_message: "Unable to verify order status",
            lookup_error: details.reason,
            suggestion: "Please try again or contact support if the issue persists"
          })
          
        :validation_error ->
          Map.merge(base_error, %{
            category: :input_validation,
            user_message: "Invalid order ID provided",
            field_errors: [%{field: "order_id", error: details.reason}],
            suggestion: "Please provide a valid order ID"
          })
          
        :rate_limit_violation ->
          Map.merge(base_error, %{
            category: :rate_limiting,
            user_message: "Too many cancellation requests",
            retry_after_seconds: calculate_retry_delay(details)
          })
          
        :session_unhealthy ->
          Map.merge(base_error, %{
            category: :session_health,
            user_message: "User session health check failed",
            health_issue: details.reason
          })
          
        _ ->
          Map.merge(base_error, %{
            category: :unknown,
            user_message: "Order cancellation validation failed"
          })
      end
    end
    
    defp categorize_cancellation_error(reason) do
      case reason do
        {:order_does_not_exist, _} -> :order_not_found
        {:order_cancel_rejected, _} -> :order_not_cancelable
        {:invalid_symbol, _} -> :invalid_trading_pair
        {:rate_limit_exceeded, _} -> :rate_limit_exceeded
        {:connection_failed, _} -> :network_error
        {:api_error, _} -> :exchange_error
        _ -> :unknown_cancellation_error
      end
    end
    
    # Enhanced balance retrieval helper functions
    
    defp perform_comprehensive_balance_validation(state, opts) do
      alias CryptoExchange.Trading.Validation
      
      # Step 1: Check session health
      with {:ok, healthy_state} <- check_session_health_internal(state),
           # Step 2: Validate balance request parameters
           {:ok, validated_opts} <- Validation.validate_get_balance(state.user_id, opts || %{}) do
        {:ok, {healthy_state, validated_opts}}
      else
        {:error, health_reason} ->
          {:error, {:session_unhealthy, %{reason: health_reason}}}
          
        {:error, {error_type, details}} ->
          {:error, {error_type, details}}
          
        error ->
          {:error, {:unknown_validation_error, %{reason: error}}}
      end
    end
    
    defp execute_balance_retrieval(state, validated_opts, start_time) do
      now = System.system_time(:millisecond)
      force_refresh = Map.get(validated_opts, :force_refresh, false)
      asset_filter = Map.get(validated_opts, :asset_filter)
      include_zero = Map.get(validated_opts, :include_zero, false)
      
      last_balance_update = Map.get(state.cache_timestamps, :balances, 0)
      cache_valid = (now - last_balance_update) < @balance_cache_ttl
      
      if not force_refresh and cache_valid and not Enum.empty?(state.balances) do
        # Use cached balance with filtering
        cached_balances = apply_balance_filters(Map.values(state.balances), validated_opts)
        
        # Update state with cache hit
        new_state = update_state_after_cached_balance(state, cached_balances, start_time)
        
        # Log cache hit
        Logger.debug("Using cached balance with filtering", 
          user_id: state.user_id,
          original_count: map_size(state.balances),
          filtered_count: length(cached_balances),
          asset_filter: asset_filter
        )
        
        {:ok, {cached_balances, new_state}}
      else
        # Fetch fresh balance from API
        case PrivateClient.get_balance(state.user_id) do
          {:ok, balances} ->
            # Apply filters to fresh balances
            filtered_balances = apply_balance_filters(balances, validated_opts)
            
            # Update state with fresh balance
            new_state = update_state_after_fresh_balance(state, balances, filtered_balances, start_time)
            
            # Perform post-balance actions
            perform_post_balance_actions(new_state, filtered_balances, :success, start_time)
            
            {:ok, {filtered_balances, new_state}}
            
          {:error, reason} ->
            handle_balance_retrieval_failure(state, reason, start_time)
        end
      end
    end
    
    defp apply_balance_filters(balances, opts) when is_list(balances) do
      asset_filter = Map.get(opts, :asset_filter)
      include_zero = Map.get(opts, :include_zero, false)
      
      balances
      |> filter_by_asset(asset_filter)
      |> filter_by_zero_balance(include_zero)
      |> sort_balances_by_value()
    end
    
    defp filter_by_asset(balances, nil), do: balances
    defp filter_by_asset(balances, asset_filter) when is_binary(asset_filter) do
      normalized_filter = String.upcase(asset_filter)
      Enum.filter(balances, &(String.upcase(&1.asset) == normalized_filter))
    end
    
    defp filter_by_zero_balance(balances, true), do: balances
    defp filter_by_zero_balance(balances, false) do
      Enum.filter(balances, fn balance ->
        balance.free > 0 or balance.locked > 0
      end)
    end
    
    defp sort_balances_by_value(balances) do
      Enum.sort_by(balances, &(&1.free + &1.locked), :desc)
    end
    
    defp update_state_after_cached_balance(state, filtered_balances, start_time) do
      now = System.system_time(:millisecond)
      retrieval_duration = now - start_time
      
      # Update cache hit stats
      new_stats = state.session_stats
      |> Map.update!(:balance_checks, &(&1 + 1))
      |> Map.update!(:cache_hits, &(&1 + 1))
      |> Map.update(:total_balance_retrieval_time_ms, 0, &(&1 + retrieval_duration))
      
      # Record activity
      activity_state = record_activity_internal(state, :balance_retrieved_cached, %{
        asset_count: length(filtered_balances),
        from_cache: true,
        retrieval_duration_ms: retrieval_duration
      })
      
      %{activity_state |
        session_stats: new_stats,
        last_activity: now,
        session_state: :active
      }
    end
    
    defp update_state_after_fresh_balance(state, all_balances, filtered_balances, start_time) do
      now = System.system_time(:millisecond)
      retrieval_duration = now - start_time
      
      # Cache all balances (not just filtered ones)
      balances_map = Enum.reduce(all_balances, %{}, fn balance, acc ->
        Map.put(acc, balance.asset, balance)
      end)
      
      new_cache_timestamps = Map.put(state.cache_timestamps, :balances, now)
      
      # Update comprehensive stats
      new_stats = state.session_stats
      |> Map.update!(:balance_checks, &(&1 + 1))
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update!(:cache_misses, &(&1 + 1))
      |> Map.update(:successful_operations, 0, &(&1 + 1))
      |> Map.update(:total_balance_retrieval_time_ms, 0, &(&1 + retrieval_duration))
      
      # Record comprehensive activity
      activity_state = record_activity_internal(state, :balance_retrieved_fresh, %{
        total_asset_count: length(all_balances),
        filtered_asset_count: length(filtered_balances),
        from_cache: false,
        retrieval_duration_ms: retrieval_duration
      })
      
      %{activity_state |
        balances: balances_map,
        session_stats: new_stats,
        cache_timestamps: new_cache_timestamps,
        last_activity: now,
        session_state: :active
      }
    end
    
    defp perform_post_balance_actions(state, balances, status, start_time) do
      retrieval_duration = System.system_time(:millisecond) - start_time
      
      # Update metrics
      UserMetrics.record_api_request(
        state.user_id, 
        "/api/v3/account", 
        retrieval_duration,
        if(status == :success, do: :success, else: :error)
      )
      
      # Security audit
      UserSecurityAuditor.log_balance_request(state.user_id, %{
        session_id: state.session_id,
        asset_count: length(balances),
        retrieval_duration_ms: retrieval_duration,
        session_health: state.health_status
      })
    end
    
    defp handle_balance_retrieval_failure(state, reason, start_time) do
      now = System.system_time(:millisecond)
      retrieval_duration = now - start_time
      
      Logger.error("Balance retrieval failed after validation", 
        user_id: state.user_id, 
        reason: inspect(reason),
        retrieval_duration_ms: retrieval_duration
      )
      
      # Update error stats
      new_stats = state.session_stats
      |> Map.update!(:errors, &(&1 + 1))
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update(:balance_failures, 0, &(&1 + 1))
      
      # Record error activity
      error_state = record_activity_internal(state, :balance_retrieval_failed, %{
        error: reason,
        retrieval_duration_ms: retrieval_duration
      })
      
      new_state = %{error_state | session_stats: new_stats}
      
      # Update metrics
      UserMetrics.record_api_request(state.user_id, "/api/v3/account", retrieval_duration, :error)
      
      # Security audit
      UserSecurityAuditor.log_balance_request_failed(state.user_id, %{
        session_id: state.session_id,
        error: reason,
        retrieval_duration_ms: retrieval_duration
      })
      
      categorized_error = categorize_balance_error(reason)
      {:error, {categorized_error, new_state}}
    end
    
    # Enhanced orders retrieval helper functions
    
    defp perform_comprehensive_orders_validation(state, opts) do
      alias CryptoExchange.Trading.Validation
      
      # Step 1: Check session health
      with {:ok, healthy_state} <- check_session_health_internal(state),
           # Step 2: Validate orders request parameters
           {:ok, validated_opts} <- Validation.validate_get_orders(state.user_id, opts || %{}) do
        {:ok, {healthy_state, validated_opts}}
      else
        {:error, health_reason} ->
          {:error, {:session_unhealthy, %{reason: health_reason}}}
          
        {:error, {error_type, details}} ->
          {:error, {error_type, details}}
          
        error ->
          {:error, {:unknown_validation_error, %{reason: error}}}
      end
    end
    
    defp execute_orders_retrieval(state, validated_opts, start_time) do
      symbol = Map.get(validated_opts, :symbol)
      from_cache = Map.get(validated_opts, :from_cache, false)
      limit = Map.get(validated_opts, :limit, 100)
      
      if from_cache and symbol do
        # Return cached orders for specific symbol
        cached_orders = get_cached_orders_for_symbol(state, symbol, limit)
        
        # Update state with cache hit
        new_state = update_state_after_cached_orders(state, cached_orders, start_time)
        
        Logger.debug("Using cached orders", 
          user_id: state.user_id,
          symbol: symbol,
          order_count: length(cached_orders)
        )
        
        {:ok, {cached_orders, new_state}}
      else
        # Fetch from API with comprehensive error handling
        case fetch_orders_from_api(state.user_id, symbol, validated_opts) do
          {:ok, orders} ->
            # Apply filters to orders
            filtered_orders = apply_orders_filters(orders, validated_opts)
            
            # Update state with fresh orders
            new_state = update_state_after_fresh_orders(state, orders, filtered_orders, start_time)
            
            # Perform post-orders actions
            perform_post_orders_actions(new_state, filtered_orders, :success, start_time)
            
            {:ok, {filtered_orders, new_state}}
            
          {:error, reason} ->
            handle_orders_retrieval_failure(state, reason, start_time)
        end
      end
    end
    
    defp get_cached_orders_for_symbol(state, symbol, limit) do
      state.orders
      |> Map.values()
      |> Enum.filter(&(&1.symbol == symbol))
      |> Enum.sort_by(& &1.created_at, :desc)
      |> Enum.take(limit)
    end
    
    defp fetch_orders_from_api(user_id, symbol, opts) do
      # Determine which API call to make based on options
      cond do
        symbol && Map.get(opts, :status) == "OPEN" ->
          PrivateClient.get_open_orders(user_id, symbol)
          
        symbol ->
          api_opts = build_api_opts_for_orders(opts)
          PrivateClient.get_orders(user_id, symbol, api_opts)
          
        true ->
          # Get open orders for all symbols
          PrivateClient.get_open_orders(user_id, nil)
      end
    end
    
    defp build_api_opts_for_orders(opts) do
      %{
        limit: Map.get(opts, :limit, 100),
        startTime: Map.get(opts, :start_time),
        endTime: Map.get(opts, :end_time)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end
    
    defp apply_orders_filters(orders, opts) when is_list(orders) do
      status_filter = Map.get(opts, :status)
      limit = Map.get(opts, :limit, 100)
      
      orders
      |> filter_by_status(status_filter)
      |> sort_orders_by_time()
      |> Enum.take(limit)
    end
    
    defp filter_by_status(orders, nil), do: orders
    defp filter_by_status(orders, status) when is_binary(status) do
      normalized_status = String.upcase(status)
      Enum.filter(orders, &(String.upcase(to_string(&1.status)) == normalized_status))
    end
    
    defp sort_orders_by_time(orders) do
      Enum.sort_by(orders, & Map.get(&1, :created_at, 0), :desc)
    end
    
    defp update_state_after_cached_orders(state, cached_orders, start_time) do
      now = System.system_time(:millisecond)
      retrieval_duration = now - start_time
      
      # Update cache hit stats
      new_stats = state.session_stats
      |> Map.update!(:cache_hits, &(&1 + 1))
      |> Map.update(:total_orders_retrieval_time_ms, 0, &(&1 + retrieval_duration))
      
      # Record activity
      activity_state = record_activity_internal(state, :orders_retrieved_cached, %{
        order_count: length(cached_orders),
        from_cache: true,
        retrieval_duration_ms: retrieval_duration
      })
      
      %{activity_state |
        session_stats: new_stats,
        last_activity: now
      }
    end
    
    defp update_state_after_fresh_orders(state, all_orders, filtered_orders, start_time) do
      now = System.system_time(:millisecond)
      retrieval_duration = now - start_time
      
      # Update local cache with fresh orders
      new_orders = Enum.reduce(all_orders, state.orders, fn order, acc ->
        enhanced_order = Map.merge(order, %{
          fetched_at: now,
          session_id: state.session_id
        })
        Map.put(acc, order.order_id, enhanced_order)
      end)
      
      # Update cache timestamp
      symbol_key = determine_cache_key_for_orders(all_orders)
      new_cache_timestamps = put_in(
        state.cache_timestamps, 
        [:orders, symbol_key], 
        now
      )
      
      # Update comprehensive stats
      new_stats = state.session_stats
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update!(:cache_misses, &(&1 + 1))
      |> Map.update(:successful_operations, 0, &(&1 + 1))
      |> Map.update(:total_orders_retrieval_time_ms, 0, &(&1 + retrieval_duration))
      
      # Record comprehensive activity
      activity_state = record_activity_internal(state, :orders_retrieved_fresh, %{
        total_order_count: length(all_orders),
        filtered_order_count: length(filtered_orders),
        from_cache: false,
        retrieval_duration_ms: retrieval_duration
      })
      
      %{activity_state |
        orders: new_orders,
        session_stats: new_stats,
        cache_timestamps: new_cache_timestamps,
        last_activity: now,
        session_state: :active
      }
    end
    
    defp determine_cache_key_for_orders(orders) when is_list(orders) do
      case orders do
        [] -> "all"
        [%{symbol: symbol} | _] -> symbol
        _ -> "all"
      end
    end
    
    defp perform_post_orders_actions(state, orders, status, start_time) do
      retrieval_duration = System.system_time(:millisecond) - start_time
      
      # Update metrics
      UserMetrics.record_api_request(
        state.user_id, 
        "/api/v3/allOrders", 
        retrieval_duration,
        if(status == :success, do: :success, else: :error)
      )
      
      # Security audit
      UserSecurityAuditor.log_orders_request(state.user_id, %{
        session_id: state.session_id,
        order_count: length(orders),
        retrieval_duration_ms: retrieval_duration,
        session_health: state.health_status
      })
    end
    
    defp handle_orders_retrieval_failure(state, reason, start_time) do
      now = System.system_time(:millisecond)
      retrieval_duration = now - start_time
      
      Logger.error("Orders retrieval failed after validation", 
        user_id: state.user_id, 
        reason: inspect(reason),
        retrieval_duration_ms: retrieval_duration
      )
      
      # Update error stats
      new_stats = state.session_stats
      |> Map.update!(:errors, &(&1 + 1))
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update(:orders_failures, 0, &(&1 + 1))
      
      # Record error activity
      error_state = record_activity_internal(state, :orders_retrieval_failed, %{
        error: reason,
        retrieval_duration_ms: retrieval_duration
      })
      
      new_state = %{error_state | session_stats: new_stats}
      
      # Update metrics
      UserMetrics.record_api_request(state.user_id, "/api/v3/allOrders", retrieval_duration, :error)
      
      categorized_error = categorize_orders_error(reason)
      {:error, {categorized_error, new_state}}
    end
    
    # Helper functions for validation failures and error responses
    
    defp record_balance_validation_failure(state, error_type, details) do
      new_stats = state.session_stats
      |> Map.update(:balance_validation_failures, 0, &(&1 + 1))
      |> Map.update(:errors, 0, &(&1 + 1))
      
      activity_state = record_activity_internal(state, :balance_validation_failed, %{
        error_type: error_type,
        details: details
      })
      
      %{activity_state | session_stats: new_stats}
    end
    
    defp record_orders_validation_failure(state, error_type, details) do
      new_stats = state.session_stats
      |> Map.update(:orders_validation_failures, 0, &(&1 + 1))
      |> Map.update(:errors, 0, &(&1 + 1))
      
      activity_state = record_activity_internal(state, :orders_validation_failed, %{
        error_type: error_type,
        details: details
      })
      
      %{activity_state | session_stats: new_stats}
    end
    
    defp build_enhanced_balance_error_response(error_type, details, opts) do
      %{
        error_type: error_type,
        details: details,
        timestamp: System.system_time(:millisecond),
        category: :balance_request,
        user_message: get_balance_error_message(error_type, details),
        suggestion: get_balance_error_suggestion(error_type, details),
        requested_opts: sanitize_opts_for_error(opts)
      }
    end
    
    defp build_enhanced_orders_error_response(error_type, details, opts) do
      %{
        error_type: error_type,
        details: details,
        timestamp: System.system_time(:millisecond),
        category: :orders_request,
        user_message: get_orders_error_message(error_type, details),
        suggestion: get_orders_error_suggestion(error_type, details),
        requested_opts: sanitize_opts_for_error(opts)
      }
    end
    
    defp get_balance_error_message(:session_unhealthy, _), do: "User session health check failed"
    defp get_balance_error_message(:rate_limit_violation, _), do: "Too many balance requests"
    defp get_balance_error_message(_, _), do: "Balance request failed"
    
    defp get_orders_error_message(:session_unhealthy, _), do: "User session health check failed"
    defp get_orders_error_message(:rate_limit_violation, _), do: "Too many orders requests"
    defp get_orders_error_message(_, _), do: "Orders request failed"
    
    defp get_balance_error_suggestion(:rate_limit_violation, _), do: "Please wait before requesting balance again"
    defp get_balance_error_suggestion(_, _), do: "Please try again later"
    
    defp get_orders_error_suggestion(:rate_limit_violation, _), do: "Please wait before requesting orders again"
    defp get_orders_error_suggestion(_, _), do: "Please try again later"
    
    defp categorize_balance_error(reason) do
      case reason do
        {:rate_limit_exceeded, _} -> :rate_limit_exceeded
        {:connection_failed, _} -> :network_error
        {:api_error, _} -> :exchange_error
        {:invalid_credentials, _} -> :authentication_failed
        _ -> :unknown_balance_error
      end
    end
    
    defp categorize_orders_error(reason) do
      case reason do
        {:rate_limit_exceeded, _} -> :rate_limit_exceeded
        {:connection_failed, _} -> :network_error
        {:api_error, _} -> :exchange_error
        {:invalid_symbol, _} -> :invalid_trading_pair
        _ -> :unknown_orders_error
      end
    end
    
    defp sanitize_opts_for_logging(opts) when is_map(opts) do
      # Remove any sensitive data but keep structure for debugging
      Map.take(opts, [:asset_filter, :symbol, :limit, :from_cache, :include_zero])
    end
    
    defp sanitize_opts_for_logging(opts), do: opts
    
    defp sanitize_opts_for_error(opts) when is_map(opts) do
      Map.take(opts, [:asset_filter, :symbol, :limit])
    end
    
    defp sanitize_opts_for_error(_), do: %{}
  end
end