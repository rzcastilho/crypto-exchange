defmodule CryptoExchange.API.ValidationTest do
  use ExUnit.Case, async: true
  alias CryptoExchange.API.Validation

  describe "validate_symbol/1" do
    test "accepts valid symbols" do
      valid_symbols = ["BTCUSDT", "ETHUSDT", "ADAUSDT", "DOTUSDT", "BTC", "A1B2C3"]
      
      for symbol <- valid_symbols do
        assert :ok = Validation.validate_symbol(symbol), "#{symbol} should be valid"
      end
    end

    test "rejects invalid symbols" do
      invalid_cases = [
        # Too short
        {"BT", "Symbol too short"},
        {"AB", "Symbol too short"},
        # Too long  
        {"VERY_LONG_SYMBOL_NAME_OVER_LIMIT", "Symbol too long"},
        # Invalid characters
        {"btcusdt", "Lowercase not allowed"},
        {"BTC-USDT", "Hyphen not allowed"},
        {"BTC_USDT", "Underscore not allowed"},
        {"BTC USDT", "Space not allowed"},
        {"BTC@USDT", "Special character not allowed"},
        # Control characters
        {"BTC\nUSDT", "Newline not allowed"},
        {"BTC\tUSDT", "Tab not allowed"},
        {"BTC\0USDT", "Null byte not allowed"},
        # Empty/nil
        {"", "Empty string not allowed"},
        # Whitespace only
        {"   ", "Whitespace only not allowed"}
      ]

      for {symbol, description} <- invalid_cases do
        assert {:error, :invalid_symbol_format} = Validation.validate_symbol(symbol), description
      end
    end

    test "rejects non-string inputs" do
      non_string_inputs = [nil, 123, :symbol, %{}, [], true]
      
      for input <- non_string_inputs do
        assert {:error, :invalid_symbol_format} = Validation.validate_symbol(input)
      end
    end

    test "trims whitespace before validation" do
      assert :ok = Validation.validate_symbol("  BTCUSDT  ")
      assert :ok = Validation.validate_symbol("\tETHUSDT\n")
    end
  end

  describe "validate_user_id/1" do
    test "accepts valid user IDs" do
      valid_user_ids = [
        "user123", "trader_001", "user-abc", "client_123", 
        "ABC123", "user_test_123", "a1b2c3d4e5f6"
      ]
      
      for user_id <- valid_user_ids do
        assert :ok = Validation.validate_user_id(user_id), "#{user_id} should be valid"
      end
    end

    test "rejects invalid user IDs" do
      invalid_cases = [
        # Too short
        {"ab", "User ID too short"},
        {"x", "User ID too short"},
        # Too long
        {"user_id_that_is_way_too_long_and_exceeds_the_maximum_allowed_length", "User ID too long"},
        # Invalid characters
        {"user with spaces", "Space not allowed"},
        {"user@domain.com", "@ symbol not allowed"},
        {"user.test", "Dot not allowed"},
        {"user#123", "Hash not allowed"},
        # Control characters
        {"user\ntest", "Newline not allowed"},
        {"user\ttest", "Tab not allowed"},
        {"user\0test", "Null byte not allowed"},
        # Empty/nil
        {"", "Empty string not allowed"}
      ]

      for {user_id, description} <- invalid_cases do
        assert {:error, :invalid_user_id_format} = Validation.validate_user_id(user_id), description
      end
    end

    test "rejects non-string inputs" do
      non_string_inputs = [nil, 123, :user, %{}, [], true]
      
      for input <- non_string_inputs do
        assert {:error, :invalid_user_id_format} = Validation.validate_user_id(input)
      end
    end

    test "trims whitespace before validation" do
      assert :ok = Validation.validate_user_id("  user123  ")
      assert :ok = Validation.validate_user_id("\tuser_test\n")
    end
  end

  describe "validate_api_credentials/2" do
    test "accepts valid credentials" do
      valid_credentials = [
        {"abcdefghijklmnopqrstuvwxyz123456", "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"},
        {"ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890AB", "abcdefghijklmnopqrstuvwxyz1234567890ab"},
        {"1234567890ABCDEF1234567890ABCDEF12345", "FEDCBA0987654321FEDCBA098765432100000"}
      ]
      
      for {api_key, secret_key} <- valid_credentials do
        assert :ok = Validation.validate_api_credentials(api_key, secret_key), 
               "#{api_key}/#{secret_key} should be valid"
      end
    end

    test "rejects invalid credentials" do
      invalid_cases = [
        # Too short
        {"short", "abcdefghijklmnopqrstuvwxyz123456", "API key too short"},
        {"abcdefghijklmnopqrstuvwxyz123456", "short", "Secret key too short"},
        {"short", "short", "Both too short"},
        # Too long
        {String.duplicate("a", 150), "abcdefghijklmnopqrstuvwxyz123456", "API key too long"},
        {"abcdefghijklmnopqrstuvwxyz123456", String.duplicate("s", 150), "Secret key too long"},
        # Invalid characters
        {"api_key_with-hyphen_in_middle_part", "abcdefghijklmnopqrstuvwxyz123456", "Hyphen not allowed"},
        {"abcdefghijklmnopqrstuvwxyz123456", "secret_with@special_character_here", "Special char not allowed"},
        {"api key with spaces in the middle", "abcdefghijklmnopqrstuvwxyz123456", "Space not allowed"},
        # Control characters
        {"api_key_32_characters\nlong_example", "abcdefghijklmnopqrstuvwxyz123456", "Newline not allowed"},
        {"abcdefghijklmnopqrstuvwxyz123456", "secret_key_32_chars\0long_example", "Null byte not allowed"},
        # Empty/nil
        {"", "abcdefghijklmnopqrstuvwxyz123456", "Empty API key"},
        {"abcdefghijklmnopqrstuvwxyz123456", "", "Empty secret key"}
      ]

      for {api_key, secret_key, description} <- invalid_cases do
        assert {:error, :invalid_credentials_format} = Validation.validate_api_credentials(api_key, secret_key), description
      end
    end

    test "rejects non-string inputs" do
      valid_api_key = "abcdefghijklmnopqrstuvwxyz123456"
      
      non_string_inputs = [nil, 123, :secret, %{}, [], true]
      
      for input <- non_string_inputs do
        assert {:error, :invalid_credentials_format} = Validation.validate_api_credentials(input, valid_api_key)
        assert {:error, :invalid_credentials_format} = Validation.validate_api_credentials(valid_api_key, input)
      end
    end

    test "trims whitespace before validation" do
      api_key = "  abcdefghijklmnopqrstuvwxyz123456  "
      secret_key = "\tABCDEFGHIJKLMNOPQRSTUVWXYZ123456\n"
      assert :ok = Validation.validate_api_credentials(api_key, secret_key)
    end
  end

  describe "validate_depth_level/1" do
    test "accepts valid depth levels" do
      valid_levels = [5, 10, 20]
      
      for level <- valid_levels do
        assert :ok = Validation.validate_depth_level(level), "#{level} should be valid"
      end
    end

    test "rejects invalid depth levels" do
      invalid_levels = [1, 3, 4, 6, 7, 8, 9, 11, 15, 19, 21, 25, 50, 100, 0, -5]
      
      for level <- invalid_levels do
        assert {:error, :invalid_depth_level} = Validation.validate_depth_level(level), "#{level} should be invalid"
      end
    end

    test "rejects non-integer inputs" do
      non_integer_inputs = ["5", 5.0, :five, nil, %{}, [], true]
      
      for input <- non_integer_inputs do
        assert {:error, :invalid_depth_level} = Validation.validate_depth_level(input)
      end
    end
  end

  describe "validate_order_params/1" do
    test "accepts valid order parameters" do
      valid_params = [
        # Market order
        %{
          "symbol" => "BTCUSDT",
          "side" => "BUY",
          "type" => "MARKET",
          "quantity" => "0.001"
        },
        # Limit order
        %{
          "symbol" => "ETHUSDT",
          "side" => "SELL",
          "type" => "LIMIT",
          "quantity" => "1.5",
          "price" => "2000.50"
        },
        # Order with all optional fields
        %{
          "symbol" => "ADAUSDT",
          "side" => "BUY",
          "type" => "LIMIT",
          "quantity" => "100",
          "price" => "0.50",
          "timeInForce" => "GTC",
          "newClientOrderId" => "my_order_123"
        }
      ]
      
      for params <- valid_params do
        assert :ok = Validation.validate_order_params(params), "#{inspect(params)} should be valid"
      end
    end

    test "rejects invalid order parameters" do
      invalid_cases = [
        # Missing required fields
        {%{"symbol" => "BTCUSDT"}, "Missing required fields"},
        {%{"symbol" => "BTCUSDT", "side" => "BUY"}, "Missing type and quantity"},
        {%{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET"}, "Missing quantity"},
        # Invalid field values
        {%{"symbol" => "BT", "side" => "BUY", "type" => "MARKET", "quantity" => "0.001"}, "Invalid symbol"},
        {%{"symbol" => "BTCUSDT", "side" => "INVALID", "type" => "MARKET", "quantity" => "0.001"}, "Invalid side"},
        {%{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "INVALID", "quantity" => "0.001"}, "Invalid type"},
        {%{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET", "quantity" => "invalid"}, "Invalid quantity"},
        {%{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET", "quantity" => "-0.001"}, "Negative quantity"},
        {%{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET", "quantity" => "0"}, "Zero quantity"},
        # LIMIT order without price
        {%{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "0.001"}, "LIMIT order missing price"},
        # Invalid price for LIMIT order
        {%{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "0.001", "price" => "invalid"}, "Invalid price format"},
        {%{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "0.001", "price" => "-1000"}, "Negative price"},
        # Nil/empty values
        {%{"symbol" => nil, "side" => "BUY", "type" => "MARKET", "quantity" => "0.001"}, "Nil symbol"},
        {%{"symbol" => "", "side" => "BUY", "type" => "MARKET", "quantity" => "0.001"}, "Empty symbol"},
        {%{"symbol" => "BTCUSDT", "side" => "", "type" => "MARKET", "quantity" => "0.001"}, "Empty side"}
      ]

      for {params, description} <- invalid_cases do
        assert {:error, _reason} = Validation.validate_order_params(params), description
      end
    end

    test "rejects non-map inputs" do
      non_map_inputs = [nil, "params", 123, :params, [], true]
      
      for input <- non_map_inputs do
        assert {:error, :invalid_order_params_format} = Validation.validate_order_params(input)
      end
    end

    test "validates time in force parameter" do
      valid_tif_values = ["GTC", "IOC", "FOK"]
      
      for tif <- valid_tif_values do
        params = %{
          "symbol" => "BTCUSDT",
          "side" => "BUY", 
          "type" => "LIMIT",
          "quantity" => "0.001",
          "price" => "50000",
          "timeInForce" => tif
        }
        assert :ok = Validation.validate_order_params(params), "#{tif} should be valid"
      end

      # Invalid time in force
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT", 
        "quantity" => "0.001",
        "price" => "50000",
        "timeInForce" => "INVALID"
      }
      assert {:error, :invalid_time_in_force} = Validation.validate_order_params(invalid_params)
    end

    test "validates client order ID parameter" do
      # Valid client order ID
      valid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "MARKET",
        "quantity" => "0.001",
        "newClientOrderId" => "my_order_123"
      }
      assert :ok = Validation.validate_order_params(valid_params)

      # Client order ID too long
      invalid_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "MARKET",
        "quantity" => "0.001", 
        "newClientOrderId" => String.duplicate("x", 50)
      }
      assert {:error, :invalid_client_order_id} = Validation.validate_order_params(invalid_params)
    end
  end

  describe "validate_order_id/1" do
    test "accepts valid order IDs" do
      valid_order_ids = [
        "12345678",
        "my_order_001", 
        "client_order_abc123",
        "ORDER_123_ABC",
        "1",
        String.duplicate("a", 50)  # Reasonable length
      ]
      
      for order_id <- valid_order_ids do
        assert :ok = Validation.validate_order_id(order_id), "#{order_id} should be valid"
      end
    end

    test "rejects invalid order IDs" do
      invalid_cases = [
        {"", "Empty order ID"},
        {String.duplicate("a", 150), "Order ID too long"},
        {"order\nid", "Newline not allowed"},
        {"order\tid", "Tab not allowed"}, 
        {"order\0id", "Null byte not allowed"}
      ]

      for {order_id, description} <- invalid_cases do
        assert {:error, :invalid_order_id_format} = Validation.validate_order_id(order_id), description
      end
    end

    test "rejects non-string inputs" do
      non_string_inputs = [nil, 123, :order_id, %{}, [], true]
      
      for input <- non_string_inputs do
        assert {:error, :invalid_order_id_format} = Validation.validate_order_id(input)
      end
    end

    test "trims whitespace before validation" do
      assert :ok = Validation.validate_order_id("  12345678  ")
      assert :ok = Validation.validate_order_id("\tmy_order_001\n")
    end
  end

  describe "validate_balance_options/1" do
    test "accepts valid balance options" do
      valid_options = [
        %{},
        %{"force_refresh" => true},
        %{"include_zero" => false},
        %{"asset_filter" => "BTC"},
        %{"timeout" => 10000},
        %{
          "force_refresh" => true,
          "include_zero" => true,
          "asset_filter" => "ETH",
          "timeout" => 15000
        }
      ]
      
      for opts <- valid_options do
        assert :ok = Validation.validate_balance_options(opts), "#{inspect(opts)} should be valid"
      end
    end

    test "rejects invalid balance options" do
      invalid_cases = [
        {%{"force_refresh" => "true"}, "Boolean as string"},
        {%{"include_zero" => 1}, "Integer instead of boolean"},
        {%{"asset_filter" => 123}, "Integer instead of string"},
        {%{"asset_filter" => "btc"}, "Lowercase asset"},
        {%{"asset_filter" => "BTC@USD"}, "Special character in asset"},
        {%{"asset_filter" => ""}, "Empty asset filter"},
        {%{"timeout" => "10000"}, "String timeout"},
        {%{"timeout" => -1000}, "Negative timeout"},
        {%{"timeout" => 0}, "Zero timeout"}
      ]

      for {opts, description} <- invalid_cases do
        assert {:error, _reason} = Validation.validate_balance_options(opts), description
      end
    end

    test "rejects non-map inputs" do
      non_map_inputs = [nil, "options", 123, :options, [], true]
      
      for input <- non_map_inputs do
        assert {:error, :invalid_options_format} = Validation.validate_balance_options(input)
      end
    end
  end

  describe "validate_orders_options/1" do
    test "accepts valid orders options" do
      valid_options = [
        %{},
        %{"symbol" => "BTCUSDT"},
        %{"status" => "NEW"},
        %{"limit" => 100},
        %{"from_cache" => true},
        %{"timeout" => 15000},
        %{
          "symbol" => "ETHUSDT",
          "status" => "FILLED",
          "limit" => 50,
          "from_cache" => false,
          "timeout" => 10000
        }
      ]
      
      for opts <- valid_options do
        assert :ok = Validation.validate_orders_options(opts), "#{inspect(opts)} should be valid"
      end
    end

    test "rejects invalid orders options" do
      invalid_cases = [
        {%{"symbol" => "BT"}, "Invalid symbol"},
        {%{"status" => "INVALID_STATUS"}, "Invalid status"},
        {%{"limit" => 0}, "Zero limit"},
        {%{"limit" => 2000}, "Limit too high"},
        {%{"limit" => "100"}, "String limit"},
        {%{"from_cache" => "true"}, "String boolean"},
        {%{"timeout" => "15000"}, "String timeout"},
        {%{"timeout" => -1000}, "Negative timeout"}
      ]

      for {opts, description} <- invalid_cases do
        assert {:error, _reason} = Validation.validate_orders_options(opts), description
      end
    end

    test "rejects non-map inputs" do
      non_map_inputs = [nil, "options", 123, :options, [], true]
      
      for input <- non_map_inputs do
        assert {:error, :invalid_options_format} = Validation.validate_orders_options(input)
      end
    end

    test "validates order status values" do
      valid_statuses = ["NEW", "PARTIALLY_FILLED", "FILLED", "CANCELED", "REJECTED", "EXPIRED"]
      
      for status <- valid_statuses do
        opts = %{"status" => status}
        assert :ok = Validation.validate_orders_options(opts), "#{status} should be valid"
      end
    end
  end

  describe "sanitize_string/1" do
    test "removes control characters" do
      input = "Hello\x00\x01\x02World\x7F"
      expected = "HelloWorld"
      assert expected == Validation.sanitize_string(input)
    end

    test "limits string length" do
      long_string = String.duplicate("a", 2000)
      result = Validation.sanitize_string(long_string)
      assert String.length(result) <= 1000
    end

    test "handles non-string inputs" do
      assert "" == Validation.sanitize_string(nil)
      assert "" == Validation.sanitize_string(123)
      assert "" == Validation.sanitize_string(%{})
    end

    test "preserves normal characters" do
      input = "Normal string with UTF-8 characters: €£¥"
      assert input == Validation.sanitize_string(input)
    end
  end

  describe "validate_and_sanitize/2" do
    test "validates and sanitizes symbols" do
      assert {:ok, "BTCUSDT"} = Validation.validate_and_sanitize("  BTCUSDT  ", :symbol)
      assert {:error, :invalid_symbol_format} = Validation.validate_and_sanitize("BT", :symbol)
    end

    test "validates and sanitizes user IDs" do
      assert {:ok, "user123"} = Validation.validate_and_sanitize("  user123  ", :user_id)
      assert {:error, :invalid_user_id_format} = Validation.validate_and_sanitize("x", :user_id)
    end

    test "validates and sanitizes order IDs" do
      assert {:ok, "12345"} = Validation.validate_and_sanitize("  12345  ", :order_id)
      assert {:error, :invalid_order_id_format} = Validation.validate_and_sanitize("", :order_id)
    end

    test "rejects unsupported validation types" do
      assert {:error, :unsupported_validation_type} = Validation.validate_and_sanitize("test", :unknown)
    end

    test "rejects non-string inputs" do
      assert {:error, :invalid_input_type} = Validation.validate_and_sanitize(123, :symbol)
    end
  end

  describe "edge cases and security" do
    test "handles unicode characters appropriately" do
      # Unicode should be rejected in symbols (exchange standard)
      assert {:error, :invalid_symbol_format} = Validation.validate_symbol("BTC€USD")
      
      # Unicode should be rejected in user IDs (security)
      assert {:error, :invalid_user_id_format} = Validation.validate_user_id("user€123")
    end

    test "handles very large strings gracefully" do
      huge_string = String.duplicate("A", 100_000)
      
      # Should not crash, should return error
      assert {:error, :invalid_symbol_format} = Validation.validate_symbol(huge_string)
      assert {:error, :invalid_user_id_format} = Validation.validate_user_id(huge_string)
    end

    test "handles null bytes and control characters" do
      malicious_inputs = [
        "symbol\0test",    # Null byte injection
        "user\ntest",      # Newline injection  
        "order\rtest",     # Carriage return
        "test\tstring",    # Tab character
        "test\vstring",    # Vertical tab
        "test\fstring",    # Form feed
        "test\bstring"     # Backspace
      ]

      for input <- malicious_inputs do
        assert {:error, _} = Validation.validate_symbol(input)
        assert {:error, _} = Validation.validate_user_id(input)
        assert {:error, _} = Validation.validate_order_id(input)
      end
    end

    test "handles precision edge cases for numeric values" do
      # Test quantity precision limits
      order_params_high_precision = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "MARKET",
        "quantity" => "0.123456789"  # 9 decimal places
      }
      
      # Should handle high precision gracefully
      result = Validation.validate_order_params(order_params_high_precision)
      # Implementation should either accept or reject consistently
      assert result in [:ok, {:error, :quantity_precision_exceeded}]
    end

    test "handles concurrent validation calls" do
      # Test that validation is thread-safe
      tasks = for i <- 1..100 do
        Task.async(fn ->
          Validation.validate_symbol("BTCUSDT#{i}")
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All should complete successfully
      assert Enum.all?(results, fn result -> 
        result in [:ok, {:error, :invalid_symbol_format}]
      end)
    end
  end
end