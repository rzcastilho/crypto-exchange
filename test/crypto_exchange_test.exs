defmodule CryptoExchangeTest do
  use ExUnit.Case

  test "application starts successfully" do
    # Application should be started by ExUnit
    assert Process.whereis(CryptoExchange.PubSub) != nil
    assert Process.whereis(CryptoExchange.Registry) != nil
  end
end
