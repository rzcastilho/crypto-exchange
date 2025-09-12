defmodule CryptoExchange.PublicStreams.StreamManager do
  @moduledoc """
  GenServer responsible for managing public market data streams from cryptocurrency exchanges.

  This module handles:
  - Subscribing to and unsubscribing from various market data streams (ticker, depth, trades)
  - Managing WebSocket connections to exchanges
  - Broadcasting market data via Phoenix.PubSub
  - Maintaining active stream subscriptions and their state

  The StreamManager follows the OTP GenServer pattern and is supervised by the main
  application supervisor. It uses Phoenix.PubSub to distribute market data to interested
  processes throughout the application.

  ## Topic Structure
  - Ticker: `binance:ticker:SYMBOL`
  - Order Book: `binance:depth:SYMBOL` 
  - Trades: `binance:trades:SYMBOL`

  ## Message Format
  Market data is broadcast as:
  ```elixir
  {:market_data, %{
    type: :ticker | :depth | :trades,
    symbol: "BTCUSDT",
    data: %{...}
  }}
  ```

  ## Usage Examples
  ```elixir
  # Subscribe to ticker updates
  {:ok, topic} = StreamManager.subscribe_to_ticker("BTCUSDT")
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  # Subscribe to order book depth (5 levels)
  {:ok, topic} = StreamManager.subscribe_to_depth("BTCUSDT", 5)
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  # Subscribe to trade updates
  {:ok, topic} = StreamManager.subscribe_to_trades("BTCUSDT")
  Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

  # Listen for market data updates
  receive do
    {:market_data, %{type: :ticker, symbol: "BTCUSDT", data: data}} ->
      IO.puts("BTC Price: \#{data.price}")
    {:market_data, %{type: :depth, symbol: "BTCUSDT", data: data}} ->
      IO.puts("Order Book Updated: \#{inspect(data)}")
    {:market_data, %{type: :trades, symbol: "BTCUSDT", data: data}} ->
      IO.puts("New Trade: \#{data.price} @ \#{data.quantity}")
  end

  # Unsubscribe from all streams for a symbol
  :ok = StreamManager.unsubscribe("BTCUSDT")
  ```

  ## Error Handling
  ```elixir
  # Handle subscription errors
  case StreamManager.subscribe_to_ticker("INVALID") do
    {:ok, topic} -> 
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
    {:error, reason} -> 
      Logger.error("Subscription failed: \#{inspect(reason)}")
  end
  ```
  """

  use GenServer
  require Logger

  @name __MODULE__

  ## Client API

  @doc """
  Starts the StreamManager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put(opts, :name, @name))
  end

  @doc """
  Subscribes to ticker data for a given symbol.
  Returns the Phoenix.PubSub topic for listening to updates.
  """
  def subscribe_to_ticker(symbol) do
    GenServer.call(@name, {:subscribe, :ticker, symbol, %{}})
  end

  @doc """
  Subscribes to order book depth data for a given symbol.
  Returns the Phoenix.PubSub topic for listening to updates.
  """
  def subscribe_to_depth(symbol, level \\ 5) do
    GenServer.call(@name, {:subscribe, :depth, symbol, %{level: level}})
  end

  @doc """
  Subscribes to trade data for a given symbol.
  Returns the Phoenix.PubSub topic for listening to updates.
  """
  def subscribe_to_trades(symbol) do
    GenServer.call(@name, {:subscribe, :trades, symbol, %{}})
  end

  @doc """
  Subscribes to kline (candlestick) data for a given symbol and interval.
  Returns the Phoenix.PubSub topic for listening to updates.

  ## Parameters
  - `symbol` - Trading symbol (e.g., "BTCUSDT")
  - `interval` - Time interval for klines (default: "1m")
    Supported intervals: 1s, 1m, 3m, 5m, 15m, 30m, 1h, 2h, 4h, 6h, 8h, 12h, 1d, 3d, 1w, 1M

  ## Examples
      # Subscribe to 1-minute klines for BTCUSDT
      {:ok, topic} = StreamManager.subscribe_to_klines("BTCUSDT", "1m")
      
      # Subscribe to 5-minute klines for ETHUSDT  
      {:ok, topic} = StreamManager.subscribe_to_klines("ETHUSDT", "5m")
      
      # Subscribe to daily klines for BNBUSDT
      {:ok, topic} = StreamManager.subscribe_to_klines("BNBUSDT", "1d")
  """
  def subscribe_to_klines(symbol, interval \\ "1m") do
    GenServer.call(@name, {:subscribe, :klines, symbol, %{interval: interval}})
  end

  @doc """
  Unsubscribes from all streams for a given symbol.
  """
  def unsubscribe(symbol) do
    GenServer.call(@name, {:unsubscribe, symbol})
  end

  ## Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("StreamManager started")

    # Initialize state with empty subscriptions map
    # In future phases, this will track active WebSocket connections
    # and subscription state
    state = %{
      subscriptions: %{},
      connections: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, stream_type, symbol, params}, _from, state) do
    Logger.debug("Subscribe request: #{stream_type} for #{symbol}")

    # Generate the Phoenix.PubSub topic for this stream
    topic = build_topic(stream_type, symbol, params)

    # Build Binance stream name based on type and symbol
    stream_name = build_binance_stream_name(stream_type, symbol, params)

    # Track the subscription - include params for klines to differentiate intervals
    subscription_key = case stream_type do
      :klines -> {stream_type, symbol, Map.get(params, :interval, "1m")}
      _ -> {stream_type, symbol}
    end

    updated_subscriptions =
      case Map.get(state.subscriptions, subscription_key) do
        nil ->
          # New subscription - subscribe to Binance stream
          case CryptoExchange.Binance.PublicStreams.subscribe(stream_name) do
            :ok ->
              Logger.info("Successfully subscribed to Binance stream: #{stream_name}")

              Map.put(state.subscriptions, subscription_key, %{
                topic: topic,
                params: params,
                subscribers: 1,
                stream_name: stream_name
              })

            {:error, reason} ->
              Logger.error(
                "Failed to subscribe to Binance stream #{stream_name}: #{inspect(reason)}"
              )

              state.subscriptions
          end

        existing ->
          # Existing subscription - increment subscriber count
          Logger.debug("Incrementing subscriber count for #{stream_name}")

          Map.put(state.subscriptions, subscription_key, %{
            existing
            | subscribers: existing.subscribers + 1
          })
      end

    new_state = %{state | subscriptions: updated_subscriptions}

    case Map.get(updated_subscriptions, subscription_key) do
      nil -> {:reply, {:error, "Failed to subscribe to stream"}, new_state}
      _subscription -> {:reply, {:ok, topic}, new_state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, symbol}, _from, state) do
    Logger.debug("Unsubscribe request for #{symbol}")

    # Find all subscriptions for this symbol and handle unsubscription
    {streams_to_unsubscribe, updated_subscriptions} =
      state.subscriptions
      |> Enum.reduce({[], %{}}, fn {key, data}, {streams, acc} ->
        # Extract symbol from different key patterns
        sub_symbol = case key do
          {_stream_type, symbol_name} -> symbol_name
          {_stream_type, symbol_name, _interval} -> symbol_name
          _ -> nil
        end

        if sub_symbol == symbol do
          # Decrement subscriber count
          new_count = data.subscribers - 1

          if new_count <= 0 do
            # No more subscribers, add to unsubscribe list
            {[data.stream_name | streams], acc}
          else
            # Still have subscribers, keep with decremented count
            {streams, Map.put(acc, key, %{data | subscribers: new_count})}
          end
        else
          # Different symbol, keep as is
          {streams, Map.put(acc, key, data)}
        end
      end)

    # Unsubscribe from Binance streams that have no more subscribers
    if not Enum.empty?(streams_to_unsubscribe) do
      case CryptoExchange.Binance.PublicStreams.unsubscribe(streams_to_unsubscribe) do
        :ok ->
          Logger.info(
            "Successfully unsubscribed from Binance streams: #{inspect(streams_to_unsubscribe)}"
          )

        {:error, reason} ->
          Logger.error("Failed to unsubscribe from Binance streams: #{inspect(reason)}")
      end
    end

    new_state = %{state | subscriptions: updated_subscriptions}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("StreamManager received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("StreamManager terminating: #{inspect(reason)}")
    :ok
  end

  ## Private Functions

  defp build_topic(stream_type, symbol, params \\ %{}) do
    case stream_type do
      :klines ->
        interval = Map.get(params, :interval, "1m")
        "binance:#{stream_type}:#{String.upcase(symbol)}:#{interval}"
      _ ->
        "binance:#{stream_type}:#{String.upcase(symbol)}"
    end
  end

  defp build_binance_stream_name(stream_type, symbol, params) do
    base_symbol = String.downcase(symbol)

    case stream_type do
      :ticker ->
        "#{base_symbol}@ticker"

      :depth ->
        level = Map.get(params, :level, 5)
        "#{base_symbol}@depth#{level}"

      :trades ->
        "#{base_symbol}@trade"

      :klines ->
        interval = Map.get(params, :interval, "1m")
        "#{base_symbol}@kline_#{interval}"
    end
  end
end
