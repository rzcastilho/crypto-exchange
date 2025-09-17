defmodule CryptoExchange.Trading.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Trading.ErrorHandler
  alias CryptoExchange.Binance.Errors

  describe "handle_trading_error/3" do
    test "handles insufficient balance errors with enhanced context" do
      {:ok, binance_error} =
        Errors.parse_api_error(%{"code" => -2018, "msg" => "Insufficient balance"})

      context = %{
        user_id: "test_user",
        order_params: %{"symbol" => "BTCUSDT", "side" => "BUY", "quantity" => "1.0"}
      }

      {:error, enhanced_error} =
        ErrorHandler.handle_trading_error(:place_order, binance_error, context)

      assert enhanced_error.category == :trading
      assert enhanced_error.operation == :place_order
      assert enhanced_error.severity == :error
      assert enhanced_error.retryable == false
      assert String.contains?(enhanced_error.user_message, "Insufficient balance")

      assert Enum.any?(
               enhanced_error.recovery_suggestions,
               &String.contains?(&1, "Check your account balance")
             )
    end

    test "handles invalid symbol errors with symbol-specific suggestions" do
      {:ok, binance_error} = Errors.parse_api_error(%{"code" => -1121, "msg" => "Invalid symbol"})

      context = %{
        user_id: "test_user",
        order_params: %{"symbol" => "INVALIDPAIR", "side" => "BUY"}
      }

      {:error, enhanced_error} =
        ErrorHandler.handle_trading_error(:place_order, binance_error, context)

      assert enhanced_error.category == :validation
      assert enhanced_error.operation == :place_order
      assert enhanced_error.severity == :error
      assert enhanced_error.retryable == false
      assert String.contains?(enhanced_error.user_message, "Invalid symbol")
      assert Enum.any?(enhanced_error.recovery_suggestions, &String.contains?(&1, "INVALIDPAIR"))
    end

    test "handles order not found errors for cancel operations" do
      {:ok, binance_error} =
        Errors.parse_api_error(%{"code" => -2011, "msg" => "Order not found"})

      context = %{
        user_id: "test_user",
        symbol: "BTCUSDT",
        order_id: "12345"
      }

      {:error, enhanced_error} =
        ErrorHandler.handle_trading_error(:cancel_order, binance_error, context)

      assert enhanced_error.category == :trading
      assert enhanced_error.operation == :cancel_order
      assert enhanced_error.severity == :error
      assert enhanced_error.retryable == false
      assert String.contains?(enhanced_error.user_message, "Order not found")
      assert Enum.any?(enhanced_error.recovery_suggestions, &String.contains?(&1, "12345"))
    end

    test "handles rate limiting errors with retry guidance" do
      {:ok, binance_error} =
        Errors.parse_api_error(%{"code" => -1003, "msg" => "Too many requests"})

      context = %{user_id: "test_user"}

      {:error, enhanced_error} =
        ErrorHandler.handle_trading_error(:place_order, binance_error, context)

      assert enhanced_error.category == :rate_limiting
      assert enhanced_error.severity == :warning
      assert enhanced_error.retryable == true
      assert String.contains?(enhanced_error.user_message, "Rate limit")
      assert Enum.any?(enhanced_error.recovery_suggestions, &String.contains?(&1, "Wait"))
    end

    test "handles network timeout errors" do
      context = %{user_id: "test_user"}

      {:error, enhanced_error} =
        ErrorHandler.handle_trading_error(:get_balance, {:error, :timeout}, context)

      assert enhanced_error.category == :network
      assert enhanced_error.severity == :warning
      assert enhanced_error.retryable == true
      assert String.contains?(enhanced_error.user_message, "timeout")
      assert Enum.any?(enhanced_error.recovery_suggestions, &String.contains?(&1, "connection"))
    end
  end

  describe "user_friendly_message/2" do
    test "provides specific messages for different error types" do
      test_cases = [
        {%Errors{code: -2018}, :place_order, "Insufficient balance"},
        {%Errors{code: -1121}, :place_order, "Invalid symbol"},
        {%Errors{code: -2011}, :cancel_order, "Order not found"},
        {%Errors{code: -1003}, :place_order, "Rate limit"},
        {{:error, :invalid_symbol}, :place_order, "Invalid trading pair"},
        {{:error, :timeout}, :get_balance, "Request timeout"}
      ]

      Enum.each(test_cases, fn {error, operation, expected_fragment} ->
        message = ErrorHandler.user_friendly_message(error, operation)

        assert String.contains?(message, expected_fragment),
               "Expected '#{expected_fragment}' in message: #{message}"
      end)
    end

    test "handles unknown errors gracefully" do
      message = ErrorHandler.user_friendly_message({:error, :unknown_error}, :place_order)
      assert is_binary(message)
      assert String.contains?(message, "unexpected error")
    end
  end

  describe "recovery_suggestions/3" do
    test "provides balance-specific suggestions for insufficient balance errors" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -2018, "msg" => "Insufficient balance"})
      context = %{user_id: "test_user"}

      suggestions = ErrorHandler.recovery_suggestions(error, :place_order, context)

      assert Enum.any?(suggestions, &String.contains?(&1, "Check your account balance"))
      assert Enum.any?(suggestions, &String.contains?(&1, "Reduce the order"))
      assert Enum.any?(suggestions, &String.contains?(&1, "Deposit"))
    end

    test "provides symbol-specific suggestions for invalid symbol errors" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1121, "msg" => "Invalid symbol"})

      context = %{
        user_id: "test_user",
        order_params: %{"symbol" => "WRONGPAIR"}
      }

      suggestions = ErrorHandler.recovery_suggestions(error, :place_order, context)

      assert Enum.any?(suggestions, &String.contains?(&1, "WRONGPAIR"))
      assert Enum.any?(suggestions, &String.contains?(&1, "trading pair symbol"))
    end

    test "provides order-specific suggestions for cancel errors" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -2011, "msg" => "Order not found"})

      context = %{
        user_id: "test_user",
        order_id: "67890"
      }

      suggestions = ErrorHandler.recovery_suggestions(error, :cancel_order, context)

      assert Enum.any?(suggestions, &String.contains?(&1, "67890"))
      assert Enum.any?(suggestions, &String.contains?(&1, "order history"))
    end

    test "provides rate limiting suggestions" do
      {:ok, error} = Errors.parse_api_error(%{"code" => -1003, "msg" => "Rate limit"})
      context = %{user_id: "test_user"}

      suggestions = ErrorHandler.recovery_suggestions(error, :place_order, context)

      assert Enum.any?(suggestions, &String.contains?(&1, "Wait"))
      assert Enum.any?(suggestions, &String.contains?(&1, "frequency"))
    end
  end

  describe "classify_error/2" do
    test "correctly classifies different error types" do
      test_cases = [
        {%Errors{category: :trading}, :place_order, :trading},
        {%Errors{category: :rate_limiting}, :place_order, :rate_limiting},
        {{:error, :insufficient_balance}, :place_order, :trading},
        {{:error, :invalid_symbol}, :place_order, :validation},
        {{:error, :timeout}, :get_balance, :network},
        {{:error, :user_not_found}, :place_order, :authentication}
      ]

      Enum.each(test_cases, fn {error, operation, expected_category} ->
        category = ErrorHandler.classify_error(error, operation)

        assert category == expected_category,
               "Expected #{expected_category}, got #{category} for #{inspect(error)}"
      end)
    end
  end

  describe "determine_severity/2" do
    test "assigns appropriate severity levels" do
      test_cases = [
        # Auth error
        {%Errors{code: -1021}, :place_order, :critical},
        {{:error, :user_not_found}, :place_order, :critical},
        # Insufficient balance
        {%Errors{code: -2018}, :place_order, :error},
        {{:error, :invalid_symbol}, :place_order, :error},
        # Rate limiting
        {%Errors{code: -1003}, :place_order, :warning},
        {{:error, :timeout}, :get_balance, :warning},
        # Order not found
        {%Errors{code: -2011}, :cancel_order, :error}
      ]

      Enum.each(test_cases, fn {error, operation, expected_severity} ->
        severity = ErrorHandler.determine_severity(error, operation)

        assert severity == expected_severity,
               "Expected #{expected_severity}, got #{severity} for #{inspect(error)}"
      end)
    end
  end

  describe "is_retryable?/2" do
    test "correctly identifies retryable and non-retryable errors" do
      retryable_errors = [
        {%Errors{retryable: true}, :place_order},
        {{:error, :timeout}, :get_balance},
        {{:error, :connection_failed}, :place_order},
        {{:error, :parse_error}, :get_orders}
      ]

      non_retryable_errors = [
        {%Errors{category: :authentication}, :place_order},
        {%Errors{category: :trading}, :place_order},
        {{:error, :insufficient_balance}, :place_order},
        {{:error, :invalid_symbol}, :place_order},
        {{:error, :user_not_found}, :get_balance}
      ]

      Enum.each(retryable_errors, fn {error, operation} ->
        assert ErrorHandler.is_retryable?(error, operation),
               "Expected #{inspect(error)} to be retryable"
      end)

      Enum.each(non_retryable_errors, fn {error, operation} ->
        refute ErrorHandler.is_retryable?(error, operation),
               "Expected #{inspect(error)} to be non-retryable"
      end)
    end
  end

  describe "validate_trading_params/2" do
    test "validates valid order parameters" do
      valid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001"
      }

      assert ErrorHandler.validate_trading_params(valid_params, "test_user") == :ok
    end

    test "rejects missing required fields" do
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY"
        # Missing type and quantity
      }

      {:error, enhanced_error} = ErrorHandler.validate_trading_params(invalid_params, "test_user")

      assert enhanced_error.category == :validation
      assert enhanced_error.operation == :place_order
      assert String.contains?(enhanced_error.user_message, "Missing required")
    end

    test "rejects invalid symbol format" do
      invalid_params = %{
        # Too short
        "symbol" => "BTC",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001"
      }

      {:error, enhanced_error} = ErrorHandler.validate_trading_params(invalid_params, "test_user")

      assert enhanced_error.category == :validation
      assert String.contains?(enhanced_error.user_message, "Invalid")
    end

    test "rejects invalid quantity values" do
      test_cases = [
        # Zero
        %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "0"},
        # Negative
        %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "-1"},
        # Non-numeric
        %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "abc"},
        # Nil
        %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => nil}
      ]

      Enum.each(test_cases, fn params ->
        {:error, enhanced_error} = ErrorHandler.validate_trading_params(params, "test_user")
        assert enhanced_error.category == :validation

        assert String.contains?(enhanced_error.user_message, "Invalid") or
                 String.contains?(enhanced_error.user_message, "Missing")
      end)
    end

    test "handles both string and atom keys" do
      atom_key_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: "0.001"
      }

      assert ErrorHandler.validate_trading_params(atom_key_params, "test_user") == :ok
    end
  end

  describe "integration with real trading scenarios" do
    test "handles complete place order error flow" do
      # Simulate a real trading error scenario
      order_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        # Large quantity to trigger insufficient balance
        "quantity" => "10.0",
        "price" => "50000.0"
      }

      context = %{
        user_id: "integration_test_user",
        order_params: order_params
      }

      # Simulate Binance insufficient balance error
      {:ok, binance_error} =
        Errors.parse_api_error(%{
          "code" => -2018,
          "msg" => "Account has insufficient balance for requested action."
        })

      {:error, enhanced_error} =
        ErrorHandler.handle_trading_error(:place_order, binance_error, context)

      # Verify the enhanced error provides comprehensive information
      assert enhanced_error.operation == :place_order
      assert enhanced_error.category == :trading
      assert enhanced_error.severity == :error
      assert enhanced_error.retryable == false
      assert is_binary(enhanced_error.user_message)
      assert is_list(enhanced_error.recovery_suggestions)
      assert length(enhanced_error.recovery_suggestions) > 0
      assert enhanced_error.context == context

      # Verify user-friendly message is actionable
      assert String.contains?(enhanced_error.user_message, "balance")
      assert String.contains?(enhanced_error.user_message, "funds")

      # Verify recovery suggestions are helpful
      suggestions_text = Enum.join(enhanced_error.recovery_suggestions, " ")
      assert String.contains?(suggestions_text, "balance")

      assert String.contains?(suggestions_text, "Reduce") or
               String.contains?(suggestions_text, "Deposit")
    end
  end
end
