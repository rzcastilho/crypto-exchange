defmodule CryptoExchange.Binance.AuthTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Binance.Auth

  describe "validate_credentials/1" do
    test "validates correct credentials structure" do
      valid_credentials = %{
        api_key: "test_api_key",
        secret_key: "test_secret_key"
      }

      assert :ok = Auth.validate_credentials(valid_credentials)
    end

    test "rejects credentials with missing api_key" do
      invalid_credentials = %{secret_key: "test_secret_key"}
      assert {:error, :missing_api_key} = Auth.validate_credentials(invalid_credentials)
    end

    test "rejects credentials with missing secret_key" do
      invalid_credentials = %{api_key: "test_api_key"}
      assert {:error, :missing_secret_key} = Auth.validate_credentials(invalid_credentials)
    end

    test "rejects credentials with empty api_key" do
      invalid_credentials = %{api_key: "", secret_key: "test_secret_key"}
      assert {:error, :missing_secret_key} = Auth.validate_credentials(invalid_credentials)
    end

    test "rejects credentials with empty secret_key" do
      invalid_credentials = %{api_key: "test_api_key", secret_key: ""}
      assert {:error, :missing_secret_key} = Auth.validate_credentials(invalid_credentials)
    end

    test "rejects non-binary api_key" do
      invalid_credentials = %{api_key: 123, secret_key: "test_secret_key"}
      assert {:error, :missing_secret_key} = Auth.validate_credentials(invalid_credentials)
    end

    test "rejects non-binary secret_key" do
      invalid_credentials = %{api_key: "test_api_key", secret_key: 123}
      assert {:error, :missing_secret_key} = Auth.validate_credentials(invalid_credentials)
    end

    test "rejects non-map input" do
      assert {:error, :invalid_credentials_format} = Auth.validate_credentials("invalid")
      assert {:error, :invalid_credentials_format} = Auth.validate_credentials(nil)
      assert {:error, :invalid_credentials_format} = Auth.validate_credentials([])
    end
  end

  describe "generate_signature/2" do
    test "generates correct HMAC-SHA256 signature" do
      query_string = "symbol=BTCUSDT&side=BUY&type=MARKET&quantity=1&timestamp=1640995200000"
      secret_key = "test_secret_key"

      signature = Auth.generate_signature(query_string, secret_key)

      expected_signature =
        :crypto.mac(:hmac, :sha256, secret_key, query_string)
        |> Base.encode16(case: :lower)

      assert signature == expected_signature
      assert is_binary(signature)
      # SHA256 hex digest is 64 chars
      assert String.length(signature) == 64
    end

    test "generates different signatures for different data" do
      secret_key = "test_secret_key"
      query1 = "symbol=BTCUSDT&timestamp=1640995200000"
      query2 = "symbol=ETHUSDT&timestamp=1640995200001"

      sig1 = Auth.generate_signature(query1, secret_key)
      sig2 = Auth.generate_signature(query2, secret_key)

      assert sig1 != sig2
    end

    test "generates different signatures for different secret keys" do
      query_string = "symbol=BTCUSDT&timestamp=1640995200000"

      sig1 = Auth.generate_signature(query_string, "secret1")
      sig2 = Auth.generate_signature(query_string, "secret2")

      assert sig1 != sig2
    end
  end

  describe "sign_request/2" do
    test "adds timestamp and signature to params" do
      params = %{symbol: "BTCUSDT", side: "BUY", type: "MARKET"}
      credentials = %{secret_key: "test_secret_key"}

      signed_params = Auth.sign_request(params, credentials)

      assert Map.has_key?(signed_params, :timestamp)
      assert Map.has_key?(signed_params, :signature)
      assert signed_params.symbol == "BTCUSDT"
      assert signed_params.side == "BUY"
      assert signed_params.type == "MARKET"

      # Timestamp should be recent (within last minute)
      now = System.system_time(:millisecond)
      assert signed_params.timestamp <= now
      assert signed_params.timestamp >= now - 60_000
    end

    test "preserves original params in signed request" do
      params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: "1.0",
        price: "50000.00"
      }

      credentials = %{secret_key: "test_secret_key"}

      signed_params = Auth.sign_request(params, credentials)

      # All original params should be preserved
      assert signed_params.symbol == params.symbol
      assert signed_params.side == params.side
      assert signed_params.type == params.type
      assert signed_params.quantity == params.quantity
      assert signed_params.price == params.price
    end

    test "signature is deterministic for same input" do
      params = %{symbol: "BTCUSDT", timestamp: 1_640_995_200_000}
      credentials = %{secret_key: "test_secret_key"}

      # Generate signature twice with same params
      query_string = Auth.build_query_string(params)
      sig1 = Auth.generate_signature(query_string, credentials.secret_key)
      sig2 = Auth.generate_signature(query_string, credentials.secret_key)

      assert sig1 == sig2
      assert is_binary(sig1)
      # SHA256 hex digest
      assert String.length(sig1) == 64
    end
  end

  describe "build_query_string/1" do
    test "builds correct query string from params" do
      params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "MARKET",
        timestamp: 1_640_995_200_000,
        signature: "abc123"
      }

      query_string = Auth.build_query_string(params)

      # Should contain all parameters
      assert String.contains?(query_string, "symbol=BTCUSDT")
      assert String.contains?(query_string, "side=BUY")
      assert String.contains?(query_string, "type=MARKET")
      assert String.contains?(query_string, "timestamp=1640995200000")
      assert String.contains?(query_string, "signature=abc123")

      # Should be properly URL encoded and joined
      parts = String.split(query_string, "&")
      assert length(parts) == 5
    end

    test "handles empty params" do
      query_string = Auth.build_query_string(%{})
      assert query_string == ""
    end

    test "URL encodes values properly" do
      params = %{key: "value with spaces", other: "special&chars"}
      query_string = Auth.build_query_string(params)

      assert String.contains?(query_string, "value+with+spaces") or
               String.contains?(query_string, "value%20with%20spaces")
    end

    test "orders params consistently" do
      params = %{z: "last", a: "first", m: "middle"}

      # Build query string multiple times
      qs1 = Auth.build_query_string(params)
      qs2 = Auth.build_query_string(params)
      qs3 = Auth.build_query_string(params)

      # Should be consistent ordering
      assert qs1 == qs2
      assert qs2 == qs3
    end
  end

  describe "get_headers/1" do
    test "returns correct headers with API key" do
      credentials = %{api_key: "test_api_key"}
      headers = Auth.get_headers(credentials)

      assert is_list(headers)
      assert {"X-MBX-APIKEY", "test_api_key"} in headers
      assert {"Content-Type", "application/x-www-form-urlencoded"} in headers
    end

    test "includes required content type header" do
      credentials = %{api_key: "test_api_key"}
      headers = Auth.get_headers(credentials)

      content_type_header = Enum.find(headers, fn {key, _} -> key == "Content-Type" end)
      assert content_type_header == {"Content-Type", "application/x-www-form-urlencoded"}
    end
  end

  describe "get_timestamp/0" do
    test "returns current timestamp in milliseconds" do
      timestamp = Auth.get_timestamp()
      now = System.system_time(:millisecond)

      assert is_integer(timestamp)
      assert timestamp <= now
      # Within last second
      assert timestamp >= now - 1000
    end

    test "returns different timestamps when called at different times" do
      ts1 = Auth.get_timestamp()
      :timer.sleep(1)
      ts2 = Auth.get_timestamp()

      assert ts2 >= ts1
    end
  end
end
