defmodule CryptoExchange.API do
  @moduledoc """
  Main public API for the CryptoExchange library.

  This module provides the primary interface for both public market data streaming
  and private user trading operations.

  ## Public Data Operations

  These operations do not require authentication and provide access to real-time
  market data via Phoenix.PubSub:

  - `subscribe_to_ticker/1` - Subscribe to ticker price updates
  - `subscribe_to_depth/2` - Subscribe to order book depth data
  - `subscribe_to_trades/1` - Subscribe to trade execution data
  - `unsubscribe_from_public_data/1` - Unsubscribe from public data streams

  ## User Trading Operations

  These operations require Binance API credentials and manage isolated user sessions:

  - `connect_user/3` - Connect a user with API credentials
  - `disconnect_user/1` - Disconnect a user session
  - `place_order/2` - Place a trading order
  - `cancel_order/2` - Cancel an existing order
  - `get_balance/1` - Get account balance information
  - `get_orders/1` - Get open/recent orders
  """

  # Public Data Operations (no authentication required)

  @doc """
  Subscribe to ticker updates for a given symbol.

  Returns a Phoenix.PubSub topic that can be subscribed to for receiving
  real-time ticker updates.

  ## Examples

      {:ok, topic} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  """
  def subscribe_to_ticker(_symbol) do
    # TODO: Implementation will delegate to PublicStreams.StreamManager
    {:error, :not_implemented}
  end

  @doc """
  Subscribe to order book depth data for a given symbol.

  ## Examples

      {:ok, topic} = CryptoExchange.API.subscribe_to_depth("BTCUSDT", 5)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  """
  def subscribe_to_depth(_symbol, _level \\ 5) do
    # TODO: Implementation will delegate to PublicStreams.StreamManager
    {:error, :not_implemented}
  end

  @doc """
  Subscribe to trade execution data for a given symbol.

  ## Examples

      {:ok, topic} = CryptoExchange.API.subscribe_to_trades("BTCUSDT")
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  """
  def subscribe_to_trades(_symbol) do
    # TODO: Implementation will delegate to PublicStreams.StreamManager
    {:error, :not_implemented}
  end

  @doc """
  Unsubscribe from public data streams for a given symbol.

  ## Examples

      :ok = CryptoExchange.API.unsubscribe_from_public_data("BTCUSDT")

  """
  def unsubscribe_from_public_data(_symbol) do
    # TODO: Implementation will delegate to PublicStreams.StreamManager
    {:error, :not_implemented}
  end

  # User Trading Operations (require authentication)

  @doc """
  Connect a user with their Binance API credentials.

  This creates an isolated user session for trading operations.

  ## Examples

      {:ok, pid} = CryptoExchange.API.connect_user("user1", "api_key", "secret_key")

  """
  def connect_user(_user_id, _api_key, _secret_key) do
    # TODO: Implementation will delegate to Trading.UserManager
    {:error, :not_implemented}
  end

  @doc """
  Disconnect a user session.

  ## Examples

      :ok = CryptoExchange.API.disconnect_user("user1")

  """
  def disconnect_user(_user_id) do
    # TODO: Implementation will delegate to Trading.UserManager
    {:error, :not_implemented}
  end

  @doc """
  Place a trading order for a user.

  ## Examples

      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: "0.001",
        price: "50000"
      }
      {:ok, order} = CryptoExchange.API.place_order("user1", order_params)

  """
  def place_order(_user_id, _order_params) do
    # TODO: Implementation will delegate to Trading.UserConnection
    {:error, :not_implemented}
  end

  @doc """
  Cancel an existing order for a user.

  ## Examples

      {:ok, cancelled_order} = CryptoExchange.API.cancel_order("user1", "order_id_123")

  """
  def cancel_order(_user_id, _order_id) do
    # TODO: Implementation will delegate to Trading.UserConnection
    {:error, :not_implemented}
  end

  @doc """
  Get account balance information for a user.

  ## Examples

      {:ok, balances} = CryptoExchange.API.get_balance("user1")

  """
  def get_balance(_user_id) do
    # TODO: Implementation will delegate to Trading.UserConnection
    {:error, :not_implemented}
  end

  @doc """
  Get open and recent orders for a user.

  ## Examples

      {:ok, orders} = CryptoExchange.API.get_orders("user1")

  """
  def get_orders(_user_id) do
    # TODO: Implementation will delegate to Trading.UserConnection
    {:error, :not_implemented}
  end
end