defmodule CryptoExchange.Trading.UserSupervisor do
  @moduledoc """
  Individual user supervision tree for secure and isolated trading sessions.

  This supervisor manages the complete lifecycle of a single user's trading session,
  providing isolation, security, and fault tolerance at the user level.

  ## Architecture

  ```
  UserSupervisor
  ├── UserConnection (GenServer - trading operations)
  ├── CredentialManager (GenServer - secure credential handling)
  └── UserHealthMonitor (GenServer - user-specific health monitoring)
  ```

  ## Security Features

  - **Credential isolation**: Credentials managed in separate process
  - **Process isolation**: User processes isolated from other users
  - **Secure cleanup**: Automatic credential purging on termination
  - **Audit trail**: All operations logged securely

  ## Fault Tolerance

  - **One-for-one strategy**: Individual process failures don't affect others
  - **Restart limits**: Prevents runaway restarts
  - **Graceful degradation**: User can continue with limited functionality
  - **Health monitoring**: Real-time health tracking per user

  ## Integration

  - Integrates with system-wide fault tolerance infrastructure
  - Reports to UserManager and HealthMonitor
  - Participates in system-wide monitoring and alerting
  """

  use Supervisor
  require Logger

  alias CryptoExchange.Trading.{UserConnection, CredentialManager, UserHealthMonitor, UserRegistry}

  @restart_intensity 3
  @restart_period 60  # seconds

  # Client API

  @doc """
  Start a UserSupervisor for a specific user.

  Creates the complete user session infrastructure including:
  - UserConnection for trading operations
  - CredentialManager for secure credential handling  
  - UserHealthMonitor for user-specific monitoring
  """
  def start_link([user_id: user_id, api_key: api_key, secret_key: secret_key, timeout: timeout]) do
    Supervisor.start_link(__MODULE__, {user_id, api_key, secret_key, timeout})
  end

  @doc """
  Get the PIDs of all child processes for a user.
  """
  def get_child_pids(supervisor_pid) when is_pid(supervisor_pid) do
    children = Supervisor.which_children(supervisor_pid)
    
    %{
      connection_pid: get_child_pid(children, UserConnection),
      credential_manager_pid: get_child_pid(children, CredentialManager),
      health_monitor_pid: get_child_pid(children, UserHealthMonitor)
    }
  end

  @doc """
  Get the status of all child processes for monitoring.
  """
  def get_children_status(supervisor_pid) when is_pid(supervisor_pid) do
    children = Supervisor.which_children(supervisor_pid)
    
    Enum.map(children, fn {id, pid, type, _modules} ->
      %{
        id: id,
        pid: pid,
        type: type,
        status: if(pid && Process.alive?(pid), do: :running, else: :stopped),
        memory_usage: get_process_memory_usage(pid)
      }
    end)
  end

  # Server Callbacks

  @impl true
  def init({user_id, api_key, secret_key, timeout}) do
    Logger.info("Starting UserSupervisor for user: #{user_id}", user_id: user_id)
    
    # Child specifications with proper ordering and dependencies
    children = [
      # 1. Credential Manager - Must start first for security
      {
        CredentialManager,
        {:user_id, user_id, :api_key, api_key, :secret_key, secret_key}
      },
      
      # 2. User Connection - Depends on credential manager
      {
        UserConnection,
        {:user_id, user_id, :timeout, timeout}
      },
      
      # 3. Health Monitor - Monitors the other processes
      {
        UserHealthMonitor,
        {:user_id, user_id, :timeout, timeout}
      }
    ]

    # Enhanced supervision options
    opts = [
      strategy: :one_for_one,
      max_restarts: @restart_intensity,
      max_seconds: @restart_period,
      name: via_tuple(user_id)
    ]

    case Supervisor.init(children, opts) do
      {:ok, _} = result ->
        # Register child PIDs with UserRegistry after successful start
        :timer.sleep(100)  # Allow processes to fully initialize
        update_user_registry(user_id)
        
        Logger.info("UserSupervisor started successfully for user: #{user_id}", user_id: user_id)
        result
        
      error ->
        Logger.error("Failed to start UserSupervisor for user #{user_id}: #{inspect(error)}", user_id: user_id)
        error
    end
  end

  # Private Functions

  defp via_tuple(user_id) do
    {:via, Registry, {CryptoExchange.Registry, {:user_supervisor, user_id}}}
  end

  defp get_child_pid(children, module) do
    case Enum.find(children, fn {id, _pid, _type, _modules} -> id == module end) do
      {_id, pid, _type, _modules} -> pid
      nil -> nil
    end
  end

  defp get_process_memory_usage(pid) when is_pid(pid) do
    try do
      case Process.info(pid, :memory) do
        {:memory, bytes} -> bytes
        nil -> 0
      end
    catch
      _ -> 0
    end
  end

  defp get_process_memory_usage(_), do: 0

  defp update_user_registry(user_id) do
    # Get the supervisor PID
    supervisor_pid = self()
    
    # Get child PIDs
    child_pids = get_child_pids(supervisor_pid)
    
    # Update the user registry with child process information
    case UserRegistry.lookup_user(user_id) do
      {:ok, user_info} ->
        updated_info = Map.merge(user_info, child_pids)
        updated_info = Map.put(updated_info, :status, :connected)
        UserRegistry.update_user(user_id, updated_info)
        
      {:error, :not_found} ->
        Logger.warning("User not found in registry during supervisor startup", user_id: user_id)
    end
  rescue
    error ->
      Logger.error("Failed to update user registry: #{inspect(error)}", user_id: user_id)
  end
end