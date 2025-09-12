defmodule CryptoExchange.Models.Order do
  @moduledoc """
  Data model for representing trading orders from Binance.

  This module handles parsing, validation, and representation of order data
  returned from Binance API endpoints. It provides a consistent structure
  for order information across different API responses.

  ## Order States

  Binance orders have the following possible states:
  - **NEW**: Order has been accepted by the engine
  - **PARTIALLY_FILLED**: Part of the order has been filled  
  - **FILLED**: Order has been completely filled
  - **CANCELED**: Order has been canceled by the user
  - **PENDING_CANCEL**: Order is currently being canceled
  - **REJECTED**: Order was rejected by the engine
  - **EXPIRED**: Order has expired (for orders with time in force)

  ## Order Types

  Supported order types include:
  - **MARKET**: Market order (immediate execution at current price)
  - **LIMIT**: Limit order (execute at specific price or better)
  - **STOP_LOSS**: Stop loss order
  - **STOP_LOSS_LIMIT**: Stop loss limit order
  - **TAKE_PROFIT**: Take profit order
  - **TAKE_PROFIT_LIMIT**: Take profit limit order
  - **LIMIT_MAKER**: Limit maker order (always makes liquidity)

  ## Usage Examples

  ```elixir
  # Parse order from Binance API response
  binance_data = %{
    "orderId" => 123456789,
    "symbol" => "BTCUSDT",
    "status" => "FILLED",
    "type" => "LIMIT",
    "side" => "BUY",
    "origQty" => "0.00100000",
    "executedQty" => "0.00100000",
    "price" => "50000.00000000",
    "time" => 1640995200000,
    "updateTime" => 1640995201000
  }

  {:ok, order} = Order.parse(binance_data)
  # %Order{
  #   id: "123456789",
  #   symbol: "BTCUSDT", 
  #   status: :filled,
  #   type: :limit,
  #   side: :buy,
  #   quantity: Decimal.new("0.001"),
  #   executed_quantity: Decimal.new("0.001"),
  #   price: Decimal.new("50000.00"),
  #   created_at: ~U[2022-01-01 00:00:00.000Z],
  #   updated_at: ~U[2022-01-01 00:00:01.000Z]
  # }

  # Convert back to map for API calls
  order_map = Order.to_map(order)
  ```
  """

  alias CryptoExchange.Models.Order

  @enforce_keys [:id, :symbol, :status, :type, :side, :quantity, :created_at]
  defstruct [
    :id,
    :symbol,
    :status,
    :type,
    :side,
    :quantity,
    :executed_quantity,
    :price,
    :stop_price,
    :iceberg_quantity,
    :time_in_force,
    :created_at,
    :updated_at,
    :fills
  ]

  @type t :: %Order{
          id: String.t(),
          symbol: String.t(),
          status: order_status(),
          type: order_type(),
          side: order_side(),
          quantity: Decimal.t(),
          executed_quantity: Decimal.t() | nil,
          price: Decimal.t() | nil,
          stop_price: Decimal.t() | nil,
          iceberg_quantity: Decimal.t() | nil,
          time_in_force: time_in_force() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t() | nil,
          fills: [fill()] | nil
        }

  @type order_status ::
          :new
          | :partially_filled
          | :filled
          | :canceled
          | :pending_cancel
          | :rejected
          | :expired

  @type order_type ::
          :market
          | :limit
          | :stop_loss
          | :stop_loss_limit
          | :take_profit
          | :take_profit_limit
          | :limit_maker

  @type order_side :: :buy | :sell

  @type time_in_force :: :gtc | :ioc | :fok

  @type fill :: %{
          price: Decimal.t(),
          quantity: Decimal.t(),
          commission: Decimal.t(),
          commission_asset: String.t()
        }

  @doc """
  Parses order data from Binance API response.

  ## Parameters
  - `data`: Map containing order data from Binance API

  ## Returns
  - `{:ok, order}` on successful parsing
  - `{:error, reason}` if parsing fails

  ## Example
  ```elixir
  binance_data = %{
    "orderId" => 123456789,
    "symbol" => "BTCUSDT",
    "status" => "FILLED",
    "type" => "LIMIT",
    "side" => "BUY",
    "origQty" => "0.00100000",
    "executedQty" => "0.00100000",
    "price" => "50000.00000000",
    "time" => 1640995200000,
    "updateTime" => 1640995201000
  }

  {:ok, order} = Order.parse(binance_data)
  ```
  """
  def parse(data) when is_map(data) do
    with {:ok, id} <- extract_string(data, "orderId"),
         {:ok, symbol} <- extract_string(data, "symbol"),
         {:ok, status} <- extract_and_convert_status(data, "status"),
         {:ok, type} <- extract_and_convert_type(data, "type"),
         {:ok, side} <- extract_and_convert_side(data, "side"),
         {:ok, quantity} <- extract_decimal(data, "origQty"),
         {:ok, created_at} <- extract_datetime(data, "time") do
      order = %Order{
        id: id,
        symbol: symbol,
        status: status,
        type: type,
        side: side,
        quantity: quantity,
        executed_quantity: extract_decimal_optional(data, "executedQty"),
        price: extract_decimal_optional(data, "price"),
        stop_price: extract_decimal_optional(data, "stopPrice"),
        iceberg_quantity: extract_decimal_optional(data, "icebergQty"),
        time_in_force: extract_time_in_force_optional(data, "timeInForce"),
        created_at: created_at,
        updated_at: extract_datetime_optional(data, "updateTime"),
        fills: parse_fills(data["fills"])
      }

      {:ok, order}
    else
      {:error, _reason} = error ->
        error
    end
  end

  def parse(_), do: {:error, :invalid_data_format}

  @doc """
  Converts an Order struct to a map representation.

  ## Parameters
  - `order`: Order struct to convert

  ## Returns
  Map with order data suitable for API responses or storage.

  ## Example
  ```elixir
  order_map = Order.to_map(order)
  # %{
  #   id: "123456789",
  #   symbol: "BTCUSDT",
  #   status: "FILLED",
  #   type: "LIMIT",
  #   side: "BUY",
  #   quantity: "0.001",
  #   price: "50000.00",
  #   ...
  # }
  ```
  """
  def to_map(%Order{} = order) do
    %{
      id: order.id,
      symbol: order.symbol,
      status: order.status |> Atom.to_string() |> String.upcase(),
      type: order.type |> Atom.to_string() |> String.upcase(),
      side: order.side |> Atom.to_string() |> String.upcase(),
      quantity: to_string(order.quantity),
      executed_quantity: decimal_to_string(order.executed_quantity),
      price: decimal_to_string(order.price),
      stop_price: decimal_to_string(order.stop_price),
      iceberg_quantity: decimal_to_string(order.iceberg_quantity),
      time_in_force: time_in_force_to_string(order.time_in_force),
      created_at: order.created_at,
      updated_at: order.updated_at,
      fills: order.fills
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  @doc """
  Validates order parameters for placing new orders.

  ## Parameters
  - `params`: Map containing order parameters

  ## Returns
  - `:ok` if parameters are valid
  - `{:error, reason}` if validation fails

  ## Example
  ```elixir
  params = %{
    symbol: "BTCUSDT",
    side: "BUY",
    type: "LIMIT",
    quantity: "0.001",
    price: "50000.00",
    timeInForce: "GTC"
  }

  :ok = Order.validate_params(params)
  ```
  """
  def validate_params(params) when is_map(params) do
    with :ok <- validate_required_fields(params),
         :ok <- validate_symbol(params["symbol"] || params[:symbol]),
         :ok <- validate_side(params["side"] || params[:side]),
         :ok <- validate_type(params["type"] || params[:type]),
         :ok <- validate_quantities(params) do
      :ok
    else
      {:error, _reason} = error ->
        error
    end
  end

  def validate_params(_), do: {:error, :invalid_params_format}

  @doc """
  Checks if an order is in a terminal state (cannot be modified).

  ## Parameters
  - `order`: Order struct to check

  ## Returns
  Boolean indicating if the order is in a terminal state.

  Terminal states are: `:filled`, `:canceled`, `:rejected`, `:expired`

  ## Example
  ```elixir
  Order.terminal_state?(order)
  # true if order is filled, canceled, rejected, or expired
  ```
  """
  def terminal_state?(%Order{status: status}) do
    status in [:filled, :canceled, :rejected, :expired]
  end

  @doc """
  Checks if an order is actively trading.

  ## Parameters  
  - `order`: Order struct to check

  ## Returns
  Boolean indicating if the order is active.

  Active states are: `:new`, `:partially_filled`

  ## Example
  ```elixir
  Order.active?(order)
  # true if order is new or partially filled
  ```
  """
  def active?(%Order{status: status}) do
    status in [:new, :partially_filled]
  end

  # Private Functions

  defp extract_string(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      value when is_integer(value) -> {:ok, to_string(value)}
      nil -> {:error, {:missing_field, key}}
      _ -> {:error, {:invalid_field_type, key}}
    end
  end

  defp extract_decimal(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) ->
        case Decimal.parse(value) do
          {decimal, ""} -> {:ok, decimal}
          _ -> {:error, {:invalid_decimal, key}}
        end

      value when is_number(value) ->
        {:ok, Decimal.from_float(value)}

      nil ->
        {:error, {:missing_field, key}}

      _ ->
        {:error, {:invalid_field_type, key}}
    end
  end

  defp extract_decimal_optional(data, key) do
    case extract_decimal(data, key) do
      {:ok, decimal} -> decimal
      {:error, _} -> nil
    end
  end

  defp extract_datetime(data, key) do
    case Map.get(data, key) do
      timestamp when is_integer(timestamp) ->
        {:ok, DateTime.from_unix!(timestamp, :millisecond)}

      nil ->
        {:error, {:missing_field, key}}

      _ ->
        {:error, {:invalid_timestamp, key}}
    end
  end

  defp extract_datetime_optional(data, key) do
    case extract_datetime(data, key) do
      {:ok, datetime} -> datetime
      {:error, _} -> nil
    end
  end

  defp extract_and_convert_status(data, key) do
    case extract_string(data, key) do
      {:ok, status_string} -> convert_status(status_string)
      error -> error
    end
  end

  defp convert_status(status_string) do
    case String.downcase(status_string) do
      "new" -> {:ok, :new}
      "partially_filled" -> {:ok, :partially_filled}
      "filled" -> {:ok, :filled}
      "canceled" -> {:ok, :canceled}
      "pending_cancel" -> {:ok, :pending_cancel}
      "rejected" -> {:ok, :rejected}
      "expired" -> {:ok, :expired}
      _ -> {:error, {:invalid_status, status_string}}
    end
  end

  defp extract_and_convert_type(data, key) do
    case extract_string(data, key) do
      {:ok, type_string} -> convert_type(type_string)
      error -> error
    end
  end

  defp convert_type(type_string) do
    case String.downcase(type_string) do
      "market" -> {:ok, :market}
      "limit" -> {:ok, :limit}
      "stop_loss" -> {:ok, :stop_loss}
      "stop_loss_limit" -> {:ok, :stop_loss_limit}
      "take_profit" -> {:ok, :take_profit}
      "take_profit_limit" -> {:ok, :take_profit_limit}
      "limit_maker" -> {:ok, :limit_maker}
      _ -> {:error, {:invalid_type, type_string}}
    end
  end

  defp extract_and_convert_side(data, key) do
    case extract_string(data, key) do
      {:ok, side_string} -> convert_side(side_string)
      error -> error
    end
  end

  defp convert_side(side_string) do
    case String.downcase(side_string) do
      "buy" -> {:ok, :buy}
      "sell" -> {:ok, :sell}
      _ -> {:error, {:invalid_side, side_string}}
    end
  end

  defp extract_time_in_force_optional(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) -> convert_time_in_force(value)
      _ -> nil
    end
  end

  defp convert_time_in_force(tif_string) do
    case String.downcase(tif_string) do
      "gtc" -> :gtc
      "ioc" -> :ioc
      "fok" -> :fok
      _ -> nil
    end
  end

  defp parse_fills(nil), do: nil

  defp parse_fills(fills) when is_list(fills) do
    Enum.map(fills, &parse_fill/1)
  end

  defp parse_fill(fill_data) when is_map(fill_data) do
    %{
      price: extract_decimal_optional(fill_data, "price") || Decimal.new(0),
      quantity: extract_decimal_optional(fill_data, "qty") || Decimal.new(0),
      commission: extract_decimal_optional(fill_data, "commission") || Decimal.new(0),
      commission_asset: fill_data["commissionAsset"] || ""
    }
  end

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(decimal), do: to_string(decimal)

  defp time_in_force_to_string(nil), do: nil
  defp time_in_force_to_string(tif), do: tif |> Atom.to_string() |> String.upcase()

  defp validate_required_fields(params) do
    required = ["symbol", "side", "type"]

    missing =
      Enum.filter(required, fn key ->
        not (Map.has_key?(params, key) or Map.has_key?(params, String.to_atom(key)))
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_symbol(symbol) when is_binary(symbol) and byte_size(symbol) > 0, do: :ok
  defp validate_symbol(_), do: {:error, :invalid_symbol}

  defp validate_side(side) when side in ["BUY", "SELL", "buy", "sell"], do: :ok
  defp validate_side(_), do: {:error, :invalid_side}

  defp validate_type(type) when is_binary(type) do
    valid_types = [
      "MARKET",
      "LIMIT",
      "STOP_LOSS",
      "STOP_LOSS_LIMIT",
      "TAKE_PROFIT",
      "TAKE_PROFIT_LIMIT",
      "LIMIT_MAKER"
    ]

    if String.upcase(type) in valid_types do
      :ok
    else
      {:error, :invalid_type}
    end
  end

  defp validate_type(_), do: {:error, :invalid_type}

  defp validate_quantities(params) do
    type = params["type"] || params[:type]
    quantity = params["quantity"] || params[:quantity]
    quote_order_qty = params["quoteOrderQty"] || params[:quoteOrderQty]

    case String.upcase(to_string(type)) do
      "MARKET" ->
        if quantity || quote_order_qty do
          :ok
        else
          {:error, :market_order_requires_quantity_or_quote_order_qty}
        end

      "LIMIT" ->
        price = params["price"] || params[:price]
        time_in_force = params["timeInForce"] || params[:timeInForce]

        cond do
          !quantity -> {:error, :limit_order_requires_quantity}
          !price -> {:error, :limit_order_requires_price}
          !time_in_force -> {:error, :limit_order_requires_time_in_force}
          true -> :ok
        end

      _ ->
        :ok
    end
  end
end
