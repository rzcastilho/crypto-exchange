defmodule CryptoExchange.APITest do
  use ExUnit.Case
  import CryptoExchange.TestHelpers

  alias CryptoExchange.API

  describe "public data operations" do
    test "subscribe_to_ticker/1 returns not implemented error" do
      assert {:error, :not_implemented} = API.subscribe_to_ticker("BTCUSDT")
    end

    test "subscribe_to_depth/2 returns not implemented error" do
      assert {:error, :not_implemented} = API.subscribe_to_depth("BTCUSDT", 5)
    end

    test "subscribe_to_trades/1 returns not implemented error" do
      assert {:error, :not_implemented} = API.subscribe_to_trades("BTCUSDT")
    end

    test "unsubscribe_from_public_data/1 returns not implemented error" do
      assert {:error, :not_implemented} = API.unsubscribe_from_public_data("BTCUSDT")
    end
  end

  describe "user trading operations" do
    test "connect_user/3 returns not implemented error" do
      credentials = mock_credentials()
      assert {:error, :not_implemented} = API.connect_user("user1", credentials.api_key, credentials.secret_key)
    end

    test "disconnect_user/1 returns not implemented error" do
      assert {:error, :not_implemented} = API.disconnect_user("user1")
    end

    test "place_order/2 returns not implemented error" do
      order_params = mock_order_params()
      assert {:error, :not_implemented} = API.place_order("user1", order_params)
    end

    test "cancel_order/2 returns not implemented error" do
      assert {:error, :not_implemented} = API.cancel_order("user1", "order_123")
    end

    test "get_balance/1 returns not implemented error" do
      assert {:error, :not_implemented} = API.get_balance("user1")
    end

    test "get_orders/1 returns not implemented error" do
      assert {:error, :not_implemented} = API.get_orders("user1")
    end
  end
end