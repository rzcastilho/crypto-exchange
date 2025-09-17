defmodule CryptoExchange.Logging do
  @moduledoc """
  Structured logging system for CryptoExchange application.

  This module provides a centralized, structured logging interface that enables
  better observability, monitoring, and debugging capabilities throughout the
  crypto exchange system.

  ## Features

  - **Structured Data**: All logs include structured metadata for better filtering and analysis
  - **Context Awareness**: Automatic context propagation (user_id, request_id, etc.)
  - **Performance Metrics**: Built-in timing and performance measurement capabilities  
  - **Error Tracking**: Enhanced error logging with stack traces and context
  - **Component Identification**: Clear identification of which system component generated logs
  - **Environment Awareness**: Automatic inclusion of environment and deployment information

  ## Log Categories

  - **Trading**: Order placement, cancellation, balance operations
  - **API**: External API calls and responses
  - **WebSocket**: Real-time connection and streaming events
  - **Authentication**: User authentication and session management
  - **System**: Application lifecycle, health checks, and system events
  - **Performance**: Timing, metrics, and performance-related events

  ## Usage Examples

  ```elixir
  # Simple structured logging
  Logging.info("Order placed successfully", %{
    category: :trading,
    user_id: "alice",
    order_id: "123456",
    symbol: "BTCUSDT",
    side: "BUY"
  })

  # Error logging with context
  Logging.error("Failed to connect to Binance API", %{
    category: :api,
    error: :connection_timeout,
    retry_count: 3,
    endpoint: "/api/v3/order"
  })

  # Performance timing
  Logging.with_timing("Processing order validation", %{category: :trading}) do
    # Order validation logic here
    :ok
  end

  # Context-aware logging
  Logging.with_context(%{user_id: "alice", request_id: "req-123"}) do
    Logging.info("Starting order processing", %{category: :trading})
    # Context is automatically included in all logs within this block
  end
  ```

  ## Log Structure

  All structured logs follow this format:
  ```json
  {
    "timestamp": "2023-01-15T10:30:45.123Z",
    "level": "info",
    "message": "Order placed successfully",
    "category": "trading",
    "component": "private_client",
    "user_id": "alice",
    "order_id": "123456",
    "symbol": "BTCUSDT",
    "environment": "production",
    "node": "crypto-exchange-01",
    "request_id": "req-abc-123"
  }
  ```
  """

  require Logger
  
  @type log_level :: :debug | :info | :warning | :error
  @type log_category :: :trading | :api | :websocket | :authentication | :system | :performance
  @type log_metadata :: %{
    category: log_category(),
    component: String.t() | nil,
    user_id: String.t() | nil,
    order_id: String.t() | nil,
    symbol: String.t() | nil,
    error: term() | nil,
    duration_ms: non_neg_integer() | nil,
    request_id: String.t() | nil
  }

  # Context storage using process dictionary
  @context_key :crypto_exchange_log_context

  ## Public API

  @doc """
  Logs a debug message with structured metadata.
  """
  @spec debug(String.t(), map()) :: :ok
  def debug(message, metadata \\ %{}) do
    log(:debug, message, metadata)
  end

  @doc """
  Logs an info message with structured metadata.
  """  
  @spec info(String.t(), map()) :: :ok
  def info(message, metadata \\ %{}) do
    log(:info, message, metadata)
  end

  @doc """
  Logs a warning message with structured metadata.
  """
  @spec warning(String.t(), map()) :: :ok
  def warning(message, metadata \\ %{}) do
    log(:warning, message, metadata)
  end

  @doc """
  Logs an error message with structured metadata.
  """
  @spec error(String.t(), map()) :: :ok
  def error(message, metadata \\ %{}) do
    log(:error, message, metadata)
  end

  @doc """
  Logs an exception with full context and stack trace.
  """
  @spec error_with_exception(String.t(), Exception.t(), list(), map()) :: :ok
  def error_with_exception(message, exception, stacktrace \\ [], metadata \\ %{}) do
    enhanced_metadata = metadata
    |> Map.put(:error_type, exception.__struct__)
    |> Map.put(:error_message, Exception.message(exception))
    |> Map.put(:stacktrace, Exception.format_stacktrace(stacktrace))

    log(:error, message, enhanced_metadata)
  end

  @doc """
  Executes a function while measuring its execution time and logging performance metrics.
  
  Returns the result of the function execution.
  """
  @spec with_timing(String.t(), map(), (() -> any())) :: any()
  def with_timing(message, metadata \\ %{}, fun) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = fun.()
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      timing_metadata = metadata
      |> Map.put(:duration_ms, duration)
      |> Map.put(:status, :success)
      
      info("#{message} completed", timing_metadata)
      result
    rescue
      exception ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        error_metadata = metadata
        |> Map.put(:duration_ms, duration)
        |> Map.put(:status, :error)
        |> Map.put(:error_type, exception.__struct__)
        |> Map.put(:error_message, Exception.message(exception))
        
        error("#{message} failed", error_metadata)
        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Sets logging context that will be automatically included in all subsequent logs
  within the current process until the context is cleared.
  """
  @spec set_context(map()) :: :ok
  def set_context(context) do
    Process.put(@context_key, context)
    :ok
  end

  @doc """
  Executes a function with temporary logging context.
  Context is automatically cleaned up after function execution.
  """
  @spec with_context(map(), (() -> any())) :: any()
  def with_context(context, fun) do
    old_context = get_context()
    new_context = Map.merge(old_context, context)
    
    set_context(new_context)
    
    try do
      fun.()
    after
      set_context(old_context)
    end
  end

  @doc """
  Gets the current logging context for the process.
  """
  @spec get_context() :: map()
  def get_context do
    Process.get(@context_key, %{})
  end

  @doc """
  Clears the current logging context.
  """
  @spec clear_context() :: :ok
  def clear_context do
    Process.delete(@context_key)
    :ok
  end

  @doc """
  Creates a new request ID for tracking operations across components.
  """
  @spec new_request_id() :: String.t()
  def new_request_id do
    "req-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  @doc """
  Logs the start of an operation and returns a function to log its completion.
  
  ## Example
  ```elixir
  complete_fn = Logging.start_operation("Processing order", %{
    category: :trading,
    user_id: "alice"
  })
  
  # ... do work ...
  
  complete_fn.(:success, %{order_id: "123"})
  ```
  """
  @spec start_operation(String.t(), map()) :: ((:success | :error, map()) -> :ok)
  def start_operation(message, metadata \\ %{}) do
    start_time = System.monotonic_time(:millisecond)
    request_id = Map.get(metadata, :request_id, new_request_id())
    
    start_metadata = Map.put(metadata, :request_id, request_id)
    info("#{message} started", start_metadata)
    
    fn status, completion_metadata ->
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      final_metadata = start_metadata
      |> Map.merge(completion_metadata)
      |> Map.put(:duration_ms, duration)
      |> Map.put(:status, status)
      
      case status do
        :success -> info("#{message} completed", final_metadata)
        :error -> error("#{message} failed", final_metadata)
      end
    end
  end

  ## Private Functions

  defp log(level, message, metadata) do
    # Merge with process context
    context = get_context()
    safe_metadata = metadata || %{}
    enhanced_metadata = Map.merge(context, safe_metadata)
    
    # Add system metadata
    final_metadata = enhanced_metadata
    |> add_system_metadata()
    |> add_component_metadata()
    |> ensure_required_fields()
    
    # Format message with structured metadata for better visibility
    formatted_message = format_structured_message(message, final_metadata)
    
    # Use Elixir Logger with key metadata fields
    Logger.log(level, formatted_message, Map.take(final_metadata, [:category, :component, :user_id, :request_id]))
  end

  defp format_structured_message(message, metadata) do
    # Create a formatted message that includes key metadata
    metadata_string = metadata
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.map(fn {k, v} -> "#{k}=#{format_value(v)}" end)
    |> Enum.join(" ")
    
    case metadata_string do
      "" -> message
      _ -> "#{message} [#{metadata_string}]"
    end
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value), do: inspect(value)

  defp add_system_metadata(metadata) do
    metadata
    |> Map.put_new(:timestamp, DateTime.utc_now())
    |> Map.put_new(:node, Node.self())
    |> Map.put_new(:environment, Application.get_env(:crypto_exchange, :environment, :development))
    |> Map.put_new(:application, :crypto_exchange)
  end

  defp add_component_metadata(metadata) do
    # Try to infer component from calling process
    component = case Process.info(self(), :registered_name) do
      {_, name} when is_atom(name) -> Atom.to_string(name)
      _ -> infer_component_from_stacktrace()
    end
    
    Map.put_new(metadata, :component, component)
  end

  defp infer_component_from_stacktrace do
    case Process.info(self(), :current_stacktrace) do
      {_, [{module, _function, _arity, _location} | _]} ->
        module
        |> Atom.to_string()
        |> String.replace("Elixir.CryptoExchange.", "")
        |> String.downcase()
      
      _ -> "unknown"
    end
  end

  defp ensure_required_fields(metadata) do
    metadata
    |> Map.put_new(:category, :system)
    |> Map.put_new(:request_id, new_request_id())
  end

  ## Helper Functions for Common Logging Patterns

  @doc """
  Logs API request initiation with standard metadata.
  """
  @spec api_request_start(String.t(), String.t(), map()) :: String.t()
  def api_request_start(method, endpoint, metadata \\ %{}) do
    request_id = new_request_id()
    
    info("API request initiated", %{
      category: :api,
      method: method,
      endpoint: endpoint,
      request_id: request_id
    } |> Map.merge(metadata))
    
    request_id
  end

  @doc """
  Logs API request completion with timing and response metadata.
  """
  @spec api_request_complete(String.t(), String.t(), integer(), map()) :: :ok
  def api_request_complete(request_id, method, status_code, metadata \\ %{}) do
    info("API request completed", %{
      category: :api,
      request_id: request_id,
      method: method,
      status_code: status_code
    } |> Map.merge(metadata))
  end

  @doc """
  Logs trading operation with standard trading metadata.
  """
  @spec trading_event(String.t(), map()) :: :ok
  def trading_event(message, metadata \\ %{}) do
    info(message, Map.put(metadata, :category, :trading))
  end

  @doc """
  Logs WebSocket events with connection metadata.
  """
  @spec websocket_event(String.t(), map()) :: :ok
  def websocket_event(message, metadata \\ %{}) do
    info(message, Map.put(metadata, :category, :websocket))
  end

  @doc """
  Logs authentication events with security context.
  """
  @spec auth_event(String.t(), map()) :: :ok
  def auth_event(message, metadata \\ %{}) do
    # Sanitize sensitive information
    sanitized_metadata = metadata
    |> Map.drop([:password, :secret_key, :api_secret, :private_key])
    |> Map.put(:category, :authentication)
    
    info(message, sanitized_metadata)
  end

  @doc """
  Logs system events with operational metadata.
  """
  @spec system_event(String.t(), map()) :: :ok
  def system_event(message, metadata \\ %{}) do
    info(message, Map.put(metadata, :category, :system))
  end
end