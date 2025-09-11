defmodule CryptoExchange.Binance do
  @moduledoc """
  Binance exchange adapter implementation.

  This module provides the concrete implementation for Binance API integration,
  including both public WebSocket streams and private REST API operations.

  ## Components

  - **PublicStreams**: WebSocket connection to Binance public streams
  - **PrivateClient**: REST API client for authenticated operations
  - **MessageParser**: Parsing of Binance-specific message formats

  ## Configuration

  Default configuration:

      config :crypto_exchange,
        binance_ws_url: "wss://stream.binance.com:9443/ws",
        binance_api_url: "https://api.binance.com"

  ## WebSocket Streams

  Binance provides various stream types via WebSocket:

  - Individual Symbol Ticker: `<symbol>@ticker`
  - Partial Book Depth: `<symbol>@depth<levels>`
  - Trade Streams: `<symbol>@trade`
  - Combined streams: `/stream?streams=btcusdt@ticker/btcusdt@depth5`

  ## REST API

  Private API operations require:

  - API Key in `X-MBX-APIKEY` header
  - HMAC-SHA256 signature in `signature` parameter
  - Timestamp synchronization

  ## Rate Limits

  Binance enforces various rate limits:

  - REST API: 1200 requests per minute
  - WebSocket: 5 messages per second per connection
  - Order placement: 100 orders per 10 seconds
  """

  defmodule PublicStreams do
    @moduledoc """
    Binance WebSocket client for public market data streams.
    
    This module implements a GenServer that manages WebSocket connections to
    Binance public streams and publishes parsed data via Phoenix.PubSub.
    
    ## Supported Stream Types
    
    - **Ticker**: `<symbol>@ticker` - 24hr ticker statistics
    - **Depth**: `<symbol>@depth<levels>` - Partial book depth streams  
    - **Trade**: `<symbol>@trade` - Trade streams
    
    ## WebSocket Connection
    
    Uses the `:websocket_client` library to establish and maintain connections
    to wss://stream.binance.com:9443/ws/. Supports automatic reconnection
    with exponential backoff.
    
    ## Message Format
    
    All messages are parsed into structured data and published as:
    
        {:market_data, %{
          type: :ticker | :depth | :trades,
          symbol: "BTCUSDT", 
          data: %{...}
        }}
    
    ## Configuration
    
    The client respects configuration from CryptoExchange.Config:
    - WebSocket URL and connection parameters
    - Retry and backoff settings
    - Stream-specific configuration
    """
    
    use GenServer
    require Logger
    
    alias CryptoExchange.{Config, Models}
    
    @pubsub CryptoExchange.PubSub
    
    # Connection states
    @state_disconnected :disconnected
    @state_connected :connected
    @state_error :error
    
    defstruct [
      :ws_pid,
      :stream_type, 
      :symbol,
      :params,
      :topic,
      :retry_count,
      :retry_timer,
      :message_callback,
      :created_at,
      :metrics,
      :message_buffer,
      :high_frequency_mode,
      state: @state_disconnected
    ]
    
    @type stream_type :: :ticker | :depth | :trades
    @type state :: %__MODULE__{}
    
    # =============================================================================
    # CLIENT API  
    # =============================================================================
    
    @doc """
    Starts a WebSocket connection for a specific stream.
    
    ## Parameters
    
    - `stream_type` - Type of stream (:ticker, :depth, :trades)
    - `symbol` - Trading pair symbol (e.g., "BTCUSDT")
    - `params` - Stream-specific parameters (e.g., %{level: 5} for depth)
    - `topic` - Phoenix.PubSub topic for publishing data
    
    ## Returns
    
    {:ok, pid} on success, {:error, reason} on failure
    """
    @spec start_link(stream_type(), String.t(), map(), String.t()) :: GenServer.on_start()
    def start_link(stream_type, symbol, params, topic) do
      GenServer.start_link(__MODULE__, {stream_type, symbol, params, topic})
    end
    
    @doc """
    Get the current connection state.
    """
    @spec get_state(pid()) :: state()
    def get_state(pid) do
      GenServer.call(pid, :get_state)
    end
    
    @doc """
    Get performance metrics for this WebSocket client.
    """
    @spec get_metrics(pid()) :: map()
    def get_metrics(pid) do
      GenServer.call(pid, :get_metrics)
    end
    
    @doc """
    Manually trigger a reconnection attempt.
    """
    @spec reconnect(pid()) :: :ok
    def reconnect(pid) do
      GenServer.cast(pid, :reconnect)
    end
    
    @doc """
    Stop the WebSocket connection gracefully.
    """
    @spec stop(pid()) :: :ok 
    def stop(pid) do
      GenServer.stop(pid, :normal)
    end
    
    # =============================================================================
    # GENSERVER CALLBACKS
    # =============================================================================
    
    @impl true
    def init({stream_type, symbol, params, topic}) do
      Logger.info("Starting Binance WebSocket client for #{stream_type}:#{symbol}")
      
      message_callback = Map.get(params, :message_callback)
      current_time = System.system_time(:millisecond)
      
      # Determine if high-frequency mode should be enabled
      high_frequency_mode = Map.get(params, :high_frequency_mode, false)
      
      # Initialize message buffer if high-frequency mode is enabled
      {message_buffer, publisher_fn} = if high_frequency_mode do
        buffer_config = Map.get(params, :buffer_config, %{
          buffer_size: 1000,
          flush_interval: 50,  # 50ms for high-frequency
          batch_size: 100,
          rate_limit: 2000,    # 2000 messages per second
          strategy: :hybrid
        })
        
        publisher = fn messages -> 
          batch_message = {:market_data_batch, %{
            type: stream_type,
            symbol: symbol,
            messages: messages,
            timestamp: System.system_time(:millisecond),
            source: :binance
          }}
          Phoenix.PubSub.broadcast(@pubsub, topic, batch_message)
        end
        
        case CryptoExchange.MessageBuffer.start_link(buffer_config, publisher) do
          {:ok, buffer_pid} -> {buffer_pid, publisher}
          {:error, reason} -> 
            Logger.warning("Failed to start message buffer: #{inspect(reason)}, falling back to direct publishing")
            {nil, nil}
        end
      else
        {nil, nil}
      end
      
      state = %__MODULE__{
        stream_type: stream_type,
        symbol: symbol,
        params: params,
        topic: topic,
        retry_count: 0,
        message_callback: message_callback,
        created_at: current_time,
        message_buffer: message_buffer,
        high_frequency_mode: high_frequency_mode,
        metrics: %{
          messages_received: 0,
          messages_processed: 0,
          parsing_errors: 0,
          broadcast_errors: 0,
          last_message_at: nil,
          created_at: current_time
        }
      }
      
      # Initialize process dictionary for fast metrics access
      Process.put(:message_count, 0)
      Process.put(:error_counts, %{})
      
      # Start connection immediately
      send(self(), :connect)
      
      {:ok, state}
    end
    
    @impl true 
    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
    
    @impl true
    def handle_call(:get_metrics, _from, state) do
      current_metrics = build_current_metrics(state)
      {:reply, current_metrics, state}
    end
    
    @impl true
    def handle_cast(:reconnect, state) do
      Logger.info("Manual reconnection requested")
      handle_info(:connect, %{state | retry_count: 0})
    end
    
    @impl true
    def handle_info(:connect, state) do
      case connect_websocket(state) do
        {:ok, ws_pid} ->
          Logger.info("WebSocket connected successfully") 
          new_state = %{state | 
            ws_pid: ws_pid, 
            state: @state_connected,
            retry_count: 0
          }
          {:noreply, new_state}
          
        {:error, reason} ->
          Logger.error("WebSocket connection failed: #{inspect(reason)}")
          new_state = schedule_reconnect(%{state | state: @state_error})
          {:noreply, new_state}
      end
    end
    
    @impl true
    def handle_info(:retry_connect, state) do
      Logger.info("Retrying WebSocket connection (attempt #{state.retry_count + 1})")
      handle_info(:connect, %{state | retry_count: state.retry_count + 1})
    end
    
    @impl true
    def handle_info({:websocket_message, message}, state) do
      case parse_and_validate_message(message, state) do
        {:ok, parsed_data} ->
          broadcast_message(parsed_data, state)
          update_message_metrics(state)
          {:noreply, state}
          
        {:error, :invalid_json, reason} ->
          Logger.error("JSON parsing failed for #{state.stream_type}:#{state.symbol}: #{inspect(reason)}")
          Logger.debug("Raw message: #{message}")
          increment_error_metric(state, :json_parse_error)
          {:noreply, state}
          
        {:error, :invalid_message_format, reason} ->
          Logger.warning("Invalid message format for #{state.stream_type}:#{state.symbol}: #{inspect(reason)}")
          Logger.debug("Raw message: #{message}")
          increment_error_metric(state, :format_error)
          {:noreply, state}
          
        {:error, :validation_failed, reason} ->
          Logger.warning("Message validation failed for #{state.stream_type}:#{state.symbol}: #{inspect(reason)}")
          increment_error_metric(state, :validation_error)
          {:noreply, state}
          
        {:error, reason} ->
          Logger.error("Unexpected error processing message for #{state.stream_type}:#{state.symbol}: #{inspect(reason)}")
          increment_error_metric(state, :unknown_error)
          {:noreply, state}
      end
    end
    
    @impl true
    def handle_info({:websocket_closed, reason}, state) do
      Logger.warning("WebSocket connection closed: #{inspect(reason)}")
      
      new_state = %{state | 
        ws_pid: nil, 
        state: @state_disconnected
      }
      
      # Schedule reconnection unless this was a normal shutdown
      if reason != :normal do
        new_state = schedule_reconnect(new_state)
        {:noreply, new_state}
      else
        {:noreply, new_state}
      end
    end
    
    @impl true  
    def handle_info({:websocket_error, reason}, state) do
      Logger.error("WebSocket error: #{inspect(reason)}")
      
      new_state = %{state | state: @state_error}
      new_state = schedule_reconnect(new_state)
      
      {:noreply, new_state}
    end
    
    @impl true
    def handle_info(msg, state) do
      Logger.debug("Unexpected message: #{inspect(msg)}")
      {:noreply, state}
    end
    
    @impl true
    def terminate(reason, state) do
      Logger.info("WebSocket client terminating: #{inspect(reason)}")
      
      # Cancel retry timer
      if state.retry_timer, do: Process.cancel_timer(state.retry_timer)
      
      # Stop message buffer if running
      if state.message_buffer do
        Logger.info("Stopping message buffer for #{state.stream_type}:#{state.symbol}")
        GenServer.stop(state.message_buffer, :normal, 5000)
      end
      
      # Stop WebSocket process if running
      if state.ws_pid do
        Process.exit(state.ws_pid, :shutdown)
      end
      
      :ok
    end
    
    # =============================================================================
    # PRIVATE FUNCTIONS
    # =============================================================================
    
    defp connect_websocket(state) do
      ws_url = Config.binance_ws_url()
      stream_name = build_stream_name(state.stream_type, state.symbol, state.params)
      
      # For individual streams, we connect directly to the stream URL
      url = "#{ws_url}/#{stream_name}"
      
      Logger.info("Connecting to WebSocket: #{url}")
      
      case :websocket_client.start_link(url, __MODULE__.WebSocketHandler, self(), websocket_options()) do
        {:ok, ws_pid} ->
          {:ok, ws_pid}
          
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp build_stream_name(:ticker, symbol, _params) do
      "#{String.downcase(symbol)}@ticker"
    end
    
    defp build_stream_name(:depth, symbol, %{level: level}) do
      "#{String.downcase(symbol)}@depth#{level}"
    end
    
    defp build_stream_name(:depth, symbol, _params) do
      "#{String.downcase(symbol)}@depth5"  # Default depth
    end
    
    defp build_stream_name(:trades, symbol, _params) do  
      "#{String.downcase(symbol)}@trade"
    end
    
    defp websocket_options do
      config = Config.websocket_config()
      
      [
        keepalive: config[:ping_interval] || 30_000,
        timeout: config[:connect_timeout] || 10_000
      ]
    end
    
    defp schedule_reconnect(state) do
      if state.retry_timer do
        Process.cancel_timer(state.retry_timer)
      end
      
      retry_config = Config.retry_config()
      delay = calculate_backoff_delay(state.retry_count, retry_config)
      
      Logger.info("Scheduling reconnect in #{delay}ms")
      timer = Process.send_after(self(), :retry_connect, delay)
      
      %{state | retry_timer: timer}
    end
    
    defp calculate_backoff_delay(retry_count, config) do
      initial_delay = config[:initial_delay] || 1_000
      max_delay = config[:max_delay] || 30_000
      backoff_factor = config[:backoff_factor] || 2.0
      
      delay = trunc(initial_delay * :math.pow(backoff_factor, retry_count))
      capped_delay = min(delay, max_delay)
      
      # Add jitter if enabled
      if config[:jitter] do
        jitter_amount = trunc(capped_delay * 0.1)
        capped_delay + :rand.uniform(jitter_amount) - div(jitter_amount, 2)
      else
        capped_delay
      end
    end
    
    # Enhanced message parsing with comprehensive validation and error handling
    defp parse_and_validate_message(raw_message, state) do
      with {:ok, json_data} <- safe_json_decode(raw_message),
           {:ok, validated_data} <- validate_message_structure(json_data, state),
           {:ok, parsed_data} <- parse_stream_message(validated_data, state),
           {:ok, filtered_data} <- apply_message_filters(parsed_data, state) do
        {:ok, filtered_data}
      else
        {:error, :json_decode, reason} -> {:error, :invalid_json, reason}
        {:error, :invalid_structure, reason} -> {:error, :invalid_message_format, reason}
        {:error, :validation_failed, reason} -> {:error, :validation_failed, reason}
        {:error, :filtered_out, reason} -> {:error, :validation_failed, reason}
        {:error, reason} -> {:error, reason}
      end
    end
    
    # Enhanced broadcasting with error recovery and reliability
    defp broadcast_message(parsed_data, state) do
      message = {:market_data, %{
        type: state.stream_type,
        symbol: state.symbol,
        data: parsed_data,
        timestamp: System.system_time(:millisecond),
        source: :binance
      }}
      
      case use_message_buffer(message, state) do
        :ok ->
          Logger.debug("Successfully processed #{state.stream_type} data for #{state.symbol}")
          notify_message_callback(state)
          
        {:error, :buffer_full} ->
          Logger.warning("Message buffer full for #{state.stream_type}:#{state.symbol}, falling back to direct broadcast")
          fallback_broadcast(message, state)
          
        {:error, reason} ->
          Logger.error("Message processing failed for #{state.stream_type}:#{state.symbol}: #{inspect(reason)}")
          fallback_broadcast(message, state)
      end
    end
    
    # Use message buffer if available, otherwise direct broadcast
    defp use_message_buffer(message, %{high_frequency_mode: true, message_buffer: buffer_pid} = state) 
        when not is_nil(buffer_pid) do
      case CryptoExchange.MessageBuffer.add_message(buffer_pid, message) do
        :ok -> :ok
        {:error, _} = error -> error
      end
    end
    
    defp use_message_buffer(message, state) do
      safe_broadcast(message, state)
    end
    
    # Fallback to direct broadcast when buffer is unavailable
    defp fallback_broadcast(message, state) do
      case safe_broadcast(message, state) do
        :ok ->
          notify_message_callback(state)
          
        {:error, reason} ->
          Logger.error("Fallback broadcasting failed: #{inspect(reason)}")
      end
    end
    
    # Safe JSON decoding with detailed error information
    defp safe_json_decode(raw_message) when is_binary(raw_message) do
      case Jason.decode(raw_message) do
        {:ok, data} when is_map(data) -> {:ok, data}
        {:ok, _invalid_data} -> {:error, :json_decode, "Expected JSON object, got other type"}
        {:error, %Jason.DecodeError{data: data, position: pos}} -> 
          {:error, :json_decode, "Invalid JSON at position #{pos}: #{String.slice(data, max(0, pos-10), 20)}"}
        {:error, reason} -> 
          {:error, :json_decode, "JSON decode error: #{inspect(reason)}"}
      end
    end
    
    defp safe_json_decode(_), do: {:error, :json_decode, "Message is not a binary string"}
    
    # Comprehensive message structure validation
    defp validate_message_structure(data, %{stream_type: :ticker}) when is_map(data) do
      required_fields = ["s", "c", "P", "v"]
      case validate_required_fields(data, required_fields) do
        :ok -> {:ok, data}
        {:error, missing_fields} -> 
          {:error, :invalid_structure, "Missing required ticker fields: #{Enum.join(missing_fields, ", ")}"}
      end
    end
    
    defp validate_message_structure(data, %{stream_type: :depth}) when is_map(data) do
      required_fields = ["s", "b", "a"]
      with :ok <- validate_required_fields(data, required_fields),
           {:ok, _} <- validate_price_levels(data["b"], "bids"),
           {:ok, _} <- validate_price_levels(data["a"], "asks") do
        {:ok, data}
      else
        {:error, missing_fields} when is_list(missing_fields) -> 
          {:error, :invalid_structure, "Missing required depth fields: #{Enum.join(missing_fields, ", ")}"}
        {:error, reason} -> 
          {:error, :invalid_structure, reason}
      end
    end
    
    defp validate_message_structure(data, %{stream_type: :trades}) when is_map(data) do
      required_fields = ["s", "p", "q", "m"]
      case validate_required_fields(data, required_fields) do
        :ok -> {:ok, data}
        {:error, missing_fields} -> 
          {:error, :invalid_structure, "Missing required trade fields: #{Enum.join(missing_fields, ", ")}"}
      end
    end
    
    defp validate_message_structure(_, state) do
      {:error, :invalid_structure, "Unknown stream type or invalid data structure for #{state.stream_type}"}
    end
    
    # Validate required fields are present and non-empty
    defp validate_required_fields(data, required_fields) do
      missing_fields = Enum.filter(required_fields, fn field ->
        not Map.has_key?(data, field) or is_nil(data[field]) or data[field] == ""
      end)
      
      if Enum.empty?(missing_fields) do
        :ok
      else
        {:error, missing_fields}
      end
    end
    
    # Validate price levels structure for depth data
    defp validate_price_levels(levels, level_type) when is_list(levels) do
      case Enum.all?(levels, &valid_price_level?/1) do
        true -> {:ok, levels}
        false -> {:error, "Invalid #{level_type} price level format"}
      end
    end
    
    defp validate_price_levels(_, level_type) do
      {:error, "#{level_type} must be a list"}
    end
    
    defp valid_price_level?([price, quantity]) when is_binary(price) and is_binary(quantity) do
      case {Float.parse(price), Float.parse(quantity)} do
        {{price_val, ""}, {qty_val, ""}} when price_val > 0 and qty_val >= 0 -> true
        _ -> false
      end
    end
    
    defp valid_price_level?(_), do: false
    
    # Apply message filtering based on configurable rules
    defp apply_message_filters(parsed_data, state) do
      filters = get_message_filters(state)
      
      case apply_filters(parsed_data, filters, state) do
        :ok -> {:ok, parsed_data}
        {:error, reason} -> {:error, :filtered_out, reason}
      end
    end
    
    defp get_message_filters(%{params: params}) do
      Map.get(params, :filters, [])
    end
    
    defp apply_filters(data, [], _state), do: :ok
    
    defp apply_filters(data, [filter | rest], state) do
      case apply_single_filter(data, filter, state) do
        :ok -> apply_filters(data, rest, state)
        {:error, _} = error -> error
      end
    end
    
    defp apply_single_filter(data, {:min_price, min_price}, %{stream_type: :ticker}) do
      if Map.get(data, :price, 0) >= min_price do
        :ok
      else
        {:error, "Price below minimum threshold"}
      end
    end
    
    defp apply_single_filter(data, {:min_volume, min_volume}, %{stream_type: :ticker}) do
      if Map.get(data, :volume, 0) >= min_volume do
        :ok
      else
        {:error, "Volume below minimum threshold"}
      end
    end
    
    defp apply_single_filter(_data, _filter, _state), do: :ok
    
    # Safe broadcasting with error handling
    defp safe_broadcast(message, state) do
      try do
        Phoenix.PubSub.broadcast(@pubsub, state.topic, message)
        :ok
      rescue
        error ->
          {:error, "PubSub broadcast failed: #{Exception.message(error)}"}
      catch
        :exit, reason ->
          {:error, "PubSub process exited: #{inspect(reason)}"}
        error ->
          {:error, "Unexpected broadcast error: #{inspect(error)}"}
      end
    end
    
    # Safe callback notification with error handling
    defp notify_message_callback(state) do
      if state.message_callback do
        try do
          state.message_callback.()
        rescue
          error ->
            Logger.debug("Message callback failed: #{inspect(error)}")
        catch
          :exit, reason ->
            Logger.debug("Message callback exited: #{inspect(reason)}")
        end
      end
    end
    
    # Update message processing metrics
    defp update_message_metrics(_state) do
      # Increment message counters
      current_count = Process.get(:message_count, 0)
      Process.put(:message_count, current_count + 1)
      Process.put(:last_message_time, System.system_time(:millisecond))
    end
    
    # Increment error metrics for monitoring
    defp increment_error_metric(_state, error_type) do
      error_counts = Process.get(:error_counts, %{})
      current_count = Map.get(error_counts, error_type, 0)
      updated_counts = Map.put(error_counts, error_type, current_count + 1)
      Process.put(:error_counts, updated_counts)
      Process.put(:last_error_time, System.system_time(:millisecond))
    end
    
    # Build comprehensive metrics from current state and process dictionary
    defp build_current_metrics(state) do
      current_time = System.system_time(:millisecond)
      message_count = Process.get(:message_count, 0)
      error_counts = Process.get(:error_counts, %{})
      last_message_time = Process.get(:last_message_time)
      last_error_time = Process.get(:last_error_time)
      
      uptime_ms = current_time - state.created_at
      messages_per_second = if uptime_ms > 0, do: message_count * 1000 / uptime_ms, else: 0.0
      
      # Get buffer stats if available
      buffer_stats = if state.message_buffer do
        case CryptoExchange.MessageBuffer.get_stats(state.message_buffer) do
          stats when is_map(stats) -> stats
          _ -> %{error: "Failed to get buffer stats"}
        end
      else
        %{buffer_enabled: false}
      end
      
      base_metrics = %{
        stream_type: state.stream_type,
        symbol: state.symbol,
        connection_state: state.state,
        created_at: state.created_at,
        uptime_ms: uptime_ms,
        messages_processed: message_count,
        messages_per_second: Float.round(messages_per_second, 2),
        last_message_at: last_message_time,
        last_error_at: last_error_time,
        error_counts: error_counts,
        total_errors: Enum.sum(Map.values(error_counts)),
        retry_count: state.retry_count,
        topic: state.topic,
        health_status: calculate_health_status(state, message_count, error_counts),
        high_frequency_mode: state.high_frequency_mode
      }
      
      Map.put(base_metrics, :buffer_stats, buffer_stats)
    end
    
    # Calculate health status based on error rates and connectivity
    defp calculate_health_status(state, message_count, error_counts) do
      total_errors = Enum.sum(Map.values(error_counts))
      error_rate = if message_count > 0, do: total_errors / message_count, else: 0.0
      
      cond do
        state.state != @state_connected -> :unhealthy
        error_rate > 0.1 -> :degraded  # More than 10% errors
        error_rate > 0.05 -> :warning  # More than 5% errors
        true -> :healthy
      end
    end
    
    # Enhanced stream message parsing with additional validation
    defp parse_stream_message(data, %{stream_type: :ticker}) do
      case Models.Ticker.from_binance_json(data) do
        {:ok, ticker} = result -> 
          Logger.debug("Successfully parsed ticker: #{ticker.symbol} @ #{ticker.price}")
          result
        {:error, _} = error -> 
          Logger.warning("Ticker parsing failed for data: #{inspect(Map.take(data, ["s", "c", "P", "v"]))}")
          error
      end
    end
    
    defp parse_stream_message(data, %{stream_type: :depth}) do
      case Models.OrderBook.from_binance_json(data) do
        {:ok, order_book} = result -> 
          Logger.debug("Successfully parsed order book: #{order_book.symbol} (#{length(order_book.bids)} bids, #{length(order_book.asks)} asks)")
          result
        {:error, _} = error -> 
          Logger.warning("Order book parsing failed for symbol: #{Map.get(data, "s", "unknown")}")
          error
      end
    end
    
    defp parse_stream_message(data, %{stream_type: :trades}) do
      case Models.Trade.from_binance_json(data) do
        {:ok, trade} = result -> 
          Logger.debug("Successfully parsed trade: #{trade.symbol} #{trade.side} #{trade.quantity} @ #{trade.price}")
          result
        {:error, _} = error -> 
          Logger.warning("Trade parsing failed for data: #{inspect(Map.take(data, ["s", "p", "q", "m"]))}")
          error
      end
    end
    
    # =============================================================================
    # WEBSOCKET HANDLER MODULE
    # =============================================================================
    
    defmodule WebSocketHandler do
      @moduledoc false
      @behaviour :websocket_client
      
      def init(parent_pid) do
        {:ok, %{parent: parent_pid}}
      end
      
      def onconnect(_req, state) do
        {:ok, state}
      end
      
      def ondisconnect(_reason, state) do
        {:ok, state}
      end
      
      def websocket_handle({:text, message}, _conn_state, %{parent: parent} = state) do
        send(parent, {:websocket_message, message})
        {:ok, state}
      end
      
      def websocket_handle({:ping, _data}, _conn_state, state) do
        # Automatically respond to pings
        {:reply, {:pong, <<>>}, state}
      end
      
      def websocket_handle({:pong, _data}, _conn_state, state) do
        # Ignore pongs
        {:ok, state}
      end
      
      def websocket_handle(frame, _conn_state, state) do
        Logger.debug("Unhandled WebSocket frame: #{inspect(frame)}")
        {:ok, state}
      end
      
      def websocket_info(:close, _conn_state, state) do
        {:close, <<>>, state}
      end
      
      def websocket_info(msg, _conn_state, state) do
        Logger.debug("Unhandled WebSocket info: #{inspect(msg)}")
        {:ok, state}
      end
      
      def websocket_terminate(reason, _conn_state, %{parent: parent} = _state) do
        send(parent, {:websocket_closed, reason})
        :ok
      end
    end
  end
end