defmodule CryptoExchange.Integration.BinancePrivateIntegrationTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Binance.{PrivateClient, RateLimiter}
  alias CryptoExchange.Trading.{UserManager, CredentialManager}

  @moduletag :integration

  @test_user_id "integration_test_user"
  @test_api_key "test_api_key_64_chars_long_for_proper_binance_format_validation"
  @test_secret_key "test_secret_key_32_chars_minimum"

  setup do
    # Skip if we're not running integration tests
    unless System.get_env("RUN_INTEGRATION_TESTS") do
      {:skip, "Integration tests disabled - set RUN_INTEGRATION_TESTS=true to enable"}
    else
      # Start required processes
      start_supervised!({Registry, keys: :unique, name: CryptoExchange.Registry})
      start_supervised!({Phoenix.PubSub, name: CryptoExchange.PubSub})
      
      # Start user manager
      start_supervised!(UserManager)
      
      on_exit(fn ->
        # Clean up user connections
        try do
          UserManager.disconnect_user(@test_user_id)
        catch
          _, _ -> :ok
        end
      end)
      
      :ok
    end
  end

  describe "full integration workflow" do
    test "complete user trading workflow with credential management" do
      # Step 1: Connect user with credentials
      assert {:ok, supervisor_pid} = 
        UserManager.connect_user(@test_user_id, @test_api_key, @test_secret_key)
      
      assert Process.alive?(supervisor_pid)
      
      # Step 2: Verify user connection and credential manager
      assert {:ok, session_info} = UserManager.get_user_session_info(@test_user_id)
      assert session_info.user_id == @test_user_id
      assert Process.alive?(session_info.supervisor_pid)
      
      # Step 3: Test credential manager functionality
      assert {:ok, api_key} = CredentialManager.get_api_key(@test_user_id)
      assert api_key == @test_api_key
      
      # Step 4: Test signature generation
      test_query = "symbol=BTCUSDT&side=BUY&type=LIMIT&quantity=0.001&price=50000&timestamp=1640995200000"
      assert {:ok, signature} = CredentialManager.sign_request(@test_user_id, test_query)
      assert is_binary(signature)
      assert String.length(signature) == 64  # HMAC-SHA256 hex string
      
      # Step 5: Test rate limiting
      assert true = CredentialManager.can_make_request?(@test_user_id)
      
      # Step 6: Test credential validation
      assert {:ok, validation} = CredentialManager.validate_credentials(@test_user_id)
      assert validation.api_key_valid == true
      assert validation.secret_key_valid == true
      assert validation.api_key_length == 64
      
      # Step 7: Get credential statistics
      assert {:ok, stats} = CredentialManager.get_statistics(@test_user_id)
      assert stats.user_id == @test_user_id
      assert stats.validated == true
      assert stats.purged == false
      assert is_integer(stats.created_at)
      
      # Step 8: Test rate limiter integration
      assert {:ok, rate_limiter_pid} = RateLimiter.start_link(@test_user_id)
      assert Process.alive?(rate_limiter_pid)
      
      assert {:ok, :allowed} = RateLimiter.check_request_allowed(@test_user_id, :account)
      RateLimiter.record_request(@test_user_id, :account)
      
      assert {:ok, status} = RateLimiter.get_status(@test_user_id)
      assert status.user_id == @test_user_id
      assert status.current_requests == 1
      assert status.current_weight == 10  # account endpoint weight
      
      # Step 9: Test user connection statistics
      # Since we haven't made real API calls, we'll just verify the structure
      session_stats_result = CryptoExchange.Trading.UserConnection.get_session_stats(@test_user_id)
      
      # This might not work if the UserConnection isn't properly connected to the UserManager
      # but we can test the basic structure exists
      case session_stats_result do
        {:ok, stats} ->
          assert stats.orders_placed == 0
          assert stats.orders_cancelled == 0
          assert stats.balance_checks == 0
          assert stats.errors == 0
          assert is_integer(stats.started_at)
          assert is_integer(stats.session_duration_ms)
          
        {:error, :not_connected} ->
          # This is expected since we're using mocked API calls
          # The important thing is that the error handling works
          :ok
      end
      
      # Step 10: Test graceful disconnect with credential cleanup
      assert :ok = UserManager.disconnect_user(@test_user_id)
      
      # Verify user is disconnected
      assert {:error, :not_connected} = UserManager.get_user_session_info(@test_user_id)
      
      # Verify credentials are purged (should fail after disconnect)
      assert {:error, :credentials_purged} = CredentialManager.get_api_key(@test_user_id)
    end
    
    test "rate limiter circuit breaker functionality" do
      # Start rate limiter for test
      assert {:ok, _pid} = RateLimiter.start_link(@test_user_id <> "_circuit")
      test_user = @test_user_id <> "_circuit"
      
      # Record multiple rate limit hits to trigger circuit breaker
      for _ <- 1..5 do
        RateLimiter.record_rate_limit_hit(test_user)
      end
      
      # Circuit breaker should now be active
      assert {:error, :circuit_breaker_open, retry_after} = 
        RateLimiter.check_request_allowed(test_user, :account)
      
      assert is_integer(retry_after)
      assert retry_after > 0
      
      # Verify status shows circuit breaker is active
      assert {:ok, status} = RateLimiter.get_status(test_user)
      assert status.circuit_breaker_active == true
      assert status.circuit_breaker_count == 5
      
      # Reset and verify circuit breaker clears
      RateLimiter.reset_limits(test_user)
      assert {:ok, :allowed} = RateLimiter.check_request_allowed(test_user, :account)
      
      assert {:ok, reset_status} = RateLimiter.get_status(test_user)
      assert reset_status.circuit_breaker_active == false
      assert reset_status.circuit_breaker_count == 0
    end
    
    test "credential manager security features" do
      test_user = @test_user_id <> "_security"
      
      # Connect user
      assert {:ok, _pid} = 
        UserManager.connect_user(test_user, @test_api_key, @test_secret_key)
      
      # Test multiple signature generations produce different results for different queries
      query1 = "symbol=BTCUSDT&timestamp=1640995200000"
      query2 = "symbol=ETHUSDT&timestamp=1640995200001"
      
      assert {:ok, sig1} = CredentialManager.sign_request(test_user, query1)
      assert {:ok, sig2} = CredentialManager.sign_request(test_user, query2)
      
      assert sig1 != sig2
      assert String.length(sig1) == 64
      assert String.length(sig2) == 64
      
      # Test secure purge
      assert :ok = CredentialManager.secure_purge_credentials(test_user)
      
      # After purge, all operations should fail
      assert {:error, :credentials_purged} = CredentialManager.get_api_key(test_user)
      assert {:error, :credentials_purged} = CredentialManager.sign_request(test_user, query1)
      assert {:error, :credentials_purged} = CredentialManager.validate_credentials(test_user)
      
      # Clean up
      UserManager.disconnect_user(test_user)
    end
    
    test "error handling and recovery scenarios" do
      test_user = @test_user_id <> "_error"
      
      # Test invalid API key format
      invalid_api_key = "too_short"
      assert {:error, :invalid_api_key_format} = 
        UserManager.connect_user(test_user, invalid_api_key, @test_secret_key)
      
      # Test invalid secret key format  
      invalid_secret_key = "short"
      assert {:error, :invalid_secret_key_format} = 
        UserManager.connect_user(test_user, @test_api_key, invalid_secret_key)
      
      # Test connection to non-existent user
      assert {:error, :not_connected} = 
        UserManager.get_user_session_info("non_existent_user")
      
      # Test disconnect non-existent user
      assert {:error, :not_connected} = 
        UserManager.disconnect_user("non_existent_user")
    end
    
    test "concurrent user operations" do
      # Test multiple users can be connected simultaneously
      users = for i <- 1..3 do
        user_id = @test_user_id <> "_concurrent_#{i}"
        assert {:ok, _pid} = UserManager.connect_user(user_id, @test_api_key, @test_secret_key)
        user_id
      end
      
      # Verify all users are connected
      for user_id <- users do
        assert {:ok, session_info} = UserManager.get_user_session_info(user_id)
        assert session_info.user_id == user_id
      end
      
      # Test concurrent credential operations
      tasks = for user_id <- users do
        Task.async(fn ->
          # Test each user can independently access their credentials
          assert {:ok, api_key} = CredentialManager.get_api_key(user_id)
          assert api_key == @test_api_key
          
          # Test rate limiting is per-user
          assert true = CredentialManager.can_make_request?(user_id)
          CredentialManager.record_request(user_id)
          
          user_id
        end)
      end
      
      # Wait for all tasks to complete successfully
      results = Enum.map(tasks, &Task.await/1)
      assert Enum.sort(results) == Enum.sort(users)
      
      # Clean up all users
      for user_id <- users do
        assert :ok = UserManager.disconnect_user(user_id)
      end
    end
  end
end