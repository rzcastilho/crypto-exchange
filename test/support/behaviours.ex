defmodule CryptoExchange.Behaviours.HTTPClientBehaviour do
  @moduledoc """
  Behaviour for HTTP client implementations.
  Allows mocking of HTTP requests in tests.
  """

  @type method :: :get | :post | :put | :delete | :patch
  @type url :: String.t()
  @type body :: String.t() | map() | nil
  @type headers :: list({String.t(), String.t()}) | map()
  @type opts :: keyword()
  @type response :: {:ok, %{status: integer(), body: String.t()}} | {:error, term()}

  @callback request(method, url, body, headers, opts) :: response
end

defmodule CryptoExchange.Behaviours.WebSocketClientBehaviour do
  @moduledoc """
  Behaviour for WebSocket client implementations.
  Allows mocking of WebSocket connections in tests.
  """

  @type url :: String.t()
  @type ws_module :: atom()
  @type state :: term()
  @type opts :: keyword()
  @type frame :: term()
  @type ws_pid :: pid()

  @callback start_link(url, ws_module, state, opts) :: {:ok, pid} | {:error, term()}
  @callback send_frame(pid, frame) :: :ok | {:error, term()}
  @callback close(pid) :: :ok
end

defmodule CryptoExchange.Behaviours.BinanceAPIBehaviour do
  @moduledoc """
  Behaviour for Binance API implementations.
  Allows mocking of Binance API calls in tests.
  """

  @type credentials :: %{api_key: String.t(), secret_key: String.t()}
  @type order_params :: map()
  @type symbol :: String.t()
  @type order_id :: String.t()
  @type result :: {:ok, term()} | {:error, term()}

  @callback place_order(credentials, order_params) :: result
  @callback cancel_order(credentials, symbol, order_id) :: result
  @callback get_order(credentials, symbol, order_id) :: result
  @callback get_account(credentials) :: result
  @callback get_orders(credentials, symbol) :: result
end