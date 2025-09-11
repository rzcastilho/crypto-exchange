defmodule CryptoExchange.PublicStreams do
  @moduledoc """
  Public market data streaming functionality.

  This module handles real-time market data streaming from cryptocurrency exchanges
  without requiring authentication. Data is distributed via Phoenix.PubSub to
  interested subscribers.

  ## Supported Stream Types

  - **Ticker**: Real-time price, volume, and change data
  - **Depth**: Order book data with configurable depth levels
  - **Trades**: Individual trade execution data

  ## Message Format

  All public stream messages follow the format:

      {:market_data, %{
        type: :ticker | :depth | :trades,
        symbol: "BTCUSDT",
        data: %{...}
      }}

  ## PubSub Topics

  - Ticker: `binance:ticker:BTCUSDT`
  - Order Book: `binance:depth:BTCUSDT`
  - Trades: `binance:trades:BTCUSDT`
  """

  defmodule StreamManager do
    @moduledoc """
    GenServer that manages public market data stream subscriptions.

    This process coordinates WebSocket connections to cryptocurrency exchange
    public streams and distributes data via Phoenix.PubSub. It maintains
    the mapping between subscribed symbols and their active streams.

    ## State Structure

    The GenServer maintains a map of active streams:

        %{
          {"ticker", "BTCUSDT"} => %{pid: pid, topic: "binance:ticker:BTCUSDT"},
          {"depth", "ETHUSDT"} => %{pid: pid, topic: "binance:depth:ETHUSDT"}
        }

    ## Restart Strategy

    Uses `:permanent` restart strategy as this is a core service that should
    always be available for public data streaming.
    """

    use GenServer
    require Logger

    @registry CryptoExchange.Registry

    # Client API

    @doc """
    Starts the StreamManager GenServer.
    """
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @doc """
    Subscribe to ticker data for a symbol.
    Returns the Phoenix.PubSub topic name for listening to updates.
    """
    def subscribe_to_ticker(symbol) do
      GenServer.call(__MODULE__, {:subscribe, :ticker, symbol, %{}})
    end

    @doc """
    Subscribe to order book depth data for a symbol.
    Level parameter controls the depth (default: 5).
    Returns the Phoenix.PubSub topic name for listening to updates.
    """
    def subscribe_to_depth(symbol, level \\ 5) do
      GenServer.call(__MODULE__, {:subscribe, :depth, symbol, %{level: level}})
    end

    @doc """
    Subscribe to trade data for a symbol.
    Returns the Phoenix.PubSub topic name for listening to updates.
    """
    def subscribe_to_trades(symbol) do
      GenServer.call(__MODULE__, {:subscribe, :trades, symbol, %{}})
    end

    @doc """
    Unsubscribe from all streams for a symbol.
    """
    def unsubscribe(symbol) do
      GenServer.call(__MODULE__, {:unsubscribe, symbol})
    end

    @doc """
    Get current active streams status.
    """
    def list_streams do
      GenServer.call(__MODULE__, :list_streams)
    end

    # Server Callbacks

    @impl true
    def init(_opts) do
      Logger.info("Starting PublicStreams.StreamManager")
      
      # Register this process for discovery
      Registry.register(@registry, {__MODULE__, :stream_manager}, self())
      
      state = %{
        streams: %{},
        stream_refs: %{}
      }
      
      {:ok, state}
    end

    @impl true
    def handle_call({:subscribe, stream_type, symbol, params}, _from, state) do
      stream_key = {stream_type, symbol}
      topic = build_topic(stream_type, symbol)
      
      case Map.get(state.streams, stream_key) do
        nil ->
          # New subscription - start the stream
          case start_stream(stream_type, symbol, params, topic) do
            {:ok, pid} ->
              ref = Process.monitor(pid)
              new_streams = Map.put(state.streams, stream_key, %{pid: pid, topic: topic})
              new_refs = Map.put(state.stream_refs, ref, stream_key)
              
              Logger.info("Started new stream: #{inspect(stream_key)}")
              {:reply, {:ok, topic}, %{state | streams: new_streams, stream_refs: new_refs}}
              
            {:error, reason} ->
              Logger.error("Failed to start stream #{inspect(stream_key)}: #{inspect(reason)}")
              {:reply, {:error, reason}, state}
          end
          
        %{topic: existing_topic} ->
          # Stream already exists, return existing topic
          {:reply, {:ok, existing_topic}, state}
      end
    end

    @impl true
    def handle_call({:unsubscribe, symbol}, _from, state) do
      # Find all streams for this symbol
      streams_to_remove = 
        state.streams
        |> Enum.filter(fn {{_type, stream_symbol}, _info} -> stream_symbol == symbol end)
        |> Enum.map(fn {key, _info} -> key end)
      
      # Stop the streams and clean up state
      {updated_streams, updated_refs} = 
        Enum.reduce(streams_to_remove, {state.streams, state.stream_refs}, fn key, {streams, refs} ->
          case Map.get(streams, key) do
            %{pid: pid} ->
              # Stop the stream process gracefully
              GenServer.stop(pid, :normal)
              
              # Remove from streams map
              new_streams = Map.delete(streams, key)
              
              # Find and remove the monitor ref
              ref_to_remove = 
                Enum.find_value(refs, fn {ref, stream_key} ->
                  if stream_key == key, do: ref
                end)
              
              new_refs = if ref_to_remove, do: Map.delete(refs, ref_to_remove), else: refs
              
              {new_streams, new_refs}
              
            nil ->
              {streams, refs}
          end
        end)
      
      Logger.info("Unsubscribed from streams for symbol: #{symbol}")
      {:reply, :ok, %{state | streams: updated_streams, stream_refs: updated_refs}}
    end

    @impl true
    def handle_call(:list_streams, _from, state) do
      stream_info = 
        state.streams
        |> Enum.map(fn {{type, symbol}, %{topic: topic}} ->
          %{type: type, symbol: symbol, topic: topic}
        end)
      
      {:reply, stream_info, state}
    end

    @impl true
    def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
      case Map.get(state.stream_refs, ref) do
        nil ->
          # Unknown process died
          {:noreply, state}
          
        stream_key ->
          Logger.warning("Stream process died: #{inspect(stream_key)}, reason: #{inspect(reason)}")
          
          # Clean up state
          new_streams = Map.delete(state.streams, stream_key)
          new_refs = Map.delete(state.stream_refs, ref)
          
          # For now, we don't restart automatically. This could be enhanced
          # to implement automatic restart with exponential backoff
          
          {:noreply, %{state | streams: new_streams, stream_refs: new_refs}}
      end
    end

    @impl true
    def handle_info(msg, state) do
      Logger.debug("Unexpected message in StreamManager: #{inspect(msg)}")
      {:noreply, state}
    end

    # Private Functions

    defp build_topic(stream_type, symbol) do
      "binance:#{stream_type}:#{symbol}"
    end

    defp start_stream(stream_type, symbol, params, topic) do
      # For now, we'll return a mock implementation
      # In a real implementation, this would start the appropriate
      # Binance WebSocket connection process
      
      Logger.info("Starting #{stream_type} stream for #{symbol} with params #{inspect(params)}")
      Logger.info("Messages will be published to topic: #{topic}")
      
      # Mock implementation - in real scenario this would start the WebSocket process
      # Add basic error simulation for invalid symbols
      if String.length(symbol) < 3 do
        {:error, :invalid_symbol}
      else
        pid = spawn_link(fn -> mock_stream_process(topic) end)
        {:ok, pid}
      end
    end

    defp mock_stream_process(topic) do
      # Mock process that simulates receiving data
      # In real implementation, this would be the WebSocket client process
      receive do
        :stop -> :ok
      after
        60_000 -> mock_stream_process(topic)
      end
    end
  end
end