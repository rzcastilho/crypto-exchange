defmodule CryptoExchange.Trading.UserConnection do
  @moduledoc """
  GenServer representing a single user's trading connection and session.

  This module handles:
  - Managing user credentials securely in process state
  - Processing trading operations for a specific user (orders, balance, etc.)
  - Maintaining user-specific trading state and context
  - Providing isolation between different users' trading activities

  Each UserConnection is supervised by the UserManager DynamicSupervisor
  and represents one user's trading session. The process lifecycle matches
  the user's connection lifecycle.

  ## Trading Operations
  - Place orders (market, limit, stop-loss, etc.)
  - Cancel existing orders
  - Query account balance
  - Get order history and status
  - Subscribe to user-specific trading events

  ## Security
  - API credentials are stored only in process state
  - Credentials are never logged or exposed
  - Each user operates in complete isolation

  ## Usage Examples
  ```elixir
  # Note: UserConnection is typically managed by UserManager
  # Direct usage is not recommended, but shown for completeness

  # Place a limit buy order
  {:ok, order} = UserConnection.place_order("user_123", %{
    symbol: "BTCUSDT",
    side: "BUY",
    type: "LIMIT",
    quantity: "0.001",
    price: "50000"
  })

  # Cancel an order
  {:ok, cancelled} = UserConnection.cancel_order("user_123", "order_id_123")

  # Get account balance
  {:ok, balances} = UserConnection.get_balance("user_123")

  # Get order history
  {:ok, orders} = UserConnection.get_orders("user_123")
  ```

  ## Process Registration
  Each UserConnection process is registered in the Registry with the key
  `{:user_connection, user_id}`, enabling efficient process discovery
  and ensuring only one connection per user.

  This is a placeholder implementation for Phase 1. Future phases will
  implement the full trading functionality with proper Binance API integration.
  """

  use GenServer
  require Logger

  ## Client API

  @doc """
  Starts a UserConnection for a specific user.

  ## Parameters
  - `{user_id, credentials}`: Tuple containing user ID and credentials map
  """
  def start_link({user_id, credentials}) do
    GenServer.start_link(__MODULE__, {user_id, credentials}, name: via_tuple(user_id))
  end

  @doc """
  Places an order for the user.

  This is a placeholder function for Phase 1.
  """
  def place_order(user_id, order_params) do
    GenServer.call(via_tuple(user_id), {:place_order, order_params})
  end

  @doc """
  Cancels an order for the user.

  This is a placeholder function for Phase 1.
  """
  def cancel_order(user_id, order_id) do
    GenServer.call(via_tuple(user_id), {:cancel_order, order_id})
  end

  @doc """
  Gets the account balance for the user.

  This is a placeholder function for Phase 1.
  """
  def get_balance(user_id) do
    GenServer.call(via_tuple(user_id), :get_balance)
  end

  @doc """
  Gets the order history for the user.

  This is a placeholder function for Phase 1.
  """
  def get_orders(user_id) do
    GenServer.call(via_tuple(user_id), :get_orders)
  end

  ## Server Callbacks

  @impl true
  def init({user_id, credentials}) do
    Logger.info("UserConnection started for user: #{user_id}")

    # Initialize state with user credentials and trading context
    # In future phases, this will validate credentials and establish
    # authenticated connections with the exchange
    state = %{
      user_id: user_id,
      credentials: credentials,
      orders: %{},
      balance: %{},
      connected_at: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:place_order, order_params}, _from, state) do
    Logger.debug("Place order request for user #{state.user_id}: #{inspect(order_params)}")

    # Placeholder implementation
    # In future phases, this will:
    # 1. Validate order parameters
    # 2. Make authenticated API call to exchange
    # 3. Handle response and update state
    # 4. Return order confirmation or error

    response = {:error, :not_implemented}
    {:reply, response, state}
  end

  @impl true
  def handle_call({:cancel_order, order_id}, _from, state) do
    Logger.debug("Cancel order request for user #{state.user_id}: #{order_id}")

    # Placeholder implementation
    response = {:error, :not_implemented}
    {:reply, response, state}
  end

  @impl true
  def handle_call(:get_balance, _from, state) do
    Logger.debug("Get balance request for user #{state.user_id}")

    # Placeholder implementation
    response = {:error, :not_implemented}
    {:reply, response, state}
  end

  @impl true
  def handle_call(:get_orders, _from, state) do
    Logger.debug("Get orders request for user #{state.user_id}")

    # Placeholder implementation
    response = {:error, :not_implemented}
    {:reply, response, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug(
      "UserConnection for user #{state.user_id} received unexpected message: #{inspect(msg)}"
    )

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("UserConnection for user #{state.user_id} terminating: #{inspect(reason)}")
    :ok
  end

  ## Private Functions

  defp via_tuple(user_id) do
    {:via, Registry, {CryptoExchange.Registry, {:user_connection, user_id}}}
  end
end
