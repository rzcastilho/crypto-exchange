defmodule CryptoExchange.Trading.ErrorHandler do
  @moduledoc """
  Specialized error handling for trading operations.

  This module provides enhanced error handling strategies specifically designed
  for trading operations, including intelligent error classification, user-friendly
  messages, and recovery suggestions for common trading scenarios.

  ## Features

  - **Intelligent Error Classification**: Categorizes errors by impact and recoverability
  - **User-Friendly Messages**: Translates technical errors into actionable user messages  
  - **Recovery Strategies**: Provides specific recovery actions for different error types
  - **Balance and Symbol Validation**: Enhanced validation for trading-specific constraints
  - **Order State Analysis**: Analyzes order errors and suggests corrections
  - **Market Context**: Considers market conditions when providing error guidance

  ## Error Categories

  - **Validation Errors**: Invalid parameters that can be corrected immediately
  - **Balance Errors**: Insufficient funds with balance-specific guidance
  - **Market Errors**: Market-related issues (closed, suspended, etc.)
  - **Symbol Errors**: Invalid or unsupported trading pairs
  - **Rate Limiting**: Request throttling with retry guidance
  - **System Errors**: Infrastructure issues requiring retry or escalation

  ## Usage Examples

  ```elixir
  # Handle a place order error
  case Trading.place_order("user_123", order_params) do
    {:ok, order} -> 
      {:ok, order}
    {:error, error} ->
      ErrorHandler.handle_trading_error(:place_order, error, %{
        user_id: "user_123",
        order_params: order_params
      })
  end

  # Get user-friendly error message
  user_message = ErrorHandler.user_friendly_message(error, :place_order)

  # Get recovery suggestions
  suggestions = ErrorHandler.recovery_suggestions(error, :place_order, context)
  ```
  """

  alias CryptoExchange.Binance.Errors
  require Logger

  @type operation :: :place_order | :cancel_order | :get_balance | :get_orders
  @type error_context :: %{
          user_id: String.t(),
          order_params: map() | nil,
          symbol: String.t() | nil,
          order_id: String.t() | nil
        }
  @type recovery_action :: :retry | :adjust_params | :check_balance | :wait | :contact_support

  @doc """
  Handles trading-specific errors with enhanced context and recovery strategies.

  ## Parameters
  - `operation`: The trading operation that failed
  - `error`: The error that occurred (can be Binance.Errors struct or generic error)
  - `context`: Additional context about the operation

  ## Returns
  Enhanced error response with user-friendly message and recovery suggestions.
  """
  @spec handle_trading_error(operation(), term(), error_context()) :: {:error, map()}
  def handle_trading_error(operation, error, context \\ %{}) do
    enhanced_error = %{
      original_error: error,
      operation: operation,
      category: classify_error(error, operation),
      user_message: user_friendly_message(error, operation),
      technical_message: technical_error_message(error),
      recovery_suggestions: recovery_suggestions(error, operation, context),
      severity: determine_severity(error, operation),
      retryable: is_retryable?(error, operation),
      context: context
    }

    log_trading_error(enhanced_error)
    {:error, enhanced_error}
  end

  @doc """
  Provides user-friendly error messages for trading operations.

  Translates technical API errors into clear, actionable messages for end users.
  """
  @spec user_friendly_message(term(), operation()) :: String.t()
  def user_friendly_message(error, operation) do
    case {error, operation} do
      # Binance API errors - Errors struct format
      {%Errors{code: -2010}, :place_order} ->
        "Order rejected: Account does not have sufficient balance for this order."

      {%Errors{code: -2018}, :place_order} ->
        "Insufficient balance: You don't have enough funds to place this order. Please check your account balance."

      {%Errors{code: -2019}, :place_order} ->
        "Margin insufficient: Not enough margin to place this order."

      {%Errors{code: -2011}, :cancel_order} ->
        "Order not found: The order you're trying to cancel doesn't exist or has already been processed."

      {%Errors{code: -1121}, :place_order} ->
        "Invalid symbol: The trading pair you specified is not valid or not currently supported."

      {%Errors{code: -1013}, :place_order} ->
        "Invalid quantity: The order quantity doesn't meet the minimum requirements for this trading pair."

      {%Errors{code: -1003}, _} ->
        "Rate limit exceeded: Too many requests. Please wait a moment before trying again."

      # Binance API errors - Raw map format
      {%{"code" => -2010}, :place_order} ->
        "Order rejected: Account does not have sufficient balance for this order."

      {%{"code" => -2018}, :place_order} ->
        "Insufficient balance: You don't have enough funds to place this order. Please check your account balance."

      {%{"code" => -2019}, :place_order} ->
        "Margin insufficient: Not enough margin to place this order."

      {%{"code" => -2011}, :cancel_order} ->
        "Order not found: The order you're trying to cancel doesn't exist or has already been processed."

      {%{"code" => -1121}, :place_order} ->
        "Invalid symbol: The trading pair you specified is not valid or not currently supported."

      {%{"code" => -1013}, :place_order} ->
        "Invalid quantity: The order quantity doesn't meet the minimum requirements for this trading pair."

      {%{"code" => -1003}, _} ->
        "Rate limit exceeded: Too many requests. Please wait a moment before trying again."

      {%{"code" => -1100}, _} ->
        "Market temporarily unavailable: The market is currently closed or under maintenance."

      # Generic validation errors
      {{:error, :insufficient_balance}, :place_order} ->
        "Insufficient balance: You don't have enough funds to place this order."

      {{:error, :invalid_symbol}, _} ->
        "Invalid trading pair: Please check that the symbol is correct and supported."

      {{:error, :invalid_symbol_format}, _} ->
        "Invalid symbol format: Please use the correct trading pair format (e.g., 'BTCUSDT')."

      {{:error, :invalid_symbol_length}, _} ->
        "Invalid symbol length: Trading pair symbols should be at least 6 characters long."

      {{:error, :invalid_params_format}, :place_order} ->
        "Invalid order format: Please check that all required order parameters are provided correctly."

      {{:error, :missing_required_fields}, :place_order} ->
        "Missing required information: Please provide all required order details (symbol, side, type, quantity)."

      {{:error, {:missing_required_fields, _}}, :place_order} ->
        "Missing required information: Please provide all required order details (symbol, side, type, quantity)."

      {{:error, :missing_quantity}, :place_order} ->
        "Missing quantity: Please specify the order quantity."

      {{:error, :invalid_quantity_format}, :place_order} ->
        "Invalid quantity format: Please provide quantity as a valid decimal number."

      {{:error, :invalid_quantity_value}, :place_order} ->
        "Invalid quantity value: Order quantity must be greater than zero."

      {{:error, :invalid_quantity_type}, :place_order} ->
        "Invalid quantity type: Please provide quantity as a string or number."

      {{:error, :parse_error}, _} ->
        "Response parsing error: There was an issue processing the server response. Please try again."

      # Network and connection errors
      {{:error, :timeout}, _} ->
        "Request timeout: The operation took too long to complete. Please check your connection and try again."

      {{:error, :connection_failed}, _} ->
        "Connection error: Unable to connect to the trading server. Please check your internet connection."

      # User not found
      {{:error, :user_not_found}, _} ->
        "Session expired: Please reconnect your trading account."

      # Generic fallback
      {%Errors{} = api_error, _} ->
        Errors.user_message(api_error)

      {error, _} ->
        "An unexpected error occurred: #{inspect(error)}. Please try again or contact support."
    end
  end

  @doc """
  Provides recovery suggestions for trading errors.

  Returns specific actions users can take to resolve the error.
  """
  @spec recovery_suggestions(term(), operation(), error_context()) :: [String.t()]
  def recovery_suggestions(error, operation, context) do
    case {error, operation} do
      # Balance-related errors
      {%Errors{code: code}, :place_order} when code in [-2010, -2018, -2019] ->
        [
          "Check your account balance for the required currency",
          "Reduce the order quantity to match your available balance",
          "Deposit additional funds to your account",
          "Consider using a different trading pair with sufficient balance"
        ]

      {{:error, :insufficient_balance}, :place_order} ->
        [
          "Check your account balance",
          "Reduce the order size",
          "Deposit more funds to your account"
        ]

      # Symbol validation errors
      {%Errors{code: -1121}, _} ->
        suggestions = ["Verify the trading pair symbol is correct (e.g., 'BTCUSDT')"]

        if symbol = context[:symbol] || get_symbol_from_params(context[:order_params]) do
          suggestions ++ ["You provided: '#{symbol}' - please double-check this symbol"]
        else
          suggestions ++ ["Common symbols include: BTCUSDT, ETHUSDT, BNBUSDT"]
        end

      {{:error, :invalid_symbol}, _} ->
        [
          "Check that the trading pair symbol is correct",
          "Ensure the symbol is in the correct format (e.g., 'BTCUSDT')",
          "Verify that trading is enabled for this pair"
        ]

      # Quantity and precision errors
      {%Errors{code: -1013}, :place_order} ->
        [
          "Check the minimum order quantity for this trading pair",
          "Verify quantity precision matches exchange requirements",
          "Ensure the order value meets minimum notional requirements"
        ]

      # Order not found errors
      {%Errors{code: -2011}, :cancel_order} ->
        order_context =
          if order_id = context[:order_id] do
            ["Check that order ID '#{order_id}' is correct and still active"]
          else
            ["Verify the order ID is correct"]
          end

        order_context ++
          [
            "The order may have already been filled or cancelled",
            "Check your order history to see the current status"
          ]

      # Rate limiting
      {%Errors{code: -1003}, _} ->
        [
          "Wait 1-2 minutes before retrying",
          "Reduce the frequency of your requests",
          "Implement proper rate limiting in your application"
        ]

      # Network and timeout errors
      {{:error, :timeout}, _} ->
        [
          "Check your internet connection",
          "Try again in a few moments",
          "If the problem persists, check exchange status"
        ]

      # Session errors
      {{:error, :user_not_found}, _} ->
        [
          "Reconnect your trading account",
          "Verify your API credentials are still valid",
          "Check if your session has expired"
        ]

      # Generic fallback
      _ ->
        [
          "Try the operation again",
          "If the error persists, contact support",
          "Check the exchange status page for any ongoing issues"
        ]
    end
  end

  @doc """
  Classifies errors by category for better handling and logging.
  """
  @spec classify_error(term(), operation()) :: atom()
  def classify_error(error, _operation) do
    case error do
      %Errors{category: category} -> category
      # Raw Binance error maps - classify by error code (string keys)
      %{"code" => -2010} -> :insufficient_funds
      %{"code" => -2018} -> :insufficient_funds
      %{"code" => -2019} -> :insufficient_funds
      %{"code" => -1121} -> :invalid_symbol
      %{"code" => -1013} -> :validation
      %{"code" => -1003} -> :rate_limiting
      %{"code" => -1015} -> :rate_limiting
      %{"code" => -2008} -> :rate_limiting
      %{"code" => -2014} -> :authentication
      %{"code" => -1022} -> :authentication
      %{"code" => -1100} -> :market_status
      # Raw Binance error maps - classify by error code (atom keys)
      %{code: -2010} -> :insufficient_funds
      %{code: -2018} -> :insufficient_funds
      %{code: -2019} -> :insufficient_funds
      %{code: -1121} -> :invalid_symbol
      %{code: -1013} -> :validation
      %{code: -1003} -> :rate_limiting
      %{code: -1015} -> :rate_limiting
      %{code: -2008} -> :rate_limiting
      %{code: -2014} -> :authentication
      %{code: -1022} -> :authentication
      %{code: -1100} -> :market_status
      # Standard error tuples
      {:error, :insufficient_balance} -> :trading
      {:error, :invalid_symbol} -> :validation
      {:error, :invalid_symbol_format} -> :validation
      {:error, :invalid_symbol_length} -> :validation
      {:error, :invalid_params_format} -> :validation
      {:error, :missing_required_fields} -> :validation
      {:error, {:missing_required_fields, _}} -> :validation
      {:error, :missing_quantity} -> :validation
      {:error, :invalid_quantity_format} -> :validation
      {:error, :invalid_quantity_value} -> :validation
      {:error, :invalid_quantity_type} -> :validation
      {:error, :parse_error} -> :system
      {:error, :timeout} -> :network
      {:error, :connection_failed} -> :network
      {:error, :user_not_found} -> :authentication
      _ -> :unknown
    end
  end

  @doc """
  Determines the severity level of trading errors.
  """
  @spec determine_severity(term(), operation()) :: :info | :warning | :error | :critical
  def determine_severity(error, operation) do
    case {error, operation} do
      # Critical errors that prevent trading
      {%Errors{code: code}, _} when code in [-1021, -1022] -> :critical
      {{:error, :user_not_found}, _} -> :critical
      # Errors that require user action
      {%Errors{code: code}, _} when code in [-2010, -2018, -2019, -1013, -1121] -> :error
      {{:error, :insufficient_balance}, _} -> :error
      {{:error, :invalid_symbol}, _} -> :error
      # Warnings for temporary issues
      {%Errors{code: -1003}, _} -> :warning
      {{:error, :timeout}, _} -> :warning
      # Info for recoverable issues  
      {%Errors{code: -2011}, :cancel_order} -> :error
      # Default to error for unknown issues
      _ -> :error
    end
  end

  @doc """
  Determines if an error is retryable based on its type and context.
  """
  @spec is_retryable?(term(), operation()) :: boolean()
  def is_retryable?(error, _operation) do
    case error do
      # Retryable errors
      %Errors{retryable: true} -> true
      {:error, :timeout} -> true
      {:error, :connection_failed} -> true
      {:error, :parse_error} -> true
      # Non-retryable errors
      %Errors{category: :authentication} -> false
      %Errors{category: :trading} -> false
      {:error, :insufficient_balance} -> false
      {:error, :invalid_symbol} -> false
      {:error, :invalid_params_format} -> false
      {:error, :user_not_found} -> false
      # Default to non-retryable for safety
      _ -> false
    end
  end

  @doc """
  Validates trading parameters with enhanced error messages.
  """
  @spec validate_trading_params(map(), String.t()) :: :ok | {:error, map()}
  def validate_trading_params(params, user_id) do
    context = %{user_id: user_id, order_params: params}

    with :ok <- validate_required_trading_fields(params),
         :ok <- validate_trading_symbol(params["symbol"] || params[:symbol]),
         :ok <- validate_trading_quantities(params) do
      :ok
    else
      {:error, reason} ->
        handle_trading_error(:place_order, {:error, reason}, context)
    end
  end

  # Private helper functions

  defp technical_error_message(error) do
    case error do
      %Errors{} = api_error -> "API Error: #{api_error.message}"
      {:error, reason} -> "Error: #{inspect(reason)}"
      error -> "Unexpected error: #{inspect(error)}"
    end
  end

  defp log_trading_error(enhanced_error) do
    level =
      case enhanced_error.severity do
        :critical -> :error
        :error -> :error
        :warning -> :warning
        :info -> :info
      end

    Logger.log(level, """
    Trading Error Occurred:
    Operation: #{enhanced_error.operation}
    Category: #{enhanced_error.category}
    User ID: #{enhanced_error.context[:user_id] || "unknown"}
    User Message: #{enhanced_error.user_message}
    Technical: #{enhanced_error.technical_message}
    Retryable: #{enhanced_error.retryable}
    """)
  end

  defp get_symbol_from_params(%{"symbol" => symbol}), do: symbol
  defp get_symbol_from_params(%{symbol: symbol}), do: symbol
  defp get_symbol_from_params(_), do: nil

  defp validate_required_trading_fields(params) do
    required = ["symbol", "side", "type", "quantity"]
    present = Map.keys(params) ++ (params |> Map.keys() |> Enum.map(&to_string/1))

    missing =
      Enum.reject(required, fn field ->
        field in present and get_param_value(params, field) not in [nil, ""]
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_trading_symbol(symbol) when is_binary(symbol) and byte_size(symbol) > 2 do
    # Enhanced symbol validation
    cond do
      not String.match?(symbol, ~r/^[A-Z]{3,}[A-Z]{3,}$/) ->
        {:error, :invalid_symbol_format}

      String.length(symbol) < 6 ->
        {:error, :invalid_symbol_length}

      true ->
        :ok
    end
  end

  defp validate_trading_symbol(_), do: {:error, :invalid_symbol}

  defp validate_trading_quantities(params) do
    quantity = get_param_value(params, "quantity") || get_param_value(params, :quantity)

    case quantity do
      nil ->
        {:error, :missing_quantity}

      qty when is_binary(qty) ->
        case Decimal.parse(qty) do
          {decimal_qty, ""} ->
            if Decimal.positive?(decimal_qty) do
              :ok
            else
              {:error, :invalid_quantity_value}
            end

          _ ->
            {:error, :invalid_quantity_format}
        end

      _ ->
        {:error, :invalid_quantity_type}
    end
  end

  defp get_param_value(params, key) when is_binary(key) do
    params[key] || params[String.to_atom(key)]
  end

  defp get_param_value(params, key) when is_atom(key) do
    params[key] || params[Atom.to_string(key)]
  end
end
