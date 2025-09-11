defmodule CryptoExchange.Trading.UserRegistry do
  @moduledoc """
  High-performance user registry for efficient user session management.

  This module provides fast lookup and management of user sessions using ETS tables
  for optimal performance with concurrent users. It maintains comprehensive information
  about each user's session and provides efficient querying capabilities.

  ## Features

  - **Fast lookups**: ETS-based storage for O(1) user lookups
  - **Concurrent access**: Optimized for high-concurrency scenarios
  - **Session tracking**: Comprehensive session information storage
  - **Health monitoring**: Integration with health monitoring systems
  - **Metrics support**: Provides data for user metrics and analytics

  ## Data Structure

  Each user registry entry contains:
  - User identification and session details
  - Process PIDs for all user-related processes
  - Connection timestamps and activity tracking
  - Resource usage and health status
  - Security and audit information

  ## Performance

  - Optimized for 10+ concurrent users (target from SPECIFICATION.md)
  - Sub-millisecond lookup times
  - Memory-efficient storage
  - Concurrent read/write operations
  """

  use GenServer
  require Logger

  @table_name :user_registry
  @cleanup_interval 60_000  # 1 minute cleanup interval
  @inactive_threshold 900_000  # 15 minutes before user is considered inactive

  # Client API

  @doc """
  Start the UserRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new user session in the registry.
  """
  def register_user(user_id, user_info) when is_binary(user_id) and is_map(user_info) do
    GenServer.call(__MODULE__, {:register_user, user_id, user_info})
  end

  @doc """
  Update an existing user's information.
  """
  def update_user(user_id, user_info) when is_binary(user_id) and is_map(user_info) do
    GenServer.call(__MODULE__, {:update_user, user_id, user_info})
  end

  @doc """
  Remove a user from the registry.
  """
  def remove_user(user_id) when is_binary(user_id) do
    GenServer.call(__MODULE__, {:remove_user, user_id})
  end

  @doc """
  Look up a user's information.
  """
  def lookup_user(user_id) when is_binary(user_id) do
    case :ets.lookup(@table_name, user_id) do
      [{^user_id, user_info}] -> {:ok, user_info}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Check if a user is registered.
  """
  def user_exists?(user_id) when is_binary(user_id) do
    case lookup_user(user_id) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  List all registered users with their information.
  """
  def list_all_users do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {user_id, user_info} -> 
      Map.put(user_info, :user_id, user_id)
    end)
  end

  @doc """
  Get user count.
  """
  def user_count do
    :ets.info(@table_name, :size)
  end

  @doc """
  List users by status.
  """
  def list_users_by_status(status) do
    :ets.match_object(@table_name, {:_, %{status: status}})
    |> Enum.map(fn {user_id, user_info} -> 
      Map.put(user_info, :user_id, user_id)
    end)
  end

  @doc """
  Get users that have been inactive for more than the threshold.
  """
  def list_inactive_users(threshold_ms \\ @inactive_threshold) do
    now = System.system_time(:millisecond)
    cutoff = now - threshold_ms
    
    :ets.foldl(fn {user_id, user_info}, acc ->
      case user_info do
        %{last_activity: last_activity} when last_activity < cutoff ->
          [Map.put(user_info, :user_id, user_id) | acc]
        _ ->
          acc
      end
    end, [], @table_name)
  end

  @doc """
  Update user's last activity timestamp.
  """
  def update_last_activity(user_id) when is_binary(user_id) do
    case lookup_user(user_id) do
      {:ok, user_info} ->
        updated_info = Map.put(user_info, :last_activity, System.system_time(:millisecond))
        update_user(user_id, updated_info)
        
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Get registry statistics for monitoring.
  """
  def get_statistics do
    now = System.system_time(:millisecond)
    users = list_all_users()
    
    active_users = Enum.count(users, fn user ->
      case user do
        %{last_activity: last_activity} when is_integer(last_activity) ->
          now - last_activity < @inactive_threshold
        _ -> false
      end
    end)

    status_counts = Enum.reduce(users, %{}, fn user, acc ->
      status = Map.get(user, :status, :unknown)
      Map.update(acc, status, 1, &(&1 + 1))
    end)

    %{
      total_users: length(users),
      active_users: active_users,
      inactive_users: length(users) - active_users,
      status_breakdown: status_counts,
      table_size: :ets.info(@table_name, :size),
      table_memory: :ets.info(@table_name, :memory),
      last_updated: now
    }
  end

  @doc """
  Perform maintenance operations on the registry.
  """
  def maintenance do
    GenServer.cast(__MODULE__, :maintenance)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting UserRegistry")
    
    # Create ETS table for fast lookups
    table = :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %{
      table: table,
      started_at: System.system_time(:millisecond)
    }
    
    Logger.info("UserRegistry started successfully with table: #{inspect(table)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_user, user_id, user_info}, _from, state) do
    Logger.debug("Registering user: #{user_id}", user_id: user_id)
    
    # Add registration timestamp
    enhanced_info = Map.merge(user_info, %{
      registered_at: System.system_time(:millisecond),
      updated_at: System.system_time(:millisecond)
    })
    
    case :ets.insert(@table_name, {user_id, enhanced_info}) do
      true ->
        Logger.info("User registered successfully", user_id: user_id)
        {:reply, :ok, state}
        
      false ->
        Logger.error("Failed to register user", user_id: user_id)
        {:reply, {:error, :registration_failed}, state}
    end
  end

  @impl true
  def handle_call({:update_user, user_id, user_info}, _from, state) do
    Logger.debug("Updating user: #{user_id}", user_id: user_id)
    
    case lookup_user(user_id) do
      {:ok, existing_info} ->
        # Merge with existing info and update timestamp
        merged_info = Map.merge(existing_info, user_info)
        enhanced_info = Map.put(merged_info, :updated_at, System.system_time(:millisecond))
        
        case :ets.insert(@table_name, {user_id, enhanced_info}) do
          true ->
            {:reply, :ok, state}
            
          false ->
            Logger.error("Failed to update user", user_id: user_id)
            {:reply, {:error, :update_failed}, state}
        end
        
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:remove_user, user_id}, _from, state) do
    Logger.info("Removing user from registry", user_id: user_id)
    
    case :ets.delete(@table_name, user_id) do
      true ->
        {:reply, :ok, state}
        
      false ->
        Logger.error("Failed to remove user", user_id: user_id)
        {:reply, {:error, :removal_failed}, state}
    end
  end

  @impl true
  def handle_cast(:maintenance, state) do
    Logger.debug("Performing UserRegistry maintenance")
    
    # Clean up stale entries
    cleanup_stale_entries()
    
    # Log statistics
    stats = get_statistics()
    Logger.info("UserRegistry maintenance completed", 
      total_users: stats.total_users,
      active_users: stats.active_users,
      table_memory: stats.table_memory
    )
    
    # Schedule next cleanup
    schedule_cleanup()
    
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    maintenance()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in UserRegistry: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("UserRegistry terminating: #{inspect(reason)}")
    
    # ETS table will be automatically cleaned up
    :ok
  end

  # Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_stale_entries do
    # Find users with dead processes
    stale_users = :ets.foldl(fn {user_id, user_info}, acc ->
      if user_has_dead_processes?(user_info) do
        [user_id | acc]
      else
        acc
      end
    end, [], @table_name)
    
    # Remove stale entries
    Enum.each(stale_users, fn user_id ->
      Logger.info("Removing stale user entry", user_id: user_id)
      :ets.delete(@table_name, user_id)
    end)
    
    if length(stale_users) > 0 do
      Logger.info("Cleaned up #{length(stale_users)} stale user entries")
    end
  end

  defp user_has_dead_processes?(user_info) do
    pids_to_check = [
      Map.get(user_info, :supervisor_pid),
      Map.get(user_info, :connection_pid),
      Map.get(user_info, :credential_manager_pid),
      Map.get(user_info, :health_monitor_pid)
    ]
    
    # If any critical PIDs are dead, consider the user stale
    Enum.any?(pids_to_check, fn pid ->
      is_pid(pid) and not Process.alive?(pid)
    end)
  end
end