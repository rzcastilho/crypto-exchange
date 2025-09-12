defmodule CryptoExchange.Binance.Auth do
  @moduledoc """
  Authentication utilities for Binance REST API.

  This module provides HMAC-SHA256 signature generation and request signing
  for authenticated Binance API requests. It handles the cryptographic
  requirements for secure API communication.

  ## Binance Authentication Requirements

  Binance requires HMAC-SHA256 signatures for authenticated endpoints:

  1. **Query String**: All parameters must be included in query string format
  2. **Timestamp**: A timestamp parameter is required and must be within acceptable server time
  3. **Signature**: HMAC-SHA256 signature of the query string using the secret key
  4. **Headers**: API key must be included in X-MBX-APIKEY header

  ## Usage Examples

  ```elixir
  # Create signed request parameters
  params = %{symbol: "BTCUSDT", side: "BUY", type: "MARKET", quantity: "0.001"}
  credentials = %{api_key: "your_key", secret_key: "your_secret"}

  signed_params = Auth.sign_request(params, credentials)
  # %{symbol: "BTCUSDT", side: "BUY", type: "MARKET", quantity: "0.001", 
  #   timestamp: 1640995200000, signature: "abc123..."}

  # Get required headers
  headers = Auth.get_headers(credentials)
  # [{"X-MBX-APIKEY", "your_key"}, {"Content-Type", "application/x-www-form-urlencoded"}]

  # Generate signature for query string
  query_string = "symbol=BTCUSDT&side=BUY&timestamp=1640995200000"
  signature = Auth.generate_signature(query_string, "your_secret")
  # "a1b2c3d4e5f6..."
  ```

  ## Security Notes

  - Secret keys are never logged or exposed in error messages
  - All cryptographic operations use Erlang's built-in :crypto module
  - Timestamps are generated using system time to prevent replay attacks
  - Query parameters are URL-encoded according to Binance requirements
  """

  require Logger

  @doc """
  Signs a request with HMAC-SHA256 signature for Binance API authentication.

  Adds timestamp and signature to the provided parameters map.

  ## Parameters
  - `params`: Map of request parameters
  - `credentials`: Map containing :api_key and :secret_key

  ## Returns
  Map with added timestamp and signature parameters.

  ## Example
  ```elixir
  params = %{symbol: "BTCUSDT", side: "BUY"}
  credentials = %{api_key: "key", secret_key: "secret"}

  Auth.sign_request(params, credentials)
  # %{symbol: "BTCUSDT", side: "BUY", timestamp: 1640995200000, signature: "..."}
  ```
  """
  def sign_request(params, %{secret_key: secret_key}) do
    timestamp = get_timestamp()

    params_with_timestamp = Map.put(params, :timestamp, timestamp)
    query_string = build_query_string(params_with_timestamp)
    signature = generate_signature(query_string, secret_key)

    Map.put(params_with_timestamp, :signature, signature)
  end

  @doc """
  Generates HMAC-SHA256 signature for a query string.

  ## Parameters
  - `query_string`: URL-encoded query string to sign
  - `secret_key`: Binance secret key for signing

  ## Returns
  Hexadecimal string representation of the HMAC-SHA256 signature.

  ## Example
  ```elixir
  query = "symbol=BTCUSDT&timestamp=1640995200000"
  Auth.generate_signature(query, "my_secret_key")
  # "a1b2c3d4e5f6789..."
  ```
  """
  def generate_signature(query_string, secret_key) do
    :crypto.mac(:hmac, :sha256, secret_key, query_string)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Gets the required HTTP headers for authenticated Binance API requests.

  ## Parameters
  - `credentials`: Map containing :api_key

  ## Returns
  List of HTTP header tuples.

  ## Example
  ```elixir
  Auth.get_headers(%{api_key: "my_api_key"})
  # [{"X-MBX-APIKEY", "my_api_key"}, {"Content-Type", "application/x-www-form-urlencoded"}]
  ```
  """
  def get_headers(%{api_key: api_key}) do
    [
      {"X-MBX-APIKEY", api_key},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]
  end

  @doc """
  Builds a URL-encoded query string from a parameters map.

  Parameters are sorted alphabetically by key to ensure consistent
  signature generation.

  ## Parameters
  - `params`: Map of parameters to encode

  ## Returns
  URL-encoded query string.

  ## Example
  ```elixir
  Auth.build_query_string(%{symbol: "BTCUSDT", side: "BUY", quantity: "0.001"})
  # "quantity=0.001&side=BUY&symbol=BTCUSDT"
  ```
  """
  def build_query_string(params) when is_map(params) do
    params
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Enum.map(&encode_param/1)
    |> Enum.join("&")
  end

  @doc """
  Gets the current timestamp in milliseconds for Binance API requests.

  Binance requires timestamps to be within a reasonable time window
  (typically 5 seconds) of the server time.

  ## Returns
  Integer timestamp in milliseconds since Unix epoch.

  ## Example
  ```elixir
  Auth.get_timestamp()
  # 1640995200000
  ```
  """
  def get_timestamp do
    System.system_time(:millisecond)
  end

  @doc """
  Validates that required credentials are present and properly formatted.

  ## Parameters
  - `credentials`: Map that should contain :api_key and :secret_key

  ## Returns
  - `:ok` if credentials are valid
  - `{:error, reason}` if credentials are invalid or missing

  ## Example
  ```elixir
  Auth.validate_credentials(%{api_key: "key", secret_key: "secret"})
  # :ok

  Auth.validate_credentials(%{api_key: "key"})
  # {:error, :missing_secret_key}
  ```
  """
  def validate_credentials(%{api_key: api_key, secret_key: secret_key})
      when is_binary(api_key) and byte_size(api_key) > 0 and
             is_binary(secret_key) and byte_size(secret_key) > 0 do
    :ok
  end

  def validate_credentials(%{api_key: _}) do
    {:error, :missing_secret_key}
  end

  def validate_credentials(%{secret_key: _}) do
    {:error, :missing_api_key}
  end

  def validate_credentials(_) do
    {:error, :invalid_credentials_format}
  end

  # Private Functions

  defp encode_param({key, value}) do
    key_str = to_string(key)
    value_str = to_string(value)
    "#{URI.encode_www_form(key_str)}=#{URI.encode_www_form(value_str)}"
  end
end
