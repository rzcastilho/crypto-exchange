defmodule CryptoExchange do
  @moduledoc """
  Main API module for CryptoExchange.

  This module provides a convenient facade for interacting with cryptocurrency
  exchanges, currently focusing on Binance.

  ## Features

  - **Historical Data**: Retrieve historical klines/candlestick data
  - **Real-time Streams**: Subscribe to real-time market data via WebSocket
  - **Trading Operations**: Place, cancel, and manage orders (requires authentication)
  - **Account Management**: Query balances and account information

  ## Historical Data

  Get historical OHLC data for backtesting and analysis:

  ```elixir
  # Get last 100 1-hour candles for BTC/USDT
  {:ok, klines} = CryptoExchange.get_historical_klines("BTCUSDT", "1h", limit: 100)

  # Get candles for specific date range
  {:ok, klines} = CryptoExchange.get_historical_klines("BTCUSDT", "1d",
    start_time: 1609459200000,  # 2021-01-01
    end_time: 1640995199000     # 2021-12-31
  )
  ```

  ## Real-time Data

  Subscribe to real-time market data streams:

  ```elixir
  # Subscribe to ticker updates
  {:ok, topic} = CryptoExchange.subscribe_to_ticker("BTCUSDT")
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  # Subscribe to kline updates
  {:ok, topic} = CryptoExchange.subscribe_to_klines("BTCUSDT", "1m")
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  # Listen for updates
  receive do
    {:market_data, data} -> IO.inspect(data)
  end
  ```

  ## Trading (Authenticated)

  Execute trades and manage orders:

  ```elixir
  # Create authenticated client
  {:ok, client} = CryptoExchange.create_trading_client(%{
    api_key: "your_api_key",
    secret_key: "your_secret_key"
  })

  # Place a limit order
  {:ok, order} = CryptoExchange.place_order(client, %{
    symbol: "BTCUSDT",
    side: "BUY",
    type: "LIMIT",
    timeInForce: "GTC",
    quantity: "0.001",
    price: "50000.00"
  })

  # Get account balances
  {:ok, account} = CryptoExchange.get_account(client)
  ```
  """

  alias CryptoExchange.Binance.{PublicClient, PrivateClient}
  alias CryptoExchange.PublicStreams.StreamManager

  # Historical Data Functions

  @doc """
  Retrieves historical kline/candlestick data for a trading pair.

  This function fetches historical OHLC (Open, High, Low, Close) data from
  Binance, which is useful for backtesting trading strategies, technical analysis,
  and historical market research.

  ## Parameters

  - `symbol` - Trading pair symbol (e.g., "BTCUSDT", "ETHBTC")
  - `interval` - Candlestick interval (e.g., "1m", "1h", "1d")
    Valid intervals: "1s", "1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h",
    "6h", "8h", "12h", "1d", "3d", "1w", "1M"
  - `opts` - Optional parameters:
    - `:start_time` - Start timestamp in milliseconds (inclusive)
    - `:end_time` - End timestamp in milliseconds (inclusive)
    - `:limit` - Number of klines to return (default: 500, max: 1000)
    - `:timezone` - Timezone for kline interpretation (default: "0" UTC)

  ## Returns

  - `{:ok, [%Kline{}]}` - List of kline structs on success
  - `{:error, reason}` - Error details on failure

  ## Examples

  ```elixir
  # Get last 100 hourly candles
  {:ok, klines} = CryptoExchange.get_historical_klines("BTCUSDT", "1h", limit: 100)

  # Get daily candles for January 2024
  {:ok, klines} = CryptoExchange.get_historical_klines("BTCUSDT", "1d",
    start_time: 1704067200000,  # 2024-01-01 00:00:00 UTC
    end_time: 1706745599000     # 2024-01-31 23:59:59 UTC
  )

  # Get last 500 5-minute candles (default limit)
  {:ok, klines} = CryptoExchange.get_historical_klines("ETHUSDT", "5m")

  # Process the klines
  Enum.each(klines, fn kline ->
    IO.puts("Open: \#{kline.open_price}, Close: \#{kline.close_price}")
  end)
  ```

  ## Kline Structure

  Each kline contains:
  - Open, High, Low, Close prices
  - Trading volume
  - Number of trades
  - Taker buy volumes
  - Start and close timestamps
  - Symbol and interval information

  ## Rate Limiting

  This function respects Binance's rate limits and includes automatic retry
  logic with exponential backoff for rate limit errors.
  """
  @spec get_historical_klines(String.t(), String.t(), keyword()) ::
          {:ok, [CryptoExchange.Models.Kline.t()]} | {:error, term()}
  def get_historical_klines(symbol, interval, opts \\ []) do
    with {:ok, client} <- PublicClient.new(),
         {:ok, klines} <- PublicClient.get_klines(client, symbol, interval, opts) do
      {:ok, klines}
    end
  end

  @doc """
  Gets the current server time from Binance.

  Useful for synchronizing local time with exchange servers and testing connectivity.

  ## Returns

  - `{:ok, %{server_time: milliseconds}}` - Server timestamp
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  {:ok, %{server_time: timestamp}} = CryptoExchange.get_server_time()
  ```
  """
  @spec get_server_time() :: {:ok, %{server_time: integer()}} | {:error, term()}
  def get_server_time do
    with {:ok, client} <- PublicClient.new(),
         {:ok, result} <- PublicClient.get_server_time(client) do
      {:ok, result}
    end
  end

  @doc """
  Gets exchange information including trading rules and symbol information.

  ## Parameters

  - `symbol` - Optional specific symbol to get info for

  ## Returns

  - `{:ok, exchange_info}` - Exchange information map
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  # Get all exchange info
  {:ok, info} = CryptoExchange.get_exchange_info()

  # Get info for specific symbol
  {:ok, info} = CryptoExchange.get_exchange_info("BTCUSDT")
  ```
  """
  @spec get_exchange_info(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def get_exchange_info(symbol \\ nil) do
    with {:ok, client} <- PublicClient.new(),
         {:ok, info} <- PublicClient.get_exchange_info(client, symbol) do
      {:ok, info}
    end
  end

  # Real-time Stream Functions

  @doc """
  Subscribes to real-time ticker updates for a symbol.

  Returns the PubSub topic name that you can subscribe to for receiving updates.

  ## Parameters

  - `symbol` - Trading pair symbol (e.g., "BTCUSDT")

  ## Returns

  - `{:ok, topic}` - PubSub topic name
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  {:ok, topic} = CryptoExchange.subscribe_to_ticker("BTCUSDT")
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  receive do
    {:market_data, %{type: :ticker, symbol: "BTCUSDT", data: ticker}} ->
      IO.puts("Price: \#{ticker.last_price}")
  end
  ```
  """
  @spec subscribe_to_ticker(String.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate subscribe_to_ticker(symbol), to: StreamManager

  @doc """
  Subscribes to real-time order book depth updates for a symbol.

  ## Parameters

  - `symbol` - Trading pair symbol (e.g., "BTCUSDT")
  - `depth` - Order book depth level (5, 10, or 20)

  ## Returns

  - `{:ok, topic}` - PubSub topic name
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  {:ok, topic} = CryptoExchange.subscribe_to_depth("BTCUSDT", 5)
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
  ```
  """
  @spec subscribe_to_depth(String.t(), integer()) :: {:ok, String.t()} | {:error, term()}
  defdelegate subscribe_to_depth(symbol, depth \\ 5), to: StreamManager

  @doc """
  Subscribes to real-time trade updates for a symbol.

  ## Parameters

  - `symbol` - Trading pair symbol (e.g., "BTCUSDT")

  ## Returns

  - `{:ok, topic}` - PubSub topic name
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  {:ok, topic} = CryptoExchange.subscribe_to_trades("BTCUSDT")
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
  ```
  """
  @spec subscribe_to_trades(String.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate subscribe_to_trades(symbol), to: StreamManager

  @doc """
  Subscribes to real-time kline/candlestick updates for a symbol and interval.

  ## Parameters

  - `symbol` - Trading pair symbol (e.g., "BTCUSDT")
  - `interval` - Candlestick interval (e.g., "1m", "1h", "1d")

  ## Returns

  - `{:ok, topic}` - PubSub topic name
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  {:ok, topic} = CryptoExchange.subscribe_to_klines("BTCUSDT", "1m")
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  receive do
    {:market_data, %{type: :klines, data: kline}} ->
      IO.puts("Close: \#{kline.close_price}")
  end
  ```
  """
  @spec subscribe_to_klines(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate subscribe_to_klines(symbol, interval), to: StreamManager

  # Trading Functions (Authenticated)

  @doc """
  Creates an authenticated trading client for placing orders and managing account.

  ## Parameters

  - `credentials` - Map with `:api_key` and `:secret_key`
  - `opts` - Optional configuration (base_url, timeout, retry_config)

  ## Returns

  - `{:ok, client}` - Authenticated client
  - `{:error, reason}` - Error if credentials are invalid

  ## Example

  ```elixir
  {:ok, client} = CryptoExchange.create_trading_client(%{
    api_key: System.get_env("BINANCE_API_KEY"),
    secret_key: System.get_env("BINANCE_SECRET_KEY")
  })
  ```
  """
  @spec create_trading_client(map(), keyword()) :: {:ok, PrivateClient.t()} | {:error, term()}
  defdelegate create_trading_client(credentials, opts \\ []), to: PrivateClient, as: :new

  @doc """
  Places a new order on the exchange.

  ## Parameters

  - `client` - Authenticated PrivateClient
  - `order_params` - Order parameters (symbol, side, type, quantity, price, etc.)

  ## Returns

  - `{:ok, order}` - Order details on success
  - `{:error, reason}` - Error details on failure

  ## Example

  ```elixir
  {:ok, order} = CryptoExchange.place_order(client, %{
    symbol: "BTCUSDT",
    side: "BUY",
    type: "LIMIT",
    timeInForce: "GTC",
    quantity: "0.001",
    price: "50000.00"
  })
  ```
  """
  @spec place_order(PrivateClient.t(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate place_order(client, order_params), to: PrivateClient

  @doc """
  Cancels an existing order.

  ## Parameters

  - `client` - Authenticated PrivateClient
  - `symbol` - Trading pair symbol
  - `order_id` - Order ID to cancel

  ## Returns

  - `{:ok, cancelled_order}` - Cancelled order details
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  {:ok, cancelled} = CryptoExchange.cancel_order(client, "BTCUSDT", "123456789")
  ```
  """
  @spec cancel_order(PrivateClient.t(), String.t(), String.t() | integer()) ::
          {:ok, map()} | {:error, term()}
  defdelegate cancel_order(client, symbol, order_id), to: PrivateClient

  @doc """
  Gets account information including balances.

  ## Parameters

  - `client` - Authenticated PrivateClient

  ## Returns

  - `{:ok, account_info}` - Account information with balances
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  {:ok, account} = CryptoExchange.get_account(client)
  balances = account["balances"]
  ```
  """
  @spec get_account(PrivateClient.t()) :: {:ok, map()} | {:error, term()}
  defdelegate get_account(client), to: PrivateClient

  @doc """
  Gets order history for a symbol.

  ## Parameters

  - `client` - Authenticated PrivateClient
  - `symbol` - Trading pair symbol
  - `opts` - Optional parameters (limit, start_time, end_time)

  ## Returns

  - `{:ok, orders}` - List of orders
  - `{:error, reason}` - Error details

  ## Example

  ```elixir
  {:ok, orders} = CryptoExchange.get_orders(client, "BTCUSDT", limit: 10)
  ```
  """
  @spec get_orders(PrivateClient.t(), String.t(), map()) :: {:ok, list()} | {:error, term()}
  defdelegate get_orders(client, symbol, opts \\ %{}), to: PrivateClient
end
