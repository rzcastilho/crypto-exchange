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

  This creates an isolated user session for trading operations using
  the enhanced UserManager architecture with comprehensive security,
  monitoring, and fault tolerance features.

  ## Parameters
  - `user_id`: Unique identifier for the user
  - `api_key`: Binance API key
  - `secret_key`: Binance secret key

  ## Returns
  - `{:ok, supervisor_pid}`: User successfully connected
  - `{:error, reason}`: Connection failed

  ## Examples

      {:ok, pid} = CryptoExchange.API.connect_user("user1", "api_key", "secret_key")

  ## Error Types
  - `:user_limit_exceeded` - Too many users connected
  - `:invalid_credentials` - Invalid API credentials
  - `:invalid_user_id` - Invalid user ID format
  """
  def connect_user(user_id, api_key, secret_key) do
    CryptoExchange.Trading.UserManager.connect_user(user_id, api_key, secret_key)
  end

  @doc """
  Disconnect a user session with secure cleanup.

  Performs graceful shutdown of the user's trading session,
  ensuring all credentials are securely purged and resources cleaned up.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `:ok`: User successfully disconnected
  - `{:error, reason}`: Disconnection failed

  ## Examples

      :ok = CryptoExchange.API.disconnect_user("user1")

  """
  def disconnect_user(user_id) do
    CryptoExchange.Trading.UserManager.disconnect_user(user_id)
  end

  @doc """
  Place a trading order with comprehensive validation and error handling.

  Creates a new trading order with full parameter validation, business rule 
  checking, balance verification, and comprehensive error handling.

  ## Parameters
  - `user_id`: User identifier
  - `order_params`: Order parameters map containing:
    - `symbol`: Trading pair (e.g., "BTCUSDT")
    - `side`: "BUY" or "SELL"
    - `type`: "LIMIT", "MARKET", "STOP_LOSS", etc.
    - `quantity`: Order quantity as string
    - `price`: Order price as string (for LIMIT orders)
    - Additional optional parameters

  ## Returns
  - `{:ok, order}`: Order placed successfully with enhanced metadata
  - `{:error, error_details}`: Order placement failed with detailed error information

  ## Examples

      order_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY", 
        "type" => "LIMIT",
        "quantity" => "0.001",
        "price" => "50000"
      }
      {:ok, order} = CryptoExchange.API.place_order("user1", order_params)

  ## Enhanced Error Handling
  Returns detailed error information including:
  - Error categorization (validation, business rules, balance, etc.)
  - User-friendly error messages
  - Specific field validation errors
  - Suggestions for resolution
  - Performance metrics
  """
  def place_order(user_id, order_params) do
    CryptoExchange.Trading.UserConnection.place_order(user_id, order_params)
  end

  @doc """
  Cancel an existing order with comprehensive validation.

  Cancels a trading order with validation, error handling, and audit logging.

  ## Parameters
  - `user_id`: User identifier
  - `order_id`: Order ID to cancel

  ## Returns
  - `{:ok, cancelled_order}`: Order cancelled successfully with metadata
  - `{:error, error_details}`: Cancellation failed with detailed error information

  ## Examples

      {:ok, cancelled_order} = CryptoExchange.API.cancel_order("user1", "order_id_123")

  ## Enhanced Features
  - Order existence validation (cache and API lookup)
  - Comprehensive error categorization
  - Performance monitoring
  - Security audit logging
  """
  def cancel_order(user_id, order_id) do
    CryptoExchange.Trading.UserConnection.cancel_order(user_id, order_id)
  end

  @doc """
  Get account balance information with caching and filtering.

  Retrieves account balances with intelligent caching, filtering options,
  and comprehensive error handling.

  ## Parameters
  - `user_id`: User identifier
  - `opts`: Options map (optional) containing:
    - `:force_refresh`: Force API call bypassing cache
    - `:asset_filter`: Filter by specific asset (e.g., "BTC")
    - `:include_zero`: Include zero balance assets

  ## Returns
  - `{:ok, balances}`: List of balance structs
  - `{:error, error_details}`: Balance retrieval failed

  ## Examples

      # Get all non-zero balances (cached if available)
      {:ok, balances} = CryptoExchange.API.get_balance("user1")

      # Force refresh and filter for BTC only
      {:ok, btc_balance} = CryptoExchange.API.get_balance("user1", %{
        force_refresh: true,
        asset_filter: "BTC"
      })

      # Include zero balance assets
      {:ok, all_balances} = CryptoExchange.API.get_balance("user1", %{
        include_zero: true
      })

  ## Enhanced Features
  - Intelligent caching with configurable TTL
  - Asset filtering and sorting
  - Zero balance filtering
  - Performance monitoring
  - Cache hit/miss metrics
  """
  def get_balance(user_id, opts \\ %{}) do
    CryptoExchange.Trading.UserConnection.get_balance(user_id, opts)
  end

  @doc """
  Get orders with flexible filtering and caching options.

  Retrieves order history with comprehensive filtering, caching support,
  and performance optimization.

  ## Parameters
  - `user_id`: User identifier
  - `opts`: Options map (optional) containing:
    - `:symbol`: Filter by trading pair
    - `:status`: Filter by order status ("NEW", "FILLED", etc.)
    - `:limit`: Maximum number of orders to return
    - `:from_cache`: Use cached orders if available
    - `:start_time`: Start time filter
    - `:end_time`: End time filter

  ## Returns
  - `{:ok, orders}`: List of order structs
  - `{:error, error_details}`: Order retrieval failed

  ## Examples

      # Get recent orders (from API)
      {:ok, orders} = CryptoExchange.API.get_orders("user1")

      # Get cached BTCUSDT orders
      {:ok, btc_orders} = CryptoExchange.API.get_orders("user1", %{
        symbol: "BTCUSDT",
        from_cache: true,
        limit: 50
      })

      # Get only open orders
      {:ok, open_orders} = CryptoExchange.API.get_orders("user1", %{
        status: "NEW"
      })

  ## Enhanced Features
  - Flexible filtering by symbol, status, time range
  - Cache-first option for performance
  - Configurable result limits
  - Comprehensive sorting and pagination
  - Performance monitoring
  """
  def get_orders(user_id, opts \\ %{}) do
    CryptoExchange.Trading.UserConnection.get_orders(user_id, opts)
  end

  # Enhanced Session Management Operations

  @doc """
  Get comprehensive user session information.

  Returns detailed information about a user's trading session including
  health status, activity metrics, and resource usage.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, session_info}`: Comprehensive session information
  - `{:error, reason}`: User not connected or error

  ## Example

      {:ok, info} = CryptoExchange.API.get_session_info("user1")
      # Returns: session state, health status, uptime, cached data counts, etc.
  """
  def get_session_info(user_id) do
    CryptoExchange.Trading.UserConnection.get_session_info(user_id)
  end

  @doc """
  Get detailed session statistics and performance metrics.

  Returns comprehensive metrics about a user's trading session performance.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, session_stats}`: Detailed session statistics
  - `{:error, reason}`: User not connected or error

  ## Example

      {:ok, stats} = CryptoExchange.API.get_session_stats("user1")
      # Returns: operation counts, timing metrics, error rates, cache performance, etc.
  """
  def get_session_stats(user_id) do
    CryptoExchange.Trading.UserConnection.get_session_stats(user_id)
  end

  @doc """
  Perform a health check on a user session.

  Triggers a comprehensive health check of the user's trading session.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, health_info}`: Health check results
  - `{:error, reason}`: Health check failed or user not connected

  ## Example

      {:ok, health} = CryptoExchange.API.check_session_health("user1")
      # Returns: health status, last activity, uptime, session state
  """
  def check_session_health(user_id) do
    CryptoExchange.Trading.UserConnection.check_session_health(user_id)
  end

  @doc """
  Get system-wide trading statistics.

  Returns comprehensive statistics about all connected users and system performance.

  ## Returns
  - `{:ok, system_stats}`: System-wide statistics

  ## Example

      {:ok, stats} = CryptoExchange.API.get_system_statistics()
      # Returns: total users, active users, resource usage, health summary, etc.
  """
  def get_system_statistics do
    CryptoExchange.Trading.UserManager.get_system_statistics()
  end

  @doc """
  List all connected users with their session information.

  Returns information about all currently connected trading users.

  ## Returns
  - `{:ok, users}`: List of connected users with session info

  ## Example

      {:ok, users} = CryptoExchange.API.list_connected_users()
      # Returns: list of user info maps with connection details
  """
  def list_connected_users do
    {:ok, CryptoExchange.Trading.UserManager.list_connected_users()}
  end
end