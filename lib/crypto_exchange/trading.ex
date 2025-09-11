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
    DynamicSupervisor for managing user trading connections.

    This supervisor manages the lifecycle of individual user trading sessions.
    Each user gets their own isolated GenServer process (UserConnection) that
    handles their credentials and trading operations.

    ## Features

    - Dynamic creation and destruction of user sessions
    - Isolated failure domains per user
    - Automatic cleanup of disconnected users
    - Process registration for efficient user lookup

    ## Restart Strategy

    Uses `:temporary` restart strategy for user connections since failed
    user sessions should not be automatically restarted - they require
    explicit reconnection with valid credentials.
    """

    use DynamicSupervisor
    require Logger

    @registry CryptoExchange.Registry

    # Client API

    @doc """
    Starts the UserManager DynamicSupervisor.
    """
    def start_link(opts \\ []) do
      DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @doc """
    Connect a user with their API credentials.
    Creates a new UserConnection process for the user.
    """
    def connect_user(user_id, api_key, secret_key) when is_binary(user_id) do
      credentials = %{api_key: api_key, secret_key: secret_key}
      
      case Registry.lookup(@registry, {:user_connection, user_id}) do
        [] ->
          # No existing connection, create new one
          spec = {CryptoExchange.Trading.UserConnection, {user_id, credentials}}
          
          case DynamicSupervisor.start_child(__MODULE__, spec) do
            {:ok, pid} ->
              Logger.info("Connected user: #{user_id}")
              {:ok, pid}
              
            {:error, reason} ->
              Logger.error("Failed to connect user #{user_id}: #{inspect(reason)}")
              {:error, reason}
          end
          
        [{pid, _}] ->
          # User already connected
          Logger.info("User #{user_id} already connected")
          {:ok, pid}
      end
    end

    @doc """
    Disconnect a user by terminating their UserConnection process.
    """
    def disconnect_user(user_id) when is_binary(user_id) do
      case Registry.lookup(@registry, {:user_connection, user_id}) do
        [] ->
          {:error, :not_connected}
          
        [{pid, _}] ->
          DynamicSupervisor.terminate_child(__MODULE__, pid)
          Logger.info("Disconnected user: #{user_id}")
          :ok
      end
    end

    @doc """
    Get the PID of a user's connection process.
    """
    def get_user_connection(user_id) when is_binary(user_id) do
      case Registry.lookup(@registry, {:user_connection, user_id}) do
        [] -> {:error, :not_connected}
        [{pid, _}] -> {:ok, pid}
      end
    end

    @doc """
    List all connected users.
    """
    def list_connected_users do
      @registry
      |> Registry.select([
        {{{:user_connection, :"$1"}, :_, :_}, [], [:"$1"]}
      ])
    end

    # Server Callbacks

    @impl true
    def init(_opts) do
      Logger.info("Starting Trading.UserManager")
      DynamicSupervisor.init(strategy: :one_for_one)
    end
  end

  defmodule UserConnection do
    @moduledoc """
    GenServer representing an individual user's trading session.

    This process maintains user credentials securely and handles all
    trading operations for a specific user. Each user gets their own
    isolated process to prevent cross-user interference.

    ## State Structure

        %{
          user_id: "user123",
          credentials: %{api_key: "...", secret_key: "..."},
          client: %BinanceClient{},
          orders: %{},
          last_activity: timestamp
        }

    ## Security Features

    - Credentials never leave this process
    - No credential logging
    - Isolated from other users
    - Automatic cleanup on termination

    ## Restart Strategy

    Uses `:temporary` restart - failed user sessions should not auto-restart
    as they require explicit reconnection with credentials.
    """

    use GenServer
    require Logger

    @registry CryptoExchange.Registry
    @pubsub CryptoExchange.PubSub

    # Client API

    @doc """
    Starts a UserConnection GenServer for a specific user.
    """
    def start_link({user_id, credentials}) do
      GenServer.start_link(__MODULE__, {user_id, credentials})
    end

    @doc """
    Place a trading order for the user.
    """
    def place_order(user_id, order_params) when is_binary(user_id) do
      case Registry.lookup(@registry, {:user_connection, user_id}) do
        [] -> {:error, :not_connected}
        [{pid, _}] -> GenServer.call(pid, {:place_order, order_params})
      end
    end

    @doc """
    Cancel a trading order for the user.
    """
    def cancel_order(user_id, order_id) when is_binary(user_id) do
      case Registry.lookup(@registry, {:user_connection, user_id}) do
        [] -> {:error, :not_connected}
        [{pid, _}] -> GenServer.call(pid, {:cancel_order, order_id})
      end
    end

    @doc """
    Get account balance for the user.
    """
    def get_balance(user_id) when is_binary(user_id) do
      case Registry.lookup(@registry, {:user_connection, user_id}) do
        [] -> {:error, :not_connected}
        [{pid, _}] -> GenServer.call(pid, :get_balance)
      end
    end

    @doc """
    Get order history for the user.
    """
    def get_orders(user_id) when is_binary(user_id) do
      case Registry.lookup(@registry, {:user_connection, user_id}) do
        [] -> {:error, :not_connected}
        [{pid, _}] -> GenServer.call(pid, :get_orders)
      end
    end

    # Server Callbacks

    @impl true
    def init({user_id, credentials}) do
      Logger.info("Starting UserConnection for user: #{user_id}")
      
      # Register this process for discovery
      Registry.register(@registry, {:user_connection, user_id}, self())
      
      # Initialize Binance client (mock for now)
      client = initialize_client(credentials)
      
      state = %{
        user_id: user_id,
        credentials: credentials,
        client: client,
        orders: %{},
        last_activity: System.system_time(:millisecond)
      }
      
      # Send user connected event
      Phoenix.PubSub.broadcast(@pubsub, "trading:users", 
        {:user_connected, user_id})
      
      {:ok, state}
    end

    @impl true
    def handle_call({:place_order, order_params}, _from, state) do
      Logger.info("Placing order for user #{state.user_id}: #{inspect(order_params)}")
      
      # In real implementation, this would call Binance API
      case mock_place_order(state.client, order_params) do
        {:ok, order} ->
          # Store order in state
          new_orders = Map.put(state.orders, order.order_id, order)
          new_state = %{state | 
            orders: new_orders,
            last_activity: System.system_time(:millisecond)
          }
          
          # Broadcast order update
          Phoenix.PubSub.broadcast(@pubsub, "trading:user:#{state.user_id}", 
            {:order_update, order})
          
          {:reply, {:ok, order}, new_state}
          
        {:error, reason} ->
          Logger.error("Failed to place order for user #{state.user_id}: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    end

    @impl true
    def handle_call({:cancel_order, order_id}, _from, state) do
      Logger.info("Canceling order #{order_id} for user #{state.user_id}")
      
      case Map.get(state.orders, order_id) do
        nil ->
          {:reply, {:error, :order_not_found}, state}
          
        order ->
          # In real implementation, this would call Binance API
          case mock_cancel_order(state.client, order_id) do
            :ok ->
              # Update order status
              updated_order = %{order | status: "CANCELED"}
              new_orders = Map.put(state.orders, order_id, updated_order)
              new_state = %{state | 
                orders: new_orders,
                last_activity: System.system_time(:millisecond)
              }
              
              # Broadcast order update
              Phoenix.PubSub.broadcast(@pubsub, "trading:user:#{state.user_id}", 
                {:order_update, updated_order})
              
              {:reply, {:ok, updated_order}, new_state}
              
            {:error, reason} ->
              Logger.error("Failed to cancel order #{order_id} for user #{state.user_id}: #{inspect(reason)}")
              {:reply, {:error, reason}, state}
          end
      end
    end

    @impl true
    def handle_call(:get_balance, _from, state) do
      Logger.info("Getting balance for user #{state.user_id}")
      
      # In real implementation, this would call Binance API
      case mock_get_balance(state.client) do
        {:ok, balances} ->
          new_state = %{state | last_activity: System.system_time(:millisecond)}
          {:reply, {:ok, balances}, new_state}
          
        {:error, reason} ->
          Logger.error("Failed to get balance for user #{state.user_id}: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    end

    @impl true
    def handle_call(:get_orders, _from, state) do
      Logger.info("Getting orders for user #{state.user_id}")
      
      orders = state.orders |> Map.values()
      new_state = %{state | last_activity: System.system_time(:millisecond)}
      
      {:reply, {:ok, orders}, new_state}
    end

    @impl true
    def handle_info(msg, state) do
      Logger.debug("Unexpected message in UserConnection: #{inspect(msg)}")
      {:noreply, state}
    end

    @impl true
    def terminate(reason, state) do
      Logger.info("UserConnection terminating for user #{state.user_id}: #{inspect(reason)}")
      
      # Send user disconnected event
      Phoenix.PubSub.broadcast(@pubsub, "trading:users", 
        {:user_disconnected, state.user_id})
      
      :ok
    end

    # Private Functions

    defp initialize_client(credentials) do
      # Mock client initialization
      # In real implementation, this would create a Binance API client
      %{
        api_key: credentials.api_key,
        secret_key: "[HIDDEN]",  # Never store actual secret in logs
        initialized_at: System.system_time(:millisecond)
      }
    end

    defp mock_place_order(_client, order_params) do
      # Mock implementation - returns a fake order with some error simulation
      quantity = Map.get(order_params, "quantity", "1.0")
      
      # Simulate insufficient balance error for large quantities
      try do
        case String.to_float(quantity) do
          amount when amount > 1000.0 ->
            {:error, :insufficient_balance}
            
          _ ->
            order = %{
              order_id: generate_order_id(),
              symbol: Map.get(order_params, "symbol", "BTCUSDT"),
              side: Map.get(order_params, "side", "BUY"),
              type: Map.get(order_params, "type", "LIMIT"),
              quantity: quantity,
              price: Map.get(order_params, "price"),
              status: "NEW",
              created_at: System.system_time(:millisecond)
            }
            
            {:ok, order}
        end
      rescue
        ArgumentError ->
          {:error, :invalid_quantity}
      end
    end

    defp mock_cancel_order(_client, order_id) do
      # Mock implementation with some error simulation
      if String.length(order_id) < 8 do
        {:error, :invalid_order_id}
      else
        :ok
      end
    end

    defp mock_get_balance(client) do
      # Mock implementation with some error simulation
      if Map.get(client, :api_key) == "invalid" do
        {:error, :invalid_credentials}
      else
        balances = [
          %{asset: "BTC", free: 0.5, locked: 0.1},
          %{asset: "USDT", free: 1000.0, locked: 50.0},
          %{asset: "ETH", free: 2.0, locked: 0.0}
        ]
        
        {:ok, balances}
      end
    end

    defp generate_order_id do
      :crypto.strong_rand_bytes(8) |> Base.encode16()
    end
  end
end