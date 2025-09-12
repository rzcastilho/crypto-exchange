defmodule CryptoExchange.Models.TradeTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Models.Trade

  describe "parse/1" do
    test "successfully parses a complete Binance trade message" do
      data = %{
        "e" => "trade",
        "E" => 1_640_995_200_000,
        "s" => "BTCUSDT",
        "t" => 12345,
        "p" => "48200.50000000",
        "q" => "0.12500000",
        "b" => 88,
        "a" => 50,
        "T" => 1_640_995_199_950,
        "m" => true,
        "M" => true
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.event_type == "trade"
      assert trade.event_time == 1_640_995_200_000
      assert trade.symbol == "BTCUSDT"
      assert trade.trade_id == 12345
      assert trade.price == "48200.50000000"
      assert trade.quantity == "0.12500000"
      assert trade.buyer_order_id == 88
      assert trade.seller_order_id == 50
      assert trade.trade_time == 1_640_995_199_950
      assert trade.is_buyer_market_maker == true
      assert trade.ignore == true
    end

    test "parses with minimal required fields" do
      data = %{
        "e" => "trade",
        "s" => "ETHUSDT",
        "p" => "4000.00000000",
        "q" => "1.00000000"
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.event_type == "trade"
      assert trade.symbol == "ETHUSDT"
      assert trade.price == "4000.00000000"
      assert trade.quantity == "1.00000000"
      assert trade.event_time == nil
      assert trade.trade_id == nil
      # No default value
      assert trade.is_buyer_market_maker == nil
      # No default value
      assert trade.ignore == nil
    end

    test "handles integer timestamps and IDs correctly" do
      data = %{
        "e" => "trade",
        "E" => 1_640_995_200_000,
        "s" => "BTCUSDT",
        "t" => 12345,
        "b" => 88,
        "a" => 50,
        "T" => 1_640_995_199_950
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.event_time == 1_640_995_200_000
      assert trade.trade_id == 12345
      assert trade.buyer_order_id == 88
      assert trade.seller_order_id == 50
      assert trade.trade_time == 1_640_995_199_950
    end

    test "handles string timestamps and IDs correctly" do
      data = %{
        "e" => "trade",
        "E" => "1640995200000",
        "s" => "BTCUSDT",
        "t" => "12345",
        "b" => "88",
        "a" => "50",
        "T" => "1640995199950"
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.event_time == 1_640_995_200_000
      assert trade.trade_id == 12345
      assert trade.buyer_order_id == 88
      assert trade.seller_order_id == 50
      assert trade.trade_time == 1_640_995_199_950
    end

    test "handles invalid integer values gracefully" do
      data = %{
        "e" => "trade",
        "E" => "invalid_timestamp",
        "s" => "BTCUSDT",
        "t" => "not_a_number",
        "b" => nil,
        "a" => [],
        "T" => "bad_time"
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.event_time == nil
      assert trade.trade_id == nil
      assert trade.buyer_order_id == nil
      assert trade.seller_order_id == nil
      assert trade.trade_time == nil
    end

    test "handles boolean market maker flags" do
      # Test buyer is market maker
      data1 = %{
        "e" => "trade",
        "s" => "BTCUSDT",
        "m" => true,
        "M" => true
      }

      {:ok, trade1} = Trade.parse(data1)
      assert trade1.is_buyer_market_maker == true
      assert trade1.ignore == true

      # Test buyer is not market maker
      data2 = %{
        "e" => "trade",
        "s" => "BTCUSDT",
        "m" => false,
        "M" => false
      }

      {:ok, trade2} = Trade.parse(data2)
      assert trade2.is_buyer_market_maker == false
      assert trade2.ignore == false
    end

    test "returns error for non-map input" do
      assert {:error, _reason} = Trade.parse("not a map")
      assert {:error, _reason} = Trade.parse(nil)
      assert {:error, _reason} = Trade.parse(42)
      assert {:error, _reason} = Trade.parse([])
    end
  end

  describe "trade_side/1" do
    test "returns :sell when buyer is market maker" do
      trade = %Trade{is_buyer_market_maker: true}
      assert Trade.trade_side(trade) == :sell
    end

    test "returns :buy when buyer is taker" do
      trade = %Trade{is_buyer_market_maker: false}
      assert Trade.trade_side(trade) == :buy
    end
  end

  describe "trade_value/1" do
    test "calculates trade value correctly" do
      trade = %Trade{
        price: "48200.50000000",
        quantity: "0.12500000"
      }

      {:ok, value} = Trade.trade_value(trade)
      assert String.starts_with?(value, "6025.0625")
    end

    test "handles integer-like decimal values" do
      trade = %Trade{
        price: "100.00000000",
        quantity: "2.00000000"
      }

      {:ok, value} = Trade.trade_value(trade)
      assert String.starts_with?(value, "200")
    end

    test "handles very small values" do
      trade = %Trade{
        price: "0.00001000",
        quantity: "1000.00000000"
      }

      {:ok, value} = Trade.trade_value(trade)
      assert String.starts_with?(value, "0.01")
    end

    test "handles very large values" do
      trade = %Trade{
        price: "99999.99999999",
        quantity: "999.99999999"
      }

      {:ok, value} = Trade.trade_value(trade)
      assert String.contains?(value, "99999999")
    end

    test "returns error for invalid price format" do
      trade = %Trade{
        price: "invalid_price",
        quantity: "1.00000000"
      }

      assert {:error, "Invalid price or quantity format"} = Trade.trade_value(trade)
    end

    test "returns error for invalid quantity format" do
      trade = %Trade{
        price: "100.00000000",
        quantity: "invalid_quantity"
      }

      assert {:error, "Invalid price or quantity format"} = Trade.trade_value(trade)
    end

    test "handles nil price and quantity" do
      trade = %Trade{
        price: nil,
        quantity: "1.00000000"
      }

      {:ok, value} = Trade.trade_value(trade)
      assert value == "0.0"

      trade2 = %Trade{
        price: "100.00000000",
        quantity: nil
      }

      {:ok, value2} = Trade.trade_value(trade2)
      assert value2 == "0.0"
    end
  end

  describe "is_large_trade?/2" do
    test "returns true when trade value exceeds threshold with string threshold" do
      trade = %Trade{
        price: "48200.50000000",
        # Value: ~6025
        quantity: "0.12500000"
      }

      {:ok, is_large} = Trade.is_large_trade?(trade, "1000")
      assert is_large == true

      {:ok, is_not_large} = Trade.is_large_trade?(trade, "10000")
      assert is_not_large == false
    end

    test "returns true when trade value exceeds threshold with numeric threshold" do
      trade = %Trade{
        price: "100.00000000",
        # Value: 1000
        quantity: "10.00000000"
      }

      {:ok, is_large} = Trade.is_large_trade?(trade, 500)
      assert is_large == true

      {:ok, is_not_large} = Trade.is_large_trade?(trade, 1500)
      assert is_not_large == false
    end

    test "returns exact match for threshold" do
      trade = %Trade{
        price: "100.00000000",
        # Value: exactly 1000
        quantity: "10.00000000"
      }

      {:ok, is_large} = Trade.is_large_trade?(trade, "1000")
      assert is_large == true

      {:ok, is_large_float} = Trade.is_large_trade?(trade, 1000.0)
      assert is_large_float == true
    end

    test "returns error for invalid threshold format" do
      trade = %Trade{
        price: "100.00000000",
        quantity: "1.00000000"
      }

      assert {:error, "Invalid value format"} = Trade.is_large_trade?(trade, "invalid")
    end

    test "returns error when trade value calculation fails" do
      trade = %Trade{
        price: "invalid_price",
        quantity: "1.00000000"
      }

      assert {:error, "Invalid value format"} = Trade.is_large_trade?(trade, "1000")
    end
  end

  describe "real Binance data examples" do
    test "parses actual Binance BNBBTC trade data" do
      # Real example from Binance documentation
      data = %{
        "e" => "trade",
        "E" => 123_456_789,
        "s" => "BNBBTC",
        "t" => 12345,
        "p" => "0.001",
        "q" => "100",
        "b" => 88,
        "a" => 50,
        "T" => 123_456_785,
        "m" => true,
        "M" => true
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.event_type == "trade"
      assert trade.event_time == 123_456_789
      assert trade.symbol == "BNBBTC"
      assert trade.trade_id == 12345
      assert trade.price == "0.001"
      assert trade.quantity == "100"
      assert trade.buyer_order_id == 88
      assert trade.seller_order_id == 50
      assert trade.trade_time == 123_456_785
      assert trade.is_buyer_market_maker == true
      assert trade.ignore == true

      # Test utility functions with real data
      assert Trade.trade_side(trade) == :sell

      {:ok, value} = Trade.trade_value(trade)
      assert String.starts_with?(value, "0.1")

      {:ok, is_large} = Trade.is_large_trade?(trade, "0.05")
      assert is_large == true
    end

    test "parses buy-side trade (buyer is taker)" do
      data = %{
        "e" => "trade",
        "E" => 123_456_789,
        "s" => "BTCUSDT",
        "t" => 12346,
        "p" => "50000.00000000",
        "q" => "0.02000000",
        "b" => 89,
        "a" => 51,
        "T" => 123_456_790,
        # Buyer is taker (buy-side trade)
        "m" => false,
        "M" => true
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.is_buyer_market_maker == false
      assert Trade.trade_side(trade) == :buy

      {:ok, value} = Trade.trade_value(trade)
      assert String.starts_with?(value, "1000")
    end

    test "parses sell-side trade (buyer is market maker)" do
      data = %{
        "e" => "trade",
        "E" => 123_456_789,
        "s" => "BTCUSDT",
        "t" => 12347,
        "p" => "49999.99000000",
        "q" => "0.05000000",
        "b" => 90,
        "a" => 52,
        "T" => 123_456_791,
        # Buyer is market maker (sell-side trade)
        "m" => true,
        "M" => true
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.is_buyer_market_maker == true
      assert Trade.trade_side(trade) == :sell

      {:ok, value} = Trade.trade_value(trade)
      assert String.starts_with?(value, "2499.9995")
    end
  end

  describe "edge cases" do
    test "handles very large trade IDs and timestamps" do
      data = %{
        "e" => "trade",
        "E" => 9_999_999_999_999,
        "s" => "BTCUSDT",
        "t" => 9_999_999_999,
        "b" => 9_999_999_999,
        "a" => 9_999_999_999,
        "T" => 9_999_999_999_999
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.event_time == 9_999_999_999_999
      assert trade.trade_id == 9_999_999_999
      assert trade.buyer_order_id == 9_999_999_999
      assert trade.seller_order_id == 9_999_999_999
      assert trade.trade_time == 9_999_999_999_999
    end

    test "handles nil values gracefully" do
      data = %{
        "e" => "trade",
        "s" => "BTCUSDT",
        "p" => nil,
        "q" => nil,
        "E" => nil,
        "t" => nil,
        "m" => nil,
        "M" => nil
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.price == nil
      assert trade.quantity == nil
      assert trade.event_time == nil
      assert trade.trade_id == nil
      # Actually nil, not false
      assert trade.is_buyer_market_maker == nil
      # Actually nil when not provided
      assert trade.ignore == nil
    end

    test "handles zero values" do
      data = %{
        "e" => "trade",
        "s" => "TESTUSDT",
        "p" => "0.00000000",
        "q" => "0.00000000",
        "t" => 0,
        "b" => 0,
        "a" => 0,
        "T" => 0
      }

      {:ok, trade} = Trade.parse(data)

      assert trade.price == "0.00000000"
      assert trade.quantity == "0.00000000"
      assert trade.trade_id == 0
      assert trade.buyer_order_id == 0
      assert trade.seller_order_id == 0
      assert trade.trade_time == 0

      {:ok, value} = Trade.trade_value(trade)
      assert value == "0.0"
    end
  end
end
