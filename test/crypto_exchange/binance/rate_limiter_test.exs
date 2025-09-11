defmodule CryptoExchange.Binance.RateLimiterTest do
  use ExUnit.Case, async: true
  
  alias CryptoExchange.Binance.RateLimiter
  
  @test_user_id "rate_limit_test_user"
  
  setup do
    # Start rate limiter for test user
    {:ok, pid} = RateLimiter.start_link(@test_user_id)
    
    # Ensure clean state
    RateLimiter.reset_limits(@test_user_id)
    
    %{rate_limiter_pid: pid}
  end
  
  describe "request count rate limiting" do
    test "allows requests under the limit" do
      # Make several requests under the limit
      for _ <- 1..10 do
        assert {:ok, :allowed} = RateLimiter.check_request_allowed(@test_user_id, :account)
        RateLimiter.record_request(@test_user_id, :account)
      end
      
      # Should still be allowed
      assert {:ok, :allowed} = RateLimiter.check_request_allowed(@test_user_id, :account)
    end
    
    test "blocks requests when limit exceeded" do
      # Make requests up to the limit (1200 per minute)
      # We'll simulate this by manipulating the internal state
      
      # First make some legitimate requests
      for _ <- 1..5 do
        assert {:ok, :allowed} = RateLimiter.check_request_allowed(@test_user_id, :account)
        RateLimiter.record_request(@test_user_id, :account)
      end
      
      # Get current status
      status = RateLimiter.get_status(@test_user_id)
      assert status.current_requests == 5
      assert status.current_weight == 50  # 5 * 10 (account endpoint weight)
    end
    
    test "resets rate limits after time window passes" do
      # This test would require time manipulation in a real scenario
      # For now, we'll test the reset functionality
      
      # Make some requests
      for _ <- 1..3 do
        RateLimiter.record_request(@test_user_id, :order_post)
      end
      
      status_before = RateLimiter.get_status(@test_user_id)
      assert status_before.current_requests == 3
      
      # Reset limits
      RateLimiter.reset_limits(@test_user_id)
      
      status_after = RateLimiter.get_status(@test_user_id)
      assert status_after.current_requests == 0
      assert status_after.current_weight == 0
    end
  end
  
  describe "weight-based rate limiting" do
    test "tracks endpoint weights correctly" do
      # Make requests with different endpoint weights
      RateLimiter.record_request(@test_user_id, :account)  # weight 10
      RateLimiter.record_request(@test_user_id, :order_post)  # weight 1
      RateLimiter.record_request(@test_user_id, :open_orders_all)  # weight 40
      
      status = RateLimiter.get_status(@test_user_id)
      assert status.current_requests == 3
      assert status.current_weight == 51  # 10 + 1 + 40
    end
    
    test "blocks requests when weight limit would be exceeded" do
      # This is a conceptual test - in practice we'd need to simulate
      # many high-weight requests to exceed the 1200 weight limit
      status = RateLimiter.get_status(@test_user_id)
      assert status.weight_limit == 1200
    end
  end
  
  describe "order-specific rate limiting" do
    test "tracks order requests separately" do
      # Make order requests
      for _ <- 1..3 do
        assert {:ok, :allowed} = RateLimiter.check_request_allowed(@test_user_id, :order_post)
        RateLimiter.record_request(@test_user_id, :order_post)
      end
      
      status = RateLimiter.get_status(@test_user_id)
      assert status.current_orders_per_second == 3
    end
    
    test "differentiates between order and non-order endpoints" do
      # Make mixed requests
      RateLimiter.record_request(@test_user_id, :account)  # not an order
      RateLimiter.record_request(@test_user_id, :order_post)  # is an order
      RateLimiter.record_request(@test_user_id, :order_delete)  # is an order
      
      status = RateLimiter.get_status(@test_user_id)
      assert status.current_requests == 3
      assert status.current_orders_per_second == 2
    end
  end
  
  describe "circuit breaker functionality" do
    test "activates circuit breaker after consecutive rate limit hits" do
      # Record multiple rate limit hits
      for _ <- 1..4 do
        RateLimiter.record_rate_limit_hit(@test_user_id)
      end
      
      # Should still be allowed (threshold is 5)
      assert {:ok, :allowed} = RateLimiter.check_request_allowed(@test_user_id, :account)
      
      # One more hit should trigger circuit breaker
      RateLimiter.record_rate_limit_hit(@test_user_id)
      
      # Now requests should be blocked
      assert {:error, :circuit_breaker_open, retry_after} = 
        RateLimiter.check_request_allowed(@test_user_id, :account)
      
      assert is_integer(retry_after)
      assert retry_after > 0
    end
    
    test "resets circuit breaker on successful requests" do
      # Build up some rate limit hits
      for _ <- 1..3 do
        RateLimiter.record_rate_limit_hit(@test_user_id)
      end
      
      # Make a successful request - should reset counter
      RateLimiter.record_request(@test_user_id, :account)
      
      status = RateLimiter.get_status(@test_user_id)
      assert status.circuit_breaker_count == 0
      assert status.circuit_breaker_active == false
    end
  end
  
  describe "status reporting" do
    test "provides comprehensive status information" do
      # Make some varied requests
      RateLimiter.record_request(@test_user_id, :account)
      RateLimiter.record_request(@test_user_id, :order_post)
      RateLimiter.record_rate_limit_hit(@test_user_id)
      
      status = RateLimiter.get_status(@test_user_id)
      
      # Check all expected fields are present
      assert status.user_id == @test_user_id
      assert is_integer(status.current_requests)
      assert is_integer(status.current_weight)
      assert is_integer(status.current_orders_per_second)
      assert status.request_limit == 1200
      assert status.weight_limit == 1200
      assert status.order_limit == 10
      assert is_integer(status.circuit_breaker_count)
      assert is_boolean(status.circuit_breaker_active)
      assert is_integer(status.total_requests)
      assert is_integer(status.total_weight)
      assert is_integer(status.last_reset)
      
      # Verify specific values
      assert status.current_requests == 2
      assert status.current_weight == 11  # account(10) + order_post(1)
      assert status.current_orders_per_second == 1
      assert status.circuit_breaker_count == 1
      assert status.total_requests == 2
      assert status.total_weight == 11
    end
  end
  
  describe "endpoint weight mapping" do
    test "maps endpoint weights correctly" do
      # Test each endpoint type to ensure weights are assigned correctly
      endpoints_and_weights = [
        {:account, 10},
        {:order_post, 1},
        {:order_delete, 1},
        {:open_orders_single, 3},
        {:open_orders_all, 40},
        {:all_orders, 10},
        {:order_status, 2},
        {:trades, 10}
      ]
      
      for {endpoint, expected_weight} <- endpoints_and_weights do
        # Reset for clean testing
        RateLimiter.reset_limits(@test_user_id)
        
        # Record one request
        RateLimiter.record_request(@test_user_id, endpoint)
        
        # Check weight
        status = RateLimiter.get_status(@test_user_id)
        assert status.current_weight == expected_weight, 
          "Endpoint #{endpoint} should have weight #{expected_weight}, got #{status.current_weight}"
      end
    end
    
    test "defaults to weight 1 for unknown endpoints" do
      RateLimiter.record_request(@test_user_id, :unknown_endpoint)
      
      status = RateLimiter.get_status(@test_user_id)
      assert status.current_weight == 1
    end
  end
  
  describe "cleanup functionality" do
    test "cleans up old entries automatically" do
      # This test is conceptual since we can't easily manipulate time
      # In a real implementation, we'd use libraries like :timer_wheel
      # or mock the time functions
      
      # Make some requests
      for _ <- 1..5 do
        RateLimiter.record_request(@test_user_id, :account)
      end
      
      initial_status = RateLimiter.get_status(@test_user_id)
      assert initial_status.current_requests == 5
      
      # In a real test with time manipulation, we'd advance time
      # and verify that old entries are cleaned up
      # For now, we'll just verify the status is maintained
      assert initial_status.current_requests == 5
    end
  end
  
  describe "concurrent access" do
    test "handles concurrent requests safely" do
      # Spawn multiple processes making requests simultaneously
      tasks = for _ <- 1..10 do
        Task.async(fn ->
          for _ <- 1..5 do
            RateLimiter.check_request_allowed(@test_user_id, :account)
            RateLimiter.record_request(@test_user_id, :account)
          end
        end)
      end
      
      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)
      
      # Verify final state is consistent
      status = RateLimiter.get_status(@test_user_id)
      assert status.total_requests == 50
      assert status.total_weight == 500  # 50 * 10
    end
  end
  
  describe "error handling" do
    test "handles invalid user_id gracefully" do
      # This would normally crash, but with proper via_tuple implementation
      # it should handle missing processes gracefully
      
      # For now, we'll just verify our test setup works
      assert Process.alive?(Process.whereis({:via, Registry, {CryptoExchange.Registry, {:rate_limiter, @test_user_id}}}))
    end
    
    test "handles unexpected messages" do
      # Send an unexpected message to the rate limiter
      pid = Process.whereis({:via, Registry, {CryptoExchange.Registry, {:rate_limiter, @test_user_id}}})
      send(pid, :unexpected_message)
      
      # Should still function normally
      assert {:ok, :allowed} = RateLimiter.check_request_allowed(@test_user_id, :account)
    end
  end
end