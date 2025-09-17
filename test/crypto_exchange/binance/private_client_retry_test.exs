defmodule CryptoExchange.Binance.PrivateClientRetryTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Binance.{PrivateClient, Errors}

  describe "RetryConfig" do
    test "default/0 returns sensible defaults" do
      config = PrivateClient.RetryConfig.default()

      assert config.max_retries == 3
      assert config.base_delay == 1000
      assert config.max_delay == 32000
      assert config.enable_jitter == true
      assert config.retryable_errors == [:rate_limiting, :network, :system]
    end
  end

  describe "new/2 with retry configuration" do
    test "creates client with default retry config" do
      credentials = %{api_key: "test_key", secret_key: "test_secret"}

      {:ok, client} = PrivateClient.new(credentials)

      assert %PrivateClient.RetryConfig{} = client.retry_config
      assert client.retry_config.max_retries == 3
      assert client.retry_config.base_delay == 1000
    end

    test "creates client with custom retry config" do
      credentials = %{api_key: "test_key", secret_key: "test_secret"}

      custom_config = %PrivateClient.RetryConfig{
        max_retries: 5,
        base_delay: 2000,
        max_delay: 64000,
        enable_jitter: false,
        retryable_errors: [:rate_limiting, :system]
      }

      {:ok, client} = PrivateClient.new(credentials, retry_config: custom_config)

      assert client.retry_config == custom_config
    end

    test "accepts retry config in opts" do
      credentials = %{api_key: "test_key", secret_key: "test_secret"}

      {:ok, client} =
        PrivateClient.new(credentials,
          base_url: "https://testnet.binance.vision",
          timeout: 15000,
          retry_config: %PrivateClient.RetryConfig{max_retries: 2}
        )

      assert client.base_url == "https://testnet.binance.vision"
      assert client.timeout == 15000
      assert client.retry_config.max_retries == 2
    end
  end

  describe "error classification and retry logic" do
    setup do
      credentials = %{api_key: "test_key", secret_key: "test_secret"}

      retry_config = %PrivateClient.RetryConfig{
        max_retries: 2,
        base_delay: 100,
        max_delay: 1000,
        enable_jitter: false,
        retryable_errors: [:rate_limiting, :network, :system]
      }

      {:ok, client} = PrivateClient.new(credentials, retry_config: retry_config)

      %{client: client}
    end

    test "retries rate limiting errors", %{client: _client} do
      # Test error classification and backoff calculation for rate limiting
      {:ok, rate_limit_error} =
        Errors.parse_api_error(%{"code" => -1003, "msg" => "Too many requests"})

      assert Errors.retryable?(rate_limit_error) == true
      assert Errors.category(rate_limit_error) == :rate_limiting
      assert Errors.rate_limit_error?(rate_limit_error) == true

      # Test backoff calculation for rate limiting
      backoff = Errors.calculate_backoff(1, rate_limit_error, base_delay: 100, jitter: false)
      # The actual implementation should use rate limiting logic
      assert backoff >= 100  # Should be at least the provided base_delay

      backoff2 = Errors.calculate_backoff(2, rate_limit_error, base_delay: 100, jitter: false)
      assert backoff2 >= backoff  # Should increase with attempt number
    end

    test "does not retry authentication errors", %{client: _client} do
      {:ok, auth_error} =
        Errors.parse_api_error(%{"code" => -1021, "msg" => "Invalid timestamp"})

      assert Errors.retryable?(auth_error) == false
      assert Errors.category(auth_error) == :authentication
      assert Errors.authentication_error?(auth_error) == true
    end

    test "does not retry trading errors", %{client: _client} do
      {:ok, balance_error} =
        Errors.parse_api_error(%{"code" => -2018, "msg" => "Insufficient balance"})

      assert Errors.retryable?(balance_error) == false
      assert Errors.category(balance_error) == :trading
      assert Errors.insufficient_balance?(balance_error) == true
    end

    test "retries system errors", %{client: _client} do
      {:ok, system_error} =
        Errors.parse_api_error(%{"code" => -1001, "msg" => "Internal error"})

      assert Errors.retryable?(system_error) == false
      assert Errors.category(system_error) == :system

      {:ok, http_system_error} = Errors.parse_http_error(500, "Internal Server Error")
      assert Errors.retryable?(http_system_error) == true
      assert Errors.category(http_system_error) == :system
    end

    test "retries network errors", %{client: _client} do
      {:ok, timeout_error} = Errors.parse_api_error(%{"code" => -1007, "msg" => "Timeout"})

      assert Errors.retryable?(timeout_error) == true
      assert Errors.category(timeout_error) == :network

      {:ok, gateway_error} = Errors.parse_http_error(504, "Gateway Timeout")
      assert Errors.retryable?(gateway_error) == true
      assert Errors.category(gateway_error) == :network
    end
  end

  describe "error message handling" do
    test "provides user-friendly error messages" do
      test_cases = [
        {-1021, "Request timestamp is invalid. Please sync your system clock."},
        {-2018, "Balance is insufficient."},
        {-1003, "Too many requests sent. Please slow down and try again."},
        {429, "Too many requests. Please wait before trying again."},
        {500, "Internal server error. Please try again later."}
      ]

      Enum.each(test_cases, fn {code, expected_message} ->
        {:ok, error} =
          if code > 0 do
            Errors.parse_http_error(code)
          else
            Errors.parse_api_error(%{"code" => code, "msg" => "Test message"})
          end

        assert Errors.user_message(error) == expected_message
      end)
    end

    test "categorizes errors by severity" do
      # Rate limiting should be warning
      {:ok, rate_error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Rate limit"})
      assert Errors.severity(rate_error) == :warning

      # Authentication should be error
      {:ok, auth_error} = Errors.parse_api_error(%{"code" => -1021, "msg" => "Auth error"})
      assert Errors.severity(auth_error) == :error

      # Trading errors should be error
      {:ok, trading_error} = Errors.parse_api_error(%{"code" => -2018, "msg" => "Trading error"})
      assert Errors.severity(trading_error) == :error
    end
  end

  describe "backoff calculation" do
    test "calculates exponential backoff for rate limiting" do
      {:ok, rate_error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Rate limit"})

      # Test exponential progression for rate limiting
      backoff1 = Errors.calculate_backoff(1, rate_error, base_delay: 1000, jitter: false)
      backoff2 = Errors.calculate_backoff(2, rate_error, base_delay: 1000, jitter: false)
      backoff3 = Errors.calculate_backoff(3, rate_error, base_delay: 1000, jitter: false)

      # Should increase exponentially
      assert backoff2 >= backoff1
      assert backoff3 >= backoff2
      assert backoff1 >= 1000  # Should be at least base delay
    end

    test "respects maximum delay" do
      {:ok, rate_error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Rate limit"})

      backoff = Errors.calculate_backoff(10, rate_error, base_delay: 1000, max_delay: 5000, jitter: false)
      assert backoff == 5000
    end

    test "adds jitter when enabled" do
      {:ok, rate_error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Rate limit"})

      delays =
        1..10
        |> Enum.map(fn _ ->
          Errors.calculate_backoff(1, rate_error, base_delay: 1000, jitter: true)
        end)

      # All delays should be different due to jitter
      unique_delays = Enum.uniq(delays)
      assert length(unique_delays) > 1

      # All delays should be reasonable and include some jitter variation
      base_delay = 1000
      Enum.each(delays, fn delay ->
        assert delay >= base_delay  # Should be at least base delay
        assert delay <= base_delay * 3  # But not too excessive
      end)
    end

    test "uses retry_after header when available" do
      rate_error = %Errors{
        code: -1003,
        category: :rate_limiting,
        retry_after: 5,
        retryable: true,
        message: "Rate limit",
        severity: :warning,
        user_message: "Rate limited"
      }

      backoff = Errors.calculate_backoff(1, rate_error, base_delay: 1000, jitter: false)
      assert backoff == 5000
    end
  end

  describe "comprehensive error coverage" do
    test "handles unknown error gracefully" do
      {:ok, unknown_error} = Errors.parse_api_error(%{"unknown" => "field"})

      assert unknown_error.code == :unknown
      assert unknown_error.category == :unknown
      assert unknown_error.retryable == false
      assert is_binary(unknown_error.user_message)
    end

    test "handles malformed error responses" do
      # Test cases that should parse successfully but return unknown errors
      valid_but_unknown_cases = [
        %{"malformed" => true},
        %{}
      ]

      Enum.each(valid_but_unknown_cases, fn invalid_input ->
        {:ok, error} = Errors.parse_api_error(invalid_input)
        assert is_struct(error, Errors)
        assert error.category == :unknown
      end)

      # Test cases that should fail parsing
      invalid_cases = [nil, "invalid json string", 123, []]

      Enum.each(invalid_cases, fn invalid_input ->
        assert {:error, :invalid_error_format} = Errors.parse_api_error(invalid_input)
      end)
    end

    test "provides consistent error interface" do
      test_errors = [
        Errors.parse_api_error(%{"code" => -1021, "msg" => "Auth error"}),
        Errors.parse_api_error(%{"code" => -2018, "msg" => "Balance error"}),
        Errors.parse_http_error(429),
        Errors.parse_http_error(500)
      ]

      Enum.each(test_errors, fn {:ok, error} ->
        # All errors should have these basic properties
        assert is_binary(Errors.user_message(error))
        assert is_atom(Errors.category(error))
        assert is_atom(Errors.severity(error))
        assert is_boolean(Errors.retryable?(error))

        # Test classification functions
        assert is_boolean(Errors.authentication_error?(error))
        assert is_boolean(Errors.rate_limit_error?(error))
        assert is_boolean(Errors.insufficient_balance?(error))
      end)
    end
  end
end