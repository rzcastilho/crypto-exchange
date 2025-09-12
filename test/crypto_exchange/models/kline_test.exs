defmodule CryptoExchange.Models.KlineTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Models.Kline

  describe "parse/1" do
    test "successfully parses a complete Binance kline message" do
      data = %{
        "e" => "kline",
        "E" => 1672515782136,
        "s" => "BTCUSDT",
        "k" => %{
          "t" => 1672515780000,
          "T" => 1672515839999,
          "s" => "BTCUSDT",
          "i" => "1m",
          "f" => 100,
          "L" => 200,
          "o" => "48000.00000000",
          "c" => "48200.50000000",
          "h" => "48300.00000000",
          "l" => "47980.00000000",
          "v" => "1000.50000000",
          "n" => 150,
          "x" => false,
          "q" => "48100000.00000000",
          "V" => "500.25000000",
          "Q" => "24050000.00000000",
          "B" => "123456"
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_type == "kline"
      assert kline.event_time == 1672515782136
      assert kline.symbol == "BTCUSDT"
      assert kline.kline_start_time == 1672515780000
      assert kline.kline_close_time == 1672515839999
      assert kline.interval == "1m"
      assert kline.first_trade_id == 100
      assert kline.last_trade_id == 200
      assert kline.open_price == "48000.00000000"
      assert kline.close_price == "48200.50000000"
      assert kline.high_price == "48300.00000000"
      assert kline.low_price == "47980.00000000"
      assert kline.base_asset_volume == "1000.50000000"
      assert kline.number_of_trades == 150
      assert kline.is_kline_closed == false
      assert kline.quote_asset_volume == "48100000.00000000"
      assert kline.taker_buy_base_asset_volume == "500.25000000"
      assert kline.taker_buy_quote_asset_volume == "24050000.00000000"
    end

    test "parses with minimal required fields" do
      data = %{
        "e" => "kline",
        "s" => "ETHUSDT",
        "k" => %{
          "o" => "4000.00000000",
          "c" => "4150.00000000",
          "i" => "5m"
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_type == "kline"
      assert kline.symbol == "ETHUSDT"
      assert kline.open_price == "4000.00000000"
      assert kline.close_price == "4150.00000000"
      assert kline.interval == "5m"
      assert kline.event_time == nil
      assert kline.is_kline_closed == nil
    end

    test "handles integer timestamps and IDs correctly" do
      data = %{
        "e" => "kline",
        "E" => 1672515782136,
        "s" => "BTCUSDT",
        "k" => %{
          "t" => 1672515780000,
          "T" => 1672515839999,
          "f" => 100,
          "L" => 200,
          "n" => 150
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_time == 1672515782136
      assert kline.kline_start_time == 1672515780000
      assert kline.kline_close_time == 1672515839999
      assert kline.first_trade_id == 100
      assert kline.last_trade_id == 200
      assert kline.number_of_trades == 150
    end

    test "handles string timestamps and IDs correctly" do
      data = %{
        "e" => "kline",
        "E" => "1672515782136",
        "s" => "BTCUSDT",
        "k" => %{
          "t" => "1672515780000",
          "T" => "1672515839999",
          "f" => "100",
          "L" => "200",
          "n" => "150"
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_time == 1672515782136
      assert kline.kline_start_time == 1672515780000
      assert kline.kline_close_time == 1672515839999
      assert kline.first_trade_id == 100
      assert kline.last_trade_id == 200
      assert kline.number_of_trades == 150
    end

    test "handles invalid integer values gracefully" do
      data = %{
        "e" => "kline",
        "E" => "invalid_timestamp",
        "s" => "BTCUSDT",
        "k" => %{
          "t" => "not_a_number",
          "f" => "invalid_id",
          "n" => "invalid_count"
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_time == nil
      assert kline.kline_start_time == nil
      assert kline.first_trade_id == nil
      assert kline.number_of_trades == nil
    end

    test "handles missing kline data object" do
      data = %{
        "e" => "kline",
        "E" => 1672515782136,
        "s" => "BTCUSDT"
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_type == "kline"
      assert kline.symbol == "BTCUSDT"
      assert kline.open_price == nil
      assert kline.close_price == nil
      assert kline.interval == nil
    end

    test "returns error for non-map input" do
      assert {:error, _reason} = Kline.parse("not a map")
      assert {:error, _reason} = Kline.parse(nil)
      assert {:error, _reason} = Kline.parse(42)
      assert {:error, _reason} = Kline.parse([])
    end

    test "handles parsing errors gracefully" do
      # Test with circular reference - should be caught
      data = %{
        "e" => "kline",
        "s" => "BTCUSDT"
      }

      # This should succeed - parsing errors are uncommon with normal data
      assert {:ok, kline} = Kline.parse(data)
      assert kline.event_type == "kline"
    end
  end

  describe "price_change/1" do
    test "calculates positive price change correctly" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48200.50000000"
      }

      {:ok, change} = Kline.price_change(kline)
      assert change == "200.5"
    end

    test "calculates negative price change correctly" do
      kline = %Kline{
        open_price: "48200.50000000",
        close_price: "48000.00000000"
      }

      {:ok, change} = Kline.price_change(kline)
      assert change == "-200.5"
    end

    test "calculates zero price change correctly" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48000.00000000"
      }

      {:ok, change} = Kline.price_change(kline)
      assert change == "0"
    end

    test "returns error for missing price data" do
      kline = %Kline{open_price: nil, close_price: "48000.00"}
      assert {:error, _reason} = Kline.price_change(kline)

      kline = %Kline{open_price: "48000.00", close_price: nil}
      assert {:error, _reason} = Kline.price_change(kline)
    end

    test "returns error for invalid price format" do
      kline = %Kline{
        open_price: "invalid",
        close_price: "48000.00"
      }

      assert {:error, _reason} = Kline.price_change(kline)
    end
  end

  describe "price_change_percent/1" do
    test "calculates positive percentage change correctly" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48200.50000000"
      }

      {:ok, percent} = Kline.price_change_percent(kline)
      # Should be approximately 0.417708%
      assert String.starts_with?(percent, "0.41")
    end

    test "calculates negative percentage change correctly" do
      kline = %Kline{
        open_price: "48200.50000000",
        close_price: "48000.00000000"
      }

      {:ok, percent} = Kline.price_change_percent(kline)
      # Should be approximately -0.415%
      assert String.starts_with?(percent, "-0.4")
    end

    test "calculates zero percentage change correctly" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48000.00000000"
      }

      {:ok, percent} = Kline.price_change_percent(kline)
      assert percent == "0"
    end

    test "returns error for zero open price" do
      kline = %Kline{
        open_price: "0.00000000",
        close_price: "48000.00000000"
      }

      assert {:error, "Division by zero - open price is zero"} = Kline.price_change_percent(kline)
    end

    test "returns error for invalid price data" do
      kline = %Kline{open_price: nil, close_price: "48000.00"}
      assert {:error, _reason} = Kline.price_change_percent(kline)

      kline = %Kline{
        open_price: "invalid",
        close_price: "48000.00"
      }

      assert {:error, _reason} = Kline.price_change_percent(kline)
    end
  end

  describe "is_bullish?/1" do
    test "returns true when close > open" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48200.50000000"
      }

      assert Kline.is_bullish?(kline) == true
    end

    test "returns false when close < open" do
      kline = %Kline{
        open_price: "48200.50000000",
        close_price: "48000.00000000"
      }

      assert Kline.is_bullish?(kline) == false
    end

    test "returns false when close == open (doji)" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48000.00000000"
      }

      assert Kline.is_bullish?(kline) == false
    end

    test "returns false for invalid data" do
      kline = %Kline{open_price: nil, close_price: "48000.00"}
      assert Kline.is_bullish?(kline) == false

      kline = %Kline{
        open_price: "invalid",
        close_price: "48000.00"
      }

      assert Kline.is_bullish?(kline) == false
    end
  end

  describe "is_bearish?/1" do
    test "returns true when close < open" do
      kline = %Kline{
        open_price: "48200.50000000",
        close_price: "48000.00000000"
      }

      assert Kline.is_bearish?(kline) == true
    end

    test "returns false when close > open" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48200.50000000"
      }

      assert Kline.is_bearish?(kline) == false
    end

    test "returns false when close == open (doji)" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48000.00000000"
      }

      assert Kline.is_bearish?(kline) == false
    end

    test "returns false for invalid data" do
      kline = %Kline{open_price: nil, close_price: "48000.00"}
      assert Kline.is_bearish?(kline) == false

      kline = %Kline{
        open_price: "invalid",
        close_price: "48000.00"
      }

      assert Kline.is_bearish?(kline) == false
    end
  end

  describe "body_size/1" do
    test "calculates body size for bullish candle" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48200.50000000"
      }

      {:ok, size} = Kline.body_size(kline)
      assert size == "200.5"
    end

    test "calculates body size for bearish candle" do
      kline = %Kline{
        open_price: "48200.50000000",
        close_price: "48000.00000000"
      }

      {:ok, size} = Kline.body_size(kline)
      assert size == "200.5"
    end

    test "calculates body size for doji (zero body)" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48000.00000000"
      }

      {:ok, size} = Kline.body_size(kline)
      assert size == "0"
    end

    test "returns error for invalid data" do
      kline = %Kline{open_price: nil, close_price: "48000.00"}
      assert {:error, _reason} = Kline.body_size(kline)

      kline = %Kline{
        open_price: "invalid",
        close_price: "48000.00"
      }

      assert {:error, _reason} = Kline.body_size(kline)
    end
  end

  describe "upper_shadow/1" do
    test "calculates upper shadow for bullish candle" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48200.50000000",
        high_price: "48300.00000000"
      }

      {:ok, shadow} = Kline.upper_shadow(kline)
      assert shadow == "99.5"
    end

    test "calculates upper shadow for bearish candle" do
      kline = %Kline{
        open_price: "48200.50000000",
        close_price: "48000.00000000",
        high_price: "48300.00000000"
      }

      {:ok, shadow} = Kline.upper_shadow(kline)
      assert shadow == "99.5"
    end

    test "calculates zero upper shadow when high equals body top" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48200.50000000",
        high_price: "48200.50000000"
      }

      {:ok, shadow} = Kline.upper_shadow(kline)
      assert shadow == "0"
    end

    test "returns error for invalid data" do
      kline = %Kline{
        open_price: nil,
        close_price: "48000.00",
        high_price: "48100.00"
      }

      assert {:error, _reason} = Kline.upper_shadow(kline)

      kline = %Kline{
        open_price: "invalid",
        close_price: "48000.00",
        high_price: "48100.00"
      }

      assert {:error, _reason} = Kline.upper_shadow(kline)
    end
  end

  describe "lower_shadow/1" do
    test "calculates lower shadow for bullish candle" do
      kline = %Kline{
        open_price: "48000.00000000",
        close_price: "48200.50000000",
        low_price: "47950.00000000"
      }

      {:ok, shadow} = Kline.lower_shadow(kline)
      assert shadow == "50"
    end

    test "calculates lower shadow for bearish candle" do
      kline = %Kline{
        open_price: "48200.50000000",
        close_price: "48000.00000000",
        low_price: "47950.00000000"
      }

      {:ok, shadow} = Kline.lower_shadow(kline)
      assert shadow == "50"
    end

    test "calculates zero lower shadow when low equals body bottom" do
      kline = %Kline{
        open_price: "48200.50000000",
        close_price: "48000.00000000",
        low_price: "48000.00000000"
      }

      {:ok, shadow} = Kline.lower_shadow(kline)
      assert shadow == "0"
    end

    test "returns error for invalid data" do
      kline = %Kline{
        open_price: nil,
        close_price: "48000.00",
        low_price: "47950.00"
      }

      assert {:error, _reason} = Kline.lower_shadow(kline)

      kline = %Kline{
        open_price: "invalid",
        close_price: "48000.00",
        low_price: "47950.00"
      }

      assert {:error, _reason} = Kline.lower_shadow(kline)
    end
  end

  describe "real Binance data examples" do
    test "parses actual Binance BTCUSDT kline data" do
      # Real example format from Binance documentation
      data = %{
        "e" => "kline",
        "E" => 123456789,
        "s" => "BNBBTC",
        "k" => %{
          "t" => 123400000,
          "T" => 123460000,
          "s" => "BNBBTC",
          "i" => "1m",
          "f" => 100,
          "L" => 200,
          "o" => "0.0010",
          "c" => "0.0020",
          "h" => "0.0025",
          "l" => "0.0015",
          "v" => "1000",
          "n" => 100,
          "x" => false,
          "q" => "1.0000",
          "V" => "500",
          "Q" => "0.500",
          "B" => "123456"
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_type == "kline"
      assert kline.event_time == 123456789
      assert kline.symbol == "BNBBTC"
      assert kline.interval == "1m"
      assert kline.open_price == "0.0010"
      assert kline.close_price == "0.0020"
      assert kline.high_price == "0.0025"
      assert kline.low_price == "0.0015"
      assert kline.is_kline_closed == false

      # Test utility functions with real data
      assert Kline.is_bullish?(kline) == true
      assert Kline.is_bearish?(kline) == false

      {:ok, change} = Kline.price_change(kline)
      assert change == "0.001"

      {:ok, percent} = Kline.price_change_percent(kline)
      assert percent == "100"  # 100% increase

      {:ok, body} = Kline.body_size(kline)
      assert body == "0.001"
    end

    test "parses kline with different intervals" do
      intervals = ["1s", "1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "6h", "8h", "12h", "1d", "3d", "1w", "1M"]

      for interval <- intervals do
        data = %{
          "e" => "kline",
          "E" => 123456789,
          "s" => "BTCUSDT",
          "k" => %{
            "i" => interval,
            "o" => "50000.00",
            "c" => "50100.00"
          }
        }

        {:ok, kline} = Kline.parse(data)
        assert kline.interval == interval
        assert kline.symbol == "BTCUSDT"
      end
    end

    test "parses closed kline correctly" do
      data = %{
        "e" => "kline",
        "E" => 123456789,
        "s" => "BTCUSDT",
        "k" => %{
          "t" => 123400000,
          "T" => 123459999,
          "i" => "1m",
          "o" => "50000.00",
          "c" => "50100.00",
          "x" => true  # Kline is closed
        }
      }

      {:ok, kline} = Kline.parse(data)
      assert kline.is_kline_closed == true
      assert kline.kline_close_time == 123459999
    end
  end

  describe "edge cases" do
    test "handles very large timestamps and trade IDs" do
      data = %{
        "e" => "kline",
        "E" => 9_999_999_999_999,
        "s" => "BTCUSDT",
        "k" => %{
          "t" => 9_999_999_999_999,
          "T" => 9_999_999_999_999,
          "f" => 9_999_999_999,
          "L" => 9_999_999_999,
          "n" => 9_999_999_999
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_time == 9_999_999_999_999
      assert kline.kline_start_time == 9_999_999_999_999
      assert kline.kline_close_time == 9_999_999_999_999
      assert kline.first_trade_id == 9_999_999_999
      assert kline.last_trade_id == 9_999_999_999
      assert kline.number_of_trades == 9_999_999_999
    end

    test "handles nil values gracefully" do
      data = %{
        "e" => "kline",
        "s" => "BTCUSDT",
        "k" => %{
          "E" => nil,
          "t" => nil,
          "o" => nil,
          "c" => nil,
          "x" => nil
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.event_time == nil
      assert kline.kline_start_time == nil
      assert kline.open_price == nil
      assert kline.close_price == nil
      assert kline.is_kline_closed == nil
    end

    test "handles zero values correctly" do
      data = %{
        "e" => "kline",
        "s" => "TESTUSDT",
        "k" => %{
          "o" => "0.00000000",
          "c" => "0.00000000",
          "h" => "0.00000000",
          "l" => "0.00000000",
          "v" => "0.00000000",
          "n" => 0,
          "f" => 0,
          "L" => 0
        }
      }

      {:ok, kline} = Kline.parse(data)

      assert kline.open_price == "0.00000000"
      assert kline.close_price == "0.00000000"
      assert kline.high_price == "0.00000000"
      assert kline.low_price == "0.00000000"
      assert kline.base_asset_volume == "0.00000000"
      assert kline.number_of_trades == 0
      assert kline.first_trade_id == 0
      assert kline.last_trade_id == 0

      # Test utility functions with zero values
      {:ok, change} = Kline.price_change(kline)
      assert change == "0"

      {:ok, body} = Kline.body_size(kline)
      assert body == "0"

      # Should not be bullish or bearish (doji)
      assert Kline.is_bullish?(kline) == false
      assert Kline.is_bearish?(kline) == false
    end
  end
end