defmodule CryptoExchange.API.ErrorHandler do
  @moduledoc """
  Centralized error handling and translation for the CryptoExchange API.
  
  This module provides standardized error handling, translation, and formatting
  across all API endpoints. It ensures consistent error responses, comprehensive
  error cataloging, and developer-friendly error messages with actionable guidance.
  
  ## Features
  
  - **Standardized Error Formats**: Consistent error response structure
  - **Comprehensive Error Catalog**: Complete mapping of all possible errors
  - **Developer-Friendly Messages**: Clear, actionable error descriptions
  - **Error Classification**: Categorized errors by type and severity
  - **Logging Integration**: Automatic error logging and monitoring
  - **Security Considerations**: Safe error messages that don't leak sensitive data
  
  ## Error Response Formats
  
  ### Simple Errors
  - `{:error, :atom_reason}` - Basic error with standardized reason atom
  
  ### Detailed Errors  
  - `{:error, :atom_reason, details}` - Error with additional context
  - `{:error, %{reason: :atom, message: string(), suggestions: list()}}` - Full error info
  
  ## Error Categories
  
  - **Validation Errors**: Input validation failures
  - **Authentication Errors**: Credential and permission issues  
  - **Business Logic Errors**: Trading rule violations
  - **Service Errors**: External service failures
  - **System Errors**: Internal system issues
  """

  require Logger
  alias CryptoExchange.API.Validation

  # Error severity levels
  @error_severities %{
    :info => "Info",
    :warning => "Warning", 
    :error => "Error",
    :critical => "Critical"
  }

  # Error categories for classification
  @error_categories %{
    validation: "Input Validation",
    authentication: "Authentication",
    authorization: "Authorization",
    business_logic: "Business Logic",
    service: "External Service",
    system: "System Error",
    rate_limit: "Rate Limiting",
    network: "Network Error"
  }

  @doc """
  Translates internal errors to standardized API error responses.
  
  Handles error translation, logging, and formatting for consistent API responses.
  """
  @spec translate_error(any(), atom()) :: any()
  def translate_error(result, api_type \\ :public)

  # Handle successful results
  def translate_error({:ok, result}, _api_type), do: {:ok, result}
  def translate_error(:ok, _api_type), do: :ok

  # Public Data API error translations
  def translate_error(error, :public) do
    case error do
      {:error, :invalid_symbol_format} -> 
        create_error(:invalid_symbol, :validation, "Invalid symbol format", [
          "Symbol must be 3-20 characters long",
          "Use uppercase letters and numbers only (e.g., 'BTCUSDT')",
          "Check symbol spelling and format"
        ])
        
      {:error, :invalid_depth_level} ->
        create_error(:invalid_level, :validation, "Invalid depth level", [
          "Depth level must be 5, 10, or 20",
          "Use one of the supported depth levels",
          "Check the API documentation for valid levels"
        ])
        
      {:error, :stream_manager_down} ->
        create_error(:service_unavailable, :service, "Stream service temporarily unavailable", [
          "Try again in a few moments",
          "Check system status",
          "Contact support if the issue persists"
        ])
        
      {:error, :startup_timeout} ->
        create_error(:connection_timeout, :network, "Connection timeout during stream setup", [
          "Check your network connection",
          "Try again with a different symbol",
          "Reduce the number of concurrent connections"
        ])
        
      {:error, :invalid_stream_type} ->
        create_error(:service_unavailable, :system, "Invalid stream configuration", [
          "This is an internal error",
          "Try again or contact support",
          "Check that the symbol is valid"
        ])
        
      _ -> 
        log_unknown_error(error, :public)
        create_error(:connection_failed, :network, "Failed to establish stream connection", [
          "Check your network connection",
          "Verify the symbol is valid and tradable",
          "Try again in a few moments"
        ])
    end
  end

  # Trading API error translations
  def translate_error(error, :trading) do
    case error do
      # User management errors
      {:error, :invalid_user_id_format} ->
        create_error(:invalid_user_id, :validation, "Invalid user ID format", [
          "User ID must be 3-32 characters long",
          "Use alphanumeric characters, underscores, and hyphens only",
          "Avoid special characters and spaces"
        ])
        
      {:error, :invalid_credentials_format} ->
        create_error(:invalid_credentials, :validation, "Invalid API credentials format", [
          "API key and secret must be 32-128 characters long",
          "Use only alphanumeric characters",
          "Check your Binance API credentials"
        ])
        
      {:error, :user_manager_down} ->
        create_error(:service_unavailable, :service, "User management service unavailable", [
          "Try again in a few moments",
          "Check system status",
          "Contact support if the issue persists"
        ])
        
      {:error, :user_already_exists} ->
        create_error(:user_already_connected, :business_logic, "User session already active", [
          "Disconnect the existing session first",
          "Use a different user ID",
          "Check if another process is using this user ID"
        ])
        
      {:error, :user_not_found} ->
        create_error(:user_not_connected, :business_logic, "User session not found", [
          "Connect the user first using connect_user/3",
          "Check that the user ID is correct",
          "Verify the user hasn't been disconnected"
        ])
        
      {:error, :max_users_reached} ->
        create_error(:user_limit_exceeded, :business_logic, "Maximum user connections reached", [
          "Disconnect inactive users first",
          "Try again later when capacity is available",
          "Contact support to increase user limits"
        ])
        
      {:error, :credential_validation_failed} ->
        create_error(:authentication_failed, :authentication, "Binance API credentials rejected", [
          "Verify your API key and secret are correct",
          "Check that API permissions are enabled",
          "Ensure credentials haven't expired"
        ])
        
      {:error, :disconnect_timeout} ->
        create_error(:disconnect_timeout, :system, "User disconnection timed out", [
          "The user session may still be terminating",
          "Wait a moment before reconnecting",
          "Contact support if the issue persists"
        ])

      # Order management errors
      {:error, :invalid_order_params_format} ->
        create_error(:invalid_order_params, :validation, "Invalid order parameters format", [
          "Ensure all required fields are provided",
          "Check parameter types and formats",
          "Review the API documentation for correct format"
        ])
        
      {:error, {:missing_required_fields, fields}} ->
        create_error(:invalid_order_params, :validation, "Missing required order fields: #{inspect(fields)}", [
          "Provide all required fields: symbol, side, type, quantity",
          "Ensure fields are not null or empty",
          "Check the order type requirements"
        ])
        
      {:error, :invalid_side_format} ->
        create_error(:invalid_side, :validation, "Invalid order side", [
          "Order side must be 'BUY' or 'SELL'",
          "Use uppercase values only",
          "Check for typos in the side parameter"
        ])
        
      {:error, :invalid_type_format} ->
        create_error(:invalid_type, :validation, "Invalid order type", [
          "Use valid order types: LIMIT, MARKET, STOP_LOSS, etc.",
          "Check the supported order types in documentation",
          "Ensure uppercase formatting"
        ])
        
      {:error, :invalid_quantity_format} ->
        create_error(:invalid_quantity, :validation, "Invalid quantity format", [
          "Quantity must be a positive numeric string",
          "Use decimal format (e.g., '0.001', '1.5')",
          "Avoid scientific notation or negative values"
        ])
        
      {:error, :invalid_price_format} ->
        create_error(:invalid_price, :validation, "Invalid price format", [
          "Price must be a positive numeric string",
          "Use decimal format (e.g., '50000', '1234.56')",
          "Required for LIMIT orders"
        ])
        
      {:error, :price_required_for_limit_orders} ->
        create_error(:invalid_order_params, :validation, "Price required for LIMIT orders", [
          "Provide a price parameter for LIMIT orders",
          "Use MARKET order type if no price is desired",
          "Ensure price is a positive numeric string"
        ])
        
      {:error, :insufficient_balance} ->
        create_error(:insufficient_funds, :business_logic, "Insufficient account balance", [
          "Check your account balance",
          "Reduce the order quantity or price",
          "Ensure you have enough funds for fees"
        ])
        
      {:error, :min_notional_not_met} ->
        create_error(:minimum_notional_not_met, :business_logic, "Order value below minimum notional", [
          "Increase order quantity or price",
          "Check minimum order value requirements",
          "Review exchange trading rules for this symbol"
        ])
        
      {:error, :price_filter_fail} ->
        create_error(:price_filter_violation, :business_logic, "Price violates exchange filters", [
          "Check the symbol's price filters",
          "Adjust price to meet tick size requirements",
          "Review exchange trading rules"
        ])
        
      {:error, :lot_size_filter_fail} ->
        create_error(:quantity_filter_violation, :business_logic, "Quantity violates lot size filters", [
          "Check the symbol's lot size filters",
          "Adjust quantity to meet step size requirements",
          "Use valid quantity increments"
        ])
        
      {:error, :trading_disabled} ->
        create_error(:market_closed, :business_logic, "Trading disabled for symbol", [
          "Check if the symbol is currently tradable",
          "Try again during trading hours",
          "Verify the symbol is not delisted"
        ])

      # Order cancellation errors
      {:error, :invalid_order_id_format} ->
        create_error(:invalid_order_id, :validation, "Invalid order ID format", [
          "Provide a valid order ID or client order ID",
          "Check that the order ID is not empty",
          "Ensure proper string format"
        ])
        
      {:error, :order_does_not_exist} ->
        create_error(:order_not_found, :business_logic, "Order not found", [
          "Check that the order ID is correct",
          "Order may have been filled or expired",
          "Verify you have permission to access this order"
        ])
        
      {:error, :order_filled} ->
        create_error(:order_not_cancellable, :business_logic, "Order already filled", [
          "Order has been completely executed",
          "Check order status before cancellation",
          "Cannot cancel filled orders"
        ])
        
      {:error, :order_cancelled} ->
        create_error(:order_not_found, :business_logic, "Order already cancelled", [
          "Order was previously cancelled",
          "Check order status",
          "No action needed"
        ])
        
      {:error, :order_expired} ->
        create_error(:order_not_cancellable, :business_logic, "Order has expired", [
          "Order expired due to time constraints",
          "Cannot cancel expired orders",
          "Check order time in force settings"
        ])

      # Balance and orders query errors
      {:error, :invalid_options_format} ->
        create_error(:invalid_options, :validation, "Invalid query options format", [
          "Ensure options is a map with valid keys",
          "Check option types and values",
          "Review API documentation for valid options"
        ])
        
      {:error, :invalid_option_types} ->
        create_error(:invalid_options, :validation, "Invalid option types", [
          "Check that boolean options are true/false",
          "Ensure numeric options are integers",
          "Verify string options are properly formatted"
        ])
        
      {:error, :invalid_asset_filter_format} ->
        create_error(:invalid_asset_filter, :validation, "Invalid asset filter", [
          "Asset filter must be a valid asset symbol",
          "Use uppercase letters and numbers only",
          "Examples: 'BTC', 'ETH', 'USDT'"
        ])
        
      {:error, :invalid_status_format} ->
        create_error(:invalid_status, :validation, "Invalid order status filter", [
          "Use valid status values: NEW, FILLED, CANCELED, etc.",
          "Check uppercase formatting",
          "Review supported order statuses"
        ])
        
      {:error, :invalid_limit_format} ->
        create_error(:invalid_limit, :validation, "Invalid result limit", [
          "Limit must be between 1 and 1000",
          "Use integer values only",
          "Default limit is 500 if not specified"
        ])
        
      {:error, :invalid_time_range} ->
        create_error(:invalid_time_range, :validation, "Invalid time range", [
          "Start time must be before end time",
          "Use valid DateTime or timestamp values",
          "Check time format and values"
        ])

      # API and service errors
      {:error, :rate_limit} ->
        create_error(:rate_limit_exceeded, :rate_limit, "API rate limit exceeded", [
          "Reduce API call frequency",
          "Wait before making additional requests",
          "Consider using WebSocket streams for real-time data"
        ])
        
      {:error, :order_rate_limit} ->
        create_error(:rate_limit_exceeded, :rate_limit, "Order rate limit exceeded", [
          "Reduce order placement frequency",
          "Wait before placing additional orders",
          "Check exchange order rate limits"
        ])
        
      {:error, :server_error} ->
        create_error(:service_unavailable, :service, "Exchange server error", [
          "Try again in a few moments",
          "Check exchange status page",
          "Contact support if the issue persists"
        ])
        
      {:error, :network_error} ->
        create_error(:service_unavailable, :network, "Network connection error", [
          "Check your internet connection",
          "Verify firewall settings",
          "Try again in a few moments"
        ])
        
      {:error, :connection_failed} ->
        create_error(:service_unavailable, :network, "Failed to connect to exchange", [
          "Check network connectivity",
          "Verify exchange API endpoints",
          "Try again later"
        ])

      # Generic fallback
      _ ->
        log_unknown_error(error, :trading)
        create_error(:service_unavailable, :system, "An unexpected error occurred", [
          "Try again in a few moments",
          "Check system status",
          "Contact support with error details if the issue persists"
        ])
    end
  end

  @doc """
  Creates a standardized error response with comprehensive information.
  """
  @spec create_error(atom(), atom(), String.t(), [String.t()]) :: {:error, atom()} | {:error, map()}
  def create_error(reason, category, message, suggestions, opts \\ []) do
    include_details = Keyword.get(opts, :include_details, false)
    # Default to logging unless explicitly disabled or in test environment
    default_log = not (Mix.env() == :test)
    log_error = Keyword.get(opts, :log_error, default_log)
    severity = Keyword.get(opts, :severity, :error)
    
    if log_error do
      log_api_error(reason, category, message, severity)
    end
    
    if include_details do
      {:error, %{
        reason: reason,
        category: Map.get(@error_categories, category, "Unknown"),
        message: Validation.sanitize_string(message),
        suggestions: Enum.map(suggestions, &Validation.sanitize_string/1),
        severity: Map.get(@error_severities, severity, "Error"),
        timestamp: DateTime.utc_now(),
        error_code: generate_error_code(reason, category)
      }}
    else
      {:error, reason}
    end
  end

  @doc """
  Creates a detailed error response for debugging and development.
  
  Used in development/testing environments to provide comprehensive error information.
  """
  @spec create_detailed_error(atom(), atom(), String.t(), [String.t()], map()) :: {:error, map()}
  def create_detailed_error(reason, category, message, suggestions, context \\ %{}) do
    {:error, %{
      reason: reason,
      category: Map.get(@error_categories, category, "Unknown"),
      message: Validation.sanitize_string(message),
      suggestions: Enum.map(suggestions, &Validation.sanitize_string/1),
      context: sanitize_context(context),
      timestamp: DateTime.utc_now(),
      error_code: generate_error_code(reason, category),
      documentation_url: generate_docs_url(reason),
      support_reference: generate_support_reference()
    }}
  end

  @doc """
  Validates if an error response is in the correct format.
  """
  @spec validate_error_format(any()) :: boolean()
  def validate_error_format({:error, reason}) when is_atom(reason), do: true
  def validate_error_format({:error, %{reason: reason}}) when is_atom(reason), do: true
  def validate_error_format(_), do: false

  @doc """
  Extracts error reason from various error formats.
  """
  @spec extract_error_reason(any()) :: atom() | nil
  def extract_error_reason({:error, reason}) when is_atom(reason), do: reason
  def extract_error_reason({:error, %{reason: reason}}) when is_atom(reason), do: reason
  def extract_error_reason(_), do: nil

  @doc """
  Gets human-readable error description for a given error reason.
  """
  @spec get_error_description(atom()) :: String.t()
  def get_error_description(reason) do
    case reason do
      :invalid_symbol -> "The provided symbol format is invalid"
      :invalid_user_id -> "The user ID format is invalid"
      :invalid_credentials -> "The API credentials format is invalid"
      :user_not_connected -> "User session is not active"
      :user_already_connected -> "User session already exists"
      :insufficient_funds -> "Account balance is insufficient for this operation"
      :rate_limit_exceeded -> "API rate limit has been exceeded"
      :service_unavailable -> "Service is temporarily unavailable"
      _ -> "An error occurred during the operation"
    end
  end

  @doc """
  Gets error category for a given error reason.
  """
  @spec get_error_category(atom()) :: atom()
  def get_error_category(reason) do
    case reason do
      r when r in [:invalid_symbol, :invalid_user_id, :invalid_credentials, :invalid_order_params,
                   :invalid_quantity, :invalid_price, :invalid_options] -> :validation
      r when r in [:authentication_failed] -> :authentication
      r when r in [:user_not_connected, :user_already_connected, :insufficient_funds,
                   :minimum_notional_not_met, :order_not_found] -> :business_logic
      r when r in [:rate_limit_exceeded] -> :rate_limit
      r when r in [:service_unavailable, :connection_failed] -> :service
      _ -> :system
    end
  end

  # Private helper functions

  # Logs unknown errors for monitoring and debugging
  defp log_unknown_error(error, api_type) do
    # Only log in non-test environments
    unless Mix.env() == :test do
      Logger.warning("Unknown error in #{api_type} API", 
        error: inspect(error),
        api_type: api_type,
        module: __MODULE__
      )
    end
  end

  # Logs API errors for monitoring
  defp log_api_error(reason, category, message, severity) do
    log_level = case severity do
      :critical -> :error
      :error -> :error
      :warning -> :warning
      :info -> :info
      _ -> :warning
    end
    
    Logger.log(log_level, "API error occurred",
      reason: reason,
      category: category,
      message: message,
      severity: severity,
      module: __MODULE__
    )
  end

  # Generates unique error code for tracking
  defp generate_error_code(reason, category) do
    category_code = case category do
      :validation -> "VAL"
      :authentication -> "AUTH"
      :business_logic -> "BIZ"
      :service -> "SVC"
      :rate_limit -> "RATE"
      :network -> "NET"
      :system -> "SYS"
      _ -> "UNK"
    end
    
    reason_hash = :crypto.hash(:md5, Atom.to_string(reason))
                  |> Base.encode16()
                  |> String.slice(0, 8)
                  
    "#{category_code}-#{reason_hash}"
  end

  # Generates documentation URL for error resolution
  defp generate_docs_url(reason) do
    base_url = "https://docs.crypto-exchange.example.com/errors"
    "#{base_url}##{reason}"
  end

  # Generates support reference for error tracking
  defp generate_support_reference do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :rand.uniform(999999) |> Integer.to_string() |> String.pad_leading(6, "0")
    "REF-#{timestamp}-#{random}"
  end

  # Sanitizes context map for safe logging
  defp sanitize_context(context) when is_map(context) do
    context
    |> Enum.map(fn {k, v} -> {k, sanitize_context_value(v)} end)
    |> Enum.into(%{})
  end
  defp sanitize_context(_), do: %{}

  # Sanitizes individual context values
  defp sanitize_context_value(value) when is_binary(value) do
    Validation.sanitize_string(value)
  end
  defp sanitize_context_value(value) when is_atom(value) or is_number(value) do
    value
  end
  defp sanitize_context_value(_), do: "[sanitized]"
end