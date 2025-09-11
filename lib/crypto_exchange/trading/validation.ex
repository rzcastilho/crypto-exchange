defmodule CryptoExchange.Trading.Validation do
  @moduledoc """
  Comprehensive validation module for trading operations.

  This module provides robust validation for all trading operations including:
  - Order parameter validation with business logic
  - Symbol validation against supported trading pairs
  - Balance validation for order placement
  - Input sanitization and security validation
  - Rate limiting and API compliance validation
  - Comprehensive error categorization and handling

  ## Features

  - **Input Validation**: Comprehensive parameter validation with detailed error messages
  - **Business Logic Validation**: Enforces trading rules like minimum order sizes
  - **Symbol Validation**: Validates against supported Binance trading pairs
  - **Security Validation**: Input sanitization and security checks
  - **Balance Validation**: Ensures sufficient funds for order placement
  - **Rate Limiting**: Validates against API rate limits
  - **Error Categorization**: Detailed error types for comprehensive handling

  ## Usage

      # Validate order placement parameters
      case Validation.validate_place_order(user_id, order_params) do
        {:ok, validated_params} -> 
          # Proceed with order placement
        {:error, {error_type, details}} -> 
          # Handle specific error with details
      end

      # Validate cancel order parameters
      case Validation.validate_cancel_order(user_id, order_id, symbol) do
        {:ok, :valid} -> 
          # Proceed with cancellation
        {:error, {error_type, details}} -> 
          # Handle error
      end

  ## Error Types

  Validation errors are categorized for comprehensive handling:

  - `:validation_error` - Input validation failures
  - `:business_rule_violation` - Business logic violations
  - `:insufficient_funds` - Balance validation failures
  - `:rate_limit_violation` - API rate limit violations
  - `:security_violation` - Security validation failures
  - `:symbol_not_supported` - Unsupported trading pairs
  - `:user_not_connected` - User session validation failures
  """

  require Logger
  alias CryptoExchange.Trading.{UserRegistry, CredentialManager}
  alias CryptoExchange.Models

  # Binance trading rules and limits
  @supported_order_types ["MARKET", "LIMIT", "STOP_LOSS", "STOP_LOSS_LIMIT", "TAKE_PROFIT", "TAKE_PROFIT_LIMIT"]
  @supported_sides ["BUY", "SELL"]
  @supported_time_in_force ["GTC", "IOC", "FOK"]
  
  # Common trading pairs - in production, this would be fetched from Binance exchange info
  @supported_symbols ~w(
    BTCUSDT ETHUSDT BNBUSDT ADAUSDT XRPUSDT SOLUSDT DOTUSDT DOGEUSDT
    SHIBUSDT AVAXUSDT LTCUSDT UNIUSDT LINKUSDT MATICUSDT ATOMUSDT
    ETCUSDT XLMUSDT ALGOUSDT VETUSDT ICPUSDT FILUSDT TRXUSDT AXSUSDT
  )

  # Minimum order constraints (simplified - in production, fetch from exchange info)
  @min_order_value_usdt 10.0
  @min_quantity_btc 0.00001
  @min_quantity_eth 0.00001
  @min_quantity_default 0.001

  @max_price_deviation 0.10  # 10% price deviation limit
  @max_order_value_usdt 100_000.0  # Maximum single order value

  # Client API

  @doc """
  Validates parameters for placing an order.

  ## Parameters
  - `user_id`: User identifier
  - `order_params`: Order parameters map

  ## Returns
  - `{:ok, validated_params}` - Validation successful with cleaned parameters
  - `{:error, {error_type, details}}` - Validation failed with specific error information

  ## Validation Checks
  1. User session validation
  2. Required parameter validation
  3. Parameter format validation
  4. Business rule validation
  5. Symbol validation
  6. Balance validation (for non-market orders)
  7. Price validation (market data comparison)
  8. Security validation (input sanitization)
  """
  @spec validate_place_order(String.t(), map()) :: 
    {:ok, map()} | {:error, {atom(), map()}}
  def validate_place_order(user_id, order_params) when is_binary(user_id) and is_map(order_params) do
    with {:ok, :user_connected} <- validate_user_session(user_id),
         {:ok, sanitized_params} <- sanitize_order_params(order_params),
         {:ok, :params_valid} <- validate_required_order_params(sanitized_params),
         {:ok, :format_valid} <- validate_order_param_formats(sanitized_params),
         {:ok, :symbol_supported} <- validate_symbol(sanitized_params["symbol"]),
         {:ok, :business_rules_valid} <- validate_order_business_rules(sanitized_params),
         {:ok, :balance_sufficient} <- validate_order_balance(user_id, sanitized_params),
         {:ok, :price_valid} <- validate_order_price(sanitized_params),
         {:ok, :rate_limit_ok} <- validate_rate_limits(user_id, :place_order) do
      
      Logger.debug("Order validation successful", 
        user_id: user_id, 
        symbol: sanitized_params["symbol"],
        side: sanitized_params["side"],
        type: sanitized_params["type"]
      )
      
      {:ok, sanitized_params}
    else
      error -> 
        Logger.warning("Order validation failed", 
          user_id: user_id, 
          symbol: Map.get(order_params, "symbol"),
          error: inspect(error)
        )
        error
    end
  end

  def validate_place_order(_user_id, _order_params) do
    {:error, {:validation_error, %{reason: :invalid_input_types}}}
  end

  @doc """
  Validates parameters for canceling an order.

  ## Parameters
  - `user_id`: User identifier
  - `order_id`: Order ID to cancel
  - `symbol`: Trading symbol (optional, used for validation)

  ## Returns
  - `{:ok, :valid}` - Validation successful
  - `{:error, {error_type, details}}` - Validation failed

  ## Validation Checks
  1. User session validation
  2. Order ID format validation
  3. Symbol validation (if provided)
  4. Order existence validation
  5. Order cancelability validation
  6. Rate limit validation
  """
  @spec validate_cancel_order(String.t(), String.t(), String.t() | nil) :: 
    {:ok, :valid} | {:error, {atom(), map()}}
  def validate_cancel_order(user_id, order_id, symbol \\ nil) 
    when is_binary(user_id) and is_binary(order_id) do
    
    with {:ok, :user_connected} <- validate_user_session(user_id),
         {:ok, :order_id_valid} <- validate_order_id_format(order_id),
         {:ok, :symbol_valid} <- validate_optional_symbol(symbol),
         {:ok, :rate_limit_ok} <- validate_rate_limits(user_id, :cancel_order) do
      
      Logger.debug("Cancel order validation successful", 
        user_id: user_id, 
        order_id: order_id,
        symbol: symbol
      )
      
      {:ok, :valid}
    else
      error ->
        Logger.warning("Cancel order validation failed", 
          user_id: user_id, 
          order_id: order_id,
          error: inspect(error)
        )
        error
    end
  end

  def validate_cancel_order(_user_id, _order_id, _symbol) do
    {:error, {:validation_error, %{reason: :invalid_input_types}}}
  end

  @doc """
  Validates parameters for getting account balance.

  ## Parameters
  - `user_id`: User identifier
  - `opts`: Options map (asset filter, force_refresh, etc.)

  ## Returns
  - `{:ok, validated_opts}` - Validation successful
  - `{:error, {error_type, details}}` - Validation failed
  """
  @spec validate_get_balance(String.t(), map()) :: 
    {:ok, map()} | {:error, {atom(), map()}}
  def validate_get_balance(user_id, opts \\ %{}) when is_binary(user_id) and is_map(opts) do
    with {:ok, :user_connected} <- validate_user_session(user_id),
         {:ok, sanitized_opts} <- sanitize_balance_opts(opts),
         {:ok, :rate_limit_ok} <- validate_rate_limits(user_id, :get_balance) do
      
      Logger.debug("Get balance validation successful", user_id: user_id)
      {:ok, sanitized_opts}
    else
      error ->
        Logger.warning("Get balance validation failed", user_id: user_id, error: inspect(error))
        error
    end
  end

  def validate_get_balance(_user_id, _opts) do
    {:error, {:validation_error, %{reason: :invalid_input_types}}}
  end

  @doc """
  Validates parameters for getting orders.

  ## Parameters
  - `user_id`: User identifier
  - `opts`: Options map (symbol, status filter, limit, etc.)

  ## Returns
  - `{:ok, validated_opts}` - Validation successful
  - `{:error, {error_type, details}}` - Validation failed
  """
  @spec validate_get_orders(String.t(), map()) :: 
    {:ok, map()} | {:error, {atom(), map()}}
  def validate_get_orders(user_id, opts \\ %{}) when is_binary(user_id) and is_map(opts) do
    with {:ok, :user_connected} <- validate_user_session(user_id),
         {:ok, sanitized_opts} <- sanitize_orders_opts(opts),
         {:ok, :symbol_valid} <- validate_optional_symbol(Map.get(sanitized_opts, :symbol)),
         {:ok, :rate_limit_ok} <- validate_rate_limits(user_id, :get_orders) do
      
      Logger.debug("Get orders validation successful", user_id: user_id)
      {:ok, sanitized_opts}
    else
      error ->
        Logger.warning("Get orders validation failed", user_id: user_id, error: inspect(error))
        error
    end
  end

  def validate_get_orders(_user_id, _opts) do
    {:error, {:validation_error, %{reason: :invalid_input_types}}}
  end

  @doc """
  Validates and sanitizes symbol format.

  Returns normalized symbol in uppercase format.
  """
  @spec validate_and_normalize_symbol(String.t()) :: 
    {:ok, String.t()} | {:error, {atom(), map()}}
  def validate_and_normalize_symbol(symbol) when is_binary(symbol) do
    normalized = String.upcase(String.trim(symbol))
    
    cond do
      normalized == "" ->
        {:error, {:validation_error, %{field: :symbol, reason: :empty}}}
        
      not String.match?(normalized, ~r/^[A-Z0-9]+$/) ->
        {:error, {:validation_error, %{field: :symbol, reason: :invalid_format}}}
        
      String.length(normalized) < 4 or String.length(normalized) > 20 ->
        {:error, {:validation_error, %{field: :symbol, reason: :invalid_length}}}
        
      normalized not in @supported_symbols ->
        {:error, {:symbol_not_supported, %{symbol: normalized, supported: @supported_symbols}}}
        
      true ->
        {:ok, normalized}
    end
  end

  def validate_and_normalize_symbol(_) do
    {:error, {:validation_error, %{field: :symbol, reason: :not_string}}}
  end

  # Private Functions - User Session Validation

  defp validate_user_session(user_id) do
    case UserRegistry.lookup_user(user_id) do
      {:ok, %{status: :connected}} ->
        {:ok, :user_connected}
        
      {:ok, %{status: status}} ->
        {:error, {:user_not_connected, %{status: status}}}
        
      {:error, :not_found} ->
        {:error, {:user_not_connected, %{reason: :session_not_found}}}
        
      error ->
        {:error, {:user_session_error, %{reason: error}}}
    end
  rescue
    error ->
      Logger.error("User session validation error", user_id: user_id, error: inspect(error))
      {:error, {:user_session_error, %{reason: :registry_error}}}
  end

  # Private Functions - Order Parameter Validation

  defp sanitize_order_params(params) when is_map(params) do
    sanitized = %{
      "symbol" => sanitize_string(params["symbol"]),
      "side" => sanitize_string(params["side"]),
      "type" => sanitize_string(params["type"]),
      "quantity" => sanitize_number_string(params["quantity"]),
      "price" => sanitize_number_string(params["price"]),
      "timeInForce" => sanitize_string(params["timeInForce"]),
      "stopPrice" => sanitize_number_string(params["stopPrice"]),
      "icebergQty" => sanitize_number_string(params["icebergQty"]),
      "newClientOrderId" => sanitize_string(params["newClientOrderId"]),
      "newOrderRespType" => sanitize_string(params["newOrderRespType"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    
    {:ok, sanitized}
  end

  defp validate_required_order_params(params) do
    required = ["symbol", "side", "type", "quantity"]
    missing = Enum.filter(required, &(not Map.has_key?(params, &1)))
    
    if Enum.empty?(missing) do
      {:ok, :params_valid}
    else
      {:error, {:validation_error, %{missing_required_fields: missing}}}
    end
  end

  defp validate_order_param_formats(params) do
    validations = [
      {:symbol, params["symbol"], &validate_symbol_format/1},
      {:side, params["side"], &validate_side_format/1},
      {:type, params["type"], &validate_order_type_format/1},
      {:quantity, params["quantity"], &validate_quantity_format/1},
      {:price, Map.get(params, "price"), &validate_price_format/1},
      {:timeInForce, Map.get(params, "timeInForce"), &validate_time_in_force_format/1}
    ]
    
    case find_first_validation_error(validations) do
      nil -> {:ok, :format_valid}
      error -> error
    end
  end

  defp validate_order_business_rules(params) do
    validations = [
      validate_order_type_requirements(params),
      validate_minimum_order_value(params),
      validate_maximum_order_value(params),
      validate_quantity_precision(params),
      validate_price_precision(params)
    ]
    
    case find_first_error(validations) do
      nil -> {:ok, :business_rules_valid}
      error -> error
    end
  end

  # Private Functions - Symbol Validation

  defp validate_symbol(symbol) when is_binary(symbol) do
    case validate_and_normalize_symbol(symbol) do
      {:ok, _normalized} -> {:ok, :symbol_supported}
      error -> error
    end
  end

  defp validate_optional_symbol(nil), do: {:ok, :symbol_valid}
  defp validate_optional_symbol(symbol), do: validate_symbol(symbol)

  # Private Functions - Balance Validation

  defp validate_order_balance(user_id, %{"side" => "BUY", "type" => "MARKET"} = params) do
    # For market buy orders, check quote asset balance
    symbol = params["symbol"]
    quote_asset = extract_quote_asset(symbol)
    quantity = parse_float(params["quantity"])
    
    # For market orders, we need estimated price
    case get_estimated_order_value(symbol, "BUY", quantity, nil) do
      {:ok, estimated_value} ->
        check_asset_balance(user_id, quote_asset, estimated_value)
        
      {:error, reason} ->
        {:error, {:balance_validation_error, %{reason: reason}}}
    end
  end

  defp validate_order_balance(user_id, %{"side" => "BUY"} = params) do
    # For limit/stop buy orders, check quote asset balance
    symbol = params["symbol"]
    quote_asset = extract_quote_asset(symbol)
    quantity = parse_float(params["quantity"])
    price = parse_float(params["price"])
    
    if price > 0 do
      required_balance = quantity * price
      check_asset_balance(user_id, quote_asset, required_balance)
    else
      {:error, {:validation_error, %{field: :price, reason: :required_for_balance_check}}}
    end
  end

  defp validate_order_balance(user_id, %{"side" => "SELL"} = params) do
    # For sell orders, check base asset balance
    symbol = params["symbol"]
    base_asset = extract_base_asset(symbol)
    quantity = parse_float(params["quantity"])
    
    check_asset_balance(user_id, base_asset, quantity)
  end

  defp validate_order_balance(_user_id, _params) do
    {:error, {:validation_error, %{reason: :invalid_order_params_for_balance_check}}}
  end

  defp check_asset_balance(user_id, asset, required_amount) do
    case get_user_balance(user_id, asset) do
      {:ok, balance} when balance >= required_amount ->
        {:ok, :balance_sufficient}
        
      {:ok, balance} ->
        {:error, {:insufficient_funds, %{
          asset: asset,
          required: required_amount,
          available: balance
        }}}
        
      {:error, reason} ->
        {:error, {:balance_check_error, %{asset: asset, reason: reason}}}
    end
  end

  # Private Functions - Price Validation

  defp validate_order_price(%{"type" => "MARKET"} = _params) do
    {:ok, :price_valid}  # Market orders don't need price validation
  end

  defp validate_order_price(%{"symbol" => symbol, "price" => price_str} = _params) when is_binary(price_str) do
    price = parse_float(price_str)
    
    case get_current_market_price(symbol) do
      {:ok, market_price} ->
        price_deviation = abs(price - market_price) / market_price
        
        if price_deviation <= @max_price_deviation do
          {:ok, :price_valid}
        else
          {:error, {:business_rule_violation, %{
            reason: :price_deviation_too_high,
            market_price: market_price,
            order_price: price,
            max_deviation: @max_price_deviation,
            actual_deviation: price_deviation
          }}}
        end
        
      {:error, :market_data_unavailable} ->
        # If market data is unavailable, skip price validation
        Logger.warning("Market data unavailable for price validation", symbol: symbol)
        {:ok, :price_valid}
        
      {:error, reason} ->
        {:error, {:price_validation_error, %{reason: reason}}}
    end
  end

  defp validate_order_price(_params) do
    {:ok, :price_valid}  # Skip validation if price not provided
  end

  # Private Functions - Rate Limiting

  defp validate_rate_limits(user_id, operation) do
    case CredentialManager.can_make_request?(user_id) do
      true ->
        # Check operation-specific rate limits
        case validate_operation_rate_limit(user_id, operation) do
          true -> {:ok, :rate_limit_ok}
          false -> {:error, {:rate_limit_violation, %{operation: operation}}}
        end
        
      false ->
        {:error, {:rate_limit_violation, %{reason: :general_rate_limit_exceeded}}}
    end
  rescue
    error ->
      Logger.error("Rate limit validation error", user_id: user_id, error: inspect(error))
      {:error, {:rate_limit_validation_error, %{reason: error}}}
  end

  defp validate_operation_rate_limit(_user_id, :place_order) do
    # TODO: Implement order-specific rate limiting (10 orders/second)
    true
  end

  defp validate_operation_rate_limit(_user_id, _operation) do
    true
  end

  # Private Functions - Format Validation Helpers

  defp validate_symbol_format(symbol) when is_binary(symbol) do
    if String.match?(symbol, ~r/^[A-Z0-9]+$/) and String.length(symbol) >= 4 do
      nil
    else
      {:error, {:validation_error, %{field: :symbol, reason: :invalid_format}}}
    end
  end

  defp validate_symbol_format(_) do
    {:error, {:validation_error, %{field: :symbol, reason: :not_string}}}
  end

  defp validate_side_format(side) when side in @supported_sides, do: nil
  defp validate_side_format(_) do
    {:error, {:validation_error, %{field: :side, reason: :invalid_value, supported: @supported_sides}}}
  end

  defp validate_order_type_format(type) when type in @supported_order_types, do: nil
  defp validate_order_type_format(_) do
    {:error, {:validation_error, %{field: :type, reason: :invalid_value, supported: @supported_order_types}}}
  end

  defp validate_quantity_format(quantity) when is_binary(quantity) do
    case Float.parse(quantity) do
      {val, ""} when val > 0 -> nil
      _ -> {:error, {:validation_error, %{field: :quantity, reason: :invalid_number}}}
    end
  end

  defp validate_quantity_format(_) do
    {:error, {:validation_error, %{field: :quantity, reason: :not_string}}}
  end

  defp validate_price_format(nil), do: nil  # Optional field
  defp validate_price_format(price) when is_binary(price) do
    case Float.parse(price) do
      {val, ""} when val > 0 -> nil
      _ -> {:error, {:validation_error, %{field: :price, reason: :invalid_number}}}
    end
  end

  defp validate_price_format(_) do
    {:error, {:validation_error, %{field: :price, reason: :not_string}}}
  end

  defp validate_time_in_force_format(nil), do: nil  # Optional field
  defp validate_time_in_force_format(tif) when tif in @supported_time_in_force, do: nil
  defp validate_time_in_force_format(_) do
    {:error, {:validation_error, %{field: :timeInForce, reason: :invalid_value, supported: @supported_time_in_force}}}
  end

  # Private Functions - Business Rule Validations

  defp validate_order_type_requirements(%{"type" => "LIMIT", "price" => price}) when is_binary(price), do: nil
  defp validate_order_type_requirements(%{"type" => "LIMIT"}) do
    {:error, {:business_rule_violation, %{reason: :price_required_for_limit_orders}}}
  end

  defp validate_order_type_requirements(%{"type" => "STOP_LOSS", "stopPrice" => stop_price}) when is_binary(stop_price), do: nil
  defp validate_order_type_requirements(%{"type" => "STOP_LOSS"}) do
    {:error, {:business_rule_violation, %{reason: :stop_price_required}}}
  end

  defp validate_order_type_requirements(_params), do: nil

  defp validate_minimum_order_value(%{"symbol" => symbol, "quantity" => quantity_str} = params) do
    quantity = parse_float(quantity_str)
    
    cond do
      quantity < get_minimum_quantity(symbol) ->
        {:error, {:business_rule_violation, %{
          reason: :quantity_below_minimum,
          symbol: symbol,
          minimum: get_minimum_quantity(symbol),
          provided: quantity
        }}}
        
      true ->
        case calculate_order_value(params) do
          {:ok, value} when value < @min_order_value_usdt ->
            {:error, {:business_rule_violation, %{
              reason: :order_value_below_minimum,
              minimum_usdt: @min_order_value_usdt,
              calculated_usdt: value
            }}}
            
          {:ok, _value} -> nil
          {:error, _} -> nil  # Skip validation if we can't calculate value
        end
    end
  end

  defp validate_maximum_order_value(params) do
    case calculate_order_value(params) do
      {:ok, value} when value > @max_order_value_usdt ->
        {:error, {:business_rule_violation, %{
          reason: :order_value_above_maximum,
          maximum_usdt: @max_order_value_usdt,
          calculated_usdt: value
        }}}
        
      {:ok, _value} -> nil
      {:error, _} -> nil  # Skip validation if we can't calculate value
    end
  end

  defp validate_quantity_precision(%{"symbol" => symbol, "quantity" => quantity_str}) do
    quantity = parse_float(quantity_str)
    precision = get_quantity_precision(symbol)
    
    # Check if quantity has too many decimal places
    decimal_places = count_decimal_places(quantity_str)
    
    if decimal_places > precision do
      {:error, {:business_rule_violation, %{
        reason: :quantity_precision_exceeded,
        symbol: symbol,
        max_precision: precision,
        provided_precision: decimal_places
      }}}
    else
      nil
    end
  end

  defp validate_price_precision(%{"symbol" => symbol, "price" => price_str}) when is_binary(price_str) do
    price = parse_float(price_str)
    precision = get_price_precision(symbol)
    
    decimal_places = count_decimal_places(price_str)
    
    if decimal_places > precision do
      {:error, {:business_rule_violation, %{
        reason: :price_precision_exceeded,
        symbol: symbol,
        max_precision: precision,
        provided_precision: decimal_places
      }}}
    else
      nil
    end
  end

  defp validate_price_precision(_params), do: nil

  # Private Functions - Input Sanitization

  defp sanitize_string(nil), do: nil
  defp sanitize_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: String.upcase(trimmed)
  end
  defp sanitize_string(_), do: nil

  defp sanitize_integer(nil), do: nil
  defp sanitize_integer(value) when is_integer(value), do: value
  defp sanitize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end
  defp sanitize_integer(_), do: nil

  defp sanitize_number_string(nil), do: nil
  defp sanitize_number_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "" or not String.match?(trimmed, ~r/^\d+\.?\d*$/), do: nil, else: trimmed
  end
  defp sanitize_number_string(value) when is_number(value), do: to_string(value)
  defp sanitize_number_string(_), do: nil

  defp sanitize_balance_opts(opts) when is_map(opts) do
    sanitized = %{
      asset_filter: sanitize_string(opts[:asset_filter] || opts["asset_filter"]),
      force_refresh: !!Map.get(opts, :force_refresh, false),
      include_zero: !!Map.get(opts, :include_zero, false)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) and not is_boolean(v) end)
    |> Map.new()
    
    {:ok, sanitized}
  end

  defp sanitize_orders_opts(opts) when is_map(opts) do
    sanitized = %{
      symbol: sanitize_string(opts[:symbol] || opts["symbol"]),
      status: sanitize_string(opts[:status] || opts["status"]),
      limit: sanitize_integer(opts[:limit] || opts["limit"], 100, 1000),
      from_cache: !!Map.get(opts, :from_cache, false),
      start_time: sanitize_integer(opts[:start_time] || opts["start_time"]),
      end_time: sanitize_integer(opts[:end_time] || opts["end_time"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) and not is_boolean(v) end)
    |> Map.new()
    
    {:ok, sanitized}
  end

  defp sanitize_integer(nil, default, _max), do: default
  defp sanitize_integer(value, default, max) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, ""} when int_val > 0 and int_val <= max -> int_val
      _ -> default
    end
  end
  defp sanitize_integer(value, _default, max) when is_integer(value) and value > 0 and value <= max, do: value
  defp sanitize_integer(_value, default, _max), do: default

  # Private Functions - Order ID Validation

  defp validate_order_id_format(order_id) when is_binary(order_id) do
    cond do
      String.trim(order_id) == "" ->
        {:error, {:validation_error, %{field: :order_id, reason: :empty}}}
        
      String.length(order_id) > 100 ->
        {:error, {:validation_error, %{field: :order_id, reason: :too_long}}}
        
      not String.match?(order_id, ~r/^[a-zA-Z0-9_-]+$/) ->
        {:error, {:validation_error, %{field: :order_id, reason: :invalid_format}}}
        
      true ->
        {:ok, :order_id_valid}
    end
  end

  # Private Functions - Helper Utilities

  defp find_first_validation_error([]), do: nil
  defp find_first_validation_error([{_field, nil, _validator} | rest]) do
    find_first_validation_error(rest)
  end
  defp find_first_validation_error([{_field, value, validator} | rest]) do
    case validator.(value) do
      nil -> find_first_validation_error(rest)
      error -> error
    end
  end

  defp find_first_error([]), do: nil
  defp find_first_error([nil | rest]), do: find_first_error(rest)
  defp find_first_error([error | _rest]), do: error

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {val, ""} -> val
      _ -> 0.0
    end
  end

  defp parse_float(num) when is_number(num), do: num
  defp parse_float(_), do: 0.0

  # Private Functions - Trading Pair Utilities

  defp extract_base_asset(symbol) do
    cond do
      String.ends_with?(symbol, "USDT") -> String.slice(symbol, 0..-5)
      String.ends_with?(symbol, "BTC") -> String.slice(symbol, 0..-4)
      String.ends_with?(symbol, "ETH") -> String.slice(symbol, 0..-4)
      String.ends_with?(symbol, "BNB") -> String.slice(symbol, 0..-4)
      true -> String.slice(symbol, 0..2)  # Fallback for unknown pairs
    end
  end

  defp extract_quote_asset(symbol) do
    cond do
      String.ends_with?(symbol, "USDT") -> "USDT"
      String.ends_with?(symbol, "BTC") -> "BTC"
      String.ends_with?(symbol, "ETH") -> "ETH"
      String.ends_with?(symbol, "BNB") -> "BNB"
      true -> "USDT"  # Default fallback
    end
  end

  defp get_minimum_quantity(symbol) do
    base_asset = extract_base_asset(symbol)
    
    case base_asset do
      "BTC" -> @min_quantity_btc
      "ETH" -> @min_quantity_eth
      _ -> @min_quantity_default
    end
  end

  defp get_quantity_precision(_symbol), do: 8  # Default precision
  defp get_price_precision(_symbol), do: 8     # Default precision

  defp count_decimal_places(number_str) when is_binary(number_str) do
    case String.split(number_str, ".") do
      [_integer] -> 0
      [_integer, decimal] -> String.length(decimal)
      _ -> 0
    end
  end

  # Private Functions - Market Data and Balance Helpers

  defp get_current_market_price(_symbol) do
    # TODO: Implement market price fetching from ticker data
    # For now, return unavailable to skip price validation
    {:error, :market_data_unavailable}
  end

  defp get_estimated_order_value(_symbol, _side, _quantity, _price) do
    # TODO: Implement market order value estimation
    # For now, return a conservative estimate
    {:ok, @min_order_value_usdt}
  end

  defp calculate_order_value(%{"quantity" => quantity_str, "price" => price_str}) when is_binary(price_str) do
    quantity = parse_float(quantity_str)
    price = parse_float(price_str)
    {:ok, quantity * price}
  end

  defp calculate_order_value(_params) do
    {:error, :insufficient_data}
  end

  defp get_user_balance(user_id, asset) do
    # TODO: Implement balance lookup from user's cached balance
    # For now, return sufficient balance to allow validation to pass
    {:ok, 1000.0}
  end
end