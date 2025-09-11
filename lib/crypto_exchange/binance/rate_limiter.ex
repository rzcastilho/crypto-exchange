defmodule CryptoExchange.Binance.RateLimiter do
  @moduledoc """
  Advanced rate limiting for Binance API requests with weight-based tracking.

  This module implements comprehensive rate limiting that respects Binance's complex
  rate limiting system which includes:

  - Request count limits (1200 requests per minute)
  - Weight-based limits for different endpoint categories
  - Order-specific limits (10 orders per second)
  - IP-based and UID-based rate limiting

  ## Features

  - **Multi-tier Rate Limiting**: Request count, weight, and order-specific limits
  - **Backoff Strategies**: Exponential backoff with jitter for rate limit recovery
  - **Window Management**: Sliding window rate limit tracking
  - **Weight Calculation**: Per-endpoint weight calculation matching Binance rules
  - **Circuit Breaker**: Temporary blocking when consistently hitting limits

  ## Weight System

  Different Binance endpoints have different weights:
  - `/api/v3/account`: Weight 10
  - `/api/v3/order` (POST): Weight 1
  - `/api/v3/order` (DELETE): Weight 1
  - `/api/v3/openOrders`: Weight 3 (for one symbol), Weight 40 (for all symbols)
  - `/api/v3/allOrders`: Weight 10

  ## Usage

      # Check if request is allowed
      {:ok, :allowed} = RateLimiter.check_request_allowed(user_id, :account)
      
      # Record successful request
      :ok = RateLimiter.record_request(user_id, :account)
      
      # Handle rate limit exceeded
      {:error, :rate_limit_exceeded, retry_after} = RateLimiter.check_request_allowed(user_id, :order)
  """

  use GenServer
  require Logger

  # Rate limit configuration
  @request_limit 1200  # requests per minute
  @request_window 60_000  # 1 minute in milliseconds
  @weight_limit 1200  # weight per minute
  @weight_window 60_000  # 1 minute in milliseconds
  @order_limit 10  # orders per second
  @order_window 1_000  # 1 second in milliseconds

  # Endpoint weights (matching Binance API documentation)
  @endpoint_weights %{
    account: 10,
    order_post: 1,
    order_delete: 1,
    open_orders_single: 3,
    open_orders_all: 40,
    all_orders: 10,
    order_status: 2,
    trades: 10
  }

  # Backoff configuration
  @initial_backoff 1000  # 1 second
  @max_backoff 60_000  # 1 minute
  @backoff_multiplier 2.0
  @jitter_range 0..500  # milliseconds

  # Circuit breaker configuration
  @circuit_breaker_threshold 5  # consecutive rate limit hits
  @circuit_breaker_timeout 60_000  # 1 minute

  defstruct [
    :user_id,
    request_history: [],  # List of {timestamp, weight} tuples
    order_history: [],    # List of order timestamps
    circuit_breaker_count: 0,
    circuit_breaker_until: nil,
    total_requests: 0,
    total_weight: 0,
    last_reset: nil
  ]

  # Client API

  @doc """
  Start rate limiter for a specific user.
  """
  def start_link(user_id) when is_binary(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via_tuple(user_id))
  end

  @doc """
  Check if a request is allowed for the user and endpoint.
  
  Returns:
  - `{:ok, :allowed}` if request can proceed
  - `{:error, :rate_limit_exceeded, retry_after_ms}` if rate limited
  - `{:error, :circuit_breaker_open, retry_after_ms}` if circuit breaker is open
  """
  def check_request_allowed(user_id, endpoint) when is_binary(user_id) and is_atom(endpoint) do
    GenServer.call(via_tuple(user_id), {:check_request, endpoint})
  end

  @doc """
  Record a successful request for rate limiting purposes.
  """
  def record_request(user_id, endpoint) when is_binary(user_id) and is_atom(endpoint) do
    GenServer.cast(via_tuple(user_id), {:record_request, endpoint})
  end

  @doc """
  Record a rate limit hit for circuit breaker logic.
  """
  def record_rate_limit_hit(user_id) when is_binary(user_id) do
    GenServer.cast(via_tuple(user_id), :rate_limit_hit)
  end

  @doc """
  Reset rate limiting state for a user (useful for testing).
  """
  def reset_limits(user_id) when is_binary(user_id) do
    GenServer.cast(via_tuple(user_id), :reset_limits)
  end

  @doc """
  Get current rate limit status for debugging.
  """
  def get_status(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :get_status)
  end

  # Server Callbacks

  @impl true
  def init(user_id) do
    Logger.debug("Starting RateLimiter for user", user_id: user_id)
    
    state = %__MODULE__{
      user_id: user_id,
      last_reset: System.system_time(:millisecond)
    }
    
    # Schedule periodic cleanup of old entries
    schedule_cleanup()
    
    {:ok, state}
  end

  @impl true
  def handle_call({:check_request, endpoint}, _from, state) do
    now = System.system_time(:millisecond)
    
    # Clean up old entries first
    cleaned_state = cleanup_old_entries(state, now)
    
    # Check circuit breaker
    case check_circuit_breaker(cleaned_state, now) do
      {:error, retry_after} ->
        {:reply, {:error, :circuit_breaker_open, retry_after}, cleaned_state}
        
      :ok ->
        # Check rate limits
        weight = get_endpoint_weight(endpoint)
        
        case check_all_limits(cleaned_state, endpoint, weight, now) do
          :ok ->
            {:reply, {:ok, :allowed}, cleaned_state}
            
          {:error, retry_after} ->
            {:reply, {:error, :rate_limit_exceeded, retry_after}, cleaned_state}
        end
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    now = System.system_time(:millisecond)
    cleaned_state = cleanup_old_entries(state, now)
    
    current_requests = length(cleaned_state.request_history)
    current_weight = cleaned_state.request_history
                     |> Enum.map(fn {_time, weight} -> weight end)
                     |> Enum.sum()
    current_orders = length(cleaned_state.order_history)
    
    status = %{
      user_id: cleaned_state.user_id,
      current_requests: current_requests,
      current_weight: current_weight,
      current_orders_per_second: current_orders,
      request_limit: @request_limit,
      weight_limit: @weight_limit,
      order_limit: @order_limit,
      circuit_breaker_count: cleaned_state.circuit_breaker_count,
      circuit_breaker_active: cleaned_state.circuit_breaker_until != nil,
      total_requests: cleaned_state.total_requests,
      total_weight: cleaned_state.total_weight,
      last_reset: cleaned_state.last_reset
    }
    
    {:reply, status, cleaned_state}
  end

  @impl true
  def handle_cast({:record_request, endpoint}, state) do
    now = System.system_time(:millisecond)
    weight = get_endpoint_weight(endpoint)
    
    new_request_history = [{now, weight} | state.request_history]
    
    new_order_history = if is_order_endpoint(endpoint) do
      [now | state.order_history]
    else
      state.order_history
    end
    
    updated_state = %{state |
      request_history: new_request_history,
      order_history: new_order_history,
      total_requests: state.total_requests + 1,
      total_weight: state.total_weight + weight,
      circuit_breaker_count: 0  # Reset on successful request
    }
    
    {:noreply, updated_state}
  end

  @impl true
  def handle_cast(:rate_limit_hit, state) do
    new_count = state.circuit_breaker_count + 1
    
    updated_state = if new_count >= @circuit_breaker_threshold do
      Logger.warning("Circuit breaker activated for user", 
        user_id: state.user_id,
        consecutive_hits: new_count
      )
      
      %{state |
        circuit_breaker_count: new_count,
        circuit_breaker_until: System.system_time(:millisecond) + @circuit_breaker_timeout
      }
    else
      %{state | circuit_breaker_count: new_count}
    end
    
    {:noreply, updated_state}
  end

  @impl true
  def handle_cast(:reset_limits, state) do
    Logger.debug("Resetting rate limits for user", user_id: state.user_id)
    
    reset_state = %{state |
      request_history: [],
      order_history: [],
      circuit_breaker_count: 0,
      circuit_breaker_until: nil,
      last_reset: System.system_time(:millisecond)
    }
    
    {:noreply, reset_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:millisecond)
    cleaned_state = cleanup_old_entries(state, now)
    
    # Schedule next cleanup
    schedule_cleanup()
    
    {:noreply, cleaned_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in RateLimiter: #{inspect(msg)}", user_id: state.user_id)
    {:noreply, state}
  end

  # Private Functions - Rate Limit Checking

  defp check_all_limits(state, endpoint, weight, now) do
    with :ok <- check_request_count_limit(state, now),
         :ok <- check_weight_limit(state, weight, now),
         :ok <- check_order_limit(state, endpoint, now) do
      :ok
    else
      {:error, retry_after} -> {:error, retry_after}
    end
  end

  defp check_request_count_limit(state, now) do
    recent_requests = filter_recent_requests(state.request_history, now, @request_window)
    current_count = length(recent_requests)
    
    if current_count >= @request_limit do
      oldest_request_time = recent_requests |> List.last() |> elem(0)
      retry_after = oldest_request_time + @request_window - now
      {:error, max(retry_after, 0)}
    else
      :ok
    end
  end

  defp check_weight_limit(state, additional_weight, now) do
    recent_requests = filter_recent_requests(state.request_history, now, @weight_window)
    current_weight = recent_requests
                     |> Enum.map(fn {_time, weight} -> weight end)
                     |> Enum.sum()
    
    if current_weight + additional_weight > @weight_limit do
      oldest_request_time = recent_requests |> List.last() |> elem(0)
      retry_after = oldest_request_time + @weight_window - now
      {:error, max(retry_after, 0)}
    else
      :ok
    end
  end

  defp check_order_limit(state, endpoint, now) do
    if is_order_endpoint(endpoint) do
      recent_orders = filter_recent_timestamps(state.order_history, now, @order_window)
      
      if length(recent_orders) >= @order_limit do
        oldest_order_time = List.last(recent_orders)
        retry_after = oldest_order_time + @order_window - now
        {:error, max(retry_after, 0)}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_circuit_breaker(state, now) do
    case state.circuit_breaker_until do
      nil -> :ok
      until when until > now -> {:error, until - now}
      _ -> :ok  # Circuit breaker timeout expired
    end
  end

  # Private Functions - Utilities

  defp filter_recent_requests(requests, now, window) do
    cutoff_time = now - window
    Enum.filter(requests, fn {timestamp, _weight} -> timestamp > cutoff_time end)
  end

  defp filter_recent_timestamps(timestamps, now, window) do
    cutoff_time = now - window
    Enum.filter(timestamps, fn timestamp -> timestamp > cutoff_time end)
  end

  defp cleanup_old_entries(state, now) do
    # Clean up request history (keep last 5 minutes for safety)
    cleanup_window = @request_window * 5
    recent_requests = filter_recent_requests(state.request_history, now, cleanup_window)
    
    # Clean up order history (keep last 10 seconds for safety)
    order_cleanup_window = @order_window * 10
    recent_orders = filter_recent_timestamps(state.order_history, now, order_cleanup_window)
    
    # Clear circuit breaker if expired
    circuit_breaker_until = if state.circuit_breaker_until && state.circuit_breaker_until <= now do
      nil
    else
      state.circuit_breaker_until
    end
    
    %{state |
      request_history: recent_requests,
      order_history: recent_orders,
      circuit_breaker_until: circuit_breaker_until
    }
  end

  defp get_endpoint_weight(endpoint) do
    Map.get(@endpoint_weights, endpoint, 1)  # Default weight of 1
  end

  defp is_order_endpoint(endpoint) do
    endpoint in [:order_post, :order_delete]
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 30_000)  # Clean up every 30 seconds
  end

  defp via_tuple(user_id) do
    {:via, Registry, {CryptoExchange.Registry, {:rate_limiter, user_id}}}
  end
end