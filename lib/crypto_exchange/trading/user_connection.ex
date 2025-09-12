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
  """

  use GenServer
  require Logger

  alias CryptoExchange.Binance.PrivateClient
  alias CryptoExchange.Models.{Order, Account}

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

  ## Parameters
  - `user_id`: User identifier
  - `symbol`: Trading symbol (e.g., "BTCUSDT")
  - `order_id`: Order ID to cancel

  ## Returns
  - `{:ok, cancelled_order}` on success
  - `{:error, reason}` on failure
  """
  def cancel_order(user_id, symbol, order_id) do
    GenServer.call(via_tuple(user_id), {:cancel_order, symbol, order_id})
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

    # Create private client for this user
    case PrivateClient.new(credentials) do
      {:ok, client} ->
        state = %{
          user_id: user_id,
          client: client,
          connected_at: DateTime.utc_now()
        }

        Logger.info("UserConnection initialized for user: #{user_id}")
        {:ok, state}

      {:error, reason} ->
        Logger.error(
          "Failed to initialize UserConnection for user #{user_id}: #{inspect(reason)}"
        )

        {:stop, {:error, :invalid_credentials}}
    end
  end

  @impl true
  def handle_call({:place_order, order_params}, _from, state) do
    Logger.debug("Place order request for user #{state.user_id}: #{inspect(order_params)}")

    case Order.validate_params(order_params) do
      :ok ->
        case PrivateClient.place_order(state.client, order_params) do
          {:ok, order_data} ->
            case Order.parse(order_data) do
              {:ok, order} ->
                Logger.info("Order placed successfully for user #{state.user_id}: #{order.id}")
                {:reply, {:ok, order}, state}

              {:error, reason} ->
                Logger.error(
                  "Failed to parse order response for user #{state.user_id}: #{inspect(reason)}"
                )

                {:reply, {:error, :parse_error}, state}
            end

          {:error, reason} = error ->
            Logger.error("Failed to place order for user #{state.user_id}: #{inspect(reason)}")
            {:reply, error, state}
        end

      {:error, reason} = error ->
        Logger.warning("Invalid order parameters for user #{state.user_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:cancel_order, symbol, order_id}, _from, state) do
    Logger.debug("Cancel order request for user #{state.user_id}: #{order_id} on #{symbol}")

    case PrivateClient.cancel_order(state.client, symbol, order_id) do
      {:ok, cancelled_order_data} ->
        case Order.parse(cancelled_order_data) do
          {:ok, order} ->
            Logger.info("Order cancelled successfully for user #{state.user_id}: #{order.id}")
            {:reply, {:ok, order}, state}

          {:error, reason} ->
            Logger.error(
              "Failed to parse cancelled order response for user #{state.user_id}: #{inspect(reason)}"
            )

            {:reply, {:error, :parse_error}, state}
        end

      {:error, reason} = error ->
        Logger.error("Failed to cancel order for user #{state.user_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_balance, _from, state) do
    Logger.debug("Get balance request for user #{state.user_id}")

    case PrivateClient.get_account(state.client) do
      {:ok, account_data} ->
        case Account.parse(account_data) do
          {:ok, account} ->
            non_zero_balances = Account.non_zero_balances(account)

            Logger.debug(
              "Balance retrieved for user #{state.user_id}: #{length(non_zero_balances)} non-zero balances"
            )

            {:reply, {:ok, non_zero_balances}, state}

          {:error, reason} ->
            Logger.error(
              "Failed to parse account data for user #{state.user_id}: #{inspect(reason)}"
            )

            {:reply, {:error, :parse_error}, state}
        end

      {:error, reason} = error ->
        Logger.error("Failed to get balance for user #{state.user_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_orders, _from, state) do
    Logger.debug("Get orders request for user #{state.user_id}")

    case PrivateClient.get_orders(state.client, "BTCUSDT") do
      {:ok, orders_data} ->
        parsed_orders =
          orders_data
          |> Enum.map(&Order.parse/1)
          |> Enum.reduce_while({:ok, []}, fn
            {:ok, order}, {:ok, acc} -> {:cont, {:ok, [order | acc]}}
            {:error, reason}, _acc -> {:halt, {:error, {:parse_error, reason}}}
          end)

        case parsed_orders do
          {:ok, orders} ->
            recent_orders = Enum.reverse(orders) |> Enum.take(50)

            Logger.debug(
              "Orders retrieved for user #{state.user_id}: #{length(recent_orders)} orders"
            )

            {:reply, {:ok, recent_orders}, state}

          {:error, reason} ->
            Logger.error("Failed to parse orders for user #{state.user_id}: #{inspect(reason)}")
            {:reply, {:error, :parse_error}, state}
        end

      {:error, reason} = error ->
        Logger.error("Failed to get orders for user #{state.user_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_connected_at, _from, state) do
    {:reply, state.connected_at, state}
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
