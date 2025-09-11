defmodule CryptoExchange.Binance.PrivateClientTest do
  use ExUnit.Case, async: true
  
  import Mox
  
  alias CryptoExchange.Binance.PrivateClient
  alias CryptoExchange.Trading.CredentialManager
  
  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!
  
  @test_user_id "test_user_123"
  @test_api_key "test_api_key_64_chars_long_for_proper_binance_format_validation"
  @test_secret_key "test_secret_key_32_chars_minimum"
  
  describe "get_balance/1" do
    test "successfully retrieves user balance" do
      user_id = @test_user_id
      
      # Setup mocks for credential manager
      expect(CredentialManagerMock, :get_api_key, fn ^user_id ->
        {:ok, @test_api_key}
      end)
      
      expect(CredentialManagerMock, :can_make_request?, fn ^user_id ->
        true
      end)
      
      expect(CredentialManagerMock, :sign_request, fn ^user_id, query_string ->
        # Verify query string contains timestamp and recvWindow
        assert String.contains?(query_string, "timestamp=")
        assert String.contains?(query_string, "recvWindow=5000")
        {:ok, "mocked_signature_hash"}
      end)
      
      expect(CredentialManagerMock, :record_request, fn ^user_id -> :ok end)
      
      # Mock HTTP response
      mock_balance_response = %{
        "balances" => [
          %{"asset" => "BTC", "free" => "1.5", "locked" => "0.1"},
          %{"asset" => "USDT", "free" => "1000.0", "locked" => "50.0"},
          %{"asset" => "ETH", "free" => "0.0", "locked" => "0.0"}  # Should be filtered out
        ]
      }
      
      expect(HTTPClientMock, :request, fn %{method: :get, url: url, headers: headers} ->
        # Verify URL structure
        assert String.contains?(url, "/api/v3/account")
        assert String.contains?(url, "signature=mocked_signature_hash")
        
        # Verify headers
        assert Enum.any?(headers, fn {key, value} -> 
          key == "X-MBX-APIKEY" and value == @test_api_key 
        end)
        
        {:ok, %{status: 200, body: mock_balance_response}}
      end)
      
      # Execute test
      assert {:ok, balances} = PrivateClient.get_balance(user_id)
      
      # Verify response structure and filtering
      assert length(balances) == 2  # ETH filtered out due to zero amounts
      
      btc_balance = Enum.find(balances, fn b -> b.asset == "BTC" end)
      assert btc_balance.free == 1.5
      assert btc_balance.locked == 0.1
      
      usdt_balance = Enum.find(balances, fn b -> b.asset == "USDT" end)
      assert usdt_balance.free == 1000.0
      assert usdt_balance.locked == 50.0
    end
    
    test "handles API error responses" do
      user_id = @test_user_id
      
      expect(CredentialManagerMock, :get_api_key, fn ^user_id ->
        {:ok, @test_api_key}
      end)
      
      expect(CredentialManagerMock, :can_make_request?, fn ^user_id ->
        true
      end)
      
      expect(CredentialManagerMock, :sign_request, fn ^user_id, _query ->
        {:ok, "signature"}
      end)
      
      expect(CredentialManagerMock, :record_request, fn ^user_id -> :ok end)
      
      # Mock API error response
      error_response = %{"code" => -2015, "msg" => "Invalid API-key, IP, or permissions for action."}
      
      expect(HTTPClientMock, :request, fn _req ->
        {:ok, %{status: 401, body: error_response}}
      end)
      
      assert {:error, :invalid_api_key_ip_or_permissions} = PrivateClient.get_balance(user_id)
    end
    
    test "handles rate limiting" do
      user_id = @test_user_id
      
      expect(CredentialManagerMock, :can_make_request?, fn ^user_id ->
        false
      end)
      
      assert {:error, :rate_limit_exceeded} = PrivateClient.get_balance(user_id)
    end
    
    test "handles user disconnection" do
      user_id = @test_user_id
      
      expect(CredentialManagerMock, :get_api_key, fn ^user_id ->
        {:error, :credentials_purged}
      end)
      
      assert {:error, :user_disconnected} = PrivateClient.get_balance(user_id)
    end
  end
  
  describe "place_order/2" do
    test "successfully places a LIMIT order" do
      order_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001",
        "price" => "50000.0",
        "timeInForce" => "GTC"
      }
      
      setup_successful_order_mocks()
      
      mock_order_response = %{
        "orderId" => 123456789,
        "clientOrderId" => "test_order_123",
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "origQty" => "0.001",
        "price" => "50000.0",
        "status" => "NEW",
        "timeInForce" => "GTC",
        "executedQty" => "0.0",
        "cummulativeQuoteQty" => "0.0",
        "time" => 1640995200000,
        "updateTime" => 1640995200000
      }
      
      expect(HTTPClientMock, :request, fn %{method: :post, body: body} ->
        # Verify order parameters are included
        assert String.contains?(body, "symbol=BTCUSDT")
        assert String.contains?(body, "side=BUY")
        assert String.contains?(body, "type=LIMIT")
        assert String.contains?(body, "quantity=0.001")
        assert String.contains?(body, "price=50000.0")
        assert String.contains?(body, "timeInForce=GTC")
        
        {:ok, %{status: 200, body: mock_order_response}}
      end)
      
      assert {:ok, order} = PrivateClient.place_order(@test_user_id, order_params)
      
      assert order.order_id == "123456789"
      assert order.symbol == "BTCUSDT"
      assert order.side == "BUY"
      assert order.type == "LIMIT"
      assert order.quantity == "0.001"
      assert order.price == "50000.0"
      assert order.status == "NEW"
    end
    
    test "successfully places a MARKET order" do
      order_params = %{
        "symbol" => "BTCUSDT",
        "side" => "SELL",
        "type" => "MARKET",
        "quantity" => "0.001"
      }
      
      setup_successful_order_mocks()
      
      mock_order_response = %{
        "orderId" => 123456790,
        "clientOrderId" => "test_market_order",
        "symbol" => "BTCUSDT",
        "side" => "SELL",
        "type" => "MARKET",
        "origQty" => "0.001",
        "price" => "0.0",
        "status" => "FILLED",
        "timeInForce" => "",
        "executedQty" => "0.001",
        "cummulativeQuoteQty" => "49.95",
        "time" => 1640995200000,
        "updateTime" => 1640995200000
      }
      
      expect(HTTPClientMock, :request, fn %{method: :post, body: body} ->
        # Verify market order doesn't include price or timeInForce
        assert String.contains?(body, "symbol=BTCUSDT")
        assert String.contains?(body, "side=SELL")
        assert String.contains?(body, "type=MARKET")
        assert String.contains?(body, "quantity=0.001")
        refute String.contains?(body, "price=")
        refute String.contains?(body, "timeInForce=")
        
        {:ok, %{status: 200, body: mock_order_response}}
      end)
      
      assert {:ok, order} = PrivateClient.place_order(@test_user_id, order_params)
      assert order.type == "MARKET"
      assert order.status == "FILLED"
    end
    
    test "validates required order parameters" do
      # Missing symbol
      invalid_params = %{
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001"
      }
      
      assert {:error, {:missing_required_fields, ["symbol"]}} = 
        PrivateClient.place_order(@test_user_id, invalid_params)
      
      # Missing price for LIMIT order
      invalid_limit_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001"
      }
      
      assert {:error, {:missing_required_field_for_type, :price, "LIMIT"}} = 
        PrivateClient.place_order(@test_user_id, invalid_limit_params)
    end
    
    test "handles order rejection" do
      order_params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.001",
        "price" => "50000.0"
      }
      
      setup_successful_order_mocks()
      
      error_response = %{"code" => -2010, "msg" => "NEW_ORDER_REJECTED"}
      
      expect(HTTPClientMock, :request, fn _req ->
        {:ok, %{status: 400, body: error_response}}
      end)
      
      assert {:error, :new_order_rejected} = PrivateClient.place_order(@test_user_id, order_params)
    end
  end
  
  describe "cancel_order/3" do
    test "successfully cancels an order" do
      setup_successful_order_mocks()
      
      mock_cancel_response = %{
        "orderId" => 123456789,
        "clientOrderId" => "cancelled_order",
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "origQty" => "0.001",
        "price" => "50000.0",
        "status" => "CANCELED",
        "timeInForce" => "GTC",
        "executedQty" => "0.0",
        "cummulativeQuoteQty" => "0.0",
        "time" => 1640995200000,
        "updateTime" => 1640995300000
      }
      
      expect(HTTPClientMock, :request, fn %{method: :delete, url: url} ->
        assert String.contains?(url, "symbol=BTCUSDT")
        assert String.contains?(url, "orderId=123456789")
        
        {:ok, %{status: 200, body: mock_cancel_response}}
      end)
      
      assert {:ok, cancelled_order} = PrivateClient.cancel_order(@test_user_id, "BTCUSDT", "123456789")
      
      assert cancelled_order.status == "CANCELED"
      assert cancelled_order.order_id == "123456789"
    end
    
    test "handles order not found" do
      setup_successful_order_mocks()
      
      error_response = %{"code" => -2013, "msg" => "Order does not exist."}
      
      expect(HTTPClientMock, :request, fn _req ->
        {:ok, %{status: 400, body: error_response}}
      end)
      
      assert {:error, :order_does_not_exist} = 
        PrivateClient.cancel_order(@test_user_id, "BTCUSDT", "999999")
    end
  end
  
  describe "get_orders/3" do
    test "retrieves order history for a symbol" do
      setup_successful_order_mocks()
      
      mock_orders_response = [
        %{
          "orderId" => 123456789,
          "clientOrderId" => "order_1",
          "symbol" => "BTCUSDT",
          "side" => "BUY",
          "type" => "LIMIT",
          "origQty" => "0.001",
          "price" => "50000.0",
          "status" => "FILLED",
          "timeInForce" => "GTC",
          "executedQty" => "0.001",
          "cummulativeQuoteQty" => "50.0",
          "time" => 1640995200000,
          "updateTime" => 1640995300000
        },
        %{
          "orderId" => 123456790,
          "clientOrderId" => "order_2",
          "symbol" => "BTCUSDT",
          "side" => "SELL",
          "type" => "MARKET",
          "origQty" => "0.001",
          "price" => "0.0",
          "status" => "FILLED",
          "timeInForce" => "",
          "executedQty" => "0.001",
          "cummulativeQuoteQty" => "49.95",
          "time" => 1640995400000,
          "updateTime" => 1640995450000
        }
      ]
      
      expect(HTTPClientMock, :request, fn %{method: :get, url: url} ->
        assert String.contains?(url, "/api/v3/allOrders")
        assert String.contains?(url, "symbol=BTCUSDT")
        
        {:ok, %{status: 200, body: mock_orders_response}}
      end)
      
      assert {:ok, orders} = PrivateClient.get_orders(@test_user_id, "BTCUSDT")
      
      assert length(orders) == 2
      assert Enum.all?(orders, fn order -> order.symbol == "BTCUSDT" end)
      
      [order1, order2] = orders
      assert order1.side == "BUY"
      assert order1.type == "LIMIT"
      assert order2.side == "SELL"
      assert order2.type == "MARKET"
    end
    
    test "applies query options" do
      setup_successful_order_mocks()
      
      expect(HTTPClientMock, :request, fn %{url: url} ->
        assert String.contains?(url, "symbol=BTCUSDT")
        assert String.contains?(url, "limit=10")
        assert String.contains?(url, "startTime=1640995200000")
        
        {:ok, %{status: 200, body: []}}
      end)
      
      opts = %{limit: 10, startTime: 1640995200000}
      assert {:ok, []} = PrivateClient.get_orders(@test_user_id, "BTCUSDT", opts)
    end
  end
  
  describe "get_open_orders/2" do
    test "retrieves open orders for a symbol" do
      setup_successful_order_mocks()
      
      mock_open_orders = [
        %{
          "orderId" => 123456789,
          "clientOrderId" => "open_order",
          "symbol" => "BTCUSDT",
          "side" => "BUY",
          "type" => "LIMIT",
          "origQty" => "0.001",
          "price" => "45000.0",
          "status" => "NEW",
          "timeInForce" => "GTC",
          "executedQty" => "0.0",
          "cummulativeQuoteQty" => "0.0",
          "time" => 1640995200000,
          "updateTime" => 1640995200000
        }
      ]
      
      expect(HTTPClientMock, :request, fn %{url: url} ->
        assert String.contains?(url, "/api/v3/openOrders")
        assert String.contains?(url, "symbol=BTCUSDT")
        
        {:ok, %{status: 200, body: mock_open_orders}}
      end)
      
      assert {:ok, orders} = PrivateClient.get_open_orders(@test_user_id, "BTCUSDT")
      
      assert length(orders) == 1
      [order] = orders
      assert order.status == "NEW"
      assert order.symbol == "BTCUSDT"
    end
    
    test "retrieves all open orders when symbol is nil" do
      setup_successful_order_mocks()
      
      expect(HTTPClientMock, :request, fn %{url: url} ->
        assert String.contains?(url, "/api/v3/openOrders")
        refute String.contains?(url, "symbol=")
        
        {:ok, %{status: 200, body: []}}
      end)
      
      assert {:ok, []} = PrivateClient.get_open_orders(@test_user_id, nil)
    end
  end
  
  describe "error handling" do
    test "handles network errors with retry" do
      user_id = @test_user_id
      
      expect(CredentialManagerMock, :get_api_key, fn ^user_id ->
        {:ok, @test_api_key}
      end)
      
      expect(CredentialManagerMock, :can_make_request?, fn ^user_id ->
        true
      end)
      
      expect(CredentialManagerMock, :sign_request, fn ^user_id, _query ->
        {:ok, "signature"}
      end)
      
      expect(CredentialManagerMock, :record_request, fn ^user_id -> :ok end)
      
      # Mock network error followed by success
      expect(HTTPClientMock, :request, 2, fn _req ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)
      
      expect(HTTPClientMock, :request, fn _req ->
        {:ok, %{status: 200, body: %{"balances" => []}}}
      end)
      
      assert {:ok, []} = PrivateClient.get_balance(@test_user_id)
    end
    
    test "handles rate limit with backoff" do
      setup_successful_order_mocks()
      
      # First request hits rate limit
      expect(HTTPClientMock, :request, fn _req ->
        {:ok, %{status: 429, headers: [{"retry-after", "5"}], body: %{"msg" => "Rate limit exceeded"}}}
      end)
      
      # Second request succeeds
      expect(HTTPClientMock, :request, fn _req ->
        {:ok, %{status: 200, body: %{"balances" => []}}}
      end)
      
      assert {:ok, []} = PrivateClient.get_balance(user_id)
    end
  end
  
  # Helper functions
  
  defp setup_successful_order_mocks do
    user_id = @test_user_id
    
    expect(CredentialManagerMock, :get_api_key, fn ^user_id ->
      {:ok, @test_api_key}
    end)
    
    expect(CredentialManagerMock, :can_make_request?, fn ^user_id ->
      true
    end)
    
    expect(CredentialManagerMock, :sign_request, fn ^user_id, _query ->
      {:ok, "mocked_signature"}
    end)
    
    expect(CredentialManagerMock, :record_request, fn ^user_id -> :ok end)
  end
end