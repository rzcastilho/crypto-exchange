defmodule CryptoExchange.TestSupport.Factory do
  @moduledoc """
  Factory module for creating test data structures.
  Provides consistent test data generation for all CryptoExchange models and scenarios.
  """

  alias CryptoExchange.Models.{Order, Ticker, OrderBook, Trade, Balance}

  # =============================================================================
  # ORDER FACTORIES
  # =============================================================================

  @doc """
  Creates test data structures based on factory type.
  """
  def build(factory_type, attrs \\ %{})

  def build(:order, attrs) do
    %Order{
      order_id: unique_id("order"),
      symbol: "BTCUSDT",
      side: :buy,
      type: :limit,
      quantity: 0.001,
      price: 50000.00,
      status: :new
    }
    |> struct(attrs)
  end

  def build(:filled_order, attrs) do
    build(:order, Map.merge(%{
      status: :filled
    }, attrs))
  end

  def build(:cancelled_order, attrs) do
    build(:order, Map.merge(%{
      status: :cancelled
    }, attrs))
  end

  def build(:market_order, attrs) do
    build(:order, Map.merge(%{
      type: :market,
      price: 0.0
    }, attrs))
  end

  # =============================================================================
  # MARKET DATA FACTORIES
  # =============================================================================

  def build(:ticker_data, attrs) do
    %Ticker{
      symbol: Map.get(attrs, :symbol, "BTCUSDT"),
      price: 50000.0,
      change: 1000.0,
      volume: 1000.123
    }
    |> struct(Map.delete(attrs, :symbol))
  end

  def build(:orderbook_data, attrs) do
    %OrderBook{
      symbol: Map.get(attrs, :symbol, "BTCUSDT"),
      bids: [["49900.00", "1.000"], ["49800.00", "2.000"]],
      asks: [["50100.00", "1.500"], ["50200.00", "0.800"]]
    }
    |> struct(Map.delete(attrs, :symbol))
  end

  def build(:trade_data, attrs) do
    %Trade{
      symbol: Map.get(attrs, :symbol, "BTCUSDT"),
      price: 50000.0,
      quantity: 0.001,
      side: :buy
    }
    |> struct(Map.delete(attrs, :symbol))
  end

  # =============================================================================
  # USER DATA FACTORIES
  # =============================================================================

  def build(:balance_data, attrs) do
    %Balance{
      asset: Map.get(attrs, :asset, "BTC"),
      free: 1.00000000,
      locked: 0.00000000
    }
    |> struct(Map.delete(attrs, :asset))
  end

  def build(:user_balances, _attrs) do
    [
      build(:balance_data, %{asset: "BTC"}),
      build(:balance_data, %{asset: "ETH", free: 10.0}),
      build(:balance_data, %{asset: "USDT", free: 10000.0})
    ]
  end

  # =============================================================================
  # WEBSOCKET MESSAGE FACTORIES
  # =============================================================================

  def build(:ws_ticker_message, attrs) do
    symbol = Map.get(attrs, :symbol, "BTCUSDT")
    
    %{
      "e" => "24hrTicker",
      "E" => System.system_time(:millisecond),
      "s" => symbol,
      "c" => "50000.00",
      "o" => "49000.00",
      "h" => "51000.00",
      "l" => "48000.00",
      "v" => "1000.123"
    }
    |> Map.merge(Map.delete(attrs, :symbol))
  end

  def build(:ws_kline_message, attrs) do
    symbol = Map.get(attrs, :symbol, "BTCUSDT")
    interval = Map.get(attrs, :interval, "1m")
    
    %{
      "e" => "kline",
      "E" => System.system_time(:millisecond),
      "s" => symbol,
      "k" => %{
        "i" => interval,
        "o" => "49500.00",
        "c" => "50000.00",
        "h" => "50500.00",
        "l" => "49000.00",
        "v" => "100.123"
      }
    }
  end

  # =============================================================================
  # API RESPONSE FACTORIES
  # =============================================================================

  def build(:api_order_response, attrs) do
    symbol = Map.get(attrs, "symbol", "BTCUSDT")
    %{
      "symbol" => symbol,
      "orderId" => 12345,
      "status" => "NEW",
      "side" => "BUY"
    }
    |> Map.merge(attrs)
  end

  def build(:api_error_response, attrs) do
    %{
      "code" => -1013,
      "msg" => "Filter failure: PRICE_FILTER"
    }
    |> Map.merge(attrs)
  end

  # =============================================================================
  # SIMPLE DATA FACTORIES
  # =============================================================================

  def build(:credentials, attrs) do
    %{
      api_key: "test_api_key_#{:rand.uniform(1000)}",
      secret_key: "test_secret_key_#{:rand.uniform(1000)}"
    }
    |> Map.merge(attrs)
  end

  def build(:order_params, attrs) do
    %{
      symbol: "BTCUSDT",
      side: "BUY",
      type: "LIMIT",
      quantity: "0.001",
      price: "50000.00"
    }
    |> Map.merge(attrs)
  end

  # =============================================================================
  # STREAMDATA GENERATORS
  # =============================================================================

  @doc """
  Creates StreamData generators for property-based testing.
  """
  def symbol_generator do
    StreamData.member_of(["BTCUSDT", "ETHUSDT", "ADAUSDT", "BNBUSDT", "DOTUSDT"])
  end

  def price_generator do
    StreamData.float(min: 0.00001, max: 100000.0)
    |> StreamData.map(&Float.to_string/1)
  end

  def quantity_generator do
    StreamData.float(min: 0.001, max: 1000.0)
    |> StreamData.map(&Float.to_string/1)
  end

  # =============================================================================
  # HELPER FUNCTIONS
  # =============================================================================

  @doc """
  Generates a unique ID for testing.
  """
  def unique_id(prefix \\ "test") do
    "#{prefix}_#{System.unique_integer([:positive])}"
  end

  @doc """
  Creates multiple instances of a factory type.
  """
  def build_list(count, factory_name, attrs \\ %{}) when count > 0 do
    Enum.map(1..count, fn _i ->
      build(factory_name, attrs)
    end)
  end
end