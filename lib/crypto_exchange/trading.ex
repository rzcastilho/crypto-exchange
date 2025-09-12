defmodule CryptoExchange.Trading do
  @moduledoc """
  Main public API for the CryptoExchange trading system.

  This module provides a unified interface for all trading operations, abstracting
  away the complexities of user connection management, authentication, and API
  integration. It serves as the primary entry point for applications using the
  crypto exchange library.

  ## Features

  - **User Management**: Automatic connection lifecycle management
  - **Order Operations**: Place, cancel, and query orders
  - **Account Management**: Balance queries and account information
  - **Error Handling**: Consistent error responses across all operations
  - **Authentication**: Secure API key management

  ## Usage Examples

  ```elixir
  # Connect a user with their API credentials
  credentials = %{
    api_key: "your_binance_api_key", 
    secret_key: "your_binance_secret_key"
  }

  {:ok, user_id} = Trading.connect_user("alice", credentials)

  # Place a limit buy order
  order_params = %{
    symbol: "BTCUSDT",
    side: "BUY", 
    type: "LIMIT",
    quantity: "0.001",
    price: "50000.00",
    timeInForce: "GTC"
  }

  {:ok, order} = Trading.place_order("alice", order_params)

  # Get account balance
  {:ok, balances} = Trading.get_balance("alice")

  # Cancel an order
  {:ok, cancelled_order} = Trading.cancel_order("alice", "BTCUSDT", order.id)

  # Get order history
  {:ok, orders} = Trading.get_orders("alice")

  # Disconnect user when done
  :ok = Trading.disconnect_user("alice")
  ```

  ## Error Handling

  All functions return either `{:ok, result}` or `{:error, reason}`. Common errors include:
  - `:user_not_found` - User is not connected
  - `:invalid_credentials` - API credentials are invalid
  - `:insufficient_balance` - Not enough funds for the operation
  - `:invalid_symbol` - Trading symbol is not valid
  - `:api_error` - Binance API returned an error

  ## Process Management

  Each connected user runs in their own supervised GenServer process, providing
  isolation and fault tolerance. If a user process crashes, it does not affect
  other users or the system stability.
  """

  alias CryptoExchange.Trading.{UserManager, UserConnection}
  require Logger

  @type user_id :: String.t()
  @type credentials :: %{api_key: String.t(), secret_key: String.t()}
  @type order_params :: %{
          symbol: String.t(),
          side: String.t(),
          type: String.t()
        }

  @doc """
  Connects a user to the trading system with their API credentials.

  This function starts a supervised UserConnection process for the user,
  establishing an authenticated session with the Binance API.

  ## Parameters
  - `user_id`: Unique identifier for the user
  - `credentials`: Map containing :api_key and :secret_key

  ## Returns
  - `{:ok, user_id}` on successful connection
  - `{:error, reason}` if connection fails

  ## Example
  ```elixir
  credentials = %{
    api_key: "your_api_key",
    secret_key: "your_secret_key"
  }

  {:ok, "alice"} = Trading.connect_user("alice", credentials)
  ```
  """
  @spec connect_user(user_id(), credentials()) :: {:ok, user_id()} | {:error, term()}
  def connect_user(user_id, credentials) when is_binary(user_id) and is_map(credentials) do
    Logger.info("Connecting user: #{user_id}")

    case UserManager.connect_user(user_id, credentials) do
      {:ok, _pid} ->
        Logger.info("User #{user_id} connected successfully")
        {:ok, user_id}

      {:error, {:already_started, _pid}} ->
        Logger.info("User #{user_id} already connected")
        {:ok, user_id}

      {:error, reason} = error ->
        Logger.error("Failed to connect user #{user_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Disconnects a user from the trading system.

  This stops the user's connection process and cleans up associated resources.
  Any pending operations will be cancelled.

  ## Parameters
  - `user_id`: User identifier to disconnect

  ## Returns
  - `:ok` on successful disconnection
  - `{:error, :user_not_found}` if user is not connected

  ## Example
  ```elixir
  :ok = Trading.disconnect_user("alice")
  ```
  """
  @spec disconnect_user(user_id()) :: :ok | {:error, :user_not_found}
  def disconnect_user(user_id) when is_binary(user_id) do
    Logger.info("Disconnecting user: #{user_id}")

    case UserManager.disconnect_user(user_id) do
      :ok ->
        Logger.info("User #{user_id} disconnected successfully")
        :ok

      {:error, :not_found} ->
        Logger.warning("User #{user_id} was not connected")
        {:error, :user_not_found}

      {:error, reason} = error ->
        Logger.error("Failed to disconnect user #{user_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Places a trading order for the specified user.

  ## Parameters
  - `user_id`: User identifier
  - `order_params`: Map containing order details

  ## Required Order Parameters
  - `symbol`: Trading symbol (e.g., "BTCUSDT")
  - `side`: "BUY" or "SELL"
  - `type`: "MARKET", "LIMIT", etc.
  - Additional parameters depend on order type

  ## Returns
  - `{:ok, order}` containing order details
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  order_params = %{
    symbol: "BTCUSDT",
    side: "BUY",
    type: "LIMIT", 
    quantity: "0.001",
    price: "50000.00",
    timeInForce: "GTC"
  }

  {:ok, order} = Trading.place_order("alice", order_params)
  ```
  """
  @spec place_order(user_id(), order_params()) :: {:ok, term()} | {:error, term()}
  def place_order(user_id, order_params) when is_binary(user_id) and is_map(order_params) do
    Logger.info(
      "Placing order for user #{user_id}: #{order_params["symbol"]} #{order_params["side"]}"
    )

    with {:ok, _pid} <- find_user_connection(user_id) do
      UserConnection.place_order(user_id, order_params)
    end
  end

  @doc """
  Cancels an existing order for the specified user.

  ## Parameters
  - `user_id`: User identifier
  - `symbol`: Trading symbol (e.g., "BTCUSDT")
  - `order_id`: Order ID to cancel

  ## Returns
  - `{:ok, cancelled_order}` on successful cancellation
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  {:ok, cancelled_order} = Trading.cancel_order("alice", "BTCUSDT", "123456789")
  ```
  """
  @spec cancel_order(user_id(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def cancel_order(user_id, symbol, order_id)
      when is_binary(user_id) and is_binary(symbol) and is_binary(order_id) do
    Logger.info("Cancelling order #{order_id} for user #{user_id}")

    with {:ok, _pid} <- find_user_connection(user_id) do
      UserConnection.cancel_order(user_id, symbol, order_id)
    end
  end

  @doc """
  Gets the account balance for the specified user.

  Returns only non-zero balances to reduce clutter.

  ## Parameters  
  - `user_id`: User identifier

  ## Returns
  - `{:ok, balances}` list of Balance structs
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  {:ok, balances} = Trading.get_balance("alice")
  # balances is a list of Balance structs with non-zero amounts
  ```
  """
  @spec get_balance(user_id()) :: {:ok, list()} | {:error, term()}
  def get_balance(user_id) when is_binary(user_id) do
    Logger.debug("Getting balance for user #{user_id}")

    with {:ok, _pid} <- find_user_connection(user_id) do
      UserConnection.get_balance(user_id)
    end
  end

  @doc """
  Gets the order history for the specified user.

  Returns recent orders (up to 50) sorted by creation time.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, orders}` list of Order structs  
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  {:ok, orders} = Trading.get_orders("alice") 
  # orders is a list of recent Order structs
  ```
  """
  @spec get_orders(user_id()) :: {:ok, list()} | {:error, term()}
  def get_orders(user_id) when is_binary(user_id) do
    Logger.debug("Getting orders for user #{user_id}")

    with {:ok, _pid} <- find_user_connection(user_id) do
      UserConnection.get_orders(user_id)
    end
  end

  @doc """
  Gets information about a connected user.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, user_info}` containing connection details
  - `{:error, :user_not_found}` if user is not connected

  ## Example  
  ```elixir
  {:ok, user_info} = Trading.get_user_info("alice")
  # user_info contains connection details
  ```
  """
  @spec get_user_info(user_id()) :: {:ok, map()} | {:error, :user_not_found}
  def get_user_info(user_id) when is_binary(user_id) do
    case find_user_connection(user_id) do
      {:ok, pid} ->
        user_info = %{
          user_id: user_id,
          pid: pid,
          connected_at: GenServer.call(via_tuple(user_id), :get_connected_at)
        }

        {:ok, user_info}

      {:error, :user_not_found} = error ->
        error
    end
  rescue
    _ -> {:error, :user_not_found}
  end

  @doc """
  Lists all currently connected users.

  ## Returns
  List of user IDs that are currently connected.

  ## Example
  ```elixir
  connected_users = Trading.list_connected_users()
  # Returns list of user IDs currently connected
  ```
  """
  @spec list_connected_users() :: [user_id()]
  def list_connected_users do
    UserManager.list_connected_users()
  end

  @doc """
  Checks if a user is currently connected.

  ## Parameters
  - `user_id`: User identifier to check

  ## Returns
  Boolean indicating connection status.

  ## Example
  ```elixir
  connected = Trading.user_connected?("alice")
  # Returns true if user is connected
  ```
  """
  @spec user_connected?(user_id()) :: boolean()
  def user_connected?(user_id) when is_binary(user_id) do
    case find_user_connection(user_id) do
      {:ok, _pid} -> true
      {:error, :user_not_found} -> false
    end
  end

  @doc """
  Gets system-wide trading statistics.

  ## Returns
  Map containing system statistics.

  ## Example
  ```elixir
  stats = Trading.get_system_stats()
  # Returns map with system statistics
  ```
  """
  @spec get_system_stats() :: map()
  def get_system_stats do
    connected_users = list_connected_users()

    %{
      connected_users: length(connected_users),
      total_connections: UserManager.connected_user_count(),
      users: connected_users
    }
  end

  # Private Functions

  defp find_user_connection(user_id) do
    case Registry.lookup(CryptoExchange.Registry, {:user_connection, user_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :user_not_found}
    end
  end

  defp via_tuple(user_id) do
    {:via, Registry, {CryptoExchange.Registry, {:user_connection, user_id}}}
  end
end
