defmodule CryptoExchange.Binance.PublicClient do
  @moduledoc """
  REST API client for Binance public endpoints (no authentication required).

  This module provides functions for accessing Binance public market data including:
  - Historical klines/candlestick data
  - Exchange information and trading rules
  - Server time

  Unlike PrivateClient, this module does not require API keys or authentication,
  making it suitable for accessing public market data.

  ## Configuration

  The client uses the following configuration options:
  - `binance_api_url`: Base URL for Binance REST API (default: "https://api.binance.com")
  - `request_timeout`: HTTP request timeout in milliseconds (default: 10_000)

  ## Usage Examples

  ```elixir
  # Create client
  {:ok, client} = PublicClient.new()

  # Get historical klines
  {:ok, klines} = PublicClient.get_klines(client, "BTCUSDT", "1h", limit: 100)

  # Get klines with date range
  {:ok, klines} = PublicClient.get_klines(client, "BTCUSDT", "1d",
    start_time: 1609459200000,  # 2021-01-01
    end_time: 1640995199000     # 2021-12-31
  )

  # Get server time
  {:ok, server_time} = PublicClient.get_server_time(client)
  ```

  ## Error Handling

  The client handles various types of errors:
  - Network errors (timeouts, connection failures)
  - Binance-specific errors (invalid symbol, invalid interval, etc.)
  - Rate limiting (HTTP 429 responses)

  All errors are returned in the format `{:error, reason}` where reason
  provides details about what went wrong.
  """

  alias CryptoExchange.Binance.Errors
  alias CryptoExchange.Models.Kline
  require Logger

  @default_base_url "https://api.binance.com"
  @default_timeout 10_000

  defmodule RetryConfig do
    @moduledoc """
    Configuration for retry logic and error handling.
    """
    defstruct [
      :max_retries,
      :base_delay,
      :max_delay,
      :enable_jitter,
      :retryable_errors
    ]

    @type t :: %__MODULE__{
            max_retries: non_neg_integer(),
            base_delay: pos_integer(),
            max_delay: pos_integer(),
            enable_jitter: boolean(),
            retryable_errors: [atom()]
          }

    def default do
      %__MODULE__{
        max_retries: 3,
        base_delay: 1000,
        max_delay: 32000,
        enable_jitter: true,
        retryable_errors: [:rate_limiting, :network, :system]
      }
    end
  end

  defstruct [:base_url, :timeout, :retry_config]

  @type t :: %__MODULE__{
          base_url: String.t(),
          timeout: pos_integer(),
          retry_config: RetryConfig.t()
        }

  # Valid kline intervals supported by Binance
  @valid_intervals [
    "1s",
    "1m",
    "3m",
    "5m",
    "15m",
    "30m",
    "1h",
    "2h",
    "4h",
    "6h",
    "8h",
    "12h",
    "1d",
    "3d",
    "1w",
    "1M"
  ]

  @doc """
  Creates a new PublicClient.

  ## Parameters
  - `opts`: Optional configuration (base_url, timeout, retry_config)

  ## Returns
  - `{:ok, client}` always succeeds

  ## Example
  ```elixir
  {:ok, client} = PublicClient.new()
  {:ok, client} = PublicClient.new(timeout: 5000)
  ```
  """
  def new(opts \\ []) do
    retry_config = Keyword.get(opts, :retry_config, RetryConfig.default())

    client = %__MODULE__{
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      retry_config: retry_config
    }

    {:ok, client}
  end

  @doc """
  Retrieves historical kline/candlestick data for a symbol.

  Klines are uniquely identified by their open time. If startTime and endTime
  are not sent, the most recent klines are returned.

  ## Parameters
  - `client`: PublicClient struct
  - `symbol`: Trading symbol (e.g., "BTCUSDT")
  - `interval`: Kline interval (e.g., "1m", "1h", "1d") - see @valid_intervals
  - `opts`: Optional parameters
    - `:start_time` - Start time in milliseconds (inclusive)
    - `:end_time` - End time in milliseconds (inclusive)
    - `:timezone` - Timezone for kline interpretation (default: "0" UTC)
    - `:limit` - Number of klines to return (default: 500, max: 1000)

  ## Returns
  - `{:ok, [%Kline{}]}` - List of parsed kline structs on success
  - `{:error, reason}` - Error details on failure

  ## Examples
  ```elixir
  # Get last 100 1-hour klines
  {:ok, klines} = PublicClient.get_klines(client, "BTCUSDT", "1h", limit: 100)

  # Get klines for specific date range
  {:ok, klines} = PublicClient.get_klines(client, "BTCUSDT", "1d",
    start_time: 1609459200000,
    end_time: 1640995199000
  )

  # Get klines in specific timezone
  {:ok, klines} = PublicClient.get_klines(client, "BTCUSDT", "1h",
    timezone: "+08:00",
    limit: 24
  )
  ```
  """
  def get_klines(%__MODULE__{} = client, symbol, interval, opts \\ []) do
    Logger.debug("Getting klines for #{symbol} at #{interval} interval")

    with :ok <- validate_symbol(symbol),
         :ok <- validate_interval(interval),
         :ok <- validate_limit(Keyword.get(opts, :limit)),
         {:ok, params} <- build_klines_params(symbol, interval, opts),
         {:ok, response} <- get_request(client, "/api/v3/klines", params) do
      parse_klines_response(response, String.upcase(symbol), interval)
    else
      {:error, reason} = error ->
        Logger.error("Failed to get klines: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets the current server time from Binance.

  This is useful for synchronizing local time with Binance servers
  and for testing connectivity.

  ## Parameters
  - `client`: PublicClient struct

  ## Returns
  - `{:ok, %{server_time: integer()}}` - Server time in milliseconds
  - `{:error, reason}` - Error details on failure

  ## Example
  ```elixir
  {:ok, %{server_time: timestamp}} = PublicClient.get_server_time(client)
  ```
  """
  def get_server_time(%__MODULE__{} = client) do
    Logger.debug("Getting Binance server time")

    case get_request(client, "/api/v3/time", %{}) do
      {:ok, %{"serverTime" => server_time}} ->
        {:ok, %{server_time: server_time}}

      {:error, reason} = error ->
        Logger.error("Failed to get server time: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets exchange information including trading rules and symbol information.

  ## Parameters
  - `client`: PublicClient struct
  - `symbol`: Optional specific symbol to get info for

  ## Returns
  - `{:ok, exchange_info}` - Exchange information map
  - `{:error, reason}` - Error details on failure

  ## Example
  ```elixir
  # Get all exchange info
  {:ok, info} = PublicClient.get_exchange_info(client)

  # Get info for specific symbol
  {:ok, info} = PublicClient.get_exchange_info(client, "BTCUSDT")
  ```
  """
  def get_exchange_info(%__MODULE__{} = client, symbol \\ nil) do
    Logger.debug("Getting exchange info#{if symbol, do: " for #{symbol}", else: ""}")

    params = if symbol, do: %{symbol: symbol}, else: %{}

    case get_request(client, "/api/v3/exchangeInfo", params) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} = error ->
        Logger.error("Failed to get exchange info: #{inspect(reason)}")
        error
    end
  end

  # Private Functions

  defp get_request(%__MODULE__{} = client, path, params) do
    execute_with_retry(client, fn ->
      make_single_request(client, :get, path, params)
    end)
  end

  defp make_single_request(%__MODULE__{} = client, :get, path, params) do
    url = client.base_url <> path

    query_string = build_query_string(params)
    full_url = if query_string == "", do: url, else: "#{url}?#{query_string}"

    http_request(:get, full_url, "", [], client.timeout)
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

        case parse_error_response(status, response_body) do
          {:ok, error_info} ->
            {:error, error_info}

          {:error, _} ->
            {:error, {:http_error, status, response_body}}
        end

      {:error, reason} = error ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        error
    end
  end

  defp build_query_string(params) when params == %{}, do: ""

  defp build_query_string(params) do
    params
    |> Enum.map(fn {key, value} -> "#{key}=#{URI.encode_www_form(to_string(value))}" end)
    |> Enum.join("&")
  end

  defp build_klines_params(symbol, interval, opts) do
    params = %{
      symbol: String.upcase(symbol),
      interval: interval
    }

    params =
      opts
      |> Enum.reduce(params, fn {key, value}, acc ->
        case key do
          :start_time -> Map.put(acc, :startTime, value)
          :end_time -> Map.put(acc, :endTime, value)
          :timezone -> Map.put(acc, :timeZone, value)
          :limit -> Map.put(acc, :limit, value)
          _ -> acc
        end
      end)

    {:ok, params}
  end

  defp validate_symbol(symbol) when is_binary(symbol) and byte_size(symbol) > 0, do: :ok
  defp validate_symbol(_), do: {:error, {:invalid_symbol, "Symbol must be a non-empty string"}}

  defp validate_interval(interval) when interval in @valid_intervals, do: :ok

  defp validate_interval(interval) do
    {:error,
     {:invalid_interval, "Invalid interval '#{interval}'. Valid intervals: #{inspect(@valid_intervals)}"}}
  end

  defp validate_limit(nil), do: :ok
  defp validate_limit(limit) when is_integer(limit) and limit > 0 and limit <= 1000, do: :ok

  defp validate_limit(limit) do
    {:error, {:invalid_limit, "Limit must be between 1 and 1000, got: #{inspect(limit)}"}}
  end

  defp parse_klines_response(response, symbol, interval) when is_list(response) do
    Logger.debug("Parsing #{length(response)} klines from response")

    klines =
      response
      |> Enum.map(&parse_single_kline(&1, symbol, interval))
      |> Enum.filter(fn
        {:ok, _} -> true
        {:error, _} -> false
      end)
      |> Enum.map(fn {:ok, kline} -> kline end)

    {:ok, klines}
  end

  defp parse_klines_response(_, _, _),
    do: {:error, {:invalid_response, "Expected array of klines"}}

  defp parse_single_kline(
         [
           open_time,
           open,
           high,
           low,
           close,
           volume,
           close_time,
           quote_volume,
           num_trades,
           taker_buy_base_volume,
           taker_buy_quote_volume,
           _unused
         ],
         symbol,
         interval
       ) do
    # Build a map in the format that Kline.parse expects
    # Note: Historical klines don't have event_type or event_time from WebSocket
    kline_map = %{
      "e" => "kline",
      "E" => open_time,
      "s" => symbol,
      "k" => %{
        "t" => open_time,
        "T" => close_time,
        "s" => symbol,
        "i" => interval,
        "f" => nil,
        # Not available in historical data
        "L" => nil,
        # Not available in historical data
        "o" => to_string(open),
        "c" => to_string(close),
        "h" => to_string(high),
        "l" => to_string(low),
        "v" => to_string(volume),
        "n" => num_trades,
        "x" => true,
        # Historical klines are always closed
        "q" => to_string(quote_volume),
        "V" => to_string(taker_buy_base_volume),
        "Q" => to_string(taker_buy_quote_volume)
      }
    }

    Kline.parse(kline_map)
  end

  defp parse_single_kline(invalid, _symbol, _interval) do
    Logger.warning("Invalid kline format: #{inspect(invalid)}")
    {:error, {:invalid_kline_format, invalid}}
  end

  # Retry Logic and Error Handling

  defp execute_with_retry(%__MODULE__{retry_config: config} = client, request_fn) do
    execute_with_retry(client, request_fn, 1, config.max_retries)
  end

  defp execute_with_retry(_client, request_fn, attempt, max_retries)
       when attempt > max_retries do
    Logger.warning("Maximum retry attempts (#{max_retries}) exceeded")

    case request_fn.() do
      {:error, error_info} = error ->
        if is_struct(error_info, Errors) do
          Logger.error("Final attempt failed: #{Errors.user_message(error_info)}")
        end

        error

      result ->
        result
    end
  end

  defp execute_with_retry(
         %__MODULE__{retry_config: config} = client,
         request_fn,
         attempt,
         max_retries
       ) do
    case request_fn.() do
      {:ok, result} ->
        if attempt > 1 do
          Logger.info("Request succeeded on attempt #{attempt}")
        end

        {:ok, result}

      {:error, error_info} = error ->
        if is_struct(error_info, Errors) and should_retry?(error_info, config) do
          backoff_ms = calculate_retry_delay(attempt, error_info, config)

          Logger.warning(
            "Request failed on attempt #{attempt}/#{max_retries}: #{Errors.user_message(error_info)}. " <>
              "Retrying in #{backoff_ms}ms..."
          )

          Process.sleep(backoff_ms)
          execute_with_retry(client, request_fn, attempt + 1, max_retries)
        else
          if is_struct(error_info, Errors) do
            Logger.error("Non-retryable error: #{Errors.user_message(error_info)}")
          else
            Logger.error("Request failed: #{inspect(error_info)}")
          end

          error
        end

      other_error ->
        Logger.error("Request failed: #{inspect(other_error)}")
        other_error
    end
  end

  defp should_retry?(%Errors{} = error_info, %RetryConfig{retryable_errors: retryable_categories}) do
    Errors.retryable?(error_info) and Errors.category(error_info) in retryable_categories
  end

  defp calculate_retry_delay(attempt, %Errors{} = error_info, %RetryConfig{} = config) do
    Errors.calculate_backoff(attempt, error_info,
      base_delay: config.base_delay,
      max_delay: config.max_delay,
      jitter: config.enable_jitter
    )
  end

  defp parse_error_response(status, response_body) when is_map(response_body) do
    # Try to parse as Binance API error first
    case Errors.parse_api_error(response_body) do
      {:ok, _error_info} = result -> result
      {:error, _} -> Errors.parse_http_error(status, inspect(response_body))
    end
  end

  defp parse_error_response(status, response_body) when is_binary(response_body) do
    # Try to decode JSON first
    case Jason.decode(response_body) do
      {:ok, decoded} -> parse_error_response(status, decoded)
      {:error, _} -> Errors.parse_http_error(status, response_body)
    end
  end

  defp parse_error_response(status, response_body) do
    Errors.parse_http_error(status, inspect(response_body))
  end
end
