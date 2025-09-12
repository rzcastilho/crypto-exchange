defmodule CryptoExchange.Models.Trade do
  @moduledoc """
  Represents individual trade data from Binance.

  This module provides a structured representation of Binance's individual trade
  messages, which contain information about each executed trade including price,
  quantity, timing, and market maker information.

  ## Fields

  - `:event_type` - Event type (always "trade")
  - `:event_time` - Event timestamp in milliseconds
  - `:symbol` - Trading symbol (e.g., "BTCUSDT") 
  - `:trade_id` - Unique trade identifier
  - `:price` - Trade execution price
  - `:quantity` - Trade execution quantity
  - `:buyer_order_id` - Buyer's order ID
  - `:seller_order_id` - Seller's order ID
  - `:trade_time` - Trade execution timestamp in milliseconds
  - `:is_buyer_market_maker` - Whether buyer was the market maker
  - `:ignore` - Ignore this field (always true, reserved for future use)

  ## Market Maker Flag

  The `:is_buyer_market_maker` field indicates whether the buyer in the trade
  was the market maker (providing liquidity) or taker (consuming liquidity):
  - `true` - Buyer was market maker (sell-side trade)  
  - `false` - Buyer was taker (buy-side trade)

  ## Example Binance Message

  ```json
  {
    "e": "trade",
    "E": 123456789,
    "s": "BNBBTC", 
    "t": 12345,
    "p": "0.001",
    "q": "100",
    "b": 88,
    "a": 50,
    "T": 123456785,
    "m": true,
    "M": true
  }
  ```

  ## Usage

  ```elixir
  # Parse from Binance JSON format
  raw_data = %{
    "e" => "trade",
    "E" => 1640995200000,
    "s" => "BTCUSDT",
    "t" => 12345,
    "p" => "48200.50000000",
    "q" => "0.12500000",
    "b" => 88,
    "a" => 50,
    "T" => 1640995199950,
    "m" => true,
    "M" => true
  }

  {:ok, trade} = CryptoExchange.Models.Trade.parse(raw_data)

  # Access parsed data
  trade.symbol                  # "BTCUSDT"
  trade.price                   # "48200.50000000"
  trade.quantity                # "0.12500000"
  trade.is_buyer_market_maker   # true
  trade.trade_side              # :sell (derived from market maker flag)
  ```
  """

  @type t :: %__MODULE__{
          event_type: String.t(),
          event_time: integer(),
          symbol: String.t(),
          trade_id: integer(),
          price: String.t(),
          quantity: String.t(),
          buyer_order_id: integer(),
          seller_order_id: integer(),
          trade_time: integer(),
          is_buyer_market_maker: boolean(),
          ignore: boolean()
        }

  defstruct [
    :event_type,
    :event_time,
    :symbol,
    :trade_id,
    :price,
    :quantity,
    :buyer_order_id,
    :seller_order_id,
    :trade_time,
    :is_buyer_market_maker,
    :ignore
  ]

  @doc """
  Parses a Binance trade message into a structured Trade model.

  Takes the raw data from a Binance WebSocket `symbol@trade` message and converts
  it into a `CryptoExchange.Models.Trade` struct with properly typed fields.

  ## Parameters

  - `data` - Map containing the raw Binance trade data

  ## Returns

  - `{:ok, %CryptoExchange.Models.Trade{}}` - Successfully parsed trade
  - `{:error, reason}` - Parsing failed with error reason

  ## Examples

      iex> data = %{
      ...>   "e" => "trade",
      ...>   "E" => 1640995200000,
      ...>   "s" => "BTCUSDT",
      ...>   "t" => 12345,
      ...>   "p" => "48200.50000000",
      ...>   "q" => "0.12500000",
      ...>   "b" => 88,
      ...>   "a" => 50,
      ...>   "T" => 1640995199950,
      ...>   "m" => true,
      ...>   "M" => true
      ...> }
      iex> {:ok, trade} = CryptoExchange.Models.Trade.parse(data)
      iex> trade.symbol
      "BTCUSDT"
      iex> trade.price
      "48200.50000000"
      iex> trade.is_buyer_market_maker
      true
  """
  @spec parse(map()) :: {:ok, t()} | {:error, term()}
  def parse(data) when is_map(data) do
    try do
      trade = %__MODULE__{
        event_type: Map.get(data, "e"),
        event_time: safe_integer(Map.get(data, "E")),
        symbol: Map.get(data, "s"),
        trade_id: safe_integer(Map.get(data, "t")),
        price: Map.get(data, "p"),
        quantity: Map.get(data, "q"),
        buyer_order_id: safe_integer(Map.get(data, "b")),
        seller_order_id: safe_integer(Map.get(data, "a")),
        trade_time: safe_integer(Map.get(data, "T")),
        is_buyer_market_maker: Map.get(data, "m"),
        ignore: Map.get(data, "M")
      }

      {:ok, trade}
    rescue
      error -> {:error, "Failed to parse trade data: #{inspect(error)}"}
    end
  end

  def parse(_), do: {:error, "Invalid data format - expected map"}

  @doc """
  Determines the trade side based on the market maker flag.

  In Binance trade data:
  - When buyer is market maker (m=true), it's a sell-side trade
  - When buyer is taker (m=false), it's a buy-side trade

  ## Parameters

  - `trade` - Trade struct

  ## Returns

  - `:buy` - Buy-side trade (buyer was taker)
  - `:sell` - Sell-side trade (buyer was market maker)

  ## Examples

      iex> trade = %CryptoExchange.Models.Trade{is_buyer_market_maker: true}
      iex> CryptoExchange.Models.Trade.trade_side(trade)
      :sell

      iex> trade = %CryptoExchange.Models.Trade{is_buyer_market_maker: false}
      iex> CryptoExchange.Models.Trade.trade_side(trade)
      :buy
  """
  @spec trade_side(t()) :: :buy | :sell
  def trade_side(%__MODULE__{is_buyer_market_maker: true}), do: :sell
  def trade_side(%__MODULE__{is_buyer_market_maker: false}), do: :buy

  @doc """
  Calculates the trade value (price * quantity) as a string.

  ## Parameters

  - `trade` - Trade struct

  ## Returns

  - `{:ok, value}` - Trade value as string
  - `{:error, reason}` - Calculation failed

  ## Examples

      iex> trade = %CryptoExchange.Models.Trade{
      ...>   price: "48200.50000000",
      ...>   quantity: "0.12500000"
      ...> }
      iex> CryptoExchange.Models.Trade.trade_value(trade)
      {:ok, "6025.06250000"}
  """
  @spec trade_value(t()) :: {:ok, String.t()} | {:error, term()}
  def trade_value(%__MODULE__{price: price, quantity: quantity}) do
    with {price_float, ""} <- Float.parse(price || "0"),
         {quantity_float, ""} <- Float.parse(quantity || "0") do
      value = price_float * quantity_float
      {:ok, :erlang.float_to_binary(value, [:compact, {:decimals, 8}])}
    else
      _ -> {:error, "Invalid price or quantity format"}
    end
  end

  @doc """
  Checks if the trade is considered a large trade based on a minimum value threshold.

  ## Parameters

  - `trade` - Trade struct
  - `min_value` - Minimum value threshold as string or number

  ## Returns

  - `{:ok, boolean}` - Whether trade exceeds minimum value
  - `{:error, reason}` - Calculation failed

  ## Examples

      iex> trade = %CryptoExchange.Models.Trade{
      ...>   price: "48200.50000000",
      ...>   quantity: "0.12500000"
      ...> }
      iex> CryptoExchange.Models.Trade.is_large_trade?(trade, "1000")
      {:ok, true}
      iex> CryptoExchange.Models.Trade.is_large_trade?(trade, "10000") 
      {:ok, false}
  """
  @spec is_large_trade?(t(), String.t() | number()) :: {:ok, boolean()} | {:error, term()}
  def is_large_trade?(trade, min_value) when is_binary(min_value) do
    with {:ok, trade_value_str} <- trade_value(trade),
         {trade_val, ""} <- Float.parse(trade_value_str),
         {min_val, ""} <- Float.parse(min_value) do
      {:ok, trade_val >= min_val}
    else
      _ -> {:error, "Invalid value format"}
    end
  end

  def is_large_trade?(trade, min_value) when is_number(min_value) do
    is_large_trade?(trade, to_string(min_value))
  end

  # Helper function to safely convert values to integers
  defp safe_integer(nil), do: nil
  defp safe_integer(value) when is_integer(value), do: value

  defp safe_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp safe_integer(_), do: nil
end
