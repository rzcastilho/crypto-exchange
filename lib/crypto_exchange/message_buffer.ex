defmodule CryptoExchange.MessageBuffer do
  @moduledoc """
  High-performance message buffering and batching system for WebSocket streams.
  
  This module implements efficient message buffering to handle high-frequency 
  message processing scenarios. It provides:
  
  - Message batching for reduced PubSub overhead
  - Rate limiting to prevent system overload
  - Backpressure handling for sustainable throughput
  - Memory-efficient circular buffer implementation
  - Configurable flush strategies (time-based, size-based, or hybrid)
  
  ## Configuration
  
  The buffer can be configured with various strategies:
  
      config = %{
        buffer_size: 1000,        # Maximum messages in buffer
        flush_interval: 100,      # Flush every 100ms
        batch_size: 50,           # Maximum messages per batch
        rate_limit: 1000,         # Messages per second limit
        strategy: :hybrid         # :time, :size, or :hybrid
      }
  
  ## Usage
  
  Start a buffer for a stream:
  
      {:ok, pid} = CryptoExchange.MessageBuffer.start_link(stream_config)
      
  Add messages to the buffer:
  
      :ok = CryptoExchange.MessageBuffer.add_message(pid, message)
      
  The buffer will automatically flush messages based on the configured strategy.
  """
  
  use GenServer
  require Logger
  
  @default_config %{
    buffer_size: 1000,
    flush_interval: 100,
    batch_size: 50,
    rate_limit: 1000,
    strategy: :hybrid,
    backpressure_threshold: 0.8
  }
  
  defstruct [
    :config,
    :buffer,
    :flush_timer,
    :rate_limiter,
    :stats,
    :publisher_fn,
    :buffer_start,
    :buffer_end,
    buffer_count: 0,
    last_flush: 0
  ]
  
  @type message :: term()
  @type config :: %{
    buffer_size: pos_integer(),
    flush_interval: pos_integer(),
    batch_size: pos_integer(),
    rate_limit: pos_integer(),
    strategy: :time | :size | :hybrid,
    backpressure_threshold: float()
  }
  
  # Client API
  
  @doc """
  Start a message buffer with the given configuration.
  
  ## Parameters
  
  - `config` - Buffer configuration map
  - `publisher_fn` - Function to call when flushing messages
  
  ## Examples
  
      config = %{buffer_size: 500, flush_interval: 50}
      publisher = fn messages -> 
        Phoenix.PubSub.broadcast_from(pubsub, self(), topic, {:batch, messages})
      end
      
      {:ok, pid} = MessageBuffer.start_link(config, publisher)
  """
  @spec start_link(config(), (list(message()) -> :ok | {:error, term()})) :: GenServer.on_start()
  def start_link(config \\ %{}, publisher_fn) when is_function(publisher_fn, 1) do
    GenServer.start_link(__MODULE__, {config, publisher_fn})
  end
  
  @doc """
  Add a message to the buffer.
  
  Returns :ok if the message was added successfully, or {:error, :buffer_full}
  if the buffer is at capacity and backpressure is applied.
  """
  @spec add_message(pid(), message()) :: :ok | {:error, :buffer_full}
  def add_message(pid, message) do
    GenServer.call(pid, {:add_message, message}, 5000)
  end
  
  @doc """
  Force flush all buffered messages immediately.
  """
  @spec flush_now(pid()) :: :ok
  def flush_now(pid) do
    GenServer.call(pid, :flush_now)
  end
  
  @doc """
  Get buffer statistics and performance metrics.
  """
  @spec get_stats(pid()) :: map()
  def get_stats(pid) do
    GenServer.call(pid, :get_stats)
  end
  
  @doc """
  Update buffer configuration dynamically.
  """
  @spec update_config(pid(), config()) :: :ok
  def update_config(pid, new_config) do
    GenServer.call(pid, {:update_config, new_config})
  end
  
  # Server Callbacks
  
  @impl true
  def init({config, publisher_fn}) do
    merged_config = Map.merge(@default_config, config)
    buffer_size = merged_config.buffer_size
    
    state = %__MODULE__{
      config: merged_config,
      buffer: :array.new(buffer_size, default: nil),
      publisher_fn: publisher_fn,
      buffer_start: 0,
      buffer_end: 0,
      rate_limiter: init_rate_limiter(merged_config.rate_limit),
      stats: init_stats(),
      last_flush: System.monotonic_time(:millisecond)
    }
    
    # Schedule first flush timer
    state = schedule_flush(state)
    
    Logger.info("Started MessageBuffer with config: #{inspect(merged_config)}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:add_message, message}, _from, state) do
    case check_backpressure(state) do
      :ok ->
        case add_message_to_buffer(message, state) do
          {:ok, new_state} ->
            updated_state = update_stats(new_state, :message_added)
            maybe_flush_state = maybe_flush_on_size(updated_state)
            {:reply, :ok, maybe_flush_state}
            
          {:error, :buffer_full} = error ->
            updated_state = update_stats(state, :buffer_full)
            {:reply, error, updated_state}
        end
        
      {:error, :backpressure} ->
        updated_state = update_stats(state, :backpressure_applied)
        {:reply, {:error, :buffer_full}, updated_state}
    end
  end
  
  @impl true
  def handle_call(:flush_now, _from, state) do
    new_state = flush_buffer(state, :manual)
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    current_stats = calculate_current_stats(state)
    {:reply, current_stats, state}
  end
  
  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    merged_config = Map.merge(state.config, new_config)
    new_state = %{state | 
      config: merged_config,
      rate_limiter: init_rate_limiter(merged_config.rate_limit)
    }
    
    # Reschedule flush timer if interval changed
    new_state = if new_config[:flush_interval] do
      cancel_flush_timer(new_state)
      |> schedule_flush()
    else
      new_state
    end
    
    Logger.info("Updated MessageBuffer config: #{inspect(new_config)}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:flush_timer, state) do
    Logger.info("MessageBuffer flush timer fired, buffer_count: #{state.buffer_count}")
    new_state = flush_buffer(state, :timer)
    new_state_with_timer = schedule_flush(new_state)
    {:noreply, new_state_with_timer}
  end
  
  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in MessageBuffer: #{inspect(msg)}")
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Flush any remaining messages
    if state.buffer_count > 0 do
      flush_buffer(state, :shutdown)
    end
    
    cancel_flush_timer(state)
    :ok
  end
  
  # Private Functions
  
  defp init_stats do
    current_time = System.monotonic_time(:millisecond)
    %{
      messages_added: 0,
      messages_flushed: 0,
      batches_sent: 0,
      buffer_full_count: 0,
      backpressure_count: 0,
      flush_timer_count: 0,
      flush_size_count: 0,
      flush_manual_count: 0,
      start_time: current_time,
      last_flush_time: current_time
    }
  end
  
  defp init_rate_limiter(rate_limit) do
    %{
      rate_limit: rate_limit,
      current_count: 0,
      window_start: System.monotonic_time(:millisecond)
    }
  end
  
  defp check_backpressure(state) do
    buffer_usage = state.buffer_count / state.config.buffer_size
    
    if buffer_usage >= state.config.backpressure_threshold do
      {:error, :backpressure}
    else
      :ok
    end
  end
  
  defp add_message_to_buffer(message, state) do
    if state.buffer_count >= state.config.buffer_size do
      {:error, :buffer_full}
    else
      new_buffer = :array.set(state.buffer_end, message, state.buffer)
      new_end = rem(state.buffer_end + 1, state.config.buffer_size)
      
      new_state = %{state | 
        buffer: new_buffer,
        buffer_end: new_end,
        buffer_count: state.buffer_count + 1
      }
      
      Logger.info("Added message to buffer, new count: #{new_state.buffer_count}")
      {:ok, new_state}
    end
  end
  
  defp maybe_flush_on_size(state) do
    case state.config.strategy do
      :size when state.buffer_count >= state.config.batch_size ->
        flush_buffer(state, :size)
        
      :hybrid when state.buffer_count >= state.config.batch_size ->
        flush_buffer(state, :size)
        
      _ ->
        state
    end
  end
  
  defp flush_buffer(state, reason) do
    if state.buffer_count == 0 do
      state
    else
      {messages, new_state} = extract_messages(state)
      
      case apply_rate_limiting(new_state, length(messages)) do
        {:ok, rate_limited_state} ->
          publish_messages(messages, rate_limited_state, reason)
          
        {:error, :rate_limited, delayed_state} ->
          # Put messages back and schedule delayed flush  
          put_messages_back(messages, delayed_state)
          |> schedule_delayed_flush(100)  # Retry in 100ms
      end
    end
  end
  
  defp extract_messages(state) do
    batch_size = min(state.buffer_count, state.config.batch_size)
    messages = extract_batch(state.buffer, state.buffer_start, batch_size, [])
    
    new_start = rem(state.buffer_start + batch_size, state.config.buffer_size)
    new_state = %{state |
      buffer_start: new_start,
      buffer_count: state.buffer_count - batch_size
    }
    
    {Enum.reverse(messages), new_state}
  end
  
  defp extract_batch(_buffer, _start, 0, acc), do: acc
  defp extract_batch(buffer, pos, count, acc) do
    message = :array.get(pos, buffer)
    new_pos = rem(pos + 1, :array.size(buffer))
    extract_batch(buffer, new_pos, count - 1, [message | acc])
  end
  
  defp apply_rate_limiting(state, message_count) do
    current_time = System.monotonic_time(:millisecond)
    limiter = state.rate_limiter
    
    # Reset window if needed
    if current_time - limiter.window_start >= 1000 do
      new_limiter = %{limiter | 
        current_count: 0, 
        window_start: current_time
      }
      new_state = %{state | rate_limiter: new_limiter}
      {:ok, new_state}
    else
      new_count = limiter.current_count + message_count
      
      if new_count <= limiter.rate_limit do
        new_limiter = %{limiter | current_count: new_count}
        new_state = %{state | rate_limiter: new_limiter}
        {:ok, new_state}
      else
        {:error, :rate_limited, state}
      end
    end
  end
  
  defp publish_messages(messages, state, reason) do
    Logger.info("Publishing #{length(messages)} messages with reason #{reason}")
    try do
      state.publisher_fn.(messages)
      update_stats(state, {:messages_published, length(messages), reason})
    rescue
      error ->
        Logger.error("Failed to publish message batch: #{Exception.message(error)}")
        update_stats(state, :publish_error)
    catch
      :exit, reason ->
        Logger.error("Publisher process exited: #{inspect(reason)}")
        update_stats(state, :publish_error)
    end
  end
  
  defp put_messages_back(messages, state) do
    # For simplicity, we'll drop messages that can't be rate-limited
    # In a production system, you might want to implement a more sophisticated strategy
    Logger.warning("Dropping #{length(messages)} messages due to rate limiting")
    update_stats(state, {:messages_dropped, length(messages)})
  end
  
  defp schedule_flush(state) do
    timer = Process.send_after(self(), :flush_timer, state.config.flush_interval)
    %{state | flush_timer: timer}
  end
  
  defp schedule_delayed_flush(state, delay) do
    timer = Process.send_after(self(), :flush_timer, delay)
    %{state | flush_timer: timer}
  end
  
  defp cancel_flush_timer(state) do
    if state.flush_timer do
      Process.cancel_timer(state.flush_timer)
    end
    %{state | flush_timer: nil}
  end
  
  defp update_stats(state, :message_added) do
    %{state | stats: %{state.stats | messages_added: state.stats.messages_added + 1}}
  end
  
  defp update_stats(state, :buffer_full) do
    %{state | stats: %{state.stats | buffer_full_count: state.stats.buffer_full_count + 1}}
  end
  
  defp update_stats(state, :backpressure_applied) do
    %{state | stats: %{state.stats | backpressure_count: state.stats.backpressure_count + 1}}
  end
  
  defp update_stats(state, {:messages_published, count, :timer}) do
    %{state | stats: %{
      state.stats | 
      messages_flushed: state.stats.messages_flushed + count,
      batches_sent: state.stats.batches_sent + 1,
      flush_timer_count: state.stats.flush_timer_count + 1,
      last_flush_time: System.monotonic_time(:millisecond)
    }}
  end
  
  defp update_stats(state, {:messages_published, count, :size}) do
    %{state | stats: %{
      state.stats | 
      messages_flushed: state.stats.messages_flushed + count,
      batches_sent: state.stats.batches_sent + 1,
      flush_size_count: state.stats.flush_size_count + 1,
      last_flush_time: System.monotonic_time(:millisecond)
    }}
  end
  
  defp update_stats(state, {:messages_published, count, :manual}) do
    %{state | stats: %{
      state.stats | 
      messages_flushed: state.stats.messages_flushed + count,
      batches_sent: state.stats.batches_sent + 1,
      flush_manual_count: state.stats.flush_manual_count + 1,
      last_flush_time: System.monotonic_time(:millisecond)
    }}
  end
  
  defp update_stats(state, {:messages_published, count, :shutdown}) do
    %{state | stats: %{
      state.stats | 
      messages_flushed: state.stats.messages_flushed + count,
      batches_sent: state.stats.batches_sent + 1,
      flush_manual_count: state.stats.flush_manual_count + 1,
      last_flush_time: System.monotonic_time(:millisecond)
    }}
  end
  
  defp update_stats(state, _other), do: state
  
  defp calculate_current_stats(state) do
    current_time = System.monotonic_time(:millisecond)
    uptime_ms = current_time - state.stats.start_time
    uptime_seconds = div(uptime_ms, 1000)
    
    messages_per_second = if uptime_seconds > 0 do
      state.stats.messages_flushed / uptime_seconds
    else
      0.0
    end
    
    buffer_utilization = state.buffer_count / state.config.buffer_size
    
    Map.merge(state.stats, %{
      current_buffer_count: state.buffer_count,
      buffer_utilization: Float.round(buffer_utilization, 3),
      messages_per_second: Float.round(messages_per_second, 2),
      uptime_seconds: uptime_seconds,
      rate_limit_current: state.rate_limiter.current_count,
      rate_limit_max: state.rate_limiter.rate_limit
    })
  end
end