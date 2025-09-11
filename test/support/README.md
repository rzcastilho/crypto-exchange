# Testing Infrastructure Documentation

This directory contains the comprehensive testing infrastructure for the CryptoExchange library, designed to achieve >90% test coverage and ensure system reliability.

## Overview

The testing infrastructure provides:

- **Behavior-based mocking** for external dependencies (HTTP, WebSocket, Binance API)
- **Test factories** for consistent data generation
- **PubSub testing utilities** for message-driven architecture testing  
- **WebSocket simulation** for real-time communication testing
- **HTTP endpoint mocking** with Bypass
- **Property-based testing** support with StreamData
- **Performance testing** utilities and helpers
- **Test configuration** management and isolation
- **Coverage reporting** with ExCoveralls (90% minimum target)

## Test Support Modules

### Core Infrastructure

- **`behaviours.ex`** - Defines behaviours for mockable external dependencies
- **`test_case_template.ex`** - Template module for consistent test setup across different test types
- **`test_config.ex`** - Test environment configuration and scenario management
- **`factory.ex`** - Data factories for creating consistent test fixtures

### Testing Utilities

- **`http_test_helpers.ex`** - HTTP endpoint mocking with Bypass, Binance API simulation
- **`pubsub_test_helpers.ex`** - PubSub message testing, subscription management
- **`websocket_test_server.ex`** - WebSocket server simulation for real-time testing

## Test Types and Usage

### Unit Tests
```elixir
defmodule MyModuleTest do
  use CryptoExchange.TestSupport.TestCaseTemplate, type: :unit
  
  test "my function works correctly" do
    result = MyModule.my_function("input")
    assert result == "expected_output"
  end
end
```

### Integration Tests
```elixir
defmodule MyIntegrationTest do
  use CryptoExchange.TestSupport.TestCaseTemplate, type: :integration, async: false
  
  test "components work together" do
    # Test multiple components interacting
  end
end
```

### WebSocket Tests
```elixir
defmodule MyWebSocketTest do
  use CryptoExchange.TestSupport.TestCaseTemplate, type: :websocket
  
  test "websocket message handling", %{ws_server: ws_server} do
    simulate_connection_lifecycle(ws_server, [
      ticker_message("BTCUSDT"),
      kline_message("BTCUSDT", "1m")
    ])
  end
end
```

### PubSub Tests
```elixir
defmodule MyPubSubTest do
  use CryptoExchange.TestSupport.TestCaseTemplate, type: :pubsub
  
  test "pubsub message delivery" do
    topic = subscribe_test_topic(:ticker, "BTCUSDT")
    publish_and_wait(CryptoExchange.PubSub, topic, {:market_data, "test"})
    assert_received_pubsub({:market_data, "test"})
  end
end
```

### Property-Based Tests
```elixir
defmodule MyPropertyTest do
  use CryptoExchange.TestSupport.TestCaseTemplate, type: :property
  
  property "function always returns positive values" do
    check all input <- positive_integer() do
      result = MyModule.process(input)
      assert result > 0
    end
  end
end
```

## Mock Configuration

### HTTP Mocks
```elixir
# Success scenario
setup_http_success_mock(%{"status" => "ok"}, 200)

# Error scenario
setup_http_error_mock(:network_error, "Connection failed")

# Binance API specific
{bypass, base_url} = start_bypass_server()
setup_binance_api_mock(bypass, base_url)
```

### WebSocket Mocks
```elixir
setup_websocket_success_mock(self())
setup_websocket_error_mock(:connection_failed)
```

## Data Factories

### Creating Test Data
```elixir
# Orders
order = build(:order, %{symbol: "ETHUSDT", side: :sell})
filled_order = build(:filled_order, %{quantity: Decimal.new("2.0")})

# Market Data
ticker = build(:ticker_data, %{symbol: "BTCUSDT"})
kline = build(:kline_data, %{symbol: "ETHUSDT"})
depth = build(:depth_data, %{symbol: "ADAUSDT"})

# User Data
user = build(:user_data, %{user_id: "test_user_123"})
user_with_orders = build(:user_with_orders)

# WebSocket Messages
ws_ticker = build(:ws_ticker_message, %{symbol: "BTCUSDT"})
ws_user_data = build(:ws_user_data_message, %{event_type: "executionReport"})

# API Responses
api_response = build(:api_order_response, %{status: "FILLED"})
error_response = build(:api_error_response, %{code: -1013})

# Multiple instances
orders = build_list(5, :order, %{symbol: "BTCUSDT"})
```

## Test Configuration

### Environment Setup
```elixir
# Automatic in test_helper.exs
setup_test_env()

# With custom options
setup_test_env(connect_timeout: 500, enable_monitoring: true)

# Test scenarios
setup_mock_config(:success)        # All operations succeed
setup_mock_config(:network_error)  # Network failures
setup_mock_config(:rate_limit)     # API rate limiting
setup_mock_config(:timeout)        # Request timeouts
setup_mock_config(:partial_failure) # Mixed success/failure
```

### Temporary Configuration
```elixir
with_test_config([{:binance_api_url, "http://localhost:8080"}], fn ->
  # Test with different configuration
end)
```

## Coverage Reporting

### Running Tests with Coverage
```bash
# Basic coverage
mix coveralls

# Detailed coverage report
mix coveralls.detail

# HTML coverage report
mix coveralls.html

# Coverage with specific pattern
mix coveralls --filter "CryptoExchange.Binance"
```

### Coverage Configuration
- **Target**: 90% minimum coverage
- **Exclusions**: Test files, build artifacts, dependencies
- **Reports**: Console, HTML, Cobertura XML formats

## Performance Testing

### Measuring Execution Time
```elixir
{result, duration_us} = measure_time(fn ->
  MyModule.expensive_operation()
end)
```

### Throughput Testing
```elixir
metrics = measure_throughput(fn ->
  MyModule.fast_operation()
end, 1000)

# Returns: %{iterations: 1000, total_duration_us: 50000, average_duration_us: 50.0, throughput_per_second: 20000.0}
```

## Test Isolation

### PubSub Isolation
- Unique topic names per test
- Automatic subscription cleanup
- Message flushing utilities

### Process Isolation
- Supervised process testing
- Automatic cleanup on test exit
- Mock ownership per test process

### Configuration Isolation
- Test-specific configuration overrides
- Automatic restoration after tests
- Environment-specific settings

## Best Practices

1. **Use appropriate test types** - Unit for isolated logic, Integration for component interaction
2. **Leverage factories** - Consistent, maintainable test data
3. **Mock external dependencies** - Reliable, fast tests
4. **Test async behavior** - Use proper synchronization helpers
5. **Verify mock expectations** - Ensure all mocks are called as expected
6. **Clean up resources** - Use `on_exit` callbacks for cleanup
7. **Test edge cases** - Use property-based testing for comprehensive coverage

## Running Tests

```bash
# All tests
mix test

# Specific test type
mix test --only unit
mix test --only integration
mix test --only slow

# With coverage
mix coveralls
mix coveralls.html

# Excluding slow tests (default)
mix test --exclude slow

# Property-based tests only  
mix test --only property
```

This infrastructure enables comprehensive testing of the CryptoExchange library with proper isolation, mocking, and coverage reporting to achieve the >90% coverage target for Phase 5.