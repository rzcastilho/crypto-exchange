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
    topic = build_topic(stream_type, symbol)

    # In future phases, this will:
    # 1. Check if we already have a connection for this symbol/stream
    # 2. Establish WebSocket connection if needed
    # 3. Send subscription message to exchange
    # 4. Track the subscription in state

    # For now, just track the subscription and return the topic
    subscription_key = {stream_type, symbol}

    updated_subscriptions =
      Map.put(state.subscriptions, subscription_key, %{
        topic: topic,
        params: params,
        subscribers: 1
      })

    new_state = %{state | subscriptions: updated_subscriptions}

    {:reply, {:ok, topic}, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, symbol}, _from, state) do
    Logger.debug("Unsubscribe request for #{symbol}")

    # In future phases, this will:
    # 1. Find all active subscriptions for the symbol
    # 2. Decrement subscriber count or remove subscription
    # 3. Close WebSocket connection if no more subscribers
    # 4. Update state accordingly

    # For now, just remove all subscriptions for this symbol
    updated_subscriptions =
      state.subscriptions
      |> Enum.reject(fn {{_stream_type, sub_symbol}, _data} -> sub_symbol == symbol end)
      |> Map.new()

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

  defp build_topic(stream_type, symbol) do
    "binance:#{stream_type}:#{String.upcase(symbol)}"
  end
end
