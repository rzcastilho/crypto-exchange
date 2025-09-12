defmodule CryptoExchange.Models.Kline do
  @moduledoc """
  Represents a kline (candlestick) message from Binance.

  This module provides a structured representation of Binance's kline/candlestick data,
  which contains OHLC (Open, High, Low, Close) price information, volume data, and 
  timing information for a specific time interval.

  Klines provide essential market data for technical analysis, showing price movements
  and trading activity over specific time periods (1s, 1m, 5m, 1h, 1d, etc.).

  ## Fields

  - `:event_type` - Event type (always "kline")
  - `:event_time` - Event timestamp in milliseconds
  - `:symbol` - Trading symbol (e.g., "BTCUSDT")
  - `:kline_start_time` - Kline start time in milliseconds
  - `:kline_close_time` - Kline close time in milliseconds
  - `:interval` - Time interval (e.g., "1m", "5m", "1h", "1d")
  - `:first_trade_id` - First trade ID during this kline period
  - `:last_trade_id` - Last trade ID during this kline period
  - `:open_price` - Opening price for this kline
  - `:close_price` - Closing/current price for this kline
  - `:high_price` - Highest price during this kline period
  - `:low_price` - Lowest price during this kline period
  - `:base_asset_volume` - Base asset volume during this period
  - `:number_of_trades` - Number of trades during this period
  - `:is_kline_closed` - Whether this kline period is closed (final)
  - `:quote_asset_volume` - Quote asset volume during this period
  - `:taker_buy_base_asset_volume` - Taker buy base asset volume
  - `:taker_buy_quote_asset_volume` - Taker buy quote asset volume

  ## Usage Examples

  ```elixir
  # Parse a raw Binance kline message
  raw_data = %{
    "e" => "kline",
    "E" => 1672515782136,
    "s" => "BTCUSDT",
    "k" => %{
      "t" => 1672515780000,
      "T" => 1672515839999,
      "i" => "1m",
      "o" => "48000.00000000",
      "c" => "48200.50000000",
      "h" => "48250.00000000",
      "l" => "47980.00000000"
      # ... other fields
    }
  }

  {:ok, kline} = CryptoExchange.Models.Kline.parse(raw_data)

  # Access parsed data
  kline.symbol                    # "BTCUSDT"
  kline.interval                  # "1m"
  kline.open_price               # "48000.00000000"
  kline.close_price              # "48200.50000000"
  kline.is_kline_closed          # false (if still active)

  # Use utility functions
  kline |> Kline.price_change()           # "200.50000000"
  kline |> Kline.price_change_percent()   # "0.42"
  kline |> Kline.is_bullish?()           # true
  kline |> Kline.body_size()             # "200.50000000"
  ```
  """

  @type t :: %__MODULE__{
          event_type: String.t() | nil,
          event_time: integer() | nil,
          symbol: String.t() | nil,
          kline_start_time: integer() | nil,
          kline_close_time: integer() | nil,
          interval: String.t() | nil,
          first_trade_id: integer() | nil,
          last_trade_id: integer() | nil,
          open_price: String.t() | nil,
          close_price: String.t() | nil,
          high_price: String.t() | nil,
          low_price: String.t() | nil,
          base_asset_volume: String.t() | nil,
          number_of_trades: integer() | nil,
          is_kline_closed: boolean() | nil,
          quote_asset_volume: String.t() | nil,
          taker_buy_base_asset_volume: String.t() | nil,
          taker_buy_quote_asset_volume: String.t() | nil
        }

  defstruct [
    :event_type,
    :event_time,
    :symbol,
    :kline_start_time,
    :kline_close_time,
    :interval,
    :first_trade_id,
    :last_trade_id,
    :open_price,
    :close_price,
    :high_price,
    :low_price,
    :base_asset_volume,
    :number_of_trades,
    :is_kline_closed,
    :quote_asset_volume,
    :taker_buy_base_asset_volume,
    :taker_buy_quote_asset_volume
  ]

  @doc """
  Parses a raw Binance kline message into a structured Kline.

  ## Parameters
  - `data` - Raw message data from Binance WebSocket

  ## Returns
  - `{:ok, %Kline{}}` on successful parsing
  - `{:error, reason}` on parsing failure

  ## Examples
      iex> data = %{
      ...>   "e" => "kline",
      ...>   "E" => 1672515782136,
      ...>   "s" => "BTCUSDT",
      ...>   "k" => %{
      ...>     "t" => 1672515780000,
      ...>     "T" => 1672515839999,
      ...>     "i" => "1m",
      ...>     "o" => "48000.00",
      ...>     "c" => "48200.50",
      ...>     "h" => "48250.00",
      ...>     "l" => "47980.00",
      ...>     "v" => "1000",
      ...>     "n" => 100,
      ...>     "x" => false,
      ...>     "q" => "48100000.00"
      ...>   }
      ...> }
      iex> {:ok, kline} = CryptoExchange.Models.Kline.parse(data)
      iex> kline.symbol
      "BTCUSDT"
  """
  @spec parse(map()) :: {:ok, t()} | {:error, String.t()}
  def parse(%{} = data) do
    try do
      # Extract main fields
      event_type = Map.get(data, "e")
      event_time = safe_integer(Map.get(data, "E"))
      symbol = Map.get(data, "s")

      # Extract kline data from nested "k" object
      kline_data = Map.get(data, "k", %{})

      kline = %__MODULE__{
        event_type: event_type,
        event_time: event_time,
        symbol: symbol,
        kline_start_time: safe_integer(Map.get(kline_data, "t")),
        kline_close_time: safe_integer(Map.get(kline_data, "T")),
        interval: Map.get(kline_data, "i"),
        first_trade_id: safe_integer(Map.get(kline_data, "f")),
        last_trade_id: safe_integer(Map.get(kline_data, "L")),
        open_price: Map.get(kline_data, "o"),
        close_price: Map.get(kline_data, "c"),
        high_price: Map.get(kline_data, "h"),
        low_price: Map.get(kline_data, "l"),
        base_asset_volume: Map.get(kline_data, "v"),
        number_of_trades: safe_integer(Map.get(kline_data, "n")),
        is_kline_closed: Map.get(kline_data, "x"),
        quote_asset_volume: Map.get(kline_data, "q"),
        taker_buy_base_asset_volume: Map.get(kline_data, "V"),
        taker_buy_quote_asset_volume: Map.get(kline_data, "Q")
      }

      {:ok, kline}
    rescue
      error ->
        {:error, "Failed to parse kline data: #{inspect(error)}"}
    end
  end

  def parse(_), do: {:error, "Invalid data format - expected map"}

  @doc """
  Calculates the price change for the kline (close - open).

  ## Parameters
  - `kline` - The kline struct

  ## Returns
  - `{:ok, price_change}` as string on success
  - `{:error, reason}` if prices are not available or invalid

  ## Examples
      iex> kline = %CryptoExchange.Models.Kline{open_price: "48000.00", close_price: "48200.50"}
      iex> {:ok, change} = CryptoExchange.Models.Kline.price_change(kline)
      iex> change
      "200.5"
  """
  @spec price_change(t()) :: {:ok, String.t()} | {:error, String.t()}
  def price_change(%__MODULE__{open_price: open, close_price: close}) 
      when is_binary(open) and is_binary(close) do
    with {:ok, open_decimal} <- safe_decimal(open),
         {:ok, close_decimal} <- safe_decimal(close) do
      change = Decimal.sub(close_decimal, open_decimal)
      {:ok, normalize_decimal_string(change)}
    else
      _ -> {:error, "Invalid price format"}
    end
  end

  def price_change(_), do: {:error, "Missing or invalid price data"}

  @doc """
  Calculates the price change percentage for the kline ((close - open) / open * 100).

  ## Parameters
  - `kline` - The kline struct

  ## Returns
  - `{:ok, percentage}` as string on success
  - `{:error, reason}` if calculation fails

  ## Examples
      iex> kline = %CryptoExchange.Models.Kline{open_price: "48000.00", close_price: "48200.50"}
      iex> {:ok, percent} = CryptoExchange.Models.Kline.price_change_percent(kline)
      iex> percent
      "0.41770833333333333333"
  """
  @spec price_change_percent(t()) :: {:ok, String.t()} | {:error, String.t()}
  def price_change_percent(%__MODULE__{open_price: open, close_price: close}) 
      when is_binary(open) and is_binary(close) do
    with {:ok, open_decimal} <- safe_decimal(open),
         {:ok, close_decimal} <- safe_decimal(close) do
      if Decimal.equal?(open_decimal, Decimal.new(0)) do
        {:error, "Division by zero - open price is zero"}
      else
        change = Decimal.sub(close_decimal, open_decimal)
        percentage = Decimal.mult(Decimal.div(change, open_decimal), Decimal.new(100))
        {:ok, Decimal.to_string(percentage)}
      end
    else
      _ -> {:error, "Invalid price format"}
    end
  end

  def price_change_percent(_), do: {:error, "Missing or invalid price data"}

  @doc """
  Determines if the kline is bullish (close > open).

  ## Parameters
  - `kline` - The kline struct

  ## Returns
  - `true` if close price > open price
  - `false` otherwise

  ## Examples
      iex> kline = %CryptoExchange.Models.Kline{open_price: "48000.00", close_price: "48200.50"}
      iex> CryptoExchange.Models.Kline.is_bullish?(kline)
      true
  """
  @spec is_bullish?(t()) :: boolean()
  def is_bullish?(%__MODULE__{open_price: open, close_price: close}) 
      when is_binary(open) and is_binary(close) do
    with {:ok, open_decimal} <- safe_decimal(open),
         {:ok, close_decimal} <- safe_decimal(close) do
      Decimal.gt?(close_decimal, open_decimal)
    else
      _ -> false
    end
  end

  def is_bullish?(_), do: false

  @doc """
  Determines if the kline is bearish (close < open).

  ## Parameters
  - `kline` - The kline struct

  ## Returns
  - `true` if close price < open price
  - `false` otherwise

  ## Examples
      iex> kline = %CryptoExchange.Models.Kline{open_price: "48200.50", close_price: "48000.00"}
      iex> CryptoExchange.Models.Kline.is_bearish?(kline)
      true
  """
  @spec is_bearish?(t()) :: boolean()
  def is_bearish?(%__MODULE__{open_price: open, close_price: close}) 
      when is_binary(open) and is_binary(close) do
    with {:ok, open_decimal} <- safe_decimal(open),
         {:ok, close_decimal} <- safe_decimal(close) do
      Decimal.lt?(close_decimal, open_decimal)
    else
      _ -> false
    end
  end

  def is_bearish?(_), do: false

  @doc """
  Calculates the body size of the candlestick (absolute difference between open and close).

  ## Parameters
  - `kline` - The kline struct

  ## Returns
  - `{:ok, body_size}` as string on success
  - `{:error, reason}` if calculation fails

  ## Examples
      iex> kline = %CryptoExchange.Models.Kline{open_price: "48000.00", close_price: "48200.50"}
      iex> {:ok, body} = CryptoExchange.Models.Kline.body_size(kline)
      iex> body
      "200.5"
  """
  @spec body_size(t()) :: {:ok, String.t()} | {:error, String.t()}
  def body_size(%__MODULE__{open_price: open, close_price: close}) 
      when is_binary(open) and is_binary(close) do
    with {:ok, open_decimal} <- safe_decimal(open),
         {:ok, close_decimal} <- safe_decimal(close) do
      size = Decimal.abs(Decimal.sub(close_decimal, open_decimal))
      {:ok, normalize_decimal_string(size)}
    else
      _ -> {:error, "Invalid price format"}
    end
  end

  def body_size(_), do: {:error, "Missing or invalid price data"}

  @doc """
  Calculates the upper shadow/wick size (high - max(open, close)).

  ## Parameters
  - `kline` - The kline struct

  ## Returns
  - `{:ok, upper_shadow}` as string on success
  - `{:error, reason}` if calculation fails

  ## Examples
      iex> kline = %CryptoExchange.Models.Kline{
      ...>   open_price: "48000.00", 
      ...>   close_price: "48200.50", 
      ...>   high_price: "48300.00"
      ...> }
      iex> {:ok, shadow} = CryptoExchange.Models.Kline.upper_shadow(kline)
      iex> shadow
      "99.5"
  """
  @spec upper_shadow(t()) :: {:ok, String.t()} | {:error, String.t()}
  def upper_shadow(%__MODULE__{open_price: open, close_price: close, high_price: high}) 
      when is_binary(open) and is_binary(close) and is_binary(high) do
    with {:ok, open_decimal} <- safe_decimal(open),
         {:ok, close_decimal} <- safe_decimal(close),
         {:ok, high_decimal} <- safe_decimal(high) do
      body_top = Decimal.max(open_decimal, close_decimal)
      shadow = Decimal.sub(high_decimal, body_top)
      {:ok, normalize_decimal_string(shadow)}
    else
      _ -> {:error, "Invalid price format"}
    end
  end

  def upper_shadow(_), do: {:error, "Missing or invalid price data"}

  @doc """
  Calculates the lower shadow/wick size (min(open, close) - low).

  ## Parameters
  - `kline` - The kline struct

  ## Returns
  - `{:ok, lower_shadow}` as string on success
  - `{:error, reason}` if calculation fails

  ## Examples
      iex> kline = %CryptoExchange.Models.Kline{
      ...>   open_price: "48000.00", 
      ...>   close_price: "48200.50", 
      ...>   low_price: "47950.00"
      ...> }
      iex> {:ok, shadow} = CryptoExchange.Models.Kline.lower_shadow(kline)
      iex> shadow
      "50.0"
  """
  @spec lower_shadow(t()) :: {:ok, String.t()} | {:error, String.t()}
  def lower_shadow(%__MODULE__{open_price: open, close_price: close, low_price: low}) 
      when is_binary(open) and is_binary(close) and is_binary(low) do
    with {:ok, open_decimal} <- safe_decimal(open),
         {:ok, close_decimal} <- safe_decimal(close),
         {:ok, low_decimal} <- safe_decimal(low) do
      body_bottom = Decimal.min(open_decimal, close_decimal)
      shadow = Decimal.sub(body_bottom, low_decimal)
      {:ok, normalize_decimal_string(shadow)}
    else
      _ -> {:error, "Invalid price format"}
    end
  end

  def lower_shadow(_), do: {:error, "Missing or invalid price data"}

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

  # Helper function to safely convert strings to Decimal
  defp safe_decimal(value) when is_binary(value) do
    try do
      {:ok, Decimal.new(value)}
    rescue
      _ -> {:error, "Invalid decimal format"}
    end
  end

  defp safe_decimal(_), do: {:error, "Invalid decimal value"}

  # Helper function to normalize Decimal output strings
  defp normalize_decimal_string(decimal_value) do
    decimal_value
    |> Decimal.to_string()
    |> String.replace(~r/\.?0+$/, "")  # Remove trailing zeros and decimal point if needed
    |> case do
      "" -> "0"  # Handle edge case where all digits were zeros
      "0E-8" -> "0"  # Handle scientific notation for zero
      result -> result
    end
  end
end