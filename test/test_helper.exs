# Test helper configuration for CryptoExchange

# Configure Mox for mocking
# Note: For CredentialManager we'll use the actual implementation
# For HTTP client we need a different approach since PrivateClient uses Req directly

# Start the PubSub system for testing
{:ok, _} = Application.ensure_all_started(:crypto_exchange)

# Configure ExUnit
ExUnit.start()

# Optional: Add custom test helpers here
defmodule CryptoExchange.TestHelpers do
  @moduledoc """
  Test helper functions for CryptoExchange tests.
  """

  @doc """
  Creates a test PubSub topic name.
  """
  def test_topic(type, symbol) do
    "test:#{type}:#{symbol}"
  end

  @doc """
  Creates mock market data for testing.
  """
  def mock_market_data(type, symbol, data \\ %{}) do
    {:market_data, %{
      type: type,
      symbol: symbol,
      data: data
    }}
  end

  @doc """
  Creates mock credentials for testing.
  """
  def mock_credentials do
    %{
      api_key: "test_api_key",
      secret_key: "test_secret_key"
    }
  end

  @doc """
  Creates mock order parameters for testing.
  """
  def mock_order_params(overrides \\ %{}) do
    %{
      symbol: "BTCUSDT",
      side: "BUY",
      type: "LIMIT",
      quantity: "0.001",
      price: "50000"
    }
    |> Map.merge(overrides)
  end
end