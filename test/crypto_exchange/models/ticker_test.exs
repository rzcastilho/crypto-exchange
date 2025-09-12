defmodule CryptoExchange.Models.TickerTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Models.Ticker

  describe "parse/1" do
    test "successfully parses a complete Binance ticker message" do
      data = %{
        "e" => "24hrTicker",
        "E" => 1_640_995_200_000,
        "s" => "BTCUSDT",
        "p" => "1500.00000000",
        "P" => "3.210",
        "w" => "47850.12345678",
        "x" => "46700.00000000",
        "c" => "48200.50000000",
        "Q" => "0.12500000",
        "b" => "48200.00000000",
        "B" => "1.50000000",
        "a" => "48201.00000000",
        "A" => "2.30000000",
        "o" => "46700.50000000",
        "h" => "49000.00000000",
        "l" => "46500.00000000",
        "v" => "12345.67890000",
        "q" => "590123456.78900000",
        "O" => 1_640_908_800_000,
        "C" => 1_640_995_200_000,
        "F" => 1_234_567,
        "L" => 1_234_890,
        "n" => 324
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.event_type == "24hrTicker"
      assert ticker.event_time == 1_640_995_200_000
      assert ticker.symbol == "BTCUSDT"
      assert ticker.price_change == "1500.00000000"
      assert ticker.price_change_percent == "3.210"
      assert ticker.weighted_avg_price == "47850.12345678"
      assert ticker.first_trade_price == "46700.00000000"
      assert ticker.last_price == "48200.50000000"
      assert ticker.last_quantity == "0.12500000"
      assert ticker.best_bid_price == "48200.00000000"
      assert ticker.best_bid_quantity == "1.50000000"
      assert ticker.best_ask_price == "48201.00000000"
      assert ticker.best_ask_quantity == "2.30000000"
      assert ticker.open_price == "46700.50000000"
      assert ticker.high_price == "49000.00000000"
      assert ticker.low_price == "46500.00000000"
      assert ticker.total_traded_base_asset_volume == "12345.67890000"
      assert ticker.total_traded_quote_asset_volume == "590123456.78900000"
      assert ticker.statistics_open_time == 1_640_908_800_000
      assert ticker.statistics_close_time == 1_640_995_200_000
      assert ticker.first_trade_id == 1_234_567
      assert ticker.last_trade_id == 1_234_890
      assert ticker.total_number_of_trades == 324
    end

    test "parses with minimal required fields" do
      data = %{
        "e" => "24hrTicker",
        "s" => "ETHUSDT",
        "c" => "4000.00000000"
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.event_type == "24hrTicker"
      assert ticker.symbol == "ETHUSDT"
      assert ticker.last_price == "4000.00000000"
      assert ticker.event_time == nil
      assert ticker.price_change == nil
    end

    test "handles integer timestamps correctly" do
      data = %{
        "e" => "24hrTicker",
        "E" => 1_640_995_200_000,
        "s" => "BTCUSDT",
        "O" => 1_640_908_800_000,
        "C" => 1_640_995_200_000,
        "F" => 1_234_567,
        "L" => 1_234_890,
        "n" => 324
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.event_time == 1_640_995_200_000
      assert ticker.statistics_open_time == 1_640_908_800_000
      assert ticker.statistics_close_time == 1_640_995_200_000
      assert ticker.first_trade_id == 1_234_567
      assert ticker.last_trade_id == 1_234_890
      assert ticker.total_number_of_trades == 324
    end

    test "handles string timestamps correctly" do
      data = %{
        "e" => "24hrTicker",
        "E" => "1640995200000",
        "s" => "BTCUSDT",
        "F" => "1234567",
        "L" => "1234890",
        "n" => "324"
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.event_time == 1_640_995_200_000
      assert ticker.first_trade_id == 1_234_567
      assert ticker.last_trade_id == 1_234_890
      assert ticker.total_number_of_trades == 324
    end

    test "handles invalid integer values gracefully" do
      data = %{
        "e" => "24hrTicker",
        "E" => "invalid_timestamp",
        "s" => "BTCUSDT",
        "F" => "not_a_number",
        "L" => nil,
        "n" => []
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.event_time == nil
      assert ticker.first_trade_id == nil
      assert ticker.last_trade_id == nil
      assert ticker.total_number_of_trades == nil
    end

    test "parses empty map successfully" do
      data = %{}

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.event_type == nil
      assert ticker.symbol == nil
      assert ticker.last_price == nil
    end

    test "returns error for non-map input" do
      assert {:error, _reason} = Ticker.parse("not a map")
      assert {:error, _reason} = Ticker.parse(nil)
      assert {:error, _reason} = Ticker.parse(42)
      assert {:error, _reason} = Ticker.parse([])
    end

    test "successfully parses data with unusual but valid values" do
      # Testing that the parser is robust enough to handle edge cases
      data = %{
        "e" => "24hrTicker",
        "s" => "TESTUSDT"
      }

      # This should succeed even with minimal data
      assert {:ok, ticker} = Ticker.parse(data)
      assert ticker.event_type == "24hrTicker"
      assert ticker.symbol == "TESTUSDT"
    end
  end

  describe "real Binance data examples" do
    test "parses actual Binance BTCUSDT ticker data" do
      # Real example from Binance documentation
      data = %{
        "e" => "24hrTicker",
        "E" => 123_456_789,
        "s" => "BNBBTC",
        "p" => "0.00000200",
        "P" => "0.833",
        "w" => "0.00242213",
        "x" => "0.00240000",
        "c" => "0.00240200",
        "Q" => "9.00000000",
        "b" => "0.00240000",
        "B" => "9.00000000",
        "a" => "0.00240200",
        "A" => "9.00000000",
        "o" => "0.00240000",
        "h" => "0.00245000",
        "l" => "0.00240000",
        "v" => "9110.00000000",
        "q" => "22.05520000",
        "O" => 123_456_785,
        "C" => 123_456_789,
        "F" => 0,
        "L" => 18150,
        "n" => 18151
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.event_type == "24hrTicker"
      assert ticker.event_time == 123_456_789
      assert ticker.symbol == "BNBBTC"
      assert ticker.price_change == "0.00000200"
      assert ticker.price_change_percent == "0.833"
      assert ticker.last_price == "0.00240200"
      assert ticker.best_bid_price == "0.00240000"
      assert ticker.best_ask_price == "0.00240200"
      assert ticker.total_number_of_trades == 18151
    end

    test "parses ticker with zero values" do
      data = %{
        "e" => "24hrTicker",
        "E" => 123_456_789,
        "s" => "TESTUSDT",
        "p" => "0.00000000",
        "P" => "0.000",
        "v" => "0.00000000",
        "q" => "0.00000000",
        "n" => 0
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.price_change == "0.00000000"
      assert ticker.price_change_percent == "0.000"
      assert ticker.total_traded_base_asset_volume == "0.00000000"
      assert ticker.total_traded_quote_asset_volume == "0.00000000"
      assert ticker.total_number_of_trades == 0
    end
  end

  describe "edge cases" do
    test "handles very large numbers as strings" do
      data = %{
        "e" => "24hrTicker",
        "E" => "9999999999999",
        "s" => "BTCUSDT",
        "v" => "999999999999.99999999",
        "q" => "99999999999999999.99999999"
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.event_time == 9_999_999_999_999
      assert ticker.total_traded_base_asset_volume == "999999999999.99999999"
      assert ticker.total_traded_quote_asset_volume == "99999999999999999.99999999"
    end

    test "handles nil values gracefully" do
      data = %{
        "e" => "24hrTicker",
        "s" => "BTCUSDT",
        "p" => nil,
        "P" => nil,
        "c" => nil,
        "E" => nil
      }

      {:ok, ticker} = Ticker.parse(data)

      assert ticker.price_change == nil
      assert ticker.price_change_percent == nil
      assert ticker.last_price == nil
      assert ticker.event_time == nil
    end
  end
end
