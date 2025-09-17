defmodule CryptoExchange.Binance.ErrorsTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Binance.Errors

  describe "parse_api_error/1" do
    test "parses standard Binance error response with code and msg" do
      response = %{
        "code" => -1021,
        "msg" => "Timestamp for this request is outside the recvWindow."
      }

      {:ok, error} = Errors.parse_api_error(response)

      assert error.code == -1021
      assert error.message == "Timestamp for this request is outside the recvWindow."
      assert error.category == :authentication
      assert error.severity == :error
      assert error.retryable == false
      assert error.user_message == "Request timestamp is invalid. Please sync your system clock."
    end

    test "parses error response with code and message field" do
      response = %{
        "code" => -2018,
        "message" => "Account has insufficient balance for requested action."
      }

      {:ok, error} = Errors.parse_api_error(response)

      assert error.code == -2018
      assert error.message == "Account has insufficient balance for requested action."
      assert error.category == :trading
      assert error.severity == :error
      assert error.retryable == false
      assert error.user_message == "Balance is insufficient."
    end

    test "parses error response with only code field" do
      response = %{"code" => -1003}

      {:ok, error} = Errors.parse_api_error(response)

      assert error.code == -1003
      assert error.message == "Unknown error"
      assert error.category == :rate_limiting
      assert error.severity == :warning
      assert error.retryable == true
      assert error.user_message == "Too many requests sent. Please slow down and try again."
    end

    test "parses unknown error codes with default configuration" do
      response = %{
        "code" => -9999,
        "msg" => "Unknown error from API"
      }

      {:ok, error} = Errors.parse_api_error(response)

      assert error.code == -9999
      assert error.message == "Unknown error from API"
      assert error.category == :unknown
      assert error.severity == :error
      assert error.retryable == false
      assert error.user_message == "An unexpected error occurred. Please try again later."
    end

    test "parses response without code field" do
      response = %{"msg" => "Some error message"}

      {:ok, error} = Errors.parse_api_error(response)

      assert error.code == :unknown
      assert error.message == "Some error message"
      assert error.category == :unknown
      assert error.severity == :error
      assert error.retryable == false
    end

    test "parses response with message field instead of msg" do
      response = %{"message" => "Error message"}

      {:ok, error} = Errors.parse_api_error(response)

      assert error.code == :unknown
      assert error.message == "Error message"
    end

    test "parses empty response with default message" do
      response = %{}

      {:ok, error} = Errors.parse_api_error(response)

      assert error.code == :unknown
      assert error.message == "Unknown error"
    end

    test "rejects invalid input" do
      assert {:error, :invalid_error_format} = Errors.parse_api_error("invalid")
      assert {:error, :invalid_error_format} = Errors.parse_api_error(nil)
      assert {:error, :invalid_error_format} = Errors.parse_api_error(123)
    end
  end

  describe "parse_http_error/2" do
    test "parses known HTTP status codes" do
      {:ok, error} = Errors.parse_http_error(429)

      assert error.code == 429
      assert error.message == "HTTP 429"
      assert error.category == :rate_limiting
      assert error.severity == :warning
      assert error.retryable == true
      assert error.user_message == "Too many requests. Please wait before trying again."
    end

    test "parses HTTP error with response body" do
      {:ok, error} = Errors.parse_http_error(500, "Internal Server Error")

      assert error.code == 500
      assert error.context == %{response_body: "Internal Server Error"}
      assert error.category == :system
      assert error.retryable == true
    end

    test "handles unknown HTTP status codes with default config" do
      {:ok, error} = Errors.parse_http_error(999)

      assert error.code == 999
      assert error.message == "HTTP 999"
      assert error.category == :system
      assert error.severity == :error
      assert error.retryable == true
      assert error.user_message == "An error occurred while processing your request."
    end

    test "categorizes 5xx errors as system errors" do
      {:ok, error} = Errors.parse_http_error(555)

      assert error.category == :system
      assert error.retryable == true
    end

    test "categorizes non-5xx unknown errors as unknown" do
      {:ok, error} = Errors.parse_http_error(499)

      assert error.category == :unknown
      assert error.retryable == false
    end
  end

  describe "retryable?/1" do
    test "returns true for retryable errors" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Too many requests"})
      assert Errors.retryable?(error) == true
    end

    test "returns false for non-retryable errors" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1021, "msg" => "Invalid timestamp"})
      assert Errors.retryable?(error) == false
    end
  end

  describe "calculate_backoff/3" do
    test "calculates exponential backoff for rate limiting errors" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Too many requests"})

      delay1 = Errors.calculate_backoff(1, error, jitter: false)
      delay2 = Errors.calculate_backoff(2, error, jitter: false)
      delay3 = Errors.calculate_backoff(3, error, jitter: false)

      assert delay1 == 2000
      assert delay2 == 4000
      assert delay3 == 8000
    end

    test "respects maximum delay for rate limiting" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Too many requests"})

      delay = Errors.calculate_backoff(10, error, jitter: false, max_delay: 16000)

      assert delay == 16000
    end

    test "uses retry_after header when available for rate limiting" do
      error = %Errors{
        code: -1003,
        category: :rate_limiting,
        retry_after: 5,
        retryable: true
      }

      delay = Errors.calculate_backoff(1, error, jitter: false, base_delay: 1000)

      assert delay == 5000
    end

    test "calculates backoff for network errors" do
      {:ok, error} = Errors.parse_http_error(504)

      delay1 = Errors.calculate_backoff(1, error, jitter: false)
      delay2 = Errors.calculate_backoff(2, error, jitter: false)

      assert delay1 == 1000
      assert delay2 == 2000
    end

    test "calculates backoff for system errors" do
      {:ok, error} = Errors.parse_http_error(500)

      delay = Errors.calculate_backoff(3, error, jitter: false)

      assert delay == 4000
    end

    test "uses default delay for non-retryable errors" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1021, "msg" => "Invalid timestamp"})

      delay = Errors.calculate_backoff(5, error, base_delay: 500)

      assert delay == 500
    end

    test "adds jitter when enabled" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Too many requests"})

      delay1 = Errors.calculate_backoff(1, error, jitter: true)
      delay2 = Errors.calculate_backoff(1, error, jitter: true)

      # Jitter should make delays different
      refute delay1 == delay2
      # But both should be close to base value
      assert delay1 >= 2000
      assert delay2 >= 2000
      assert delay1 <= 2200
      assert delay2 <= 2200
    end
  end

  describe "error classification functions" do
    test "user_message/1 returns user-friendly message" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -2018, "msg" => "Insufficient balance"})

      assert Errors.user_message(error) == "Balance is insufficient."
    end

    test "severity/1 returns error severity" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Rate limit"})

      assert Errors.severity(error) == :warning
    end

    test "category/1 returns error category" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1021, "msg" => "Invalid timestamp"})

      assert Errors.category(error) == :authentication
    end

    test "authentication_error?/1 identifies auth errors" do
      {:ok, auth_error} = Errors.parse_api_error(%{"code" => -1021, "msg" => "Invalid timestamp"})

      {:ok, other_error} =
        Errors.parse_api_error(%{"code" => -2018, "msg" => "Insufficient balance"})

      assert Errors.authentication_error?(auth_error) == true
      assert Errors.authentication_error?(other_error) == false
    end

    test "rate_limit_error?/1 identifies rate limit errors" do
      {:ok, rate_error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Too many requests"})

      {:ok, other_error} =
        Errors.parse_api_error(%{"code" => -1021, "msg" => "Invalid timestamp"})

      assert Errors.rate_limit_error?(rate_error) == true
      assert Errors.rate_limit_error?(other_error) == false
    end

    test "insufficient_balance?/1 identifies balance errors" do
      {:ok, balance_error} =
        Errors.parse_api_error(%{"code" => -2018, "msg" => "Insufficient balance"})

      {:ok, margin_error} =
        Errors.parse_api_error(%{"code" => -2019, "msg" => "Insufficient margin"})

      {:ok, other_error} =
        Errors.parse_api_error(%{"code" => -1021, "msg" => "Invalid timestamp"})

      assert Errors.insufficient_balance?(balance_error) == true
      assert Errors.insufficient_balance?(margin_error) == true
      assert Errors.insufficient_balance?(other_error) == false
    end
  end

  describe "comprehensive error mapping coverage" do
    test "covers all major authentication error codes" do
      auth_codes = [-1021, -1022, -1125, -2014, -2015]

      Enum.each(auth_codes, fn code ->
        {:ok, error} = Errors.parse_api_error(%{"code" => code, "msg" => "Test message"})
        assert error.category == :authentication
      end)
    end

    test "covers all rate limiting error codes" do
      rate_limit_codes = [-1003, -1015, -2022]

      Enum.each(rate_limit_codes, fn code ->
        {:ok, error} = Errors.parse_api_error(%{"code" => code, "msg" => "Test message"})
        assert error.category == :rate_limiting
        assert error.retryable == true
      end)
    end

    test "covers trading error codes" do
      trading_codes = [-2010, -2013, -2018, -2019, -2020]

      Enum.each(trading_codes, fn code ->
        {:ok, error} = Errors.parse_api_error(%{"code" => code, "msg" => "Test message"})
        assert error.category == :trading
        assert error.retryable == false
      end)
    end

    test "covers validation error codes" do
      validation_codes = [-1100, -1101, -1102, -1103, -1104, -1105]

      Enum.each(validation_codes, fn code ->
        {:ok, error} = Errors.parse_api_error(%{"code" => code, "msg" => "Test message"})
        assert error.category == :validation
        assert error.retryable == false
      end)
    end

    test "covers system error codes" do
      system_codes = [-1000, -1001, -1016]

      Enum.each(system_codes, fn code ->
        {:ok, error} = Errors.parse_api_error(%{"code" => code, "msg" => "Test message"})
        assert error.category == :system
      end)
    end

    test "covers network timeout and connection errors" do
      {:ok, timeout_error} = Errors.parse_api_error(%{"code" => -1007, "msg" => "Timeout"})
      assert timeout_error.category == :network
      assert timeout_error.retryable == true
    end
  end

  describe "HTTP error mapping coverage" do
    test "covers all major HTTP error status codes" do
      http_codes = [400, 401, 403, 404, 418, 429, 500, 502, 503, 504]

      Enum.each(http_codes, fn code ->
        {:ok, error} = Errors.parse_http_error(code)
        assert is_atom(error.category)
        assert is_atom(error.severity)
        assert is_boolean(error.retryable)
        assert is_binary(error.user_message)
      end)
    end

    test "properly categorizes 4xx vs 5xx errors" do
      # 4xx errors should generally not be retryable
      {:ok, client_error} = Errors.parse_http_error(404)
      assert client_error.retryable == false

      # 5xx errors should generally be retryable
      {:ok, server_error} = Errors.parse_http_error(500)
      assert server_error.retryable == true
    end

    test "handles special HTTP codes correctly" do
      # 418 is special Binance IP ban error
      {:ok, ban_error} = Errors.parse_http_error(418)
      assert ban_error.category == :authentication
      assert ban_error.retryable == false

      # 429 is rate limiting
      {:ok, rate_error} = Errors.parse_http_error(429)
      assert rate_error.category == :rate_limiting
      assert rate_error.retryable == true
    end
  end
end
