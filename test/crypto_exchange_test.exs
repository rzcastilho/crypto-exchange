defmodule CryptoExchangeTest do
  use ExUnit.Case

  test "application can be configured correctly" do
    # Test that the application module exists and can be started
    # This tests the basic application structure without requiring full startup
    assert Code.ensure_loaded?(CryptoExchange.Application)
    
    # Test that the main modules exist
    assert Code.ensure_loaded?(CryptoExchange.Logging)
    assert Code.ensure_loaded?(CryptoExchange.Health)
    assert Code.ensure_loaded?(CryptoExchange.Trading.ErrorHandler)
    assert Code.ensure_loaded?(CryptoExchange.Binance.Errors)
  end
end
