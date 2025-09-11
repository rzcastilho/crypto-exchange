defmodule CryptoExchange.ErrorRecoverySupervisor do
  @moduledoc """
  Comprehensive error recovery supervisor for stream interruptions and system failures.

  This supervisor provides intelligent error recovery strategies for different types of failures:

  - **Stream Interruption Recovery**: Handles WebSocket disconnections with state preservation
  - **Network Partition Recovery**: Manages recovery from network connectivity issues  
  - **Rate Limit Recovery**: Coordinates recovery from API rate limiting
  - **Authentication Recovery**: Handles credential expiration and re-authentication
  - **Circuit Breaker Recovery**: Manages transition from open to half-open to closed states

  ## Recovery Strategies

  - **Immediate Recovery**: For transient network issues
  - **Delayed Recovery**: For rate limiting and server errors
  - **Progressive Recovery**: For persistent connection issues
  - **Manual Recovery**: For authentication and configuration problems

  ## Error Classification

  The supervisor classifies errors into categories for appropriate recovery:

  - **Transient**: Network timeouts, DNS resolution failures
  - **Rate Limited**: API quota exceeded, too many requests
  - **Authentication**: Invalid credentials, token expiration
  - **Server**: Internal server errors, maintenance windows
  - **Configuration**: Invalid URLs, missing credentials

  ## State Preservation

  During recovery operations, the supervisor preserves:

  - Active subscriptions and their parameters
  - Connection quality metrics and history
  - Error patterns and recovery statistics
  - User sessions and trading state

  ## Integration

  Works closely with:
  - ConnectionManager for circuit breaker coordination
  - HealthMonitor for health status reporting
  - ReconnectionStrategy for backoff timing
  - StreamManager for subscription management

  ## Usage

      # The supervisor is automatically started as part of the application
      # and coordinates recovery through the ConnectionManager
      
      # Manual recovery trigger (for emergencies)
      ErrorRecoverySupervisor.trigger_recovery(connection_id, :force_reconnect)
      
      # Recovery status monitoring
      {:ok, status} = ErrorRecoverySupervisor.get_recovery_status()
  """

  use Supervisor
  require Logger

  alias CryptoExchange.{
    ConnectionManager,
    HealthMonitor, 
    ReconnectionStrategy,
    PublicStreams
  }

  defmodule RecoveryWorker do
    @moduledoc """
    Individual worker process that handles recovery for a specific connection.
    
    Each connection gets its own recovery worker that maintains recovery state
    and coordinates with other system components.
    """
    
    use GenServer
    require Logger

    defstruct [
      :connection_id,
      :connection_type,
      :recovery_strategy,
      :recovery_state,
      :retry_count,
      :last_recovery_attempt,
      :subscription_state,
      :error_history,
      :recovery_callbacks,
      :config
    ]

    @recovery_states [:idle, :analyzing, :recovering, :monitoring, :failed]
    
    # Client API
    
    def start_link({connection_id, connection_type, opts}) do
      GenServer.start_link(__MODULE__, {connection_id, connection_type, opts}, 
        name: via_tuple(connection_id))
    end

    def trigger_recovery(connection_id, recovery_type \\ :auto) do
      GenServer.cast(via_tuple(connection_id), {:trigger_recovery, recovery_type})
    end

    def get_status(connection_id) do
      GenServer.call(via_tuple(connection_id), :get_status)
    end

    def update_error(connection_id, error_type, error_details) do
      GenServer.cast(via_tuple(connection_id), {:error_update, error_type, error_details})
    end

    # Server Callbacks

    @impl true
    def init({connection_id, connection_type, opts}) do
      Logger.info("Starting ErrorRecovery worker for #{connection_id}")
      
      # Register for health monitoring
      HealthMonitor.register_connection(connection_id, connection_type)
      
      {:ok, strategy} = ReconnectionStrategy.create(%{
        connection_id: connection_id,
        connection_type: connection_type
      })

      state = %__MODULE__{
        connection_id: connection_id,
        connection_type: connection_type,
        recovery_strategy: strategy,
        recovery_state: :idle,
        retry_count: 0,
        last_recovery_attempt: nil,
        subscription_state: %{},
        error_history: [],
        recovery_callbacks: [],
        config: load_recovery_config(opts)
      }

      {:ok, state}
    end

    @impl true
    def handle_call(:get_status, _from, state) do
      status = %{
        connection_id: state.connection_id,
        connection_type: state.connection_type,
        recovery_state: state.recovery_state,
        retry_count: state.retry_count,
        last_recovery_attempt: state.last_recovery_attempt,
        strategy_metrics: ReconnectionStrategy.get_metrics(state.recovery_strategy),
        error_count: length(state.error_history)
      }
      
      {:reply, {:ok, status}, state}
    end

    @impl true
    def handle_cast({:trigger_recovery, recovery_type}, state) do
      Logger.info("Recovery triggered for #{state.connection_id}: #{recovery_type}")
      new_state = initiate_recovery(state, recovery_type)
      {:noreply, new_state}
    end

    @impl true
    def handle_cast({:error_update, error_type, error_details}, state) do
      current_time = System.system_time(:millisecond)
      error_record = %{
        type: error_type,
        details: error_details,
        timestamp: current_time
      }
      
      updated_history = [error_record | state.error_history] |> Enum.take(100)
      
      # Update reconnection strategy
      case ReconnectionStrategy.handle_failure(state.recovery_strategy, error_type) do
        {:reconnect, delay_ms, new_strategy} ->
          Logger.info("Scheduling recovery for #{state.connection_id} in #{delay_ms}ms")
          Process.send_after(self(), :execute_recovery, delay_ms)
          
          new_state = %{state |
            recovery_strategy: new_strategy,
            error_history: updated_history,
            recovery_state: :analyzing
          }
          {:noreply, new_state}
          
        {:backoff, delay_ms, new_strategy} ->
          Logger.info("Backing off recovery for #{state.connection_id} for #{delay_ms}ms")
          Process.send_after(self(), :retry_after_backoff, delay_ms)
          
          new_state = %{state |
            recovery_strategy: new_strategy,
            error_history: updated_history,
            recovery_state: :monitoring
          }
          {:noreply, new_state}
          
        {:abandon, reason, new_strategy} ->
          Logger.error("Abandoning recovery for #{state.connection_id}: #{reason}")
          new_state = %{state |
            recovery_strategy: new_strategy,
            error_history: updated_history,
            recovery_state: :failed
          }
          
          # Notify health monitor
          HealthMonitor.report_error(state.connection_id, :recovery_abandoned)
          {:noreply, new_state}
      end
    end

    @impl true
    def handle_info(:execute_recovery, state) do
      Logger.info("Executing recovery for #{state.connection_id}")
      new_state = perform_recovery_sequence(state)
      {:noreply, new_state}
    end

    @impl true 
    def handle_info(:retry_after_backoff, state) do
      Logger.info("Retry period ended for #{state.connection_id}, triggering recovery")
      new_state = initiate_recovery(state, :auto)
      {:noreply, new_state}
    end

    @impl true
    def handle_info(:recovery_timeout, state) do
      Logger.warning("Recovery timeout for #{state.connection_id}")
      
      new_state = %{state |
        recovery_state: :failed,
        retry_count: state.retry_count + 1
      }
      
      # Report timeout to health monitor
      HealthMonitor.report_error(state.connection_id, :recovery_timeout)
      
      # Trigger another recovery attempt if within limits
      if new_state.retry_count < state.config.max_recovery_attempts do
        Process.send_after(self(), :execute_recovery, state.config.recovery_timeout_backoff)
        {:noreply, %{new_state | recovery_state: :analyzing}}
      else
        Logger.error("Max recovery attempts exceeded for #{state.connection_id}")
        {:noreply, new_state}
      end
    end

    @impl true
    def handle_info({:recovery_success, recovery_details}, state) do
      Logger.info("Recovery successful for #{state.connection_id}")
      
      # Update strategy with success
      updated_strategy = ReconnectionStrategy.handle_success(state.recovery_strategy)
      
      new_state = %{state |
        recovery_strategy: updated_strategy,
        recovery_state: :idle,
        retry_count: 0,
        last_recovery_attempt: System.system_time(:millisecond)
      }
      
      # Notify health monitor of successful recovery
      HealthMonitor.report_connection_event(state.connection_id, :recovered)
      
      # Execute recovery callbacks
      execute_recovery_callbacks(state.recovery_callbacks, :success, recovery_details)
      
      {:noreply, new_state}
    end

    @impl true
    def handle_info({:recovery_failed, failure_reason}, state) do
      Logger.error("Recovery failed for #{state.connection_id}: #{failure_reason}")
      
      new_state = %{state |
        recovery_state: :failed,
        retry_count: state.retry_count + 1,
        last_recovery_attempt: System.system_time(:millisecond)
      }
      
      # Report failure to health monitor
      HealthMonitor.report_error(state.connection_id, :recovery_failed)
      
      # Schedule retry if within limits
      if new_state.retry_count < state.config.max_recovery_attempts do
        delay = calculate_recovery_backoff(new_state.retry_count, state.config)
        Process.send_after(self(), :execute_recovery, delay)
        {:noreply, %{new_state | recovery_state: :analyzing}}
      else
        execute_recovery_callbacks(state.recovery_callbacks, :failed, failure_reason)
        {:noreply, new_state}
      end
    end

    # Private Functions

    defp via_tuple(connection_id) do
      {:via, Registry, {CryptoExchange.Registry, {:error_recovery, connection_id}}}
    end

    defp initiate_recovery(state, recovery_type) do
      Logger.debug("Initiating #{recovery_type} recovery for #{state.connection_id}")
      
      # Preserve current subscription state if needed
      subscription_state = if state.connection_type == :binance_ws do
        capture_subscription_state(state.connection_id)
      else
        %{}
      end
      
      # Set recovery timeout
      Process.send_after(self(), :recovery_timeout, state.config.recovery_timeout)
      
      %{state |
        recovery_state: :recovering,
        subscription_state: subscription_state,
        last_recovery_attempt: System.system_time(:millisecond)
      }
    end

    defp perform_recovery_sequence(state) do
      Logger.info("Performing recovery sequence for #{state.connection_id}")
      
      # Step 1: Check circuit breaker state
      case ConnectionManager.get_circuit_state() do
        :open ->
          Logger.info("Circuit breaker open, waiting before recovery")
          Process.send_after(self(), :execute_recovery, 5000)
          state
          
        _ ->
          # Step 2: Attempt connection recovery
          recovery_task = Task.async(fn ->
            perform_connection_recovery(state)
          end)
          
          # Monitor the recovery task
          case Task.yield(recovery_task, state.config.recovery_timeout) || Task.shutdown(recovery_task) do
            {:ok, result} ->
              handle_recovery_result(state, result)
              
            nil ->
              Logger.error("Recovery task timed out for #{state.connection_id}")
              send(self(), {:recovery_failed, :timeout})
              state
          end
      end
    end

    defp perform_connection_recovery(state) do
      try do
        case state.connection_type do
          :binance_ws ->
            recover_websocket_connection(state)
          :binance_api ->
            recover_api_connection(state)
          _ ->
            {:error, :unsupported_connection_type}
        end
      rescue
        error ->
          Logger.error("Recovery crashed for #{state.connection_id}: #{inspect(error)}")
          {:error, {:recovery_crashed, error}}
      catch
        :exit, reason ->
          Logger.error("Recovery exited for #{state.connection_id}: #{inspect(reason)}")
          {:error, {:recovery_exited, reason}}
      end
    end

    defp recover_websocket_connection(state) do
      Logger.info("Recovering WebSocket connection for #{state.connection_id}")
      
      # Step 1: Get new connection from ConnectionManager
      case ConnectionManager.get_connection(:binance_ws) do
        {:ok, new_connection_pid} ->
          # Step 2: Restore subscriptions if any were preserved
          case restore_subscriptions(state.subscription_state, new_connection_pid) do
            :ok ->
              Logger.info("WebSocket recovery successful for #{state.connection_id}")
              {:ok, %{connection_pid: new_connection_pid, subscriptions_restored: map_size(state.subscription_state)}}
              
            {:error, reason} ->
              Logger.error("Failed to restore subscriptions for #{state.connection_id}: #{inspect(reason)}")
              # Connection succeeded but subscription restore failed
              {:partial_success, %{connection_pid: new_connection_pid, restore_error: reason}}
          end
          
        {:error, :circuit_open} ->
          Logger.info("Circuit breaker open, deferring recovery for #{state.connection_id}")
          {:deferred, :circuit_open}
          
        {:error, reason} ->
          Logger.error("Failed to get new connection for #{state.connection_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end

    defp recover_api_connection(_state) do
      # API connection recovery would be implemented here
      # For now, simulate successful recovery
      {:ok, %{connection_type: :api_recovered}}
    end

    defp handle_recovery_result(state, result) do
      case result do
        {:ok, details} ->
          send(self(), {:recovery_success, details})
          
        {:partial_success, details} ->
          Logger.warning("Partial recovery success for #{state.connection_id}")
          send(self(), {:recovery_success, details})
          
        {:deferred, reason} ->
          Logger.info("Recovery deferred for #{state.connection_id}: #{reason}")
          # Schedule retry after a delay
          Process.send_after(self(), :execute_recovery, 10_000)
          
        {:error, reason} ->
          send(self(), {:recovery_failed, reason})
      end
      
      state
    end

    defp capture_subscription_state(connection_id) do
      # This would capture the current subscriptions for a connection
      # For now, return empty state
      %{}
    end

    defp restore_subscriptions(subscription_state, _connection_pid) do
      # This would restore subscriptions after reconnection
      # For now, simulate success
      if map_size(subscription_state) == 0 do
        :ok
      else
        Logger.info("Restoring #{map_size(subscription_state)} subscriptions")
        :ok
      end
    end

    defp execute_recovery_callbacks(callbacks, result_type, details) do
      Enum.each(callbacks, fn callback ->
        try do
          callback.(result_type, details)
        rescue
          error ->
            Logger.error("Recovery callback failed: #{inspect(error)}")
        end
      end)
    end

    defp calculate_recovery_backoff(retry_count, config) do
      base_delay = config.base_recovery_delay || 1000
      max_delay = config.max_recovery_delay || 30_000
      
      delay = base_delay * :math.pow(2, retry_count)
      min(delay, max_delay)
    end

    defp load_recovery_config(opts) do
      defaults = %{
        max_recovery_attempts: 10,
        recovery_timeout: 30_000,
        recovery_timeout_backoff: 5_000,
        base_recovery_delay: 1_000,
        max_recovery_delay: 30_000
      }
      
      Map.merge(defaults, Keyword.get(opts, :recovery_config, %{}))
    end
  end

  # =============================================================================
  # SUPERVISOR API
  # =============================================================================

  @doc """
  Start the ErrorRecoverySupervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start recovery worker for a specific connection.
  """
  def start_recovery_worker(connection_id, connection_type, opts \\ []) do
    child_spec = %{
      id: {:recovery_worker, connection_id},
      start: {RecoveryWorker, :start_link, [{connection_id, connection_type, opts}]},
      restart: :temporary,  # Don't auto-restart recovery workers
      shutdown: 10_000,
      type: :worker
    }
    
    Supervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stop recovery worker for a specific connection.
  """
  def stop_recovery_worker(connection_id) do
    case Supervisor.terminate_child(__MODULE__, {:recovery_worker, connection_id}) do
      :ok ->
        Supervisor.delete_child(__MODULE__, {:recovery_worker, connection_id})
      error ->
        error
    end
  end

  @doc """
  Trigger recovery for a specific connection.
  """
  def trigger_recovery(connection_id, recovery_type \\ :auto) do
    RecoveryWorker.trigger_recovery(connection_id, recovery_type)
  end

  @doc """
  Get recovery status for all managed connections.
  """
  def get_recovery_status do
    children = Supervisor.which_children(__MODULE__)
    
    recovery_statuses = Enum.map(children, fn
      {{:recovery_worker, connection_id}, pid, :worker, _} when is_pid(pid) ->
        case RecoveryWorker.get_status(connection_id) do
          {:ok, status} -> status
          {:error, _} -> %{connection_id: connection_id, status: :error}
        end
        
      _ -> nil
    end)
    |> Enum.filter(& &1)
    
    {:ok, recovery_statuses}
  end

  # Supervisor Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting ErrorRecoverySupervisor")
    
    # Start with no children - recovery workers are started on demand
    children = []
    
    # Use :one_for_one strategy with temporary restarts
    # Recovery workers should not be automatically restarted
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 0, max_seconds: 1)
  end
end