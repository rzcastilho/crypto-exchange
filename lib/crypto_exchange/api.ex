defmodule CryptoExchange.API do
  @moduledoc """
  Main public API for the CryptoExchange library.

  This module provides the primary interface for both public market data streaming
  and private user trading operations with comprehensive input validation,
  standardized error handling, and production-grade robustness.

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
  - `get_balance/2` - Get account balance information
  - `get_orders/2` - Get open/recent orders

  ## Enhanced Features

  - **Comprehensive Input Validation**: All inputs are validated with detailed error messages
  - **Edge Case Handling**: Robust handling of null, empty, malformed, and malicious inputs
  - **Standardized Error Responses**: Consistent error formats across all endpoints
  - **Security Focused**: Protection against injection attacks and data leaks
  - **Performance Optimized**: Efficient validation with pre-compiled patterns
  - **Developer Friendly**: Clear error messages with actionable suggestions
  """

  # Import centralized validation and error handling modules
  alias CryptoExchange.API.Validation
  alias CryptoExchange.API.ErrorHandler

  # Public Data Operations (no authentication required)

  @doc """
  Subscribe to ticker updates for a given symbol.

  Returns a Phoenix.PubSub topic that can be subscribed to for receiving
  real-time ticker updates including price, volume, and percentage change data.

  ## Parameters
  - `symbol`: Trading pair symbol (e.g., "BTCUSDT", "ETHUSDT")

  ## Returns
  - `{:ok, topic}`: Successfully subscribed, returns PubSub topic name
  - `{:error, :invalid_symbol}`: Invalid symbol format
  - `{:error, :service_unavailable}`: StreamManager unavailable
  - `{:error, :connection_failed}`: Failed to establish stream connection
  - `{:error, :connection_timeout}`: Connection establishment timed out

  ## Examples

      {:ok, topic} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Listen for ticker updates
      receive do
        {:market_data, %{type: :ticker, symbol: "BTCUSDT", data: ticker_data}} ->
          IO.inspect(ticker_data)
      end

  """
  @spec subscribe_to_ticker(String.t()) :: 
    {:ok, String.t()} | 
    {:error, :invalid_symbol | :connection_failed | :service_unavailable | :connection_timeout}
  def subscribe_to_ticker(symbol) do
    with :ok <- Validation.validate_symbol(symbol),
         {:ok, topic} <- CryptoExchange.PublicStreams.StreamManager.subscribe(:ticker, symbol, %{}) do
      {:ok, topic}
    else
      error -> ErrorHandler.translate_error(error, :public)
    end
  end

  @doc """
  Subscribe to order book depth data for a given symbol.

  Returns real-time order book data with configurable depth levels.
  The depth data includes bids and asks with price and quantity information.

  ## Parameters
  - `symbol`: Trading pair symbol (e.g., "BTCUSDT", "ETHUSDT")
  - `level`: Depth level - must be 5, 10, or 20 (default: 5)

  ## Returns
  - `{:ok, topic}`: Successfully subscribed, returns PubSub topic name
  - `{:error, :invalid_symbol}`: Invalid symbol format
  - `{:error, :invalid_level}`: Invalid depth level (must be 5, 10, or 20)
  - `{:error, :service_unavailable}`: StreamManager unavailable
  - `{:error, :connection_failed}`: Failed to establish stream connection
  - `{:error, :connection_timeout}`: Connection establishment timed out

  ## Examples

      {:ok, topic} = CryptoExchange.API.subscribe_to_depth("BTCUSDT", 5)
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Listen for depth updates
      receive do
        {:market_data, %{type: :depth, symbol: "BTCUSDT", data: depth_data}} ->
          IO.inspect(depth_data)
      end

  """
  @spec subscribe_to_depth(String.t(), pos_integer()) :: 
    {:ok, String.t()} | 
    {:error, :invalid_symbol | :invalid_level | :connection_failed | :service_unavailable | :connection_timeout}
  def subscribe_to_depth(symbol, level \\ 5) do
    with :ok <- Validation.validate_symbol(symbol),
         :ok <- Validation.validate_depth_level(level),
         {:ok, topic} <- CryptoExchange.PublicStreams.StreamManager.subscribe(:depth, symbol, %{level: level}) do
      {:ok, topic}
    else
      error -> ErrorHandler.translate_error(error, :public)
    end
  end

  @doc """
  Subscribe to trade execution data for a given symbol.

  Returns real-time trade execution data including price, quantity, time,
  and buyer/seller information for individual trades.

  ## Parameters
  - `symbol`: Trading pair symbol (e.g., "BTCUSDT", "ETHUSDT")

  ## Returns
  - `{:ok, topic}`: Successfully subscribed, returns PubSub topic name
  - `{:error, :invalid_symbol}`: Invalid symbol format
  - `{:error, :service_unavailable}`: StreamManager unavailable
  - `{:error, :connection_failed}`: Failed to establish stream connection
  - `{:error, :connection_timeout}`: Connection establishment timed out

  ## Examples

      {:ok, topic} = CryptoExchange.API.subscribe_to_trades("BTCUSDT")
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Listen for trade updates
      receive do
        {:market_data, %{type: :trades, symbol: "BTCUSDT", data: trade_data}} ->
          IO.inspect(trade_data)
      end

  """
  @spec subscribe_to_trades(String.t()) :: 
    {:ok, String.t()} | 
    {:error, :invalid_symbol | :connection_failed | :service_unavailable | :connection_timeout}
  def subscribe_to_trades(symbol) do
    with :ok <- Validation.validate_symbol(symbol),
         {:ok, topic} <- CryptoExchange.PublicStreams.StreamManager.subscribe(:trades, symbol, %{}) do
      {:ok, topic}
    else
      error -> ErrorHandler.translate_error(error, :public)
    end
  end

  @doc """
  Unsubscribe from public data streams for a given symbol.

  Stops all active streams (ticker, depth, trades) for the specified symbol.
  This will stop the streams for all subscribers, not just the calling process.

  ## Parameters
  - `symbol`: Trading pair symbol (e.g., "BTCUSDT", "ETHUSDT")

  ## Returns
  - `:ok`: Successfully unsubscribed from all streams for the symbol
  - `{:error, :invalid_symbol}`: Invalid symbol format
  - `{:error, :service_unavailable}`: StreamManager unavailable

  ## Examples

      :ok = CryptoExchange.API.unsubscribe_from_public_data("BTCUSDT")
      
      # All ticker, depth, and trade streams for BTCUSDT are now stopped

  """
  @spec unsubscribe_from_public_data(String.t()) :: 
    :ok | 
    {:error, :invalid_symbol | :service_unavailable}
  def unsubscribe_from_public_data(symbol) do
    with :ok <- Validation.validate_symbol(symbol),
         :ok <- CryptoExchange.PublicStreams.StreamManager.unsubscribe(symbol) do
      :ok
    else
      error -> ErrorHandler.translate_error(error, :public)
    end
  end

  # User Trading Operations (require authentication)

  @doc """
  Connect a user with their Binance API credentials.

  This creates an isolated user session for trading operations using
  the enhanced UserManager architecture with comprehensive security,
  monitoring, and fault tolerance features.

  ## Parameters
  - `user_id`: Unique identifier for the user (3-32 alphanumeric characters)
  - `api_key`: Binance API key (64-character hex string)
  - `secret_key`: Binance secret key (64-character hex string)

  ## Returns
  - `{:ok, supervisor_pid}`: User successfully connected with session PID
  - `{:error, :invalid_user_id}`: Invalid user ID format or length
  - `{:error, :invalid_credentials}`: Invalid API key or secret format
  - `{:error, :authentication_failed}`: Credentials rejected by exchange
  - `{:error, :user_already_connected}`: User session already exists
  - `{:error, :user_limit_exceeded}`: Maximum user connections reached
  - `{:error, :service_unavailable}`: UserManager unavailable

  ## Examples

      # Successful connection
      {:ok, pid} = CryptoExchange.API.connect_user(
        "user123", 
        "abcd1234...", 
        "secret5678..."
      )
      
      # Invalid credentials
      {:error, :invalid_credentials} = CryptoExchange.API.connect_user(
        "user1", 
        "invalid", 
        "credentials"
      )
      
      # User ID too short
      {:error, :invalid_user_id} = CryptoExchange.API.connect_user(
        "x", 
        "valid_api_key...", 
        "valid_secret..."
      )

  ## Security Features
  - Credential validation before connection attempt
  - Secure credential storage using encrypted memory
  - Session isolation with individual supervision trees
  - Automatic credential cleanup on disconnection
  - Comprehensive security audit logging
  """
  @spec connect_user(String.t(), String.t(), String.t()) :: 
    {:ok, pid()} | 
    {:error, :invalid_user_id | :invalid_credentials | :authentication_failed | 
     :user_already_connected | :user_limit_exceeded | :service_unavailable}
  def connect_user(user_id, api_key, secret_key) do
    with :ok <- Validation.validate_user_id(user_id),
         :ok <- Validation.validate_api_credentials(api_key, secret_key),
         result <- CryptoExchange.Trading.UserManager.connect_user(user_id, api_key, secret_key) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
  end

  @doc """
  Disconnect a user session with secure cleanup.

  Performs graceful shutdown of the user's trading session,
  ensuring all credentials are securely purged and resources cleaned up.
  All pending operations are completed or cancelled before disconnection.

  ## Parameters
  - `user_id`: User identifier (must be valid format)

  ## Returns
  - `:ok`: User successfully disconnected and all resources cleaned
  - `{:error, :invalid_user_id}`: Invalid user ID format
  - `{:error, :user_not_connected}`: User was not connected
  - `{:error, :service_unavailable}`: UserManager unavailable
  - `{:error, :disconnect_timeout}`: Graceful shutdown timed out

  ## Examples

      # Successful disconnection
      :ok = CryptoExchange.API.disconnect_user("user123")
      
      # User not connected
      {:error, :user_not_connected} = CryptoExchange.API.disconnect_user("unknown_user")
      
      # Invalid user ID
      {:error, :invalid_user_id} = CryptoExchange.API.disconnect_user("")

  ## Security Features
  - Secure credential purging from memory
  - Graceful termination of all user operations
  - Complete resource cleanup and deregistration
  - Security audit logging of disconnection events
  - Automatic timeout handling for unresponsive sessions
  """
  @spec disconnect_user(String.t()) :: 
    :ok | 
    {:error, :invalid_user_id | :user_not_connected | :service_unavailable | :disconnect_timeout}
  def disconnect_user(user_id) do
    with :ok <- Validation.validate_user_id(user_id),
         result <- CryptoExchange.Trading.UserManager.disconnect_user(user_id) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
  end

  @doc """
  Place a trading order with comprehensive validation and error handling.

  Creates a new trading order with full parameter validation, business rule 
  checking, balance verification, and comprehensive error handling.

  ## Parameters
  - `user_id`: User identifier (must be connected)
  - `order_params`: Order parameters map containing:
    - `symbol`: Trading pair (e.g., "BTCUSDT", "ETHUSDT")
    - `side`: Order side ("BUY" or "SELL")
    - `type`: Order type ("LIMIT", "MARKET", "STOP_LOSS", "STOP_LOSS_LIMIT", "TAKE_PROFIT", "TAKE_PROFIT_LIMIT")
    - `quantity`: Order quantity as string (must be positive)
    - `price`: Order price as string (required for LIMIT orders)
    - `stopPrice`: Stop price for stop orders (optional)
    - `timeInForce`: Time in force ("GTC", "IOC", "FOK") - optional, defaults to "GTC"
    - `newClientOrderId`: Client order ID (optional)

  ## Returns
  - `{:ok, order}`: Order placed successfully with complete order details
  - `{:error, :invalid_user_id}`: Invalid user ID format
  - `{:error, :user_not_connected}`: User session not active
  - `{:error, :invalid_order_params}`: Invalid order parameters
  - `{:error, :invalid_symbol}`: Invalid or unsupported trading pair
  - `{:error, :invalid_side}`: Invalid order side (must be BUY/SELL)
  - `{:error, :invalid_type}`: Invalid order type
  - `{:error, :invalid_quantity}`: Invalid quantity format or value
  - `{:error, :invalid_price}`: Invalid price format or value
  - `{:error, :insufficient_funds}`: Insufficient balance for order
  - `{:error, :minimum_notional_not_met}`: Order value below minimum
  - `{:error, :price_filter_violation}`: Price violates exchange filters
  - `{:error, :quantity_filter_violation}`: Quantity violates exchange filters
  - `{:error, :market_closed}`: Trading not allowed for symbol
  - `{:error, :rate_limit_exceeded}`: API rate limit exceeded
  - `{:error, :service_unavailable}`: Trading service unavailable

  ## Examples

      # Successful limit buy order
      order_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY", 
        "type" => "LIMIT",
        "quantity" => "0.001",
        "price" => "50000",
        "timeInForce" => "GTC"
      }
      {:ok, order} = CryptoExchange.API.place_order("user123", order_params)
      
      # Market sell order
      market_params = %{
        "symbol" => "ETHUSDT",
        "side" => "SELL",
        "type" => "MARKET",
        "quantity" => "0.1"
      }
      {:ok, order} = CryptoExchange.API.place_order("user123", market_params)
      
      # Error - insufficient funds
      {:error, :insufficient_funds} = CryptoExchange.API.place_order(
        "user123", 
        %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET", "quantity" => "1000"}
      )

  ## Enhanced Features
  - Pre-trade balance validation
  - Exchange filter compliance checking
  - Comprehensive parameter validation at API layer
  - Detailed error categorization and user-friendly messages
  - Performance monitoring and metrics collection
  - Security audit logging of all trading operations
  """
  @spec place_order(String.t(), map()) :: 
    {:ok, map()} | 
    {:error, :invalid_user_id | :user_not_connected | :invalid_order_params | 
     :invalid_symbol | :invalid_side | :invalid_type | :invalid_quantity | 
     :invalid_price | :insufficient_funds | :minimum_notional_not_met | 
     :price_filter_violation | :quantity_filter_violation | :market_closed | 
     :rate_limit_exceeded | :service_unavailable}
  def place_order(user_id, order_params) do
    with :ok <- Validation.validate_user_id(user_id),
         :ok <- Validation.validate_order_params(order_params),
         result <- CryptoExchange.Trading.UserConnection.place_order(user_id, order_params) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
  end

  @doc """
  Cancel an existing order with comprehensive validation.

  Cancels a trading order with validation, error handling, and audit logging.
  Supports cancellation by order ID or client order ID.

  ## Parameters
  - `user_id`: User identifier (must be connected)
  - `order_id`: Order ID to cancel (integer as string or client order ID)

  ## Returns
  - `{:ok, cancelled_order}`: Order cancelled successfully with cancellation details
  - `{:error, :invalid_user_id}`: Invalid user ID format
  - `{:error, :user_not_connected}`: User session not active
  - `{:error, :invalid_order_id}`: Invalid order ID format
  - `{:error, :order_not_found}`: Order does not exist or already filled
  - `{:error, :order_not_cancellable}`: Order cannot be cancelled (filled/expired)
  - `{:error, :unauthorized_order}`: Order belongs to different user
  - `{:error, :rate_limit_exceeded}`: API rate limit exceeded
  - `{:error, :service_unavailable}`: Trading service unavailable

  ## Examples

      # Cancel by order ID
      {:ok, cancelled_order} = CryptoExchange.API.cancel_order("user123", "12345678")
      
      # Cancel by client order ID
      {:ok, cancelled_order} = CryptoExchange.API.cancel_order("user123", "my_order_001")
      
      # Error - order not found
      {:error, :order_not_found} = CryptoExchange.API.cancel_order("user123", "999999")
      
      # Error - order already filled
      {:error, :order_not_cancellable} = CryptoExchange.API.cancel_order("user123", "filled_order")

  ## Enhanced Features
  - Dual ID support (order ID and client order ID)
  - Order existence validation with cache lookup optimization
  - Order ownership verification for security
  - Comprehensive error categorization with specific reasons
  - Performance monitoring and latency tracking
  - Security audit logging of all cancellation attempts
  """
  @spec cancel_order(String.t(), String.t()) :: 
    {:ok, map()} | 
    {:error, :invalid_user_id | :user_not_connected | :invalid_order_id | 
     :order_not_found | :order_not_cancellable | :unauthorized_order | 
     :rate_limit_exceeded | :service_unavailable}
  def cancel_order(user_id, order_id) do
    with :ok <- Validation.validate_user_id(user_id),
         :ok <- Validation.validate_order_id(order_id),
         result <- CryptoExchange.Trading.UserConnection.cancel_order(user_id, order_id) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
  end

  @doc """
  Get account balance information with caching and filtering.

  Retrieves account balances with intelligent caching, filtering options,
  and comprehensive error handling. Balance data includes available and locked amounts.

  ## Parameters
  - `user_id`: User identifier (must be connected)
  - `opts`: Options map (optional) containing:
    - `:force_refresh`: Force API call bypassing cache (boolean, default: false)
    - `:asset_filter`: Filter by specific asset (string, e.g., "BTC", "ETH")
    - `:include_zero`: Include zero balance assets (boolean, default: false)
    - `:timeout`: Request timeout in milliseconds (integer, default: 10000)

  ## Returns
  - `{:ok, balances}`: List of balance maps with asset, free, and locked amounts
  - `{:error, :invalid_user_id}`: Invalid user ID format
  - `{:error, :user_not_connected}`: User session not active
  - `{:error, :invalid_options}`: Invalid options format
  - `{:error, :invalid_asset_filter}`: Invalid asset filter format
  - `{:error, :balance_fetch_timeout}`: Balance retrieval timed out
  - `{:error, :rate_limit_exceeded}`: API rate limit exceeded
  - `{:error, :service_unavailable}`: Trading service unavailable

  ## Examples

      # Get all non-zero balances (cached if available)
      {:ok, balances} = CryptoExchange.API.get_balance("user123")
      # Returns: [%{"asset" => "BTC", "free" => "0.5", "locked" => "0.0"}, ...]

      # Force refresh and filter for BTC only
      {:ok, [btc_balance]} = CryptoExchange.API.get_balance("user123", %{
        force_refresh: true,
        asset_filter: "BTC"
      })
      # Returns: [%{"asset" => "BTC", "free" => "0.5", "locked" => "0.1"}]

      # Include zero balance assets with timeout
      {:ok, all_balances} = CryptoExchange.API.get_balance("user123", %{
        include_zero: true,
        timeout: 15000
      })
      
      # Error - invalid asset filter
      {:error, :invalid_asset_filter} = CryptoExchange.API.get_balance("user123", %{
        asset_filter: 123  # Must be string
      })

  ## Enhanced Features
  - Intelligent caching with configurable TTL (default 30 seconds)
  - Multi-asset filtering with case-insensitive matching
  - Automatic zero balance filtering for performance
  - Real-time cache invalidation on trading operations
  - Performance monitoring and cache hit/miss metrics
  - Secure balance data handling with audit logging
  """
  @spec get_balance(String.t(), map()) :: 
    {:ok, [map()]} | 
    {:error, :invalid_user_id | :user_not_connected | :invalid_options | 
     :invalid_asset_filter | :balance_fetch_timeout | :rate_limit_exceeded | :service_unavailable}
  def get_balance(user_id, opts \\ %{}) do
    with :ok <- Validation.validate_user_id(user_id),
         :ok <- Validation.validate_balance_options(opts),
         result <- CryptoExchange.Trading.UserConnection.get_balance(user_id, opts) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
  end

  @doc """
  Get orders with flexible filtering and caching options.

  Retrieves order history with comprehensive filtering, caching support,
  and performance optimization. Supports both open and historical orders.

  ## Parameters
  - `user_id`: User identifier (must be connected)
  - `opts`: Options map (optional) containing:
    - `:symbol`: Filter by trading pair (string, e.g., "BTCUSDT")
    - `:status`: Filter by order status ("NEW", "PARTIALLY_FILLED", "FILLED", "CANCELED", "EXPIRED")
    - `:limit`: Maximum number of orders to return (integer, 1-1000, default: 500)
    - `:from_cache`: Use cached orders if available (boolean, default: false)
    - `:start_time`: Start time filter (integer timestamp or DateTime)
    - `:end_time`: End time filter (integer timestamp or DateTime)
    - `:order_id`: Get orders starting from this order ID (integer)
    - `:timeout`: Request timeout in milliseconds (integer, default: 15000)

  ## Returns
  - `{:ok, orders}`: List of order maps with complete order details
  - `{:error, :invalid_user_id}`: Invalid user ID format
  - `{:error, :user_not_connected}`: User session not active
  - `{:error, :invalid_options}`: Invalid options format
  - `{:error, :invalid_symbol}`: Invalid trading pair format
  - `{:error, :invalid_status}`: Invalid order status value
  - `{:error, :invalid_limit}`: Invalid limit value (must be 1-1000)
  - `{:error, :invalid_time_range}`: Invalid or conflicting time filters
  - `{:error, :orders_fetch_timeout}`: Order retrieval timed out
  - `{:error, :rate_limit_exceeded}`: API rate limit exceeded
  - `{:error, :service_unavailable}`: Trading service unavailable

  ## Examples

      # Get recent orders (from API, all symbols)
      {:ok, orders} = CryptoExchange.API.get_orders("user123")
      # Returns: [%{"orderId" => 123, "symbol" => "BTCUSDT", "status" => "FILLED", ...}, ...]

      # Get cached BTCUSDT orders with limit
      {:ok, btc_orders} = CryptoExchange.API.get_orders("user123", %{
        symbol: "BTCUSDT",
        from_cache: true,
        limit: 50
      })

      # Get only open orders across all symbols
      {:ok, open_orders} = CryptoExchange.API.get_orders("user123", %{
        status: "NEW"
      })
      
      # Get orders within time range
      {:ok, recent_orders} = CryptoExchange.API.get_orders("user123", %{
        start_time: DateTime.add(DateTime.utc_now(), -24, :hour),
        end_time: DateTime.utc_now(),
        limit: 100
      })
      
      # Error - invalid limit
      {:error, :invalid_limit} = CryptoExchange.API.get_orders("user123", %{
        limit: 2000  # Exceeds maximum of 1000
      })

  ## Enhanced Features
  - Flexible multi-criteria filtering (symbol, status, time, order ID)
  - Intelligent caching with cache-first option for performance
  - Configurable result limits with automatic pagination support
  - Time range filtering with multiple timestamp format support
  - Comprehensive sorting by order ID, time, or symbol
  - Performance monitoring and query optimization
  - Real-time cache updates from trading operations
  """
  @spec get_orders(String.t(), map()) :: 
    {:ok, [map()]} | 
    {:error, :invalid_user_id | :user_not_connected | :invalid_options | 
     :invalid_symbol | :invalid_status | :invalid_limit | :invalid_time_range | 
     :orders_fetch_timeout | :rate_limit_exceeded | :service_unavailable}
  def get_orders(user_id, opts \\ %{}) do
    with :ok <- Validation.validate_user_id(user_id),
         :ok <- Validation.validate_orders_options(opts),
         result <- CryptoExchange.Trading.UserConnection.get_orders(user_id, opts) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
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
    with :ok <- Validation.validate_user_id(user_id),
         result <- CryptoExchange.Trading.UserConnection.get_session_info(user_id) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
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
    with :ok <- Validation.validate_user_id(user_id),
         result <- CryptoExchange.Trading.UserConnection.get_session_stats(user_id) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
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
    with :ok <- Validation.validate_user_id(user_id),
         result <- CryptoExchange.Trading.UserConnection.check_session_health(user_id) do
      ErrorHandler.translate_error(result, :trading)
    else
      error -> ErrorHandler.translate_error(error, :trading)
    end
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

  @doc """
  Enables detailed error responses for development and debugging.
  
  When enabled, API functions return detailed error maps with comprehensive
  information including error categories, suggestions, and context.
  
  ## Usage
  
      # Enable detailed errors (useful for development)
      CryptoExchange.API.enable_detailed_errors()
      
      # API calls now return detailed error information
      {:error, %{
        reason: :invalid_symbol,
        category: "Input Validation",
        message: "Invalid symbol format",
        suggestions: ["Symbol must be 3-20 characters long", ...],
        error_code: "VAL-A1B2C3D4",
        timestamp: ~U[2024-01-01 12:00:00Z]
      }} = CryptoExchange.API.subscribe_to_ticker("BT")
  """
  @spec enable_detailed_errors() :: :ok
  def enable_detailed_errors do
    Application.put_env(:crypto_exchange, :detailed_errors, true)
  end
  
  @doc """
  Disables detailed error responses, returning simple error atoms.
  
  This is the default mode, returning concise error responses suitable for production.
  """
  @spec disable_detailed_errors() :: :ok
  def disable_detailed_errors do
    Application.put_env(:crypto_exchange, :detailed_errors, false)
  end
  
  @doc """
  Checks if detailed error responses are enabled.
  """
  @spec detailed_errors_enabled?() :: boolean()
  def detailed_errors_enabled? do
    Application.get_env(:crypto_exchange, :detailed_errors, false)
  end
end