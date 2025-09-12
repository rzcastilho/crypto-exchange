defmodule CryptoExchange.Models.Ticker do
  @moduledoc """
  Represents a 24hr ticker statistics message from Binance.

  This module provides a structured representation of Binance's 24hr ticker data,
  which includes price changes, volume information, and best bid/ask prices for
  a trading symbol over a 24-hour period.

  ## Fields

  - `:event_type` - Event type (always "24hrTicker")
  - `:event_time` - Event timestamp in milliseconds
  - `:symbol` - Trading symbol (e.g., "BTCUSDT")
  - `:price_change` - 24hr price change amount
  - `:price_change_percent` - 24hr price change percentage
  - `:weighted_avg_price` - Weighted average price over 24hr
  - `:first_trade_price` - First trade price before 24hr rolling window
  - `:last_price` - Last/current price
  - `:last_quantity` - Last trade quantity
  - `:best_bid_price` - Current best bid price
  - `:best_bid_quantity` - Current best bid quantity
  - `:best_ask_price` - Current best ask price  
  - `:best_ask_quantity` - Current best ask quantity
  - `:open_price` - Opening price 24hr ago
  - `:high_price` - Highest price in last 24hr
  - `:low_price` - Lowest price in last 24hr
  - `:total_traded_base_asset_volume` - Total base asset volume in 24hr
  - `:total_traded_quote_asset_volume` - Total quote asset volume in 24hr
  - `:statistics_open_time` - Statistics calculation start time
  - `:statistics_close_time` - Statistics calculation end time
  - `:first_trade_id` - First trade ID in the statistics window
  - `:last_trade_id` - Last trade ID in the statistics window
  - `:total_number_of_trades` - Total number of trades in 24hr

  ## Example Binance Message

  ```json
  {
    "e": "24hrTicker",
    "E": 123456789,
    "s": "BNBBTC",
    "p": "0.00000200",
    "P": "0.833",
    "w": "0.00242213",
    "x": "0.00240000",
    "c": "0.00240200",
    "Q": "9.00000000",
    "b": "0.00240000",
    "B": "9.00000000",
    "a": "0.00240200",
    "A": "9.00000000",
    "o": "0.00240000",
    "h": "0.00245000",
    "l": "0.00240000",
    "v": "9110.00000000",
    "q": "22.05520000",
    "O": 123456785,
    "C": 123456789,
    "F": 0,
    "L": 18150,
    "n": 18151
  }
  ```

  ## Usage

  ```elixir
  # Parse from Binance JSON format
  raw_data = %{
    "e" => "24hrTicker",
    "E" => 1640995200000,
    "s" => "BTCUSDT",
    "p" => "1500.00",
    "P" => "3.21",
    "c" => "48200.50"
    # ... other fields
  }

  {:ok, ticker} = CryptoExchange.Models.Ticker.parse(raw_data)

  # Access parsed data
  ticker.symbol          # "BTCUSDT"
  ticker.last_price      # "48200.50"
  ticker.price_change    # "1500.00"
  ```
  """

  @type t :: %__MODULE__{
          event_type: String.t(),
          event_time: integer(),
          symbol: String.t(),
          price_change: String.t(),
          price_change_percent: String.t(),
          weighted_avg_price: String.t(),
          first_trade_price: String.t(),
          last_price: String.t(),
          last_quantity: String.t(),
          best_bid_price: String.t(),
          best_bid_quantity: String.t(),
          best_ask_price: String.t(),
          best_ask_quantity: String.t(),
          open_price: String.t(),
          high_price: String.t(),
          low_price: String.t(),
          total_traded_base_asset_volume: String.t(),
          total_traded_quote_asset_volume: String.t(),
          statistics_open_time: integer(),
          statistics_close_time: integer(),
          first_trade_id: integer(),
          last_trade_id: integer(),
          total_number_of_trades: integer()
        }

  defstruct [
    :event_type,
    :event_time,
    :symbol,
    :price_change,
    :price_change_percent,
    :weighted_avg_price,
    :first_trade_price,
    :last_price,
    :last_quantity,
    :best_bid_price,
    :best_bid_quantity,
    :best_ask_price,
    :best_ask_quantity,
    :open_price,
    :high_price,
    :low_price,
    :total_traded_base_asset_volume,
    :total_traded_quote_asset_volume,
    :statistics_open_time,
    :statistics_close_time,
    :first_trade_id,
    :last_trade_id,
    :total_number_of_trades
  ]

  @doc """
  Parses a Binance 24hr ticker message into a structured Ticker model.

  Takes the raw data from a Binance WebSocket `symbol@ticker` message and converts
  it into a `CryptoExchange.Models.Ticker` struct with properly typed fields.

  ## Parameters

  - `data` - Map containing the raw Binance ticker data

  ## Returns

  - `{:ok, %CryptoExchange.Models.Ticker{}}` - Successfully parsed ticker
  - `{:error, reason}` - Parsing failed with error reason

  ## Examples

      iex> data = %{
      ...>   "e" => "24hrTicker",
      ...>   "E" => 1640995200000,
      ...>   "s" => "BTCUSDT",
      ...>   "p" => "1500.00000000",
      ...>   "P" => "3.210",
      ...>   "w" => "47850.12345678",
      ...>   "x" => "46700.00000000",
      ...>   "c" => "48200.50000000",
      ...>   "Q" => "0.12500000",
      ...>   "b" => "48200.00000000",
      ...>   "B" => "1.50000000",
      ...>   "a" => "48201.00000000",
      ...>   "A" => "2.30000000",
      ...>   "o" => "46700.50000000",
      ...>   "h" => "49000.00000000",
      ...>   "l" => "46500.00000000",
      ...>   "v" => "12345.67890000",
      ...>   "q" => "590123456.78900000",
      ...>   "O" => 1640908800000,
      ...>   "C" => 1640995200000,
      ...>   "F" => 1234567,
      ...>   "L" => 1234890,
      ...>   "n" => 324
      ...> }
      iex> {:ok, ticker} = CryptoExchange.Models.Ticker.parse(data)
      iex> ticker.symbol
      "BTCUSDT"
      iex> ticker.last_price
      "48200.50000000"
  """
  @spec parse(map()) :: {:ok, t()} | {:error, term()}
  def parse(data) when is_map(data) do
    try do
      ticker = %__MODULE__{
        event_type: Map.get(data, "e"),
        event_time: safe_integer(Map.get(data, "E")),
        symbol: Map.get(data, "s"),
        price_change: Map.get(data, "p"),
        price_change_percent: Map.get(data, "P"),
        weighted_avg_price: Map.get(data, "w"),
        first_trade_price: Map.get(data, "x"),
        last_price: Map.get(data, "c"),
        last_quantity: Map.get(data, "Q"),
        best_bid_price: Map.get(data, "b"),
        best_bid_quantity: Map.get(data, "B"),
        best_ask_price: Map.get(data, "a"),
        best_ask_quantity: Map.get(data, "A"),
        open_price: Map.get(data, "o"),
        high_price: Map.get(data, "h"),
        low_price: Map.get(data, "l"),
        total_traded_base_asset_volume: Map.get(data, "v"),
        total_traded_quote_asset_volume: Map.get(data, "q"),
        statistics_open_time: safe_integer(Map.get(data, "O")),
        statistics_close_time: safe_integer(Map.get(data, "C")),
        first_trade_id: safe_integer(Map.get(data, "F")),
        last_trade_id: safe_integer(Map.get(data, "L")),
        total_number_of_trades: safe_integer(Map.get(data, "n"))
      }

      {:ok, ticker}
    rescue
      error -> {:error, "Failed to parse ticker data: #{inspect(error)}"}
    end
  end

  def parse(_), do: {:error, "Invalid data format - expected map"}

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
