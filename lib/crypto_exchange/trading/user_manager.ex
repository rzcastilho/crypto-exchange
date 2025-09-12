defmodule CryptoExchange.Trading.UserManager do
  @moduledoc """
  DynamicSupervisor responsible for managing user trading connections.

  This module handles:
  - Starting and stopping UserConnection processes for individual users
  - Managing the lifecycle of user trading sessions
  - Providing isolation between different user trading operations
  - Supervising user connections with proper restart strategies

  Each user gets their own UserConnection process that manages their trading
  operations, credentials, and state. This provides isolation and allows
  individual users to be managed independently.

  The UserManager uses the DynamicSupervisor pattern to allow runtime
  creation and termination of user connections as users connect and
  disconnect from the trading system.

  ## Child Process Structure
  ```
  Trading.UserManager (DynamicSupervisor)
  ├── UserConnection (user_1) 
  ├── UserConnection (user_2)
  └── UserConnection (user_N)
  ```

  ## Usage Examples
  ```elixir
  # Connect a user with credentials
  {:ok, pid} = UserManager.connect_user("user_123", %{
    api_key: "your_binance_api_key",
    secret_key: "your_binance_secret_key"
  })

  # Disconnect a user
  :ok = UserManager.disconnect_user("user_123")

  # Get user connection process
  {:ok, pid} = UserManager.get_user_connection("user_123")

  # List all connected users
  user_ids = UserManager.list_connected_users()
  # => ["user_123", "user_456", "user_789"]

  # Get count of connected users
  count = UserManager.connected_user_count()
  # => 3
  ```

  ## Error Handling
  ```elixir
  # Handle connection errors
  case UserManager.connect_user("user_123", %{invalid: "credentials"}) do
    {:ok, pid} -> 
      Logger.info("User connected: \#{inspect(pid)}")
    {:error, reason} -> 
      Logger.error("Connection failed: \#{inspect(reason)}")
  end

  # Handle disconnection of non-existent user
  case UserManager.disconnect_user("non_existent_user") do
    :ok -> 
      Logger.info("User disconnected")
    {:error, :not_found} -> 
      Logger.warning("User was not connected")
  end
  ```
  """

  use DynamicSupervisor
  require Logger

  @name __MODULE__

  ## Client API

  @doc """
  Starts the UserManager DynamicSupervisor.
  """
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, Keyword.put(opts, :name, @name))
  end

  @doc """
  Connects a user by starting a new UserConnection process.

  ## Parameters
  - `user_id`: Unique identifier for the user
  - `credentials`: Map containing user's API credentials

  ## Returns
  - `{:ok, pid}` on success
  - `{:error, reason}` on failure
  """
  def connect_user(user_id, credentials) do
    Logger.info("Connecting user: #{user_id}")

    # Enhanced child specification with proper restart strategy
    child_spec = %{
      id: {:user_connection, user_id},
      start: {CryptoExchange.Trading.UserConnection, :start_link, [{user_id, credentials}]},
      # Only restart on abnormal termination
      restart: :transient,
      # Allow 5 seconds for graceful shutdown
      shutdown: 5000,
      type: :worker
    }

    case DynamicSupervisor.start_child(@name, child_spec) do
      {:ok, pid} ->
        Logger.info("User #{user_id} connected successfully")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.warning("User #{user_id} already connected")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to connect user #{user_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Disconnects a user by terminating their UserConnection process.

  ## Parameters
  - `user_id`: Unique identifier for the user to disconnect

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if user not found or termination failed
  """
  def disconnect_user(user_id) do
    Logger.info("Disconnecting user: #{user_id}")

    case find_user_connection(user_id) do
      {:ok, pid} ->
        case DynamicSupervisor.terminate_child(@name, pid) do
          :ok ->
            Logger.info("User #{user_id} disconnected successfully")
            :ok

          {:error, reason} = error ->
            Logger.error("Failed to disconnect user #{user_id}: #{inspect(reason)}")
            error
        end

      {:error, :not_found} = error ->
        Logger.warning("User #{user_id} not found for disconnection")
        error
    end
  end

  @doc """
  Gets the UserConnection process for a given user.

  ## Parameters
  - `user_id`: Unique identifier for the user

  ## Returns
  - `{:ok, pid}` if user connection exists
  - `{:error, :not_found}` if user is not connected
  """
  def get_user_connection(user_id) do
    find_user_connection(user_id)
  end

  @doc """
  Lists all connected users.

  ## Returns
  List of user_ids for all currently connected users.
  """
  def list_connected_users do
    # Use DynamicSupervisor to get all children and extract user_ids
    # This is simpler and avoids Registry pattern matching complexity
    @name
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {id, _pid, _, _} ->
      case id do
        {:user_connection, user_id} -> user_id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns the count of currently connected users.
  """
  def connected_user_count do
    @name
    |> DynamicSupervisor.count_children()
    |> Map.get(:active, 0)
  end

  ## Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("UserManager started")

    # Configure DynamicSupervisor with restart strategy
    # :one_for_one means if a UserConnection crashes, only that specific
    # user connection is restarted, not affecting other users
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  ## Private Functions

  defp find_user_connection(user_id) do
    # Use Registry to efficiently find the user's connection process
    case Registry.lookup(CryptoExchange.Registry, {:user_connection, user_id}) do
      [{pid, _}] when is_pid(pid) ->
        # Verify the process is still alive
        if Process.alive?(pid) do
          {:ok, pid}
        else
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end
end
