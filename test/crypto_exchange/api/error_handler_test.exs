defmodule CryptoExchange.API.ErrorHandlerTest do
  use ExUnit.Case, async: true
  alias CryptoExchange.API.ErrorHandler

  describe "translate_error/2 for public API" do
    test "translates successful results unchanged" do
      assert {:ok, "result"} = ErrorHandler.translate_error({:ok, "result"}, :public)
      assert :ok = ErrorHandler.translate_error(:ok, :public)
    end

    test "translates symbol validation errors" do
      assert {:error, :invalid_symbol} = ErrorHandler.translate_error({:error, :invalid_symbol_format}, :public)
    end

    test "translates depth level validation errors" do
      assert {:error, :invalid_level} = ErrorHandler.translate_error({:error, :invalid_depth_level}, :public)
    end

    test "translates service errors" do
      assert {:error, :service_unavailable} = ErrorHandler.translate_error({:error, :stream_manager_down}, :public)
      assert {:error, :service_unavailable} = ErrorHandler.translate_error({:error, :invalid_stream_type}, :public)
    end

    test "translates timeout errors" do
      assert {:error, :connection_timeout} = ErrorHandler.translate_error({:error, :startup_timeout}, :public)
    end

    test "handles unknown errors with fallback" do
      assert {:error, :connection_failed} = ErrorHandler.translate_error({:error, :unknown_error}, :public)
    end
  end

  describe "translate_error/2 for trading API" do
    test "translates user management errors" do
      assert {:error, :invalid_user_id} = ErrorHandler.translate_error({:error, :invalid_user_id_format}, :trading)
      assert {:error, :invalid_credentials} = ErrorHandler.translate_error({:error, :invalid_credentials_format}, :trading)
      assert {:error, :user_already_connected} = ErrorHandler.translate_error({:error, :user_already_exists}, :trading)
      assert {:error, :user_not_connected} = ErrorHandler.translate_error({:error, :user_not_found}, :trading)
    end

    test "translates order validation errors" do
      assert {:error, :invalid_order_params} = ErrorHandler.translate_error({:error, :invalid_order_params_format}, :trading)
      assert {:error, :invalid_order_params} = ErrorHandler.translate_error({:error, {:missing_required_fields, ["symbol"]}}, :trading)
      assert {:error, :invalid_symbol} = ErrorHandler.translate_error({:error, :invalid_symbol_format}, :trading)
      assert {:error, :invalid_side} = ErrorHandler.translate_error({:error, :invalid_side_format}, :trading)
      assert {:error, :invalid_type} = ErrorHandler.translate_error({:error, :invalid_type_format}, :trading)
      assert {:error, :invalid_quantity} = ErrorHandler.translate_error({:error, :invalid_quantity_format}, :trading)
      assert {:error, :invalid_price} = ErrorHandler.translate_error({:error, :invalid_price_format}, :trading)
    end

    test "translates business logic errors" do
      assert {:error, :insufficient_funds} = ErrorHandler.translate_error({:error, :insufficient_balance}, :trading)
      assert {:error, :minimum_notional_not_met} = ErrorHandler.translate_error({:error, :min_notional_not_met}, :trading)
      assert {:error, :price_filter_violation} = ErrorHandler.translate_error({:error, :price_filter_fail}, :trading)
      assert {:error, :quantity_filter_violation} = ErrorHandler.translate_error({:error, :lot_size_filter_fail}, :trading)
      assert {:error, :market_closed} = ErrorHandler.translate_error({:error, :trading_disabled}, :trading)
    end

    test "translates order cancellation errors" do
      assert {:error, :invalid_order_id} = ErrorHandler.translate_error({:error, :invalid_order_id_format}, :trading)
      assert {:error, :order_not_found} = ErrorHandler.translate_error({:error, :order_does_not_exist}, :trading)
      assert {:error, :order_not_cancellable} = ErrorHandler.translate_error({:error, :order_filled}, :trading)
      assert {:error, :order_not_found} = ErrorHandler.translate_error({:error, :order_cancelled}, :trading)
      assert {:error, :order_not_cancellable} = ErrorHandler.translate_error({:error, :order_expired}, :trading)
    end

    test "translates rate limiting errors" do
      assert {:error, :rate_limit_exceeded} = ErrorHandler.translate_error({:error, :rate_limit}, :trading)
      assert {:error, :rate_limit_exceeded} = ErrorHandler.translate_error({:error, :order_rate_limit}, :trading)
    end

    test "translates service and network errors" do
      assert {:error, :service_unavailable} = ErrorHandler.translate_error({:error, :server_error}, :trading)
      assert {:error, :service_unavailable} = ErrorHandler.translate_error({:error, :network_error}, :trading)
      assert {:error, :service_unavailable} = ErrorHandler.translate_error({:error, :connection_failed}, :trading)
    end

    test "handles unknown errors with fallback" do
      assert {:error, :service_unavailable} = ErrorHandler.translate_error({:error, :unknown_trading_error}, :trading)
    end
  end

  describe "create_error/4" do
    test "creates simple error by default" do
      assert {:error, :invalid_symbol} = ErrorHandler.create_error(
        :invalid_symbol, 
        :validation, 
        "Invalid symbol format", 
        ["Use uppercase symbols"]
      )
    end

    test "creates detailed error when requested" do
      {:error, error_details} = ErrorHandler.create_error(
        :invalid_symbol,
        :validation,
        "Invalid symbol format",
        ["Use uppercase symbols"],
        include_details: true
      )

      assert error_details.reason == :invalid_symbol
      assert error_details.category == "Input Validation"
      assert error_details.message == "Invalid symbol format"
      assert error_details.suggestions == ["Use uppercase symbols"]
      assert error_details.severity == "Error"
      assert %DateTime{} = error_details.timestamp
      assert is_binary(error_details.error_code)
    end

    test "sanitizes message and suggestions" do
      {:error, error_details} = ErrorHandler.create_error(
        :test_error,
        :validation,
        "Message with\x00null byte",
        ["Suggestion with\x01control char"],
        include_details: true
      )

      assert error_details.message == "Message withnull byte"
      assert error_details.suggestions == ["Suggestion withcontrol char"]
    end

    test "generates unique error codes" do
      {:error, error1} = ErrorHandler.create_error(:test1, :validation, "Test", [], include_details: true)
      {:error, error2} = ErrorHandler.create_error(:test2, :validation, "Test", [], include_details: true)
      {:error, error3} = ErrorHandler.create_error(:test1, :authentication, "Test", [], include_details: true)

      # Different reasons should have different codes
      assert error1.error_code != error2.error_code
      # Different categories should have different codes
      assert error1.error_code != error3.error_code
    end

    test "handles different severity levels" do
      severities = [:info, :warning, :error, :critical]

      for severity <- severities do
        {:error, error_details} = ErrorHandler.create_error(
          :test_error,
          :validation,
          "Test message",
          [],
          include_details: true,
          severity: severity
        )

        expected_severity = case severity do
          :info -> "Info"
          :warning -> "Warning"
          :error -> "Error"
          :critical -> "Critical"
        end

        assert error_details.severity == expected_severity
      end
    end
  end

  describe "create_detailed_error/5" do
    test "creates comprehensive error details" do
      context = %{user_id: "test123", operation: "place_order"}
      
      {:error, error_details} = ErrorHandler.create_detailed_error(
        :insufficient_funds,
        :business_logic,
        "Account balance insufficient",
        ["Check balance", "Reduce order size"],
        context
      )

      assert error_details.reason == :insufficient_funds
      assert error_details.category == "Business Logic"
      assert error_details.message == "Account balance insufficient"
      assert error_details.suggestions == ["Check balance", "Reduce order size"]
      assert error_details.context == %{user_id: "test123", operation: "place_order"}
      assert %DateTime{} = error_details.timestamp
      assert is_binary(error_details.error_code)
      assert is_binary(error_details.documentation_url)
      assert is_binary(error_details.support_reference)
    end

    test "sanitizes context values" do
      context = %{
        safe_value: "normal_string",
        unsafe_value: "string\x00with\x01control\x02chars",
        numeric_value: 123,
        atom_value: :test,
        invalid_value: %{nested: "map"}
      }
      
      {:error, error_details} = ErrorHandler.create_detailed_error(
        :test_error,
        :validation,
        "Test",
        [],
        context
      )

      assert error_details.context.safe_value == "normal_string"
      assert error_details.context.unsafe_value == "stringwithcontrolchars"
      assert error_details.context.numeric_value == 123
      assert error_details.context.atom_value == :test
      assert error_details.context.invalid_value == "[sanitized]"
    end
  end

  describe "validate_error_format/1" do
    test "validates simple error format" do
      assert true == ErrorHandler.validate_error_format({:error, :invalid_symbol})
      assert true == ErrorHandler.validate_error_format({:error, :user_not_connected})
    end

    test "validates detailed error format" do
      detailed_error = {:error, %{reason: :invalid_symbol, message: "Test"}}
      assert true == ErrorHandler.validate_error_format(detailed_error)
    end

    test "rejects invalid error formats" do
      invalid_formats = [
        {:error, "string_reason"},
        {:error, 123},
        {:error, %{message: "no reason"}},
        {:ok, :not_an_error},
        :invalid_format,
        nil
      ]

      for invalid <- invalid_formats do
        assert false == ErrorHandler.validate_error_format(invalid)
      end
    end
  end

  describe "extract_error_reason/1" do
    test "extracts reason from simple errors" do
      assert :invalid_symbol == ErrorHandler.extract_error_reason({:error, :invalid_symbol})
      assert :user_not_connected == ErrorHandler.extract_error_reason({:error, :user_not_connected})
    end

    test "extracts reason from detailed errors" do
      detailed_error = {:error, %{reason: :insufficient_funds, message: "Test"}}
      assert :insufficient_funds == ErrorHandler.extract_error_reason(detailed_error)
    end

    test "returns nil for invalid formats" do
      invalid_formats = [
        {:error, "string_reason"},
        {:ok, :success},
        :not_an_error,
        nil
      ]

      for invalid <- invalid_formats do
        assert nil == ErrorHandler.extract_error_reason(invalid)
      end
    end
  end

  describe "get_error_description/1" do
    test "returns descriptions for known errors" do
      known_errors = [
        :invalid_symbol,
        :invalid_user_id,
        :invalid_credentials,
        :user_not_connected,
        :insufficient_funds,
        :rate_limit_exceeded,
        :service_unavailable
      ]

      for error <- known_errors do
        description = ErrorHandler.get_error_description(error)
        assert is_binary(description)
        assert String.length(description) > 0
      end
    end

    test "returns generic description for unknown errors" do
      description = ErrorHandler.get_error_description(:unknown_error)
      assert description == "An error occurred during the operation"
    end
  end

  describe "get_error_category/1" do
    test "categorizes validation errors" do
      validation_errors = [
        :invalid_symbol,
        :invalid_user_id,
        :invalid_credentials,
        :invalid_order_params,
        :invalid_quantity,
        :invalid_price,
        :invalid_options
      ]

      for error <- validation_errors do
        assert :validation == ErrorHandler.get_error_category(error)
      end
    end

    test "categorizes authentication errors" do
      assert :authentication == ErrorHandler.get_error_category(:authentication_failed)
    end

    test "categorizes business logic errors" do
      business_errors = [
        :user_not_connected,
        :user_already_connected,
        :insufficient_funds,
        :minimum_notional_not_met,
        :order_not_found
      ]

      for error <- business_errors do
        assert :business_logic == ErrorHandler.get_error_category(error)
      end
    end

    test "categorizes rate limiting errors" do
      assert :rate_limit == ErrorHandler.get_error_category(:rate_limit_exceeded)
    end

    test "categorizes service errors" do
      service_errors = [:service_unavailable, :connection_failed]

      for error <- service_errors do
        assert :service == ErrorHandler.get_error_category(error)
      end
    end

    test "defaults to system category for unknown errors" do
      assert :system == ErrorHandler.get_error_category(:unknown_error)
    end
  end

  describe "error logging" do
    import ExUnit.CaptureLog

    test "logs errors by default" do
      log = capture_log(fn ->
        ErrorHandler.create_error(
          :test_error,
          :validation,
          "Test error message",
          [],
          log_error: true
        )
      end)

      assert log =~ "API error occurred"
      assert log =~ "test_error"
      assert log =~ "validation"
    end

    test "skips logging when disabled" do
      log = capture_log(fn ->
        ErrorHandler.create_error(
          :test_error,
          :validation,
          "Test error message",
          [],
          log_error: false
        )
      end)

      assert log == ""
    end

    test "logs unknown errors with warnings" do
      log = capture_log(fn ->
        ErrorHandler.translate_error({:error, :unknown_error}, :public)
      end)

      assert log =~ "Unknown error in public API"
      assert log =~ "unknown_error"
    end
  end

  describe "error response consistency" do
    test "all public API errors return consistent format" do
      public_errors = [
        {:error, :invalid_symbol_format},
        {:error, :invalid_depth_level},
        {:error, :stream_manager_down},
        {:error, :startup_timeout}
      ]

      for error <- public_errors do
        result = ErrorHandler.translate_error(error, :public)
        assert ErrorHandler.validate_error_format(result)
      end
    end

    test "all trading API errors return consistent format" do
      trading_errors = [
        {:error, :invalid_user_id_format},
        {:error, :invalid_credentials_format},
        {:error, :user_not_found},
        {:error, :insufficient_balance},
        {:error, :rate_limit}
      ]

      for error <- trading_errors do
        result = ErrorHandler.translate_error(error, :trading)
        assert ErrorHandler.validate_error_format(result)
      end
    end
  end
end