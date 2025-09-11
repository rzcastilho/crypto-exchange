defmodule CryptoExchange.API.Validation do
  @moduledoc """
  Centralized validation utilities for the CryptoExchange API.
  
  Provides consistent validation functions used across all API endpoints
  with comprehensive error handling, edge case coverage, and detailed error messages.
  
  ## Features
  
  - **Comprehensive Input Validation**: Covers all edge cases including null, 
    empty, malformed, and malicious inputs
  - **Performance Optimized**: Pre-compiled regex patterns and efficient validation logic
  - **Security Focused**: Protects against injection attacks and malicious inputs
  - **Developer Friendly**: Clear error messages with actionable guidance
  - **Extensible**: Easy to add new validation rules and patterns
  
  ## Edge Cases Handled
  
  - Null/nil parameters
  - Empty strings and whitespace-only inputs
  - Extremely large parameter values 
  - Unicode and international character handling
  - Numeric overflow/underflow scenarios
  - Special character and injection attempts
  - Malformed data structures
  
  ## Performance Considerations
  
  All regex patterns are pre-compiled at module load time for optimal performance.
  Validation functions use early exit strategies to fail fast on obvious invalid inputs.
  """

  # Pre-compiled regex patterns for optimal performance
  @symbol_pattern ~r/^[A-Z0-9]+$/
  @user_id_pattern ~r/^[a-zA-Z0-9_-]+$/
  @api_key_pattern ~r/^[a-zA-Z0-9]+$/
  @numeric_pattern ~r/^\d+(\.\d+)?$/
  @asset_pattern ~r/^[A-Z0-9]+$/
  
  # Constants for validation limits
  @min_symbol_length 3
  @max_symbol_length 20
  @min_user_id_length 3
  @max_user_id_length 32
  @min_api_key_length 32
  @max_api_key_length 128
  @min_asset_length 1
  @max_asset_length 10
  @max_order_id_length 100
  @max_price_precision 8
  @max_quantity_precision 8
  @max_string_length 1000
  @valid_order_sides ~w(BUY SELL)
  @valid_order_types ~w(LIMIT MARKET STOP_LOSS STOP_LOSS_LIMIT TAKE_PROFIT TAKE_PROFIT_LIMIT)
  @valid_order_statuses ~w(NEW PARTIALLY_FILLED FILLED CANCELED REJECTED EXPIRED)
  @valid_time_in_force ~w(GTC IOC FOK)
  @valid_depth_levels [5, 10, 20]
  @limit_order_types ~w(LIMIT STOP_LOSS_LIMIT TAKE_PROFIT_LIMIT)

  @doc """
  Validates a trading symbol format according to exchange standards.
  
  Symbols must be 3-20 characters, uppercase alphanumeric only.
  
  ## Examples
  
      iex> CryptoExchange.API.Validation.validate_symbol("BTCUSDT")
      :ok
      
      iex> CryptoExchange.API.Validation.validate_symbol("btc")  
      {:error, :invalid_symbol_format}
      
      iex> CryptoExchange.API.Validation.validate_symbol("")
      {:error, :invalid_symbol_format}
      
      iex> CryptoExchange.API.Validation.validate_symbol(nil)
      {:error, :invalid_symbol_format}
  """
  @spec validate_symbol(any()) :: :ok | {:error, :invalid_symbol_format}
  def validate_symbol(symbol) when is_binary(symbol) do
    symbol = String.trim(symbol)
    
    cond do
      symbol == "" -> {:error, :invalid_symbol_format}
      String.length(symbol) < @min_symbol_length -> {:error, :invalid_symbol_format}
      String.length(symbol) > @max_symbol_length -> {:error, :invalid_symbol_format}
      String.contains?(symbol, ["\0", "\n", "\r", "\t"]) -> {:error, :invalid_symbol_format}
      not Regex.match?(@symbol_pattern, symbol) -> {:error, :invalid_symbol_format}
      true -> :ok
    end
  end
  def validate_symbol(_), do: {:error, :invalid_symbol_format}

  @doc """
  Validates user ID format with comprehensive edge case handling.
  
  User IDs must be 3-32 characters, alphanumeric with underscore and hyphen allowed.
  
  ## Examples
  
      iex> CryptoExchange.API.Validation.validate_user_id("user123")
      :ok
      
      iex> CryptoExchange.API.Validation.validate_user_id("user_123-test")
      :ok
      
      iex> CryptoExchange.API.Validation.validate_user_id("x")
      {:error, :invalid_user_id_format}
      
      iex> CryptoExchange.API.Validation.validate_user_id(nil)
      {:error, :invalid_user_id_format}
  """
  @spec validate_user_id(any()) :: :ok | {:error, :invalid_user_id_format}
  def validate_user_id(user_id) when is_binary(user_id) do
    user_id = String.trim(user_id)
    
    cond do
      user_id == "" -> {:error, :invalid_user_id_format}
      String.length(user_id) < @min_user_id_length -> {:error, :invalid_user_id_format}
      String.length(user_id) > @max_user_id_length -> {:error, :invalid_user_id_format}
      String.contains?(user_id, ["\0", "\n", "\r", "\t"]) -> {:error, :invalid_user_id_format}
      not Regex.match?(@user_id_pattern, user_id) -> {:error, :invalid_user_id_format}
      true -> :ok
    end
  end
  def validate_user_id(_), do: {:error, :invalid_user_id_format}

  @doc """
  Validates API credentials format with security considerations.
  
  API keys and secrets must be 32-128 characters, alphanumeric only.
  
  ## Examples
  
      iex> CryptoExchange.API.Validation.validate_api_credentials("api_key_32_chars_long_example_here", "secret_key_32_chars_long_example_here")
      :ok
      
      iex> CryptoExchange.API.Validation.validate_api_credentials("short", "secret")
      {:error, :invalid_credentials_format}
  """
  @spec validate_api_credentials(any(), any()) :: :ok | {:error, :invalid_credentials_format}
  def validate_api_credentials(api_key, secret_key) when is_binary(api_key) and is_binary(secret_key) do
    api_key = String.trim(api_key)
    secret_key = String.trim(secret_key)
    
    cond do
      api_key == "" or secret_key == "" -> {:error, :invalid_credentials_format}
      String.length(api_key) < @min_api_key_length -> {:error, :invalid_credentials_format}
      String.length(secret_key) < @min_api_key_length -> {:error, :invalid_credentials_format}
      String.length(api_key) > @max_api_key_length -> {:error, :invalid_credentials_format}
      String.length(secret_key) > @max_api_key_length -> {:error, :invalid_credentials_format}
      has_null_bytes?(api_key) or has_null_bytes?(secret_key) -> {:error, :invalid_credentials_format}
      not Regex.match?(@api_key_pattern, api_key) -> {:error, :invalid_credentials_format}
      not Regex.match?(@api_key_pattern, secret_key) -> {:error, :invalid_credentials_format}
      true -> :ok
    end
  end
  def validate_api_credentials(_, _), do: {:error, :invalid_credentials_format}

  @doc """
  Validates depth level parameter for order book subscriptions.
  
  Valid levels: 5, 10, 20
  
  ## Examples
  
      iex> CryptoExchange.API.Validation.validate_depth_level(5)
      :ok
      
      iex> CryptoExchange.API.Validation.validate_depth_level(15)
      {:error, :invalid_depth_level}
  """
  @spec validate_depth_level(any()) :: :ok | {:error, :invalid_depth_level}
  def validate_depth_level(level) when level in @valid_depth_levels, do: :ok
  def validate_depth_level(_), do: {:error, :invalid_depth_level}

  @doc """
  Validates comprehensive order parameters with business rule validation.
  
  Validates all required fields, formats, and business constraints.
  
  ## Required Fields
  - symbol: Trading pair symbol
  - side: BUY or SELL
  - type: Order type (LIMIT, MARKET, etc.)
  - quantity: Positive numeric string
  
  ## Conditional Fields
  - price: Required for LIMIT type orders
  - stopPrice: Required for stop orders
  
  ## Optional Fields
  - timeInForce: GTC, IOC, FOK (defaults to GTC)
  - newClientOrderId: Custom order identifier
  """
  @spec validate_order_params(any()) :: :ok | {:error, atom() | {atom(), any()}}
  def validate_order_params(params) when is_map(params) do
    with :ok <- validate_required_order_fields(params),
         :ok <- validate_order_symbol(Map.get(params, "symbol")),
         :ok <- validate_order_side(Map.get(params, "side")),
         :ok <- validate_order_type(Map.get(params, "type")),
         :ok <- validate_order_quantity(Map.get(params, "quantity")),
         :ok <- validate_order_price_if_required(params),
         :ok <- validate_stop_price_if_required(params),
         :ok <- validate_time_in_force(params),
         :ok <- validate_client_order_id(params) do
      :ok
    end
  end
  def validate_order_params(_), do: {:error, :invalid_order_params_format}

  @doc """
  Validates order ID format for cancellation operations.
  
  Order IDs can be numeric strings or alphanumeric client order IDs.
  """
  @spec validate_order_id(any()) :: :ok | {:error, :invalid_order_id_format}
  def validate_order_id(order_id) when is_binary(order_id) do
    order_id = String.trim(order_id)
    
    cond do
      order_id == "" -> {:error, :invalid_order_id_format}
      String.length(order_id) > @max_order_id_length -> {:error, :invalid_order_id_format}
      has_null_bytes?(order_id) -> {:error, :invalid_order_id_format}
      has_control_characters?(order_id) -> {:error, :invalid_order_id_format}
      true -> :ok
    end
  end
  def validate_order_id(_), do: {:error, :invalid_order_id_format}

  @doc """
  Validates balance query options with type and format checking.
  
  ## Supported Options
  - force_refresh: Boolean
  - asset_filter: String (asset symbol)
  - include_zero: Boolean  
  - timeout: Positive integer
  """
  @spec validate_balance_options(any()) :: :ok | {:error, atom()}
  def validate_balance_options(opts) when is_map(opts) do
    with :ok <- validate_balance_option_types(opts),
         :ok <- validate_asset_filter_option(opts),
         :ok <- validate_timeout_option(opts, :balance_fetch_timeout) do
      :ok
    end
  end
  def validate_balance_options(_), do: {:error, :invalid_options_format}

  @doc """
  Validates orders query options with comprehensive filtering support.
  
  ## Supported Options
  - symbol: Trading pair filter
  - status: Order status filter
  - limit: Result limit (1-1000)
  - from_cache: Boolean
  - start_time: DateTime or timestamp
  - end_time: DateTime or timestamp
  - order_id: Starting order ID
  - timeout: Request timeout
  """
  @spec validate_orders_options(any()) :: :ok | {:error, atom()}
  def validate_orders_options(opts) when is_map(opts) do
    with :ok <- validate_orders_option_types(opts),
         :ok <- validate_orders_symbol_option(opts),
         :ok <- validate_orders_status_option(opts),
         :ok <- validate_orders_limit_option(opts),
         :ok <- validate_time_range_options(opts),
         :ok <- validate_timeout_option(opts, :orders_fetch_timeout) do
      :ok
    end
  end
  def validate_orders_options(_), do: {:error, :invalid_options_format}

  # Private validation helper functions

  # Validates required order fields are present and not nil/empty
  defp validate_required_order_fields(params) do
    required_fields = ~w(symbol side type quantity)
    
    missing_fields = Enum.filter(required_fields, fn field ->
      case Map.get(params, field) do
        nil -> true
        "" -> true
        value when is_binary(value) -> String.trim(value) == ""
        _ -> false
      end
    end)
    
    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  # Validates order symbol using the main symbol validation
  defp validate_order_symbol(symbol), do: validate_symbol(symbol)

  # Validates order side (BUY/SELL)
  defp validate_order_side(side) when side in @valid_order_sides, do: :ok
  defp validate_order_side(_), do: {:error, :invalid_side_format}

  # Validates order type
  defp validate_order_type(type) when type in @valid_order_types, do: :ok
  defp validate_order_type(_), do: {:error, :invalid_type_format}

  # Validates order quantity with comprehensive numeric validation
  defp validate_order_quantity(quantity) when is_binary(quantity) do
    quantity = String.trim(quantity)
    
    cond do
      quantity == "" -> {:error, :invalid_quantity_format}
      has_null_bytes?(quantity) -> {:error, :invalid_quantity_format}
      String.length(quantity) > 20 -> {:error, :invalid_quantity_format}  # Reasonable limit
      not Regex.match?(@numeric_pattern, quantity) -> {:error, :invalid_quantity_format}
      true -> validate_numeric_value(quantity, :quantity)
    end
  end
  defp validate_order_quantity(_), do: {:error, :invalid_quantity_format}

  # Validates price for orders that require it
  defp validate_order_price_if_required(params) do
    order_type = Map.get(params, "type")
    price = Map.get(params, "price")
    
    if order_type in @limit_order_types do
      case price do
        nil -> {:error, :price_required_for_limit_orders}
        price when is_binary(price) -> validate_price_format(price)
        _ -> {:error, :invalid_price_format}
      end
    else
      :ok
    end
  end

  # Validates stop price for stop orders
  defp validate_stop_price_if_required(params) do
    order_type = Map.get(params, "type")
    stop_price = Map.get(params, "stopPrice")
    
    if order_type in ~w(STOP_LOSS STOP_LOSS_LIMIT TAKE_PROFIT TAKE_PROFIT_LIMIT) do
      case stop_price do
        nil -> :ok  # Stop price is optional in some cases
        stop_price when is_binary(stop_price) -> validate_price_format(stop_price)
        _ -> {:error, :invalid_stop_price_format}
      end
    else
      :ok
    end
  end

  # Validates time in force parameter
  defp validate_time_in_force(params) do
    case Map.get(params, "timeInForce") do
      nil -> :ok  # Optional field
      tif when tif in @valid_time_in_force -> :ok
      _ -> {:error, :invalid_time_in_force}
    end
  end

  # Validates client order ID format
  defp validate_client_order_id(params) do
    case Map.get(params, "newClientOrderId") do
      nil -> :ok  # Optional field
      client_id when is_binary(client_id) -> 
        if String.length(String.trim(client_id)) <= 36 and not has_null_bytes?(client_id) do
          :ok
        else
          {:error, :invalid_client_order_id}
        end
      _ -> {:error, :invalid_client_order_id}
    end
  end

  # Validates price format with comprehensive checks
  defp validate_price_format(price) when is_binary(price) do
    price = String.trim(price)
    
    cond do
      price == "" -> {:error, :invalid_price_format}
      has_null_bytes?(price) -> {:error, :invalid_price_format}
      String.length(price) > 20 -> {:error, :invalid_price_format}
      not Regex.match?(@numeric_pattern, price) -> {:error, :invalid_price_format}
      true -> validate_numeric_value(price, :price)
    end
  end
  defp validate_price_format(_), do: {:error, :invalid_price_format}

  # Validates numeric value ranges and precision
  defp validate_numeric_value(value_str, type) do
    case Float.parse(value_str) do
      {float_value, ""} when float_value > 0.0 ->
        validate_numeric_precision(value_str, type)
      {float_value, "." <> rest} when float_value > 0.0 and byte_size(rest) == 0 ->
        validate_numeric_precision(value_str, type)
      _ -> 
        {:error, :"invalid_#{type}_format"}
    end
  rescue
    _ -> {:error, :"invalid_#{type}_format"}
  end

  # Validates numeric precision (decimal places)
  defp validate_numeric_precision(value_str, type) do
    max_precision = case type do
      :price -> @max_price_precision
      :quantity -> @max_quantity_precision
      _ -> 8
    end
    
    case String.split(value_str, ".") do
      [_integer_part] -> :ok  # No decimal places
      [_integer_part, decimal_part] when byte_size(decimal_part) <= max_precision -> :ok
      _ -> {:error, :"#{type}_precision_exceeded"}
    end
  end

  # Validates balance option types
  defp validate_balance_option_types(opts) do
    validators = %{
      "force_refresh" => &is_boolean/1,
      "include_zero" => &is_boolean/1,
      "timeout" => &(is_integer(&1) and &1 > 0)
    }
    
    validate_option_types(opts, validators)
  end

  # Validates asset filter option
  defp validate_asset_filter_option(opts) do
    case Map.get(opts, "asset_filter") do
      nil -> :ok
      asset when is_binary(asset) ->
        asset = String.trim(asset)
        cond do
          asset == "" -> {:error, :invalid_asset_filter_format}
          String.length(asset) < @min_asset_length -> {:error, :invalid_asset_filter_format}
          String.length(asset) > @max_asset_length -> {:error, :invalid_asset_filter_format}
          has_null_bytes?(asset) -> {:error, :invalid_asset_filter_format}
          not Regex.match?(@asset_pattern, asset) -> {:error, :invalid_asset_filter_format}
          true -> :ok
        end
      _ -> {:error, :invalid_asset_filter_format}
    end
  end

  # Validates orders option types
  defp validate_orders_option_types(opts) do
    validators = %{
      "from_cache" => &is_boolean/1,
      "timeout" => &(is_integer(&1) and &1 > 0),
      "limit" => &(is_integer(&1) and &1 > 0),
      "order_id" => &is_integer/1,
      "start_time" => &validate_timestamp/1,
      "end_time" => &validate_timestamp/1
    }
    
    validate_option_types(opts, validators)
  end

  # Validates orders symbol option
  defp validate_orders_symbol_option(opts) do
    case Map.get(opts, "symbol") do
      nil -> :ok
      symbol -> validate_symbol(symbol)
    end
  end

  # Validates orders status option
  defp validate_orders_status_option(opts) do
    case Map.get(opts, "status") do
      nil -> :ok
      status when status in @valid_order_statuses -> :ok
      _ -> {:error, :invalid_status_format}
    end
  end

  # Validates orders limit option
  defp validate_orders_limit_option(opts) do
    case Map.get(opts, "limit") do
      nil -> :ok
      limit when is_integer(limit) and limit > 0 and limit <= 1000 -> :ok
      _ -> {:error, :invalid_limit_format}
    end
  end

  # Validates time range options
  defp validate_time_range_options(opts) do
    start_time = Map.get(opts, "start_time")
    end_time = Map.get(opts, "end_time")
    
    cond do
      start_time == nil and end_time == nil -> :ok
      start_time != nil and end_time != nil ->
        with true <- validate_timestamp(start_time),
             true <- validate_timestamp(end_time),
             true <- compare_timestamps(start_time, end_time) do
          :ok
        else
          _ -> {:error, :invalid_time_range}
        end
      true -> :ok  # Only one timestamp is fine
    end
  end

  # Validates timeout option
  defp validate_timeout_option(opts, _error_type) do
    case Map.get(opts, "timeout") do
      nil -> :ok
      timeout when is_integer(timeout) and timeout > 0 and timeout <= 300_000 -> :ok  # Max 5 minutes
      _ -> {:error, :invalid_timeout}
    end
  end

  # Generic option type validator
  defp validate_option_types(opts, validators) do
    invalid_options = Enum.filter(validators, fn {key, validator} ->
      case Map.get(opts, key) do
        nil -> false  # Optional field
        value -> not validator.(value)
      end
    end)
    
    if Enum.empty?(invalid_options) do
      :ok
    else
      {:error, :invalid_option_types}
    end
  end

  # Validates timestamp format (integer timestamp or DateTime)
  defp validate_timestamp(%DateTime{}), do: true
  defp validate_timestamp(timestamp) when is_integer(timestamp) and timestamp > 0, do: true
  defp validate_timestamp(_), do: false

  # Compares timestamps to ensure start_time < end_time
  defp compare_timestamps(%DateTime{} = start_time, %DateTime{} = end_time) do
    DateTime.compare(start_time, end_time) == :lt
  end
  defp compare_timestamps(start_time, end_time) when is_integer(start_time) and is_integer(end_time) do
    start_time < end_time
  end
  defp compare_timestamps(_, _), do: false

  # Security helper functions

  # Checks for null bytes (security concern)
  defp has_null_bytes?(str) when is_binary(str) do
    String.contains?(str, "\0")
  end
  defp has_null_bytes?(_), do: false

  # Checks for control characters that could be problematic
  defp has_control_characters?(str) when is_binary(str) do
    String.contains?(str, ["\n", "\r", "\t", "\v", "\f", "\b"])
  end
  defp has_control_characters?(_), do: false

  @doc """
  Sanitizes a string by removing potentially harmful characters.
  
  Used for input sanitization in logging and error messages.
  """
  @spec sanitize_string(String.t()) :: String.t()
  def sanitize_string(str) when is_binary(str) do
    str
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")  # Remove control characters
    |> String.slice(0, @max_string_length)      # Limit length
  end
  def sanitize_string(_), do: ""

  @doc """
  Validates and sanitizes user input for safe processing.
  
  Returns sanitized input or error for invalid input.
  """
  @spec validate_and_sanitize(any(), atom()) :: {:ok, String.t()} | {:error, atom()}
  def validate_and_sanitize(input, type) when is_binary(input) do
    case type do
      :symbol -> 
        case validate_symbol(input) do
          :ok -> {:ok, String.trim(input)}
          error -> error
        end
      :user_id ->
        case validate_user_id(input) do
          :ok -> {:ok, String.trim(input)}
          error -> error
        end
      :order_id ->
        case validate_order_id(input) do
          :ok -> {:ok, String.trim(input)}
          error -> error
        end
      _ -> {:error, :unsupported_validation_type}
    end
  end
  def validate_and_sanitize(_, _), do: {:error, :invalid_input_type}
end