defmodule CryptoExchange.Binance.PublicStreams do
  @moduledoc """
  WebSocket adapter for Binance public market data streams.

  This module manages WebSocket connections to Binance's public data streams,
  handling market data reception, parsing, and broadcasting via Phoenix.PubSub.
  It implements robust reconnection logic with exponential backoff and integrates
  with the StreamManager to provide real-time market data.

  ## Features

  - **WebSocket Connection Management**: Establishes and maintains WebSocket connection to Binance
  - **Message Parsing**: Parses incoming JSON messages and extracts market data
  - **Phoenix.PubSub Broadcasting**: Broadcasts parsed data to appropriate topics
  - **Exponential Backoff Reconnection**: Handles connection failures with progressive retry delays
  - **Stream Subscription Management**: Supports dynamic subscription to ticker, depth, trade, and kline streams

  ## WebSocket Connection

  Connects to Binance WebSocket API at the configured endpoint (default: wss://stream.binance.com:9443/ws).
  The connection is managed by the `:websocket_client` library and follows OTP GenServer patterns.

  ## Message Format

  Binance sends messages in the following format:
  ```json
  {
    "stream": "btcusdt@ticker",
    "data": {
      "e": "24hrTicker",
      "E": 123456789,
      "s": "BTCUSDT",
      "p": "0.0015",
      "c": "0.0025"
    }
  }
  ```

  These are parsed and broadcast as:
  ```elixir
  {:market_data, %{
    type: :ticker,
    symbol: "BTCUSDT", 
    data: %{price: "0.0025", ...}
  }}
  ```

  ## Topic Structure

  Data is broadcast on Phoenix.PubSub topics matching the format:
  - Ticker: `binance:ticker:SYMBOL`
  - Order Book Depth: `binance:depth:SYMBOL`
  - Trades: `binance:trades:SYMBOL`

  ## Usage Example

  ```elixir
  # Start the WebSocket adapter
  {:ok, pid} = CryptoExchange.Binance.PublicStreams.start_link([])

  # Subscribe to streams through StreamManager
  {:ok, topic} = CryptoExchange.PublicStreams.StreamManager.subscribe_to_ticker("BTCUSDT")
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  # Subscribe to the adapter to receive stream data
  CryptoExchange.Binance.PublicStreams.subscribe(["btcusdt@ticker"])

  # Listen for market data
  receive do
    {:market_data, %{type: :ticker, symbol: "BTCUSDT", data: data}} ->
      IO.puts("BTC Price: \#{data.last_price}")
  end
  ```

  ## Error Handling

  The module implements comprehensive error handling:

  - **Connection Failures**: Automatic reconnection with exponential backoff (1s to 60s)
  - **Malformed Messages**: Graceful handling with error logging
  - **WebSocket Errors**: Connection reset and resubscription to active streams
  - **JSON Parsing Errors**: Error logging without crashing

  ## Configuration

  The WebSocket URL is configurable via application config:
  ```elixir
  config :crypto_exchange,
    binance_ws_url: "wss://stream.binance.com:9443/ws"
  ```
  """

  use GenServer
  require Logger

  alias CryptoExchange.Models.{Ticker, OrderBook, Trade, Kline}
  alias CryptoExchange.Binance.WebSocketHandler

  @name __MODULE__

  # Reconnection settings
  # 1 second
  @initial_backoff 1000
  # 60 seconds
  @max_backoff 60_000
  @backoff_multiplier 2

  ## Client API

  @doc """
  Starts the Binance PublicStreams WebSocket adapter.

  ## Options
  - `:name` - Process name (defaults to module name)
  - `:ws_url` - WebSocket URL (defaults to config value)

  ## Examples
      {:ok, pid} = CryptoExchange.Binance.PublicStreams.start_link([])
      {:ok, pid} = CryptoExchange.Binance.PublicStreams.start_link(name: :binance_streams)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes to one or more Binance streams.

  ## Parameters
  - `streams` - List of stream names (e.g., ["btcusdt@ticker", "ethusdt@depth5"])

  ## Examples
      :ok = CryptoExchange.Binance.PublicStreams.subscribe(["btcusdt@ticker"])
      :ok = CryptoExchange.Binance.PublicStreams.subscribe(["btcusdt@ticker", "ethusdt@depth5"])
  """
  def subscribe(streams) when is_list(streams) do
    GenServer.call(@name, {:subscribe, streams})
  end

  def subscribe(stream) when is_binary(stream) do
    subscribe([stream])
  end

  @doc """
  Unsubscribes from one or more Binance streams.

  ## Parameters
  - `streams` - List of stream names to unsubscribe from

  ## Examples
      :ok = CryptoExchange.Binance.PublicStreams.unsubscribe(["btcusdt@ticker"])
  """
  def unsubscribe(streams) when is_list(streams) do
    GenServer.call(@name, {:unsubscribe, streams})
  end

  def unsubscribe(stream) when is_binary(stream) do
    unsubscribe([stream])
  end

  @doc """
  Gets the current connection status and subscribed streams.

  ## Returns
  - `{:connected, streams}` - Connected with list of subscribed streams
  - `{:disconnected, reason}` - Disconnected with reason
  - `{:reconnecting, backoff_ms}` - Reconnecting with current backoff delay

  ## Examples
      {:connected, ["btcusdt@ticker"]} = CryptoExchange.Binance.PublicStreams.status()
  """
  def status do
    GenServer.call(@name, :status)
  end

  @doc """
  Gets the health of the WebSocket connection.

  ## Returns
  - `{:ok, health_map}` - Health information including connection status
  - `{:error, reason}` - If unable to get health (e.g., PublicStreams not started)

  ## Examples
      {:ok, health} = CryptoExchange.Binance.PublicStreams.get_connection_health()
  """
  def get_connection_health do
    try do
      case GenServer.whereis(@name) do
        nil ->
          {:error, :not_started}

        pid ->
          GenServer.call(pid, :get_connection_health, 2000)
      end
    catch
      :exit, reason -> {:error, reason}
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting Binance PublicStreams adapter")

    ws_url = Keyword.get(opts, :ws_url, get_ws_url())

    state = %{
      ws_url: ws_url,
      websocket: nil,
      subscriptions: MapSet.new(),
      backoff: @initial_backoff,
      connection_status: :disconnected,
      reconnect_timer: nil,
      pending_subscriptions: []
    }

    # Connect immediately
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, streams}, _from, state) do
    Logger.debug("Subscribe request for streams: #{inspect(streams)}")

    new_subscriptions =
      streams
      |> Enum.reduce(state.subscriptions, &MapSet.put(&2, &1))

    new_state = %{state | subscriptions: new_subscriptions}

    # Send subscription message only if fully connected
    case {state.websocket, state.connection_status} do
      {nil, _} ->
        Logger.debug("Not connected, will subscribe when connection is established")
        {:reply, :ok, new_state}

      {_, :connected} ->
        case send_subscription_message(state.websocket, streams, "SUBSCRIBE") do
          :ok -> {:reply, :ok, new_state}
          {:error, reason} -> {:reply, {:error, reason}, new_state}
        end

      {_, status} ->
        Logger.debug("Connection status is #{status}, will subscribe when fully connected")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, streams}, _from, state) do
    Logger.debug("Unsubscribe request for streams: #{inspect(streams)}")

    new_subscriptions =
      streams
      |> Enum.reduce(state.subscriptions, &MapSet.delete(&2, &1))

    new_state = %{state | subscriptions: new_subscriptions}

    # Send unsubscription message only if fully connected
    case {state.websocket, state.connection_status} do
      {nil, _} ->
        Logger.debug("Not connected, removing from subscription list only")
        {:reply, :ok, new_state}

      {_, :connected} ->
        case send_subscription_message(state.websocket, streams, "UNSUBSCRIBE") do
          :ok -> {:reply, :ok, new_state}
          {:error, reason} -> {:reply, {:error, reason}, new_state}
        end

      {_, status} ->
        Logger.debug("Connection status is #{status}, removing from subscription list only")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status =
      case state.connection_status do
        :connected -> {:connected, MapSet.to_list(state.subscriptions)}
        :connecting -> {:connecting, "WebSocket connected, waiting for subscription confirmation"}
        :disconnected -> {:disconnected, "Not connected"}
        :reconnecting -> {:reconnecting, state.backoff}
      end

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_connection_health, _from, state) do
    # If we have a websocket PID, get its health directly
    health =
      case state.websocket do
        nil ->
          %{
            connected: false,
            connection_status: state.connection_status,
            circuit_breaker_state: :open,
            retry_count: 0,
            total_reconnects: 0,
            buffered_messages: 0,
            subscriptions: MapSet.to_list(state.subscriptions)
          }

        ws_pid ->
          # Try to get health from the WebSocket handler
          case WebSocketHandler.get_connection_health(ws_pid) do
            health_map when is_map(health_map) ->
              Map.put(health_map, :subscriptions, MapSet.to_list(state.subscriptions))

            {:error, _reason} ->
              %{
                connected: false,
                connection_status: state.connection_status,
                circuit_breaker_state: :open,
                retry_count: 0,
                total_reconnects: 0,
                buffered_messages: 0,
                subscriptions: MapSet.to_list(state.subscriptions)
              }
          end
      end

    {:reply, {:ok, health}, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("Connecting to Binance WebSocket at #{state.ws_url}")

    case CryptoExchange.Binance.WebSocketHandler.start_link(state.ws_url, self()) do
      {:ok, websocket} ->
        Logger.info("Successfully connected to Binance WebSocket")

        # Reset backoff on successful connection but don't subscribe yet
        # Set a fallback timer in case onconnect callback doesn't fire
        fallback_timer = Process.send_after(self(), :connection_timeout, 2000)

        new_state = %{
          state
          | websocket: websocket,
            connection_status: :connecting,
            backoff: @initial_backoff,
            reconnect_timer: fallback_timer,
            pending_subscriptions: MapSet.to_list(state.subscriptions)
        }

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to connect to Binance WebSocket: #{inspect(reason)}")
        schedule_reconnect(state)
    end
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect to Binance WebSocket")
    send(self(), :connect)
    {:noreply, %{state | reconnect_timer: nil}}
  end

  @impl true
  def handle_info({:websocket_disconnect, _reason}, state) do
    Logger.warning("WebSocket disconnected")

    new_state = %{
      state
      | websocket: nil,
        connection_status: :disconnected,
        pending_subscriptions: MapSet.to_list(state.subscriptions)
    }

    schedule_reconnect(new_state)
  end

  @impl true
  def handle_info(:websocket_connected, state) do
    Logger.info("WebSocket connection confirmed - processing pending subscriptions")
    handle_connection_confirmed(state)
  end

  @impl true
  def handle_info(:connection_timeout, state) do
    Logger.info("Connection timeout reached - assuming WebSocket is ready")
    handle_connection_confirmed(state)
  end

  @impl true
  def handle_info({:websocket_message, message}, state) do
    case Jason.decode(message) do
      {:ok, decoded} ->
        handle_binance_message(decoded)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to parse WebSocket message: #{inspect(reason)}, message: #{message}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:websocket_error, reason}, state) do
    Logger.error("WebSocket error: #{inspect(reason)}")

    new_state = %{
      state
      | websocket: nil,
        connection_status: :disconnected,
        pending_subscriptions: MapSet.to_list(state.subscriptions)
    }

    schedule_reconnect(new_state)
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("PublicStreams received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("PublicStreams terminating: #{inspect(reason)}")

    # Cancel reconnect timer if active
    if state.reconnect_timer do
      Process.cancel_timer(state.reconnect_timer)
    end

    # Close WebSocket connection if active
    # Note: websocket_client processes terminate automatically

    :ok
  end

  ## Private Functions

  defp get_ws_url do
    Application.get_env(:crypto_exchange, :binance_ws_url, "wss://stream.binance.com:9443/ws")
  end

  defp schedule_reconnect(state) do
    Logger.info("Scheduling reconnect in #{state.backoff}ms")

    timer = Process.send_after(self(), :reconnect, state.backoff)

    # Apply exponential backoff
    new_backoff = min(state.backoff * @backoff_multiplier, @max_backoff)

    new_state = %{
      state
      | connection_status: :reconnecting,
        backoff: new_backoff,
        reconnect_timer: timer
    }

    {:noreply, new_state}
  end

  defp send_subscription_message(websocket, streams, method) do
    message = %{
      method: method,
      params: streams,
      id: :os.system_time(:millisecond)
    }

    case Jason.encode(message) do
      {:ok, json} ->
        Logger.debug("Sending #{method} message: #{json}")

        # Send message using WebSockex handler
        case CryptoExchange.Binance.WebSocketHandler.send_message(websocket, message) do
          :ok ->
            Logger.debug("WebSocket message sent successfully")
            :ok

          {:error, reason} ->
            Logger.error("Failed to send WebSocket message: #{inspect(reason)}")
            Logger.error("WebSocket client might not be properly connected")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to encode subscription message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_binance_message(%{"stream" => stream, "data" => data}) do
    Logger.debug("Received stream data: #{stream}")

    case parse_stream_data(stream, data) do
      {:ok, parsed_data} ->
        broadcast_market_data(parsed_data)

      {:error, reason} ->
        Logger.error("Failed to parse stream data for #{stream}: #{inspect(reason)}")
    end
  end

  defp handle_binance_message(%{"e" => "kline", "s" => symbol, "k" => kline_data}) do
    Logger.debug("Received kline data for #{symbol}")

    case parse_kline_message(symbol, kline_data) do
      {:ok, parsed_data} ->
        broadcast_market_data(parsed_data)

      {:error, reason} ->
        Logger.error("Failed to parse kline data for #{symbol}: #{inspect(reason)}")
    end
  end

  defp handle_binance_message(%{"e" => "trade", "s" => symbol} = message) do
    Logger.debug("Received trade data for #{symbol}")

    case parse_trade_message(symbol, message) do
      {:ok, parsed_data} ->
        broadcast_market_data(parsed_data)

      {:error, reason} ->
        Logger.error("Failed to parse trade data for #{symbol}: #{inspect(reason)}")
    end
  end

  defp handle_binance_message(%{"e" => "24hrTicker", "s" => symbol} = message) do
    Logger.debug("Received ticker data for #{symbol}")

    case parse_ticker_message(symbol, message) do
      {:ok, parsed_data} ->
        broadcast_market_data(parsed_data)

      {:error, reason} ->
        Logger.error("Failed to parse ticker data for #{symbol}: #{inspect(reason)}")
    end
  end

  defp handle_binance_message(%{"asks" => _asks, "bids" => _bids, "lastUpdateId" => _} = message) do
    Logger.debug("Received depth data")

    case parse_depth_message(message) do
      {:ok, parsed_data} ->
        broadcast_market_data(parsed_data)

      {:error, reason} ->
        Logger.error("Failed to parse depth data: #{inspect(reason)}")
    end
  end

  defp handle_binance_message(%{"result" => result, "id" => id}) do
    Logger.debug("Received subscription response: #{inspect(result)} for id: #{id}")
  end

  defp handle_binance_message(%{"error" => error}) do
    Logger.error("Received error from Binance: #{inspect(error)}")
  end

  defp handle_binance_message(message) do
    Logger.warning("Received unknown message format: #{inspect(message)}")
  end

  defp parse_stream_data(stream, data) do
    cond do
      String.ends_with?(stream, "@ticker") ->
        symbol = extract_symbol_from_stream(stream, "@ticker")
        parse_ticker_data(symbol, data)

      String.contains?(stream, "@depth") ->
        {symbol, _depth} = extract_symbol_and_depth_from_stream(stream)
        parse_depth_data(symbol, data)

      String.ends_with?(stream, "@trade") ->
        symbol = extract_symbol_from_stream(stream, "@trade")
        parse_trade_data(symbol, data)

      String.contains?(stream, "@kline") ->
        {symbol, interval} = extract_symbol_and_interval_from_stream(stream)
        parse_kline_data(symbol, interval, data)

      true ->
        {:error, "Unknown stream type: #{stream}"}
    end
  end

  defp extract_symbol_from_stream(stream, suffix) do
    stream
    |> String.replace(suffix, "")
    |> String.upcase()
  end

  defp extract_symbol_and_depth_from_stream(stream) do
    case String.split(stream, "@depth") do
      [symbol_part, depth_part] ->
        symbol = String.upcase(symbol_part)
        depth = String.to_integer(depth_part)
        {symbol, depth}

      _ ->
        # default depth
        {String.upcase(stream), 5}
    end
  end

  defp extract_symbol_and_interval_from_stream(stream) do
    case String.split(stream, "@kline_") do
      [symbol_part, interval_part] ->
        symbol = String.upcase(symbol_part)
        {symbol, interval_part}

      _ ->
        # default to 1m interval if parsing fails
        {String.upcase(stream), "1m"}
    end
  end

  defp parse_ticker_data(symbol, data) do
    case Ticker.parse(data) do
      {:ok, ticker} ->
        parsed = %{
          type: :ticker,
          symbol: symbol,
          data: ticker
        }

        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_depth_data(symbol, data) do
    case OrderBook.parse(data) do
      {:ok, order_book} ->
        parsed = %{
          type: :depth,
          symbol: symbol,
          data: order_book
        }

        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_trade_data(symbol, data) do
    case Trade.parse(data) do
      {:ok, trade} ->
        parsed = %{
          type: :trades,
          symbol: symbol,
          data: trade
        }

        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_kline_data(symbol, interval, data) do
    case Kline.parse(data) do
      {:ok, kline} ->
        parsed = %{
          type: :klines,
          symbol: symbol,
          interval: interval,
          data: kline
        }

        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_kline_message(symbol, kline_data) do
    # Extract interval from the kline data
    interval = kline_data["i"]

    case Kline.parse(kline_data) do
      {:ok, kline} ->
        parsed = %{
          type: :klines,
          symbol: symbol,
          interval: interval,
          data: kline
        }

        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_depth_message(%{"asks" => asks, "bids" => bids, "lastUpdateId" => last_update_id}) do
    # We need to determine the symbol from the current subscriptions context
    # For now, we'll create a generic depth message and let the caller handle it
    order_book_data = %{
      "asks" => asks,
      "bids" => bids,
      "lastUpdateId" => last_update_id
    }

    case OrderBook.parse(order_book_data) do
      {:ok, order_book} ->
        # Note: We might need to track which symbols are subscribed to determine the symbol
        # For now, we'll use a placeholder approach
        parsed = %{
          type: :depth,
          # This needs to be fixed by tracking subscriptions
          symbol: "UNKNOWN",
          data: order_book
        }

        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_trade_message(symbol, trade_data) do
    case Trade.parse(trade_data) do
      {:ok, trade} ->
        parsed = %{
          type: :trades,
          symbol: symbol,
          data: trade
        }

        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_ticker_message(symbol, ticker_data) do
    case Ticker.parse(ticker_data) do
      {:ok, ticker} ->
        parsed = %{
          type: :ticker,
          symbol: symbol,
          data: ticker
        }

        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast_market_data(market_data) do
    topic =
      case market_data.type do
        :klines ->
          build_topic_with_interval(market_data.type, market_data.symbol, market_data.interval)

        _ ->
          build_topic(market_data.type, market_data.symbol)
      end

    Phoenix.PubSub.broadcast(
      CryptoExchange.PubSub,
      topic,
      {:market_data, market_data}
    )
  end

  defp build_topic(stream_type, symbol) do
    "binance:#{stream_type}:#{symbol}"
  end

  defp build_topic_with_interval(stream_type, symbol, interval) do
    "binance:#{stream_type}:#{symbol}:#{interval}"
  end

  defp handle_connection_confirmed(state) do
    # Cancel any pending connection timeout
    if state.reconnect_timer do
      Process.cancel_timer(state.reconnect_timer)
    end

    # Now that connection is confirmed, subscribe to pending streams
    new_state =
      case {state.websocket, state.pending_subscriptions} do
        {websocket, streams} when websocket != nil and length(streams) > 0 ->
          Logger.info("Subscribing to pending streams: #{inspect(streams)}")
          send_subscription_message(websocket, streams, "SUBSCRIBE")

          %{
            state
            | connection_status: :connected,
              pending_subscriptions: [],
              reconnect_timer: nil
          }

        _ ->
          Logger.info("No pending subscriptions, marking as connected")

          %{
            state
            | connection_status: :connected,
              pending_subscriptions: [],
              reconnect_timer: nil
          }
      end

    {:noreply, new_state}
  end
end
