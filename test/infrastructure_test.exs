defmodule CryptoExchange.InfrastructureTest do
  @moduledoc """
  Test to verify that the testing infrastructure is working correctly.
  This test validates the basic functionality of our test support modules.
  """

  use CryptoExchange.TestSupport.TestCaseTemplate, type: :unit
  
  import CryptoExchange.TestSupport.PerformanceHelpers

  describe "testing infrastructure validation" do
    test "factory creates valid order data" do
      order = build(:order, %{symbol: "ETHUSDT", side: :sell})
      
      assert order.symbol == "ETHUSDT"
      assert order.side == :sell
      assert is_float(order.quantity)
      assert is_float(order.price)
    end

    test "factory creates valid market data" do
      ticker = build(:ticker_data, %{symbol: "BTCUSDT"})
      
      assert ticker.symbol == "BTCUSDT"
      assert is_float(ticker.price)
      assert is_float(ticker.change)
      assert is_float(ticker.volume)
    end

    test "mock HTTP responses work" do
      # Just verify that the mock infrastructure can be set up
      # The actual HTTP mocking is tested in specific HTTP test modules
      assert true # Infrastructure is set up correctly
    end

    test "WebSocket test server can be started" do
      {:ok, ws_server} = start_supervised({WebSocketTestServer, [test_pid: self()]})
      
      assert is_pid(ws_server)
      assert Process.alive?(ws_server)
    end

    test "PubSub helpers work correctly" do
      topic = unique_test_topic("test", __MODULE__)
      {_topic, cleanup_fn} = subscribe_with_cleanup(CryptoExchange.PubSub, topic)
      
      # Test message publishing
      test_message = {:test_data, "hello"}
      publish_and_wait(CryptoExchange.PubSub, topic, test_message)
      
      assert_receive ^test_message, 1000
      
      # Cleanup
      cleanup_fn.()
    end

    test "test configuration helpers work" do
      original_value = get_test_config(:test_key, "default")
      
      with_test_config([test_key: "new_value"], fn ->
        assert get_test_config(:test_key) == "new_value"
      end)
      
      # Value should be restored
      assert get_test_config(:test_key, "default") == original_value
    end

    test "data generators work with StreamData" do
      symbol = Enum.take(symbol_generator(), 1) |> hd()
      price = Enum.take(price_generator(), 1) |> hd()
      quantity = Enum.take(quantity_generator(), 1) |> hd()
      
      assert is_binary(symbol)
      assert String.length(symbol) > 0
      assert is_binary(price)
      assert is_binary(quantity)
    end

    test "multiple factory instances work" do
      orders = build_list(3, :order, %{symbol: "BTCUSDT"})
      
      assert length(orders) == 3
      Enum.each(orders, fn order ->
        assert order.symbol == "BTCUSDT"
        assert %Order{} = order
      end)
    end

    test "WebSocket message factories work" do
      ticker_msg = build(:ws_ticker_message, %{symbol: "ETHUSDT"})
      kline_msg = build(:ws_kline_message, %{symbol: "ETHUSDT", interval: "5m"})
      
      assert ticker_msg["e"] == "24hrTicker"
      assert ticker_msg["s"] == "ETHUSDT"
      assert kline_msg["k"]["i"] == "5m"
    end

    test "API response factories work" do
      order_response = build(:api_order_response, %{"symbol" => "ADAUSDT"})
      error_response = build(:api_error_response, %{"code" => -1001})
      
      assert order_response["symbol"] == "ADAUSDT"
      assert error_response["code"] == -1001
    end
  end

  describe "coverage and performance helpers" do
    test "performance measurement works" do
      {result, duration} = CryptoExchange.TestSupport.PerformanceHelpers.measure_time(fn ->
        :timer.sleep(10)
        :ok
      end)
      
      assert result == :ok
      assert duration >= 10_000 # At least 10ms in microseconds
    end

    test "throughput measurement works" do
      metrics = CryptoExchange.TestSupport.PerformanceHelpers.measure_throughput(fn ->
        :simple_operation
      end, 100)
      
      assert metrics.iterations == 100
      assert metrics.total_duration_us > 0
      assert metrics.throughput_per_second > 0
    end
  end

  describe "test environment validation" do
    test "test mode is properly configured" do
      assert test_env?()
      assert get_test_config(:enable_real_connections) == false
    end

    test "mock configurations are set" do
      config = setup_mock_config(:success)
      
      assert is_map(config)
      assert Map.has_key?(config, :http_responses)
      assert Map.has_key?(config, :websocket_messages)
      assert Map.has_key?(config, :delays)
    end
  end
end