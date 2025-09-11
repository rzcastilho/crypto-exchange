defmodule CryptoExchange.APITest do
  use ExUnit.Case
  import CryptoExchange.TestHelpers

  alias CryptoExchange.API

  describe "public data operations" do
    test "subscribe_to_ticker/1 returns topic for valid symbol" do
      assert {:ok, topic} = API.subscribe_to_ticker("BTCUSDT")
      assert topic == "binance:ticker:BTCUSDT"
    end

    test "subscribe_to_ticker/1 validates symbol format" do
      assert {:error, :invalid_symbol} = API.subscribe_to_ticker("BT")
      assert {:error, :invalid_symbol} = API.subscribe_to_ticker("btcusdt")
      assert {:error, :invalid_symbol} = API.subscribe_to_ticker("")
      assert {:error, :invalid_symbol} = API.subscribe_to_ticker(nil)
    end

    test "subscribe_to_depth/2 returns topic for valid symbol and level" do
      assert {:ok, topic} = API.subscribe_to_depth("BTCUSDT", 5)
      assert topic == "binance:depth:BTCUSDT"
      
      assert {:ok, topic} = API.subscribe_to_depth("ETHUSDT", 10)
      assert topic == "binance:depth:ETHUSDT"
    end

    test "subscribe_to_depth/2 validates symbol format" do
      assert {:error, :invalid_symbol} = API.subscribe_to_depth("BT", 5)
      assert {:error, :invalid_symbol} = API.subscribe_to_depth("", 5)
    end

    test "subscribe_to_depth/2 validates depth level" do
      assert {:error, :invalid_level} = API.subscribe_to_depth("BTCUSDT", 3)
      assert {:error, :invalid_level} = API.subscribe_to_depth("BTCUSDT", 100)
      assert {:error, :invalid_level} = API.subscribe_to_depth("BTCUSDT", 0)
    end

    test "subscribe_to_trades/1 returns topic for valid symbol" do
      assert {:ok, topic} = API.subscribe_to_trades("BTCUSDT")
      assert topic == "binance:trades:BTCUSDT"
    end

    test "subscribe_to_trades/1 validates symbol format" do
      assert {:error, :invalid_symbol} = API.subscribe_to_trades("BT")
      assert {:error, :invalid_symbol} = API.subscribe_to_trades("")
      assert {:error, :invalid_symbol} = API.subscribe_to_trades(nil)
    end

    test "unsubscribe_from_public_data/1 succeeds for valid symbol" do
      assert :ok = API.unsubscribe_from_public_data("BTCUSDT")
    end

    test "unsubscribe_from_public_data/1 validates symbol format" do
      assert {:error, :invalid_symbol} = API.unsubscribe_from_public_data("BT")
      assert {:error, :invalid_symbol} = API.unsubscribe_from_public_data("")
      assert {:error, :invalid_symbol} = API.unsubscribe_from_public_data(nil)
    end
  end

  describe "user trading operations" do
    test "connect_user/3 validates credentials format" do
      credentials = mock_credentials()
      assert {:error, :invalid_api_key_format} = API.connect_user("user1", credentials.api_key, credentials.secret_key)
    end

    test "disconnect_user/1 returns not connected error for non-existent user" do
      assert {:error, :not_connected} = API.disconnect_user("user1")
    end

    test "place_order/2 returns not connected error for non-existent user" do
      order_params = mock_order_params()
      assert {:error, :not_connected} = API.place_order("user1", order_params)
    end

    test "cancel_order/2 returns not connected error for non-existent user" do
      assert {:error, :not_connected} = API.cancel_order("user1", "order_123")
    end

    test "get_balance/1 returns not connected error for non-existent user" do
      assert {:error, :not_connected} = API.get_balance("user1")
    end

    test "get_orders/1 returns not connected error for non-existent user" do
      assert {:error, :not_connected} = API.get_orders("user1")
    end
  end
end