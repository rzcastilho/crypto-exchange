defmodule CryptoExchangeTest do
  use ExUnit.Case
  doctest CryptoExchange

  describe "version/0" do
    test "returns the application version" do
      version = CryptoExchange.version()
      assert is_binary(version)
      assert version =~ ~r/^\d+\.\d+\.\d+/
    end
  end

  describe "status/0" do
    test "returns :running when application is started" do
      assert CryptoExchange.status() == :running
    end
  end
end