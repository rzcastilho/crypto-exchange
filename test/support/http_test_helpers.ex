defmodule CryptoExchange.TestSupport.HTTPTestHelpers do
  @moduledoc """
  Test helpers for HTTP client testing using Bypass.
  Provides utilities for mocking HTTP endpoints and testing HTTP interactions.
  """

  alias Bypass
  import ExUnit.Assertions

  # =============================================================================
  # BYPASS SERVER SETUP
  # =============================================================================

  @doc """
  Starts a Bypass server and returns it with the base URL.
  Automatically stops the server when the test process exits.
  """
  def start_bypass_server(opts \\ []) do
    bypass = Bypass.open(opts)
    base_url = "http://localhost:#{bypass.port}"
    {bypass, base_url}
  end

  @doc """
  Configures Bypass to expect a specific HTTP request and return a response.
  """
  def expect_http_request(bypass, method, path, response_body, status_code \\ 200, headers \\ []) do
    Bypass.expect_once(bypass, method, path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> add_response_headers(headers)
      |> Plug.Conn.resp(status_code, Jason.encode!(response_body))
    end)
  end

  @doc """
  Configures Bypass to expect multiple requests to the same endpoint.
  """
  def expect_multiple_requests(bypass, method, path, responses) do
    Bypass.expect(bypass, method, path, fn conn ->
      # Use a simple counter to cycle through responses
      response_index = get_request_count(bypass, method, path)
      {response_body, status_code, headers} = Enum.at(responses, response_index, List.last(responses))
      
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> add_response_headers(headers)
      |> Plug.Conn.resp(status_code, Jason.encode!(response_body))
    end)
  end

  @doc """
  Configures Bypass to return an error (connection failure).
  """
  def expect_connection_error(bypass, method, path) do
    Bypass.expect_once(bypass, method, path, fn _conn ->
      # This will cause the connection to be closed abruptly
      exit(:connection_error)
    end)
  end

  @doc """
  Configures Bypass to return a timeout (slow response).
  """
  def expect_timeout(bypass, method, path, delay_ms \\ 5000) do
    Bypass.expect_once(bypass, method, path, fn conn ->
      :timer.sleep(delay_ms)
      Plug.Conn.resp(conn, 200, Jason.encode!(%{status: "ok"}))
    end)
  end

  # =============================================================================
  # BINANCE API SPECIFIC HELPERS
  # =============================================================================

  @doc """
  Sets up Bypass to mock Binance API endpoints with proper authentication.
  """
  def setup_binance_api_mock(bypass, base_url) do
    # Mock server info endpoint
    expect_http_request(bypass, "GET", "/api/v3/exchangeInfo", %{
      "symbols" => [
        %{
          "symbol" => "BTCUSDT",
          "status" => "TRADING",
          "baseAsset" => "BTC",
          "quoteAsset" => "USDT"
        }
      ]
    })

    # Mock account endpoint
    expect_http_request(bypass, "GET", "/api/v3/account", %{
      "balances" => [
        %{"asset" => "BTC", "free" => "1.00000000", "locked" => "0.00000000"},
        %{"asset" => "USDT", "free" => "10000.00000000", "locked" => "0.00000000"}
      ]
    })

    # Mock order placement endpoint
    expect_http_request(bypass, "POST", "/api/v3/order", %{
      "symbol" => "BTCUSDT",
      "orderId" => 12345,
      "clientOrderId" => "test_order_123",
      "status" => "NEW",
      "side" => "BUY",
      "type" => "LIMIT",
      "origQty" => "0.00100000",
      "price" => "50000.00000000"
    })

    # Mock order cancellation endpoint
    expect_http_request(bypass, "DELETE", "/api/v3/order", %{
      "symbol" => "BTCUSDT",
      "orderId" => 12345,
      "status" => "CANCELED"
    })

    base_url
  end

  @doc """
  Creates a mock Binance error response.
  """
  def binance_error_response(code, msg) do
    %{
      "code" => code,
      "msg" => msg
    }
  end

  @doc """
  Sets up Bypass to return Binance API errors.
  """
  def expect_binance_error(bypass, method, path, error_code, error_msg, status_code \\ 400) do
    error_response = binance_error_response(error_code, error_msg)
    expect_http_request(bypass, method, path, error_response, status_code)
  end

  # =============================================================================
  # REQUEST VALIDATION HELPERS
  # =============================================================================

  @doc """
  Validates that a request contains the expected headers.
  """
  def assert_request_headers(conn, expected_headers) do
    Enum.each(expected_headers, fn {key, expected_value} ->
      actual_value = Plug.Conn.get_req_header(conn, key) |> List.first()
      assert actual_value == expected_value, 
        "Expected header #{key} to be #{expected_value}, got #{actual_value}"
    end)
  end

  @doc """
  Validates that a request body contains expected JSON data.
  """
  def assert_request_body(conn, expected_body) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    
    case Jason.decode(body) do
      {:ok, decoded_body} ->
        assert decoded_body == expected_body,
          "Expected body #{inspect(expected_body)}, got #{inspect(decoded_body)}"
      {:error, _} ->
        # If it's not JSON, compare as string
        assert body == expected_body,
          "Expected body #{inspect(expected_body)}, got #{inspect(body)}"
    end
  end

  @doc """
  Validates that a request contains proper Binance authentication.
  """
  def assert_binance_auth(conn) do
    # Check for API key header
    api_key = Plug.Conn.get_req_header(conn, "x-mbx-apikey") |> List.first()
    assert api_key != nil, "Missing X-MBX-APIKEY header"
    
    # Check for signature in query params
    query_params = Plug.Conn.fetch_query_params(conn).query_params
    assert Map.has_key?(query_params, "signature"), "Missing signature parameter"
    assert Map.has_key?(query_params, "timestamp"), "Missing timestamp parameter"
  end

  # =============================================================================
  # RESPONSE HELPERS
  # =============================================================================

  @doc """
  Creates a successful JSON response with optional custom headers.
  """
  def json_response(conn, data, status \\ 200, headers \\ []) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> add_response_headers(headers)
    |> Plug.Conn.resp(status, Jason.encode!(data))
  end

  @doc """
  Creates an error response with standard error format.
  """
  def error_response(conn, error_code, message, status \\ 400) do
    error_data = %{
      "error" => %{
        "code" => error_code,
        "message" => message
      }
    }
    json_response(conn, error_data, status)
  end

  @doc """
  Adds custom headers to a response.
  """
  defp add_response_headers(conn, []), do: conn
  defp add_response_headers(conn, [{key, value} | rest]) do
    conn
    |> Plug.Conn.put_resp_header(key, value)
    |> add_response_headers(rest)
  end

  # =============================================================================
  # REQUEST COUNTING AND TRACKING
  # =============================================================================

  @doc """
  Tracks the number of requests made to a specific endpoint.
  """
  def track_requests(bypass, method, path) do
    counter_key = request_counter_key(method, path)
    :ets.new(counter_key, [:public, :named_table])
    :ets.insert(counter_key, {:count, 0})
    
    Bypass.expect(bypass, method, path, fn conn ->
      increment_request_count(counter_key)
      Plug.Conn.resp(conn, 200, Jason.encode!(%{status: "ok"}))
    end)
  end

  @doc """
  Gets the number of requests made to a specific endpoint.
  """
  def get_request_count(bypass, method, path) do
    counter_key = request_counter_key(method, path)
    
    case :ets.lookup(counter_key, :count) do
      [{:count, count}] -> count
      [] -> 0
    end
  end

  defp request_counter_key(method, path) do
    :"#{method}_#{String.replace(path, "/", "_")}_counter"
  end

  defp increment_request_count(counter_key) do
    :ets.update_counter(counter_key, :count, 1)
  end

  # =============================================================================
  # RATE LIMITING HELPERS
  # =============================================================================

  @doc """
  Sets up Bypass to simulate rate limiting responses.
  """
  def expect_rate_limit(bypass, method, path, retry_after \\ 60) do
    headers = [{"retry-after", to_string(retry_after)}]
    error_response = %{
      "code" => -1003,
      "msg" => "Too many requests"
    }
    expect_http_request(bypass, method, path, error_response, 429, headers)
  end

  @doc """
  Verifies that rate limiting headers are present in a response.
  """
  def assert_rate_limit_headers(conn) do
    retry_after = Plug.Conn.get_resp_header(conn, "retry-after") |> List.first()
    assert retry_after != nil, "Missing retry-after header in rate limit response"
  end
end