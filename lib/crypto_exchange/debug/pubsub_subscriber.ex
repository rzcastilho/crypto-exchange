defmodule CryptoExchange.Debug.PubSubSubscriber do
  @moduledoc """
  Test subscriber for debugging PubSub message flow.

  This module provides a simple GenServer that subscribes to PubSub topics
  and logs all received messages with detailed information including timestamps.

  ## Usage

  ```elixir
  # Start the subscriber
  {:ok, pid} = CryptoExchange.Debug.PubSubSubscriber.start_link()

  # Subscribe to a specific topic
  CryptoExchange.Debug.PubSubSubscriber.subscribe("binance:ticker:BTCUSDT")

  # Subscribe to all topics matching a pattern (using wildcard)
  CryptoExchange.Debug.PubSubSubscriber.subscribe_pattern("binance:ticker:*")

  # Check received message count
  count = CryptoExchange.Debug.PubSubSubscriber.message_count()

  # Get last N messages
  messages = CryptoExchange.Debug.PubSubSubscriber.get_messages(10)

  # Clear message history
  CryptoExchange.Debug.PubSubSubscriber.clear_messages()
  ```
  """

  use GenServer
  require Logger

  @max_stored_messages 100

  defmodule State do
    @moduledoc false
    defstruct subscribed_topics: [],
              messages: [],
              message_count: 0,
              start_time: nil
  end

  ## Client API

  @doc """
  Starts the PubSub subscriber GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put(opts, :name, __MODULE__))
  end

  @doc """
  Subscribes to a specific PubSub topic.

  ## Parameters
  - `topic` - PubSub topic to subscribe to (e.g., "binance:ticker:BTCUSDT")

  ## Examples
      CryptoExchange.Debug.PubSubSubscriber.subscribe("binance:ticker:BTCUSDT")
  """
  def subscribe(topic) when is_binary(topic) do
    GenServer.call(__MODULE__, {:subscribe, topic})
  end

  @doc """
  Unsubscribes from a specific PubSub topic.

  ## Parameters
  - `topic` - PubSub topic to unsubscribe from

  ## Examples
      CryptoExchange.Debug.PubSubSubscriber.unsubscribe("binance:ticker:BTCUSDT")
  """
  def unsubscribe(topic) when is_binary(topic) do
    GenServer.call(__MODULE__, {:unsubscribe, topic})
  end

  @doc """
  Gets the total count of messages received.

  ## Returns
  Integer count of all messages received since start or last clear.
  """
  def message_count do
    GenServer.call(__MODULE__, :message_count)
  end

  @doc """
  Gets the last N messages received.

  ## Parameters
  - `count` - Number of messages to retrieve (default: 10)

  ## Returns
  List of message tuples with metadata.
  """
  def get_messages(count \\ 10) do
    GenServer.call(__MODULE__, {:get_messages, count})
  end

  @doc """
  Clears all stored messages and resets the count.
  """
  def clear_messages do
    GenServer.call(__MODULE__, :clear_messages)
  end

  @doc """
  Gets current subscription status.

  ## Returns
  Map with subscribed topics and message statistics.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("PubSub Debug Subscriber started")

    state = %State{
      subscribed_topics: [],
      messages: [],
      message_count: 0,
      start_time: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, topic}, _from, state) do
    Logger.info("[PUBSUB DEBUG] Subscribing to topic: #{topic}")

    case Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic) do
      :ok ->
        new_topics = [topic | state.subscribed_topics] |> Enum.uniq()
        {:reply, :ok, %{state | subscribed_topics: new_topics}}

      {:error, reason} = error ->
        Logger.error("[PUBSUB DEBUG] Failed to subscribe to #{topic}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, topic}, _from, state) do
    Logger.info("[PUBSUB DEBUG] Unsubscribing from topic: #{topic}")

    Phoenix.PubSub.unsubscribe(CryptoExchange.PubSub, topic)
    new_topics = Enum.reject(state.subscribed_topics, &(&1 == topic))

    {:reply, :ok, %{state | subscribed_topics: new_topics}}
  end

  @impl true
  def handle_call(:message_count, _from, state) do
    {:reply, state.message_count, state}
  end

  @impl true
  def handle_call({:get_messages, count}, _from, state) do
    messages = Enum.take(state.messages, count)
    {:reply, messages, state}
  end

  @impl true
  def handle_call(:clear_messages, _from, state) do
    Logger.info("[PUBSUB DEBUG] Clearing message history")
    {:reply, :ok, %{state | messages: [], message_count: 0}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    uptime =
      if state.start_time do
        DateTime.diff(DateTime.utc_now(), state.start_time, :second)
      else
        0
      end

    status = %{
      subscribed_topics: state.subscribed_topics,
      total_messages: state.message_count,
      stored_messages: length(state.messages),
      uptime_seconds: uptime
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info({:market_data, market_data} = message, state) do
    received_at = DateTime.utc_now()

    Logger.info("""
    [PUBSUB DEBUG - MESSAGE RECEIVED]
    Timestamp: #{DateTime.to_iso8601(received_at)}
    Type: #{market_data.type}
    Symbol: #{market_data.symbol}
    Data: #{inspect(market_data.data, pretty: true, limit: :infinity)}
    Full Message: #{inspect(message, pretty: true, limit: :infinity)}
    """)

    # Store message with metadata
    message_record = %{
      received_at: received_at,
      type: market_data.type,
      symbol: market_data.symbol,
      data: market_data.data,
      full_message: message
    }

    # Keep only last N messages
    new_messages = [message_record | state.messages] |> Enum.take(@max_stored_messages)

    new_state = %{
      state
      | messages: new_messages,
        message_count: state.message_count + 1
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("[PUBSUB DEBUG] Received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("[PUBSUB DEBUG] Subscriber terminating: #{inspect(reason)}")
    :ok
  end
end
