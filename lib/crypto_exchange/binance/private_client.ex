defmodule CryptoExchange.Binance.PrivateClient do
  @moduledoc """
  REST API client for Binance private endpoints requiring authentication.

  This module provides functions for authenticated Binance operations including:
  - Order management (place, cancel, modify)
  - Account information (balance, trading fees)
  - Order history and status queries
  - Trading permissions and restrictions

  All requests are signed with HMAC-SHA256 signatures using the Auth module
  and include proper authentication headers and timestamps.

  ## Configuration

  The client uses the following configuration options:
  - `binance_api_url`: Base URL for Binance REST API (default: "https://api.binance.com")
  - `request_timeout`: HTTP request timeout in milliseconds (default: 10_000)

  ## Usage Examples

  ```elixir
  # Create client with credentials
  client = PrivateClient.new(%{
    api_key: "your_binance_api_key",
    secret_key: "your_binance_secret_key"
  })

  # Place a limit buy order
  {:ok, order} = PrivateClient.place_order(client, %{
    symbol: "BTCUSDT",
    side: "BUY",
    type: "LIMIT",
    timeInForce: "GTC",
    quantity: "0.001",
    price: "50000.00"
  })

  # Cancel an order
  {:ok, cancelled} = PrivateClient.cancel_order(client, "BTCUSDT", "123456789")

  # Get account balances
  {:ok, account} = PrivateClient.get_account(client)

  # Get order history
  {:ok, orders} = PrivateClient.get_orders(client, "BTCUSDT")
  ```

  ## Error Handling

  The client handles various types of errors:
  - Network errors (timeouts, connection failures)
  - Authentication errors (invalid API keys, signature mismatch)
  - Binance-specific errors (insufficient balance, invalid symbol, etc.)
  - Rate limiting (HTTP 429 responses)

  All errors are returned in the format `{:error, reason}` where reason
  provides details about what went wrong.
  """

  alias CryptoExchange.Binance.Auth
  require Logger

  @default_base_url "https://api.binance.com"
  @default_timeout 10_000

  defstruct [:credentials, :base_url, :timeout]

  @type t :: %__MODULE__{
          credentials: %{api_key: String.t(), secret_key: String.t()},
          base_url: String.t(),
          timeout: pos_integer()
        }

  @type order_params :: %{
          symbol: String.t(),
          side: String.t(),
          type: String.t()
        }

  @type credentials :: %{api_key: String.t(), secret_key: String.t()}

  @doc """
  Creates a new PrivateClient with the given credentials.

  ## Parameters
  - `credentials`: Map containing :api_key and :secret_key
  - `opts`: Optional configuration (base_url, timeout)

  ## Returns
  - `{:ok, client}` on success
  - `{:error, reason}` if credentials are invalid

  ## Example
  ```elixir
  client = PrivateClient.new(%{
    api_key: "your_api_key",
    secret_key: "your_secret_key"
  })
  ```
  """
  def new(credentials, opts \\ []) do
    case Auth.validate_credentials(credentials) do
      :ok ->
        client = %__MODULE__{
          credentials: credentials,
          base_url: Keyword.get(opts, :base_url, @default_base_url),
          timeout: Keyword.get(opts, :timeout, @default_timeout)
        }

        {:ok, client}

      {:error, reason} = error ->
        Logger.error("Invalid credentials for PrivateClient: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Places a new order on Binance.

  ## Parameters
  - `client`: PrivateClient struct
  - `order_params`: Map containing order parameters

  ## Required Parameters
  - `symbol`: Trading symbol (e.g., "BTCUSDT")
  - `side`: Order side ("BUY" or "SELL")  
  - `type`: Order type ("LIMIT", "MARKET", "STOP_LOSS", etc.)

  ## Optional Parameters (depending on order type)
  - `quantity`: Order quantity
  - `price`: Order price (required for LIMIT orders)
  - `timeInForce`: Time in force ("GTC", "IOC", "FOK")
  - `stopPrice`: Stop price for stop orders
  - `icebergQty`: Iceberg order quantity

  ## Returns
  - `{:ok, order}` on success with order details
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  {:ok, order} = PrivateClient.place_order(client, %{
    symbol: "BTCUSDT",
    side: "BUY",
    type: "LIMIT", 
    timeInForce: "GTC",
    quantity: "0.001",
    price: "50000.00"
  })
  ```
  """
  def place_order(%__MODULE__{} = client, order_params) when is_map(order_params) do
    Logger.debug("Placing order: #{inspect(order_params, pretty: true)}")

    with :ok <- validate_order_params(order_params),
         {:ok, response} <- post_request(client, "/api/v3/order", order_params) do
      Logger.info("Order placed successfully: #{response["orderId"]}")
      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("Failed to place order: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Cancels an existing order.

  ## Parameters
  - `client`: PrivateClient struct
  - `symbol`: Trading symbol (e.g., "BTCUSDT")
  - `order_id`: Order ID to cancel (string or integer)

  ## Returns
  - `{:ok, cancelled_order}` on success
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  {:ok, cancelled} = PrivateClient.cancel_order(client, "BTCUSDT", "123456789")
  ```
  """
  def cancel_order(%__MODULE__{} = client, symbol, order_id) do
    Logger.debug("Cancelling order: #{order_id} for #{symbol}")

    params = %{
      symbol: symbol,
      orderId: to_string(order_id)
    }

    with {:ok, response} <- delete_request(client, "/api/v3/order", params) do
      Logger.info("Order cancelled successfully: #{order_id}")
      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("Failed to cancel order #{order_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets account information including balances.

  ## Parameters
  - `client`: PrivateClient struct

  ## Returns
  - `{:ok, account_info}` containing balances and account details
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  {:ok, account} = PrivateClient.get_account(client)
  # account["balances"] contains array of balance objects
  ```
  """
  def get_account(%__MODULE__{} = client) do
    Logger.debug("Getting account information")

    with {:ok, response} <- get_request(client, "/api/v3/account", %{}) do
      Logger.debug("Account information retrieved successfully")
      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("Failed to get account information: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets all orders for a symbol (active, canceled, filled).

  ## Parameters
  - `client`: PrivateClient struct  
  - `symbol`: Trading symbol (e.g., "BTCUSDT")
  - `opts`: Optional parameters (limit, start_time, end_time)

  ## Returns
  - `{:ok, orders}` containing array of order objects
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  # Get recent orders
  {:ok, orders} = PrivateClient.get_orders(client, "BTCUSDT")

  # Get orders with limit
  {:ok, orders} = PrivateClient.get_orders(client, "BTCUSDT", %{limit: 10})
  ```
  """
  def get_orders(%__MODULE__{} = client, symbol, opts \\ %{}) do
    Logger.debug("Getting orders for #{symbol}")

    params = Map.put(opts, :symbol, symbol)

    with {:ok, response} <- get_request(client, "/api/v3/allOrders", params) do
      Logger.debug("Orders retrieved successfully: #{length(response)} orders")
      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("Failed to get orders for #{symbol}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets the status of a specific order.

  ## Parameters
  - `client`: PrivateClient struct
  - `symbol`: Trading symbol (e.g., "BTCUSDT") 
  - `order_id`: Order ID to query

  ## Returns
  - `{:ok, order}` with order status and details
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  {:ok, order} = PrivateClient.get_order_status(client, "BTCUSDT", "123456789")
  ```
  """
  def get_order_status(%__MODULE__{} = client, symbol, order_id) do
    Logger.debug("Getting order status: #{order_id} for #{symbol}")

    params = %{
      symbol: symbol,
      orderId: to_string(order_id)
    }

    with {:ok, response} <- get_request(client, "/api/v3/order", params) do
      Logger.debug("Order status retrieved: #{response["status"]}")
      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("Failed to get order status #{order_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets current open orders for a symbol.

  ## Parameters
  - `client`: PrivateClient struct
  - `symbol`: Optional trading symbol. If nil, gets all open orders.

  ## Returns
  - `{:ok, open_orders}` containing array of active orders
  - `{:error, reason}` on failure

  ## Example
  ```elixir
  # Get all open orders
  {:ok, orders} = PrivateClient.get_open_orders(client)

  # Get open orders for specific symbol  
  {:ok, orders} = PrivateClient.get_open_orders(client, "BTCUSDT")
  ```
  """
  def get_open_orders(%__MODULE__{} = client, symbol \\ nil) do
    Logger.debug("Getting open orders#{if symbol, do: " for #{symbol}", else: ""}")

    params = if symbol, do: %{symbol: symbol}, else: %{}

    with {:ok, response} <- get_request(client, "/api/v3/openOrders", params) do
      Logger.debug("Open orders retrieved: #{length(response)} orders")
      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("Failed to get open orders: #{inspect(reason)}")
        error
    end
  end

  # Private Functions

  defp get_request(%__MODULE__{} = client, path, params) do
    make_signed_request(client, :get, path, params)
  end

  defp post_request(%__MODULE__{} = client, path, params) do
    make_signed_request(client, :post, path, params)
  end

  defp delete_request(%__MODULE__{} = client, path, params) do
    make_signed_request(client, :delete, path, params)
  end

  defp make_signed_request(%__MODULE__{} = client, method, path, params) do
    signed_params = Auth.sign_request(params, client.credentials)
    headers = Auth.get_headers(client.credentials)
    url = client.base_url <> path

    case method do
      :get ->
        query_string = Auth.build_query_string(signed_params)
        full_url = "#{url}?#{query_string}"
        http_request(:get, full_url, "", headers, client.timeout)

      :post ->
        body = Auth.build_query_string(signed_params)
        http_request(:post, url, body, headers, client.timeout)

      :delete ->
        query_string = Auth.build_query_string(signed_params)
        full_url = "#{url}?#{query_string}"
        http_request(:delete, full_url, "", headers, client.timeout)
    end
  end

  defp http_request(method, url, body, headers, timeout) do
    Logger.debug("Making #{method} request to #{URI.parse(url).path}")

    case Req.request(
           method: method,
           url: url,
           body: body,
           headers: headers,
           receive_timeout: timeout
         ) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("HTTP error #{status}: #{inspect(response_body)}")
        {:error, {:http_error, status, response_body}}

      {:error, reason} = error ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        error
    end
  end

  defp validate_order_params(params) do
    required_fields = [:symbol, :side, :type]

    case check_required_fields(params, required_fields) do
      :ok -> validate_order_specific_params(params)
      error -> error
    end
  end

  defp check_required_fields(params, required_fields) do
    missing = Enum.filter(required_fields, &(!Map.has_key?(params, &1)))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_order_specific_params(%{type: "LIMIT"} = params) do
    limit_required = [:quantity, :price, :timeInForce]
    check_required_fields(params, limit_required)
  end

  defp validate_order_specific_params(%{type: "MARKET"} = params) do
    # Market orders require either quantity OR quoteOrderQty
    if Map.has_key?(params, :quantity) or Map.has_key?(params, :quoteOrderQty) do
      :ok
    else
      {:error, {:missing_required_fields, [:quantity_or_quote_order_qty]}}
    end
  end

  defp validate_order_specific_params(_params) do
    # For other order types, basic validation is sufficient
    :ok
  end
end
