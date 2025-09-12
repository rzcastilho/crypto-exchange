defmodule CryptoExchange.Binance.WebSocketHandler do
  @moduledoc """
  WebSocket client handler for Binance WebSocket connections.

  This module implements the :websocket_client behavior and handles
  the low-level WebSocket communication with Binance, forwarding
  messages to the PublicStreams GenServer.
  """

  require Logger

  @behaviour :websocket_client

  @impl :websocket_client
  def init(parent_pid) do
    {:ok, %{parent: parent_pid}}
  end

  @impl :websocket_client
  def onconnect(_req, state) do
    Logger.info("WebSocket onconnect callback triggered - sending :websocket_connected")
    send(state.parent, :websocket_connected)
    {:ok, state}
  end

  @impl :websocket_client
  def ondisconnect({:error, reason}, state) do
    Logger.warning("WebSocket disconnected with error: #{inspect(reason)}")
    send(state.parent, {:websocket_disconnect, reason})
    {:ok, state}
  end

  def ondisconnect({:close, reason}, state) do
    Logger.info("WebSocket closed: #{inspect(reason)}")
    send(state.parent, {:websocket_disconnect, reason})
    {:ok, state}
  end

  @impl :websocket_client
  def websocket_handle({:text, message}, _conn_state, state) do
    send(state.parent, {:websocket_message, message})
    {:ok, state}
  end

  def websocket_handle({:binary, _data}, _conn_state, state) do
    Logger.debug("Received binary WebSocket message (ignored)")
    {:ok, state}
  end

  def websocket_handle(frame, _conn_state, state) do
    Logger.debug("Received unknown WebSocket frame: #{inspect(frame)}")
    {:ok, state}
  end

  @impl :websocket_client
  def websocket_info(info, _conn_state, state) do
    Logger.debug("WebSocket received info: #{inspect(info)}")
    {:ok, state}
  end

  @impl :websocket_client
  def websocket_terminate(reason, _conn_state, state) do
    Logger.info("WebSocket terminated: #{inspect(reason)}")
    send(state.parent, {:websocket_error, reason})
    :ok
  end
end