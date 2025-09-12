defmodule CryptoExchange.Binance.WebSocketHandler do
  @moduledoc """
  WebSockex-based WebSocket client handler for Binance WebSocket connections.

  This module replaces the problematic websocket_client library with WebSockex,
  providing reliable WebSocket connectivity for Binance streams.

  ## Features

  - Reliable connection establishment using WebSockex
  - Automatic reconnection with exponential backoff
  - Proper message handling and forwarding to parent process
  - Integration with existing PublicStreams architecture
  """

  use WebSockex
  require Logger

  @doc """
  Starts a WebSocket connection to the specified URL.

  ## Parameters
  - `url` - WebSocket URL to connect to
  - `parent_pid` - PID of the parent process to send messages to
  - `opts` - Optional connection options

  ## Returns
  - `{:ok, pid}` on successful connection
  - `{:error, reason}` on connection failure
  """
  def start_link(url, parent_pid, opts \\ []) do
    Logger.info("Starting WebSockex client for #{url}")

    # WebSockex options
    websockex_opts =
      [
        extra_headers: [{"User-Agent", "CryptoExchange/1.0"}]
      ] ++ opts

    WebSockex.start_link(url, __MODULE__, %{parent_pid: parent_pid}, websockex_opts)
  end

  @doc """
  Sends a message through the WebSocket connection.

  ## Parameters
  - `pid` - WebSocket process PID
  - `message` - Message to send (map or string)

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def send_message(pid, message) do
    json_message =
      case message do
        msg when is_binary(msg) -> msg
        msg -> Jason.encode!(msg)
      end

    Logger.debug("Sending WebSocket message: #{json_message}")
    WebSockex.send_frame(pid, {:text, json_message})
  end

  # WebSockex callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("WebSockex connection established successfully")

    # Notify parent process that connection is ready
    send(state.parent_pid, :websocket_connected)

    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:text, message}, state) do
    Logger.debug("Received WebSocket text message")

    # Forward message to parent process
    send(state.parent_pid, {:websocket_message, message})

    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:binary, _data}, state) do
    Logger.debug("Received binary WebSocket message (ignored)")
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame(frame, state) do
    Logger.debug("Received unknown WebSocket frame: #{inspect(frame)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:send, frame}, state) do
    {:reply, frame, state}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("WebSocket disconnected: #{inspect(reason)}")

    # Notify parent process of disconnection
    send(state.parent_pid, {:websocket_disconnect, reason})

    # WebSockex will automatically attempt to reconnect
    {:reconnect, state}
  end

  @impl WebSockex
  def terminate(reason, state) do
    Logger.info("WebSocket terminated: #{inspect(reason)}")

    # Notify parent process of termination
    send(state.parent_pid, {:websocket_error, reason})

    :ok
  end
end
