defmodule CryptoExchange.Models.OrderBook do
  @moduledoc """
  Represents order book depth data from Binance.

  This module provides a structured representation of Binance's order book depth
  updates, containing bid and ask price levels with their corresponding quantities.
  The order book represents the current state of buy and sell orders at different
  price levels.

  ## Fields

  - `:event_type` - Event type (typically "depthUpdate")
  - `:event_time` - Event timestamp in milliseconds
  - `:symbol` - Trading symbol (e.g., "BTCUSDT")
  - `:first_update_id` - First update ID in this event
  - `:final_update_id` - Final update ID in this event
  - `:bids` - List of bid price levels [["price", "quantity"], ...]
  - `:asks` - List of ask price levels [["price", "quantity"], ...]

  ## Bid/Ask Format

  Each bid and ask is represented as a two-element list:
  - First element: Price as string
  - Second element: Quantity as string

  A quantity of "0.00000000" indicates the price level should be removed.

  ## Example Binance Message

  ```json
  {
    "e": "depthUpdate",
    "E": 123456789,
    "s": "BNBBTC",
    "U": 157,
    "u": 160,
    "b": [
      ["0.0024", "10"],
      ["0.0023", "100"]
    ],
    "a": [
      ["0.0026", "100"],
      ["0.0027", "50"]
    ]
  }
  ```

  ## Usage

  ```elixir
  # Parse from Binance JSON format
  raw_data = %{
    "e" => "depthUpdate",
    "E" => 1640995200000,
    "s" => "BTCUSDT",
    "U" => 157,
    "u" => 160,
    "b" => [["48200.00", "1.5"], ["48199.00", "2.3"]],
    "a" => [["48201.00", "0.8"], ["48202.00", "1.2"]]
  }

  {:ok, order_book} = CryptoExchange.Models.OrderBook.parse(raw_data)

  # Access parsed data
  order_book.symbol              # "BTCUSDT"
  order_book.bids                # [["48200.00", "1.5"], ["48199.00", "2.3"]]
  order_book.asks                # [["48201.00", "0.8"], ["48202.00", "1.2"]]
  order_book.first_update_id     # 157
  ```
  """

  @type price_level :: [String.t()]
  @type t :: %__MODULE__{
          event_type: String.t(),
          event_time: integer(),
          symbol: String.t(),
          first_update_id: integer(),
          final_update_id: integer(),
          bids: [price_level()],
          asks: [price_level()]
        }

  defstruct [
    :event_type,
    :event_time,
    :symbol,
    :first_update_id,
    :final_update_id,
    :bids,
    :asks
  ]

  @doc """
  Parses a Binance order book depth message into a structured OrderBook model.

  Takes the raw data from a Binance WebSocket `symbol@depth` message and converts
  it into a `CryptoExchange.Models.OrderBook` struct with properly typed fields.

  ## Parameters

  - `data` - Map containing the raw Binance order book depth data

  ## Returns

  - `{:ok, %CryptoExchange.Models.OrderBook{}}` - Successfully parsed order book
  - `{:error, reason}` - Parsing failed with error reason

  ## Examples

      iex> data = %{
      ...>   "e" => "depthUpdate",
      ...>   "E" => 1640995200000,
      ...>   "s" => "BTCUSDT",
      ...>   "U" => 157,
      ...>   "u" => 160,
      ...>   "b" => [["48200.00000000", "1.50000000"], ["48199.00000000", "2.30000000"]],
      ...>   "a" => [["48201.00000000", "0.80000000"], ["48202.00000000", "1.20000000"]]
      ...> }
      iex> {:ok, order_book} = CryptoExchange.Models.OrderBook.parse(data)
      iex> order_book.symbol
      "BTCUSDT"
      iex> length(order_book.bids)
      2
      iex> hd(order_book.bids)
      ["48200.00000000", "1.50000000"]
  """
  @spec parse(map()) :: {:ok, t()} | {:error, term()}
  def parse(data) when is_map(data) do
    try do
      order_book = %__MODULE__{
        event_type: Map.get(data, "e"),
        event_time: safe_integer(Map.get(data, "E")),
        symbol: Map.get(data, "s"),
        first_update_id: safe_integer(Map.get(data, "U")),
        final_update_id: safe_integer(Map.get(data, "u")),
        bids: parse_price_levels(Map.get(data, "b", [])),
        asks: parse_price_levels(Map.get(data, "a", []))
      }

      {:ok, order_book}
    rescue
      error -> {:error, "Failed to parse order book data: #{inspect(error)}"}
    end
  end

  def parse(_), do: {:error, "Invalid data format - expected map"}

  @doc """
  Retrieves the best bid (highest buy price) from the order book.

  ## Parameters

  - `order_book` - OrderBook struct

  ## Returns

  - `{:ok, [price, quantity]}` - Best bid price level
  - `{:error, :no_bids}` - No bids available

  ## Examples

      iex> order_book = %CryptoExchange.Models.OrderBook{
      ...>   bids: [["48200.00", "1.5"], ["48199.00", "2.3"]]
      ...> }
      iex> CryptoExchange.Models.OrderBook.best_bid(order_book)
      {:ok, ["48200.00", "1.5"]}
  """
  @spec best_bid(t()) :: {:ok, price_level()} | {:error, :no_bids}
  def best_bid(%__MODULE__{bids: []}), do: {:error, :no_bids}
  def best_bid(%__MODULE__{bids: [best | _]}), do: {:ok, best}

  @doc """
  Retrieves the best ask (lowest sell price) from the order book.

  ## Parameters

  - `order_book` - OrderBook struct

  ## Returns

  - `{:ok, [price, quantity]}` - Best ask price level
  - `{:error, :no_asks}` - No asks available

  ## Examples

      iex> order_book = %CryptoExchange.Models.OrderBook{
      ...>   asks: [["48201.00", "0.8"], ["48202.00", "1.2"]]
      ...> }
      iex> CryptoExchange.Models.OrderBook.best_ask(order_book)
      {:ok, ["48201.00", "0.8"]}
  """
  @spec best_ask(t()) :: {:ok, price_level()} | {:error, :no_asks}
  def best_ask(%__MODULE__{asks: []}), do: {:error, :no_asks}
  def best_ask(%__MODULE__{asks: [best | _]}), do: {:ok, best}

  @doc """
  Calculates the bid-ask spread from the order book.

  ## Parameters

  - `order_book` - OrderBook struct

  ## Returns

  - `{:ok, spread}` - Spread as string (ask_price - bid_price)
  - `{:error, reason}` - Calculation failed

  ## Examples

      iex> order_book = %CryptoExchange.Models.OrderBook{
      ...>   bids: [["48200.00", "1.5"]],
      ...>   asks: [["48201.00", "0.8"]]
      ...> }
      iex> CryptoExchange.Models.OrderBook.spread(order_book)
      {:ok, "1.00"}
  """
  @spec spread(t()) :: {:ok, String.t()} | {:error, term()}
  def spread(order_book) do
    with {:ok, [best_bid_price, _]} <- best_bid(order_book),
         {:ok, [best_ask_price, _]} <- best_ask(order_book),
         {bid_decimal, ""} <- Float.parse(best_bid_price),
         {ask_decimal, ""} <- Float.parse(best_ask_price) do
      spread = ask_decimal - bid_decimal
      {:ok, :erlang.float_to_binary(spread, [:compact, {:decimals, 8}])}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Invalid price format"}
    end
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

  # Helper function to parse price levels ensuring they're valid two-element lists
  defp parse_price_levels(levels) when is_list(levels) do
    Enum.map(levels, &parse_price_level/1)
  end

  defp parse_price_levels(_), do: []

  defp parse_price_level([price, quantity]) when is_binary(price) and is_binary(quantity) do
    [price, quantity]
  end

  defp parse_price_level(level) when is_list(level) and length(level) == 2 do
    [to_string(Enum.at(level, 0)), to_string(Enum.at(level, 1))]
  end

  defp parse_price_level(_), do: ["0.00000000", "0.00000000"]
end
