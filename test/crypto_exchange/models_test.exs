defmodule CryptoExchange.ModelsTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Models.{Ticker, OrderBook, Trade, Order, Balance}

  describe "Ticker" do
    test "creates valid ticker from attributes" do
      attrs = %{
        symbol: "BTCUSDT",
        price: 50000.0,
        change: 1.5,
        volume: 1234.56
      }

      assert {:ok, %Ticker{} = ticker} = Ticker.new(attrs)
      assert ticker.symbol == "BTCUSDT"
      assert ticker.price == 50000.0
      assert ticker.change == 1.5
      assert ticker.volume == 1234.56
    end

    test "validates symbol presence" do
      attrs = %{symbol: nil, price: 50000.0, change: 1.5, volume: 1234.56}
      assert {:error, :invalid_symbol} = Ticker.new(attrs)
    end

    test "parses from Binance JSON format" do
      binance_data = %{
        "s" => "BTCUSDT",
        "c" => "50000.00",
        "P" => "1.50",
        "v" => "1234.56"
      }

      assert {:ok, %Ticker{} = ticker} = Ticker.from_binance_json(binance_data)
      assert ticker.symbol == "BTCUSDT"
      assert ticker.price == 50000.0
    end

    test "converts to JSON" do
      {:ok, ticker} = Ticker.new(%{
        symbol: "BTCUSDT",
        price: 50000.0,
        change: 1.5,
        volume: 1234.56
      })

      json = Ticker.to_json(ticker)
      assert json["symbol"] == "BTCUSDT"
      assert json["price"] == 50000.0
    end
  end

  describe "OrderBook" do
    test "creates valid order book" do
      attrs = %{
        symbol: "BTCUSDT",
        bids: [[50000.0, 0.5], [49999.0, 1.0]],
        asks: [[50001.0, 0.3], [50002.0, 0.8]]
      }

      assert {:ok, %OrderBook{} = order_book} = OrderBook.new(attrs)
      assert order_book.symbol == "BTCUSDT"
      assert length(order_book.bids) == 2
      assert length(order_book.asks) == 2
    end

    test "calculates best bid and ask" do
      {:ok, order_book} = OrderBook.new(%{
        symbol: "BTCUSDT",
        bids: [[50000.0, 0.5], [49999.0, 1.0]],
        asks: [[50001.0, 0.3], [50002.0, 0.8]]
      })

      assert OrderBook.best_bid(order_book) == 50000.0
      assert OrderBook.best_ask(order_book) == 50001.0
    end

    test "calculates spread" do
      {:ok, order_book} = OrderBook.new(%{
        symbol: "BTCUSDT",
        bids: [[50000.0, 0.5]],
        asks: [[50001.0, 0.3]]
      })

      assert OrderBook.spread(order_book) == 1.0
    end
  end

  describe "Trade" do
    test "creates valid trade" do
      attrs = %{
        symbol: "BTCUSDT",
        price: 50000.0,
        quantity: 0.1,
        side: :buy
      }

      assert {:ok, %Trade{} = trade} = Trade.new(attrs)
      assert trade.symbol == "BTCUSDT"
      assert trade.side == :buy
    end

    test "calculates notional value" do
      {:ok, trade} = Trade.new(%{
        symbol: "BTCUSDT",
        price: 50000.0,
        quantity: 0.1,
        side: :buy
      })

      assert Trade.notional_value(trade) == 5000.0
    end

    test "parses from Binance JSON" do
      binance_data = %{
        "s" => "BTCUSDT",
        "p" => "50000.0",
        "q" => "0.1",
        "m" => false
      }

      assert {:ok, %Trade{} = trade} = Trade.from_binance_json(binance_data)
      assert trade.side == :buy
    end
  end

  describe "Order" do
    test "creates valid limit order" do
      attrs = %{
        order_id: "123456",
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: 0.001,
        price: 50000.0,
        status: :new
      }

      assert {:ok, %Order{} = order} = Order.new(attrs)
      assert order.order_id == "123456"
      assert order.type == :limit
      assert order.price == 50000.0
    end

    test "creates valid market order without price" do
      attrs = %{
        order_id: "123456",
        symbol: "BTCUSDT",
        side: :buy,
        type: :market,
        quantity: 0.001,
        price: nil,
        status: :new
      }

      assert {:ok, %Order{} = order} = Order.new(attrs)
      assert order.type == :market
      assert order.price == nil
    end

    test "validates price required for limit orders" do
      attrs = %{
        order_id: "123456",
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: 0.001,
        price: nil,
        status: :new
      }

      assert {:error, :price_required_for_limit_orders} = Order.new(attrs)
    end

    test "checks if order is active" do
      {:ok, active_order} = Order.new(%{
        order_id: "123456",
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: 0.001,
        price: 50000.0,
        status: :new
      })

      {:ok, filled_order} = Order.new(%{
        order_id: "123456",
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: 0.001,
        price: 50000.0,
        status: :filled
      })

      assert Order.active?(active_order) == true
      assert Order.active?(filled_order) == false
    end

    test "calculates notional value" do
      {:ok, order} = Order.new(%{
        order_id: "123456",
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: 0.001,
        price: 50000.0,
        status: :new
      })

      assert Order.notional_value(order) == 50.0
    end
  end

  describe "Balance" do
    test "creates valid balance" do
      attrs = %{
        asset: "BTC",
        free: 0.5,
        locked: 0.1
      }

      assert {:ok, %Balance{} = balance} = Balance.new(attrs)
      assert balance.asset == "BTC"
      assert balance.free == 0.5
      assert balance.locked == 0.1
    end

    test "calculates total balance" do
      {:ok, balance} = Balance.new(%{
        asset: "BTC",
        free: 0.5,
        locked: 0.1
      })

      assert Balance.total(balance) == 0.6
    end

    test "checks sufficient free amount" do
      {:ok, balance} = Balance.new(%{
        asset: "BTC",
        free: 0.5,
        locked: 0.1
      })

      assert Balance.sufficient_free?(balance, 0.3) == true
      assert Balance.sufficient_free?(balance, 0.7) == false
    end

    test "checks if balance is non-zero" do
      {:ok, balance} = Balance.new(%{
        asset: "BTC",
        free: 0.5,
        locked: 0.0
      })

      {:ok, zero_balance} = Balance.new(%{
        asset: "BTC",
        free: 0.0,
        locked: 0.0
      })

      assert Balance.non_zero?(balance) == true
      assert Balance.non_zero?(zero_balance) == false
    end
  end

  describe "Utility functions" do
    test "parse_list with valid data" do
      balances_json = [
        %{"asset" => "BTC", "free" => "0.5", "locked" => "0.1"},
        %{"asset" => "ETH", "free" => "10.0", "locked" => "2.0"}
      ]

      assert {:ok, balances} = CryptoExchange.Models.parse_list(balances_json, &Balance.from_binance_json/1)
      assert length(balances) == 2
      assert [%Balance{asset: "BTC"}, %Balance{asset: "ETH"}] = balances
    end

    test "to_json_list converts models to JSON" do
      {:ok, balance1} = Balance.new(%{asset: "BTC", free: 0.5, locked: 0.1})
      {:ok, balance2} = Balance.new(%{asset: "ETH", free: 10.0, locked: 2.0})

      json_list = CryptoExchange.Models.to_json_list([balance1, balance2], &Balance.to_json/1)

      assert length(json_list) == 2
      assert Enum.any?(json_list, &(&1["asset"] == "BTC"))
      assert Enum.any?(json_list, &(&1["asset"] == "ETH"))
    end
  end
end