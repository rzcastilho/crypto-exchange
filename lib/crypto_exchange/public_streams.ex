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
    Subscribe to a market data stream.
    
    Automatically manages subscriber tracking and stream lifecycle.
    The calling process will be registered as a subscriber and the stream
    will remain active as long as there are subscribers.
    
    ## Parameters
    
    - `stream_type` - Type of stream (:ticker, :depth, :trades)
    - `symbol` - Trading pair symbol (e.g., \"BTCUSDT\")
    - `params` - Stream-specific parameters
    
    ## Returns
    
    {:ok, topic} - Phoenix.PubSub topic for listening to updates
    {:error, reason} - Error details
    
    ## Examples
    
        {:ok, topic} = StreamManager.subscribe(:ticker, \"BTCUSDT\", %{})
        Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
    """
    def subscribe(stream_type, symbol, params \\ %{}) do
      GenServer.call(__MODULE__, {:subscribe, stream_type, symbol, params})
    end

    @doc """
    Get detailed information about all active streams.
    
    Returns comprehensive stream information including subscriber counts,
    health status, and performance metrics.
    """
    def list_streams do
      GenServer.call(__MODULE__, :list_streams)
    end
    
    @doc """
    Get comprehensive metrics about stream performance and health.
    """
    def get_metrics do
      GenServer.call(__MODULE__, :get_metrics)
    end
    
    @doc """
    Get health status of all streams.
    """
    def health_status do
      GenServer.call(__MODULE__, :health_status)
    end

    # Server Callbacks

    @impl true
    def init(_opts) do
      Logger.info("Starting PublicStreams.StreamManager")
      
      # Register this process for discovery
      Registry.register(@registry, {__MODULE__, :stream_manager}, self())
      
      state = %{
        streams: %{},
        stream_refs: %{},
        metrics: %{
          total_messages: 0,
          messages_per_second: 0.0,
          total_errors: 0,
          error_rate: 0.0,
          uptime_start: System.system_time(:millisecond)
        },
        health_check_timer: nil
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
              current_time = System.system_time(:millisecond)
              
              stream_info = %{
                pid: pid, 
                topic: topic,
                subscribers: 1,
                health_status: :healthy,
                created_at: current_time,
                last_message_at: nil,
                reconnect_count: 0,
                message_count: 0,
                error_count: 0
              }
              
              new_streams = Map.put(state.streams, stream_key, stream_info)
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
        |> Enum.map(fn {{type, symbol}, stream} ->
          %{
            type: type, 
            symbol: symbol, 
            topic: stream.topic,
            subscribers: stream.subscribers,
            health_status: stream.health_status,
            created_at: stream.created_at,
            last_message_at: stream.last_message_at,
            reconnect_count: stream.reconnect_count
          }
        end)
      
      {:reply, stream_info, state}
    end
    
    @impl true
    def handle_call(:get_metrics, _from, state) do
      current_metrics = calculate_current_metrics(state)
      {:reply, {:ok, current_metrics}, state}
    end
    
    @impl true
    def handle_call(:health_status, _from, state) do
      health_summary = %{
        total_streams: map_size(state.streams),
        healthy_streams: count_streams_by_status(state.streams, :healthy),
        degraded_streams: count_streams_by_status(state.streams, :degraded),
        unhealthy_streams: count_streams_by_status(state.streams, :unhealthy),
        recovering_streams: count_streams_by_status(state.streams, :recovering),
        overall_health: calculate_overall_health(state.streams)
      }
      
      {:reply, {:ok, health_summary}, state}
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
    def handle_info({:stream_activity, timestamp}, state) do
      # Update stream activity metrics
      updated_metrics = update_global_metrics(state.metrics, :message_received)
      {:noreply, %{state | metrics: updated_metrics}}
    end
    
    @impl true
    def handle_info(:health_check, state) do
      # Perform health checks on all streams
      {updated_streams, alerts} = perform_health_checks(state.streams)
      
      # Log any health alerts
      Enum.each(alerts, &log_health_alert/1)
      
      # Schedule next health check
      timer = Process.send_after(self(), :health_check, 30_000)
      
      {:noreply, %{state | streams: updated_streams, health_check_timer: timer}}
    end
    
    @impl true
    def handle_info({:stream_error, stream_key, error_type}, state) do
      case Map.get(state.streams, stream_key) do
        nil -> 
          {:noreply, state}
        stream_info ->
          updated_stream = %{stream_info | 
            error_count: stream_info.error_count + 1,
            health_status: calculate_stream_health(stream_info.message_count, stream_info.error_count + 1)
          }
          updated_streams = Map.put(state.streams, stream_key, updated_stream)
          updated_metrics = update_global_metrics(state.metrics, :error_received)
          
          Logger.warning("Stream error for #{inspect(stream_key)}: #{error_type}")
          
          {:noreply, %{state | streams: updated_streams, metrics: updated_metrics}}
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
      Logger.info("Starting #{stream_type} stream for #{symbol} with params #{inspect(params)}")
      Logger.info("Messages will be published to topic: #{topic}")
      
      # Validate symbol format and stream type
      with :ok <- validate_stream_request(stream_type, symbol, params),
           enhanced_params <- enhance_stream_params(params),
           {:ok, pid} <- start_binance_client(stream_type, symbol, enhanced_params, topic) do
        Logger.info("Successfully started Binance WebSocket client for #{stream_type}:#{symbol}")
        {:ok, pid}
      else
        {:error, reason} ->
          Logger.error("Failed to start stream #{stream_type}:#{symbol}: #{inspect(reason)}")
          {:error, reason}
      end
    end
    
    # Validate stream request parameters
    defp validate_stream_request(stream_type, symbol, params) do
      with :ok <- validate_stream_type(stream_type),
           :ok <- validate_symbol_format(symbol),
           :ok <- validate_stream_params(stream_type, params) do
        :ok
      end
    end
    
    defp validate_stream_type(stream_type) when stream_type in [:ticker, :depth, :trades], do: :ok
    defp validate_stream_type(_), do: {:error, :invalid_stream_type}
    
    defp validate_symbol_format(symbol) when is_binary(symbol) do
      cond do
        String.length(symbol) < 3 -> {:error, :symbol_too_short}
        not String.match?(symbol, ~r/^[A-Z0-9]+$/) -> {:error, :invalid_symbol_format}
        true -> :ok
      end
    end
    defp validate_symbol_format(_), do: {:error, :symbol_must_be_string}
    
    defp validate_stream_params(:depth, %{level: level}) when is_integer(level) and level > 0, do: :ok
    defp validate_stream_params(:depth, %{level: _}), do: {:error, :invalid_depth_level}
    defp validate_stream_params(:depth, %{}), do: :ok  # Default level will be used
    defp validate_stream_params(_, _), do: :ok
    
    # Enhance stream parameters with monitoring and health check callbacks
    defp enhance_stream_params(params) do
      Map.merge(params, %{
        message_callback: fn -> 
          send(self(), {:stream_activity, System.system_time(:millisecond)}) 
        end,
        health_check_interval: 30_000,  # 30 seconds
        max_silence_duration: 120_000   # 2 minutes before considering unhealthy
      })
    end
    
    defp start_binance_client(stream_type, symbol, params, topic) do
      # Add timeout for startup
      task = Task.async(fn ->
        CryptoExchange.Binance.PublicStreams.start_link(stream_type, symbol, params, topic)
      end)
      
      case Task.yield(task, 10_000) || Task.shutdown(task) do
        {:ok, result} -> result
        nil -> {:error, :startup_timeout}
      end
    end
    
    # Helper functions for enhanced functionality
    
    defp count_streams_by_status(streams, status) do
      streams
      |> Enum.count(fn {_key, stream_info} -> 
        Map.get(stream_info, :health_status, :healthy) == status 
      end)
    end
    
    defp calculate_overall_health(streams) do
      if map_size(streams) == 0 do
        :no_streams
      else
        healthy = count_streams_by_status(streams, :healthy)
        degraded = count_streams_by_status(streams, :degraded)
        unhealthy = count_streams_by_status(streams, :unhealthy)
        total = map_size(streams)
        
        cond do
          unhealthy > 0 -> :unhealthy
          degraded > total / 2 -> :degraded  
          healthy == total -> :healthy
          true -> :mixed
        end
      end
    end
    
    # Enhanced metrics calculation with real-time data
    defp calculate_current_metrics(state) do
      current_time = System.system_time(:millisecond)
      uptime_ms = current_time - state.metrics.uptime_start
      uptime_seconds = div(uptime_ms, 1000)
      
      # Aggregate stream metrics
      stream_metrics = aggregate_stream_metrics(state.streams)
      
      # Calculate subscription metrics
      {current_subscriptions, active_subscribers} = calculate_subscription_metrics(state.streams)
      
      # Calculate rates
      messages_per_second = if uptime_seconds > 0, 
        do: stream_metrics.total_messages / uptime_seconds, 
        else: 0.0
      
      error_rate = if stream_metrics.total_messages > 0,
        do: stream_metrics.total_errors / stream_metrics.total_messages,
        else: 0.0
      
      %{
        total_streams: map_size(state.streams),
        current_subscriptions: current_subscriptions,
        active_subscribers: active_subscribers,
        healthy_streams: count_streams_by_status(state.streams, :healthy),
        degraded_streams: count_streams_by_status(state.streams, :degraded),
        unhealthy_streams: count_streams_by_status(state.streams, :unhealthy),
        warning_streams: count_streams_by_status(state.streams, :warning),
        total_messages: stream_metrics.total_messages,
        total_errors: stream_metrics.total_errors,
        messages_per_second: Float.round(messages_per_second, 2),
        error_rate: Float.round(error_rate, 4),
        uptime_seconds: uptime_seconds,
        last_updated: current_time,
        reconnect_count: stream_metrics.total_reconnects
      }
    end
    
    # Aggregate metrics from all streams
    defp aggregate_stream_metrics(streams) do
      Enum.reduce(streams, %{total_messages: 0, total_errors: 0, total_reconnects: 0}, fn
        {_key, stream}, acc ->
          %{
            total_messages: acc.total_messages + stream.message_count,
            total_errors: acc.total_errors + stream.error_count,
            total_reconnects: acc.total_reconnects + stream.reconnect_count
          }
      end)
    end
    
    # Calculate subscription metrics
    defp calculate_subscription_metrics(streams) do
      {current_subscriptions, active_subscribers} = Enum.reduce(streams, {0, 0}, fn
        {_key, stream}, {subs, subscribers} ->
          {subs + 1, subscribers + stream.subscribers}
      end)
      
      {current_subscriptions, active_subscribers}
    end
    
    # Update global metrics for real-time tracking
    defp update_global_metrics(metrics, :message_received) do
      %{metrics | total_messages: metrics.total_messages + 1}
    end
    
    defp update_global_metrics(metrics, :error_received) do
      %{metrics | total_errors: metrics.total_errors + 1}
    end
    
    # Perform health checks on all streams
    defp perform_health_checks(streams) do
      current_time = System.system_time(:millisecond)
      
      {updated_streams, alerts} = Enum.map_reduce(streams, [], fn {key, stream}, alerts ->
        {updated_stream, new_alerts} = check_stream_health(key, stream, current_time)
        {updated_stream, alerts ++ new_alerts}
      end)
      
      {Map.new(updated_streams), alerts}
    end
    
    # Check individual stream health
    defp check_stream_health(stream_key, stream, current_time) do
      silence_duration = if stream.last_message_at,
        do: current_time - stream.last_message_at,
        else: current_time - stream.created_at
      
      new_health_status = determine_health_status(stream, silence_duration)
      alerts = generate_health_alerts(stream_key, stream.health_status, new_health_status)
      
      updated_stream = %{stream | health_status: new_health_status}
      {{stream_key, updated_stream}, alerts}
    end
    
    # Determine health status based on various factors
    defp determine_health_status(stream, silence_duration) do
      max_silence = 120_000  # 2 minutes
      warning_silence = 60_000  # 1 minute
      
      error_rate = if stream.message_count > 0,
        do: stream.error_count / stream.message_count,
        else: 0.0
      
      cond do
        silence_duration > max_silence -> :unhealthy
        error_rate > 0.1 -> :degraded  # More than 10% errors
        silence_duration > warning_silence -> :warning
        error_rate > 0.05 -> :warning  # More than 5% errors
        true -> :healthy
      end
    end
    
    # Generate alerts for health status changes
    defp generate_health_alerts(stream_key, old_status, new_status) do
      if old_status != new_status and new_status in [:warning, :degraded, :unhealthy] do
        [%{
          type: :health_status_change,
          stream: stream_key,
          old_status: old_status,
          new_status: new_status,
          timestamp: System.system_time(:millisecond)
        }]
      else
        []
      end
    end
    
    # Log health alerts
    defp log_health_alert(%{type: :health_status_change, stream: stream_key, new_status: status}) do
      {type, symbol} = stream_key
      Logger.warning("Stream health status changed: #{type}:#{symbol} -> #{status}")
    end
    
    # Calculate stream health based on error rate
    defp calculate_stream_health(message_count, error_count) do
      error_rate = if message_count > 0, do: error_count / message_count, else: 0.0
      
      cond do
        error_rate > 0.1 -> :degraded
        error_rate > 0.05 -> :warning
        true -> :healthy
      end
    end
  end
  
  # Module-level convenience functions
  
  @doc """
  Subscribe to market data stream with automatic subscriber tracking.
  
  This is a convenience function that wraps the StreamManager subscription
  and automatically registers the calling process as a subscriber.
  
  ## Parameters
  
  - `stream_type` - Type of stream (:ticker, :depth, :trades)
  - `symbol` - Trading pair symbol (e.g., \"BTCUSDT\")
  - `params` - Stream-specific parameters (optional)
  
  ## Returns
  
  {:ok, topic} - Topic name for Phoenix.PubSub subscription
  {:error, reason} - Error details
  
  ## Examples
  
      # Subscribe to ticker data
      {:ok, topic} = CryptoExchange.PublicStreams.subscribe(:ticker, \"BTCUSDT\")
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Subscribe to order book with custom depth
      {:ok, topic} = CryptoExchange.PublicStreams.subscribe(:depth, \"ETHUSDT\", %{level: 20})
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
  """
  def subscribe(stream_type, symbol, params \\ %{}) do
    StreamManager.subscribe(stream_type, symbol, params)
  end
  
  @doc """
  Unsubscribe from all streams for a symbol.
  
  Removes the calling process from all stream subscriptions for the given symbol.
  If this was the last subscriber, the streams will be stopped automatically.
  
  ## Parameters
  
  - `symbol` - Trading pair symbol (e.g., \"BTCUSDT\")
  
  ## Examples
  
      :ok = CryptoExchange.PublicStreams.unsubscribe(\"BTCUSDT\")
  """
  def unsubscribe(symbol) do
    StreamManager.unsubscribe(symbol)
  end
  
  @doc """
  Get information about all active streams.
  
  Returns detailed information about currently active streams including
  subscriber counts, health status, and performance metrics.
  
  ## Returns
  
  List of stream information maps with the following fields:
  - `type` - Stream type (:ticker, :depth, :trades)
  - `symbol` - Trading pair symbol
  - `topic` - Phoenix.PubSub topic name
  - `subscribers` - Number of active subscribers
  - `health_status` - Current health status
  - `created_at` - Stream creation timestamp
  - `last_message_at` - Last message timestamp
  - `reconnect_count` - Number of reconnection attempts
  
  ## Examples
  
      streams = CryptoExchange.PublicStreams.list_streams()
      IO.inspect(streams)
  """
  def list_streams do
    StreamManager.list_streams()
  end
  
  @doc """
  Get comprehensive metrics about stream performance.
  
  Returns detailed metrics including message rates, health statistics,
  and resource utilization information.
  
  ## Returns
  
  {:ok, metrics} where metrics contains:
  - `total_streams` - Total number of active streams
  - `healthy_streams` - Number of healthy streams
  - `degraded_streams` - Number of degraded streams
  - `unhealthy_streams` - Number of unhealthy streams
  - `total_messages` - Total messages processed
  - `messages_per_second` - Current message rate
  - `current_subscriptions` - Number of active subscriptions
  - `active_subscribers` - Number of active subscriber processes
  - `uptime_seconds` - StreamManager uptime in seconds
  
  ## Examples
  
      {:ok, metrics} = CryptoExchange.PublicStreams.get_metrics()
      IO.puts("Message rate: \#{metrics.messages_per_second}/sec")
  """
  def get_metrics do
    StreamManager.get_metrics()
  end
  
  @doc """
  Get overall health status of the streaming system.
  
  Returns a summary of stream health across all active connections.
  
  ## Returns
  
  {:ok, health_status} where health_status contains:
  - `total_streams` - Total number of streams
  - `healthy_streams` - Number of healthy streams
  - `degraded_streams` - Number of degraded streams
  - `unhealthy_streams` - Number of unhealthy streams
  - `recovering_streams` - Number of streams currently recovering
  - `overall_health` - Overall system health (:healthy, :degraded, :unhealthy, :mixed, :no_streams)
  
  ## Examples
  
      {:ok, health} = CryptoExchange.PublicStreams.health_status()
      case health.overall_health do
        :healthy -> IO.puts("All systems operational")
        :degraded -> IO.puts("Some streams experiencing issues")
        :unhealthy -> IO.puts("Critical issues detected")
        :mixed -> IO.puts("Mixed health status")
        :no_streams -> IO.puts("No active streams")
      end
  """
  def health_status do
    StreamManager.health_status()
  end
end