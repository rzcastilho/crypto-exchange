defmodule CryptoExchange.Binance.PublicClientTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Binance.PublicClient

  describe "new/1" do
    test "creates a new client with default configuration" do
      assert {:ok, %PublicClient{} = client} = PublicClient.new()
      assert client.base_url == "https://api.binance.com"
      assert client.timeout == 10_000
      assert %PublicClient.RetryConfig{} = client.retry_config
    end

    test "creates a new client with custom configuration" do
      opts = [
        base_url: "https://testnet.binance.vision",
        timeout: 5000
      ]

      assert {:ok, %PublicClient{} = client} = PublicClient.new(opts)
      assert client.base_url == "https://testnet.binance.vision"
      assert client.timeout == 5000
    end

    test "creates a client with custom retry configuration" do
      retry_config = %PublicClient.RetryConfig{
        max_retries: 5,
        base_delay: 2000,
        max_delay: 60_000,
        enable_jitter: false,
        retryable_errors: [:network]
      }

      opts = [retry_config: retry_config]

      assert {:ok, %PublicClient{} = client} = PublicClient.new(opts)
      assert client.retry_config.max_retries == 5
      assert client.retry_config.base_delay == 2000
    end
  end

  describe "get_klines/4 - parameter validation" do
    setup do
      {:ok, client} = PublicClient.new()
      %{client: client}
    end

    test "validates symbol is non-empty string", %{client: client} do
      assert {:error, {:invalid_symbol, _}} = PublicClient.get_klines(client, "", "1h")
      assert {:error, {:invalid_symbol, _}} = PublicClient.get_klines(client, nil, "1h")
    end

    test "validates interval is valid", %{client: client} do
      assert {:error, {:invalid_interval, _}} =
               PublicClient.get_klines(client, "BTCUSDT", "invalid")

      assert {:error, {:invalid_interval, _}} = PublicClient.get_klines(client, "BTCUSDT", "2m")
    end

    test "accepts all valid intervals", %{client: client} do
      valid_intervals = [
        "1s",
        "1m",
        "3m",
        "5m",
        "15m",
        "30m",
        "1h",
        "2h",
        "4h",
        "6h",
        "8h",
        "12h",
        "1d",
        "3d",
        "1w",
        "1M"
      ]

      # We can't actually make the requests without mocking, but we can verify
      # that validation passes (request will fail at HTTP level which is ok for this test)
      for interval <- valid_intervals do
        # Validation should pass, even if HTTP request fails
        result = PublicClient.get_klines(client, "BTCUSDT", interval, limit: 1)

        case result do
          {:error, {:invalid_interval, _}} ->
            flunk("Interval #{interval} should be valid but was rejected")

          _ ->
            :ok
        end
      end
    end

    test "validates limit is within range", %{client: client} do
      assert {:error, {:invalid_limit, _}} =
               PublicClient.get_klines(client, "BTCUSDT", "1h", limit: 0)

      assert {:error, {:invalid_limit, _}} =
               PublicClient.get_klines(client, "BTCUSDT", "1h", limit: 1001)

      assert {:error, {:invalid_limit, _}} =
               PublicClient.get_klines(client, "BTCUSDT", "1h", limit: -1)
    end

    test "accepts valid limit values", %{client: client} do
      # Validation should pass for these values
      for limit <- [1, 100, 500, 1000] do
        result = PublicClient.get_klines(client, "BTCUSDT", "1h", limit: limit)

        case result do
          {:error, {:invalid_limit, _}} ->
            flunk("Limit #{limit} should be valid but was rejected")

          _ ->
            :ok
        end
      end
    end
  end

  # Note: We cannot directly test private functions in Elixir.
  # The validation logic is tested through the public get_klines/4 function above.

  describe "RetryConfig" do
    test "default/0 returns default configuration" do
      config = PublicClient.RetryConfig.default()

      assert config.max_retries == 3
      assert config.base_delay == 1000
      assert config.max_delay == 32000
      assert config.enable_jitter == true
      assert config.retryable_errors == [:rate_limiting, :network, :system]
    end
  end
end
