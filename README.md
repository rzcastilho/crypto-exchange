# CryptoExchange

A production-ready Elixir/OTP library for cryptocurrency exchange integration with comprehensive error handling, health monitoring, and real-time market data streaming. Currently supports Binance with an extensible architecture for additional exchanges.

[![CI](https://github.com/rzcastilho/crypto-exchange/workflows/CI/badge.svg)](https://github.com/rzcastilho/crypto-exchange/actions)
[![Elixir](https://img.shields.io/badge/elixir-~%3E%201.16-purple.svg)](https://elixir-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- 🚀 **Real-Time Market Data**: WebSocket streaming with automatic reconnection and circuit breaker patterns
- 📈 **Historical Data Retrieval**: REST API access to historical klines/candlestick data with bulk fetching support (>1000 candles)
- 💼 **Secure Trading Operations**: Isolated user sessions with credential management
- 🔄 **Phoenix.PubSub Integration**: Efficient market data distribution to multiple subscribers
- 🛡️ **Comprehensive Error Handling**: Intelligent error classification with retry strategies
- 📊 **Health Monitoring**: Component-level and system-wide health checks
- 📝 **Structured Logging**: Context-aware logging with performance tracking
- ⚡ **Production Ready**: Battle-tested with 373+ tests and robust resilience patterns

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [Usage Examples](#usage-examples)
- [Configuration](#configuration)
- [Error Handling](#error-handling)
- [Health Monitoring](#health-monitoring)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Installation

Add `crypto_exchange` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:crypto_exchange, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### 1. Subscribe to Public Market Data

```elixir
# Start subscribing to BTC ticker updates
{:ok, topic} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")

# Subscribe to the PubSub topic
Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

# Receive real-time updates
receive do
  {:market_data, %{type: :ticker, symbol: "BTCUSDT", data: ticker}} ->
    IO.puts("BTC Price: $#{ticker.price}")
    IO.puts("24h Change: #{ticker.price_change_percent}%")
    IO.puts("Volume: #{ticker.volume}")
end

# Subscribe to order book depth
{:ok, topic} = CryptoExchange.API.subscribe_to_depth("ETHUSDT", 10)
Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

receive do
  {:market_data, %{type: :depth, symbol: "ETHUSDT", data: order_book}} ->
    IO.inspect(order_book.bids, label: "Top Bids")
    IO.inspect(order_book.asks, label: "Top Asks")
end

# Subscribe to live trades
{:ok, topic} = CryptoExchange.API.subscribe_to_trades("BTCUSDT")
Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

receive do
  {:market_data, %{type: :trade, symbol: "BTCUSDT", data: trade}} ->
    IO.puts("Trade: #{trade.quantity} BTC @ $#{trade.price}")
end
```

### 2. User Trading Operations

```elixir
# Connect a user with their Binance API credentials
user_id = "user123"
api_key = System.get_env("BINANCE_API_KEY")
secret_key = System.get_env("BINANCE_SECRET_KEY")

{:ok, _pid} = CryptoExchange.API.connect_user(user_id, api_key, secret_key)

# Check account balance
{:ok, balances} = CryptoExchange.API.get_balance(user_id)
IO.inspect(balances)

# Place a limit order
{:ok, order} = CryptoExchange.API.place_order(user_id, %{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "LIMIT",
  quantity: "0.001",
  price: "50000",
  time_in_force: "GTC"
})

IO.puts("Order placed: #{order.order_id}")

# Get open orders
{:ok, orders} = CryptoExchange.API.get_orders(user_id, "BTCUSDT")
IO.inspect(orders, label: "Open Orders")

# Cancel an order
{:ok, result} = CryptoExchange.API.cancel_order(user_id, order.order_id, "BTCUSDT")
IO.puts("Order cancelled: #{result.order_id}")

# Disconnect user when done
:ok = CryptoExchange.API.disconnect_user(user_id)
```

### 3. Health Monitoring

```elixir
# Check overall system health
{:ok, health} = CryptoExchange.Health.check_system()

IO.puts("System Status: #{health.status}")
IO.inspect(health.components, label: "Component Health")

# Check specific component
{:ok, ws_health} = CryptoExchange.Health.check_component(:websocket_connections)
IO.puts("WebSocket Status: #{ws_health.status}")
```

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    CryptoExchange.API                       │
│                   (Public Interface)                        │
├─────────────────────────────────────────────────────────────┤
│   PublicStreams              │         Trading              │
│  ┌────────────────────┐      │   ┌────────────────────┐     │
│  │  StreamManager     │      │   │   UserManager      │     │
│  │  (Subscriptions)   │      │   │   (DynamicSup)     │     │
│  └────────────────────┘      │   └────────────────────┘     │
│           │                  │            │                 │
├───────────┼──────────────────┼────────────┼─────────────────┤
│           ▼                  │            ▼                 │
│  ┌────────────────────┐      │   ┌────────────────────┐     │
│  │ Binance            │      │   │ UserConnection     │     │
│  │ PublicStreams      │      │   │ (per user)         │     │
│  │ (WebSocket)        │      │   │  + PrivateClient   │     │
│  └────────────────────┘      │   └────────────────────┘     │
├─────────────────────────────────────────────────────────────┤
│          Infrastructure & Cross-Cutting Concerns            │
│  ┌──────────┬──────────┬──────────┬────────────────┐        │
│  │ PubSub   │ Registry │ Logging  │ Error Handler  │        │
│  │          │          │          │ Health Monitor │        │
│  └──────────┴──────────┴──────────┴────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Supervision Tree

```
CryptoExchange.Application (Supervisor)
├── Registry (CryptoExchange.Registry)
├── Phoenix.PubSub (CryptoExchange.PubSub)
├── Binance.PublicStreams (WebSocket Connection)
├── PublicStreams.StreamManager (Subscription Manager)
└── Trading.UserManager (DynamicSupervisor)
    └── UserConnection (one per connected user)
        └── Binance.PrivateClient (REST API Client)
```

**Supervision Strategy**: `:one_for_one` - Each component restarts independently on failure, ensuring isolated fault tolerance.

## Core Components

### 1. Public Market Data Streaming

**Purpose**: Provides real-time market data from Binance via WebSocket with automatic reconnection and resilience patterns.

**Key Modules**:
- `CryptoExchange.PublicStreams.StreamManager` - Manages subscriptions and coordinates with WebSocket adapter
- `CryptoExchange.Binance.PublicStreams` - WebSocket connection to Binance public streams
- `CryptoExchange.Binance.WebSocketHandler` - Low-level WebSocket handler with circuit breaker

**Features**:
- Automatic WebSocket reconnection with exponential backoff
- Circuit breaker pattern to prevent cascading failures
- Message buffering during temporary disconnections
- Health monitoring with ping/pong protocol compliance

**Supported Data Types**:
- **Ticker**: 24hr price statistics
- **Order Book Depth**: Best bid/ask prices with configurable levels (5, 10, 20)
- **Trades**: Real-time executed trades

### 2. User Trading System

**Purpose**: Enables secure, isolated trading operations for multiple users with individual Binance API credentials.

**Key Modules**:
- `CryptoExchange.Trading.UserManager` - Dynamic supervisor managing user connections
- `CryptoExchange.Trading.UserConnection` - GenServer representing individual user session
- `CryptoExchange.Binance.PrivateClient` - REST API client for authenticated Binance operations

**Features**:
- Isolated user sessions with credential encapsulation
- Rate limiting and retry strategies
- Error recovery with intelligent backoff
- Comprehensive error classification

**Supported Operations**:
- Place orders (LIMIT, MARKET, STOP_LOSS, etc.)
- Cancel orders
- Query account balance
- Get open orders
- Order status tracking

### 3. Error Handling & Resilience

**Purpose**: Provides comprehensive error classification, intelligent retry strategies, and user-friendly error messages.

**Key Modules**:
- `CryptoExchange.Trading.ErrorHandler` - Classifies and enhances trading errors
- `CryptoExchange.Binance.Errors` - Binance-specific error mappings and parsing

**Features**:
- Intelligent error classification (network, rate limiting, validation, authentication, etc.)
- Severity levels (info, warning, error, critical)
- Retryable vs non-retryable error detection
- Contextual recovery suggestions
- User-friendly error messages

**Error Categories**:
- Network errors (timeouts, connection failures)
- Rate limiting (with backoff recommendations)
- Authentication errors (invalid credentials)
- Validation errors (invalid parameters)
- Insufficient funds
- Market status errors

### 4. Health Monitoring

**Purpose**: Provides real-time visibility into system health at component and system levels.

**Key Module**:
- `CryptoExchange.Health` - Comprehensive health check system

**Features**:
- Component-level health checks (application, trading system, user connections, WebSocket)
- System-wide aggregated health status
- Performance metrics (response times, connection counts)
- Graceful degradation detection
- Timeout protection for health checks

**Health Statuses**:
- `:healthy` - All systems operational
- `:degraded` - Partial functionality (e.g., no users connected)
- `:unhealthy` - Component failures detected
- `:unknown` - Unable to determine health

### 5. Structured Logging

**Purpose**: Provides context-aware, structured logging with performance tracking and error monitoring.

**Key Module**:
- `CryptoExchange.Logging` - Structured logging infrastructure

**Features**:
- Context propagation (user_id, session_id, request_id)
- Performance timing with automatic duration calculation
- Error tuple detection (logs failures vs successes)
- Exception logging with stack traces
- API request/response logging
- WebSocket event logging
- Trading operation logging

## Usage Examples

### Historical Data Retrieval

```elixir
# Get last 500 1-hour candles (up to 1000 with standard function)
{:ok, klines} = CryptoExchange.get_historical_klines("BTCUSDT", "1h", limit: 500)

# Get candles for a specific date range
{:ok, klines} = CryptoExchange.get_historical_klines("ETHUSDT", "1d",
  start_time: 1609459200000,  # 2021-01-01
  end_time: 1640995199000     # 2021-12-31
)

# Fetch more than 1000 candles using bulk fetching (automatic pagination)
{:ok, klines} = CryptoExchange.get_historical_klines_bulk("BTCUSDT", "1h", limit: 5000)

IO.puts("Fetched #{length(klines)} klines")
first_kline = List.first(klines)
last_kline = List.last(klines)

# Process the klines
Enum.each(klines, fn kline ->
  IO.puts("Time: #{kline.open_time}, Open: #{kline.open_price}, Close: #{kline.close_price}")
end)

# Calculate statistics
total_volume = Enum.reduce(klines, 0, fn kline, acc -> acc + kline.volume end)
IO.puts("Total volume: #{total_volume}")
```

### Advanced Trading Scenarios

```elixir
# Market order with error handling
case CryptoExchange.API.place_order(user_id, %{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "MARKET",
  quantity: "0.001"
}) do
  {:ok, order} ->
    IO.puts("Market order executed: #{order.order_id}")

  {:error, %{category: :insufficient_funds, user_message: msg}} ->
    IO.puts("Error: #{msg}")

  {:error, %{category: :rate_limiting, recovery_suggestions: suggestions}} ->
    IO.puts("Rate limited. Suggestions:")
    Enum.each(suggestions, &IO.puts("  - #{&1}"))

  {:error, error} ->
    IO.puts("Unexpected error: #{inspect(error)}")
end
```

### Multiple Subscriptions

```elixir
# Subscribe to multiple symbols
symbols = ["BTCUSDT", "ETHUSDT", "BNBUSDT", "ADAUSDT"]

topics =
  Enum.map(symbols, fn symbol ->
    {:ok, topic} = CryptoExchange.API.subscribe_to_ticker(symbol)
    Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
    topic
  end)

# Handle updates from any symbol
defmodule MarketDataHandler do
  def listen do
    receive do
      {:market_data, %{type: :ticker, symbol: symbol, data: ticker}} ->
        IO.puts("#{symbol}: $#{ticker.price}")
        listen()
    end
  end
end

MarketDataHandler.listen()
```

### Using Structured Logging

```elixir
alias CryptoExchange.Logging

# Set user context for all subsequent logs
Logging.set_context(%{user_id: "user123", session_id: "abc-def"})

# Log trading operation with timing
result = Logging.with_timing("Place order", %{category: :trading}, fn ->
  CryptoExchange.API.place_order(user_id, order_params)
end)

# Logs will include:
# - duration_ms
# - status (:success or :error)
# - user_id and session_id from context

# Clear context when done
Logging.clear_context()
```

## Configuration

### Environment Variables

```bash
# Binance API Credentials (for user trading)
export BINANCE_API_KEY="your_api_key"
export BINANCE_SECRET_KEY="your_secret_key"

# Optional: Use testnet for testing
export BINANCE_WS_URL="wss://testnet.binance.vision/ws"
export BINANCE_API_URL="https://testnet.binance.vision"
```

### Application Configuration

```elixir
# config/config.exs
config :crypto_exchange,
  binance_ws_url: System.get_env("BINANCE_WS_URL", "wss://stream.binance.com:9443/ws"),
  binance_api_url: System.get_env("BINANCE_API_URL", "https://api.binance.com")

# config/test.exs
config :logger, level: :debug

# config/prod.exs
config :logger,
  level: :info,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]
```

## Error Handling

### Error Response Format

All errors follow a consistent structure:

```elixir
%{
  category: :rate_limiting,           # Error category
  severity: :warning,                 # Severity level
  retryable: true,                   # Can be retried?
  user_message: "Too many requests", # User-friendly message
  technical_details: "...",          # Technical details
  recovery_suggestions: [            # How to recover
    "Wait 60 seconds before retrying",
    "Reduce request frequency"
  ],
  context: %{                        # Request context
    user_id: "user123",
    symbol: "BTCUSDT",
    operation: :place_order
  }
}
```

### Common Error Scenarios

```elixir
# Insufficient balance
{:error, %{
  category: :insufficient_funds,
  retryable: false,
  user_message: "Insufficient balance to complete this order"
}}

# Rate limiting
{:error, %{
  category: :rate_limiting,
  retryable: false,
  user_message: "API request limit exceeded",
  recovery_suggestions: ["Wait 60 seconds", "Reduce request frequency"]
}}

# Network timeout
{:error, %{
  category: :network,
  retryable: true,
  severity: :warning,
  user_message: "Request timeout. Please try again."
}}
```

## Health Monitoring

### System Health Check

```elixir
{:ok, health} = CryptoExchange.Health.check_system()

# Response format
%{
  status: :healthy,  # :healthy | :degraded | :unhealthy | :unknown
  timestamp: ~U[2025-01-15 10:30:00Z],
  components: %{
    application: %{
      status: :healthy,
      uptime_ms: 3600000,
      memory_mb: 45.2
    },
    trading_system: %{
      status: :healthy,
      total_users: 5,
      active_connections: 5
    },
    websocket_connections: %{
      status: :healthy,
      connected: true,
      circuit_breaker_state: :closed,
      total_reconnects: 2
    }
  }
}
```

### Component Health Checks

```elixir
# Check specific components
{:ok, app_health} = CryptoExchange.Health.check_component(:application)
{:ok, trading_health} = CryptoExchange.Health.check_component(:trading_system)
{:ok, ws_health} = CryptoExchange.Health.check_component(:websocket_connections)
{:ok, users_health} = CryptoExchange.Health.check_component(:user_connections)
```

## Testing

The library includes comprehensive test coverage:

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/crypto_exchange/api_test.exs

# Run tests with specific tag
mix test --only integration
```

**Test Statistics**:
- 359+ total tests
- 0 failures
- Coverage: >90%

**Test Categories**:
- Unit tests for individual modules
- Integration tests for end-to-end workflows
- Error scenario tests for resilience validation
- Health monitoring tests
- WebSocket protocol compliance tests

## API Reference

### CryptoExchange.API

Main public API module.

#### Public Market Data

- `subscribe_to_ticker(symbol)` - Subscribe to 24hr ticker statistics
- `subscribe_to_depth(symbol, level \\ 5)` - Subscribe to order book depth
- `subscribe_to_trades(symbol)` - Subscribe to live trades
- `unsubscribe_from_public_data(symbol)` - Unsubscribe from all public streams

#### User Trading

- `connect_user(user_id, api_key, secret_key)` - Connect user with credentials
- `disconnect_user(user_id)` - Disconnect user and cleanup resources
- `place_order(user_id, order_params)` - Place a new order
- `cancel_order(user_id, order_id, symbol)` - Cancel an existing order
- `get_balance(user_id)` - Get account balance
- `get_orders(user_id, symbol)` - Get open orders for symbol

### CryptoExchange.Health

Health monitoring system.

- `check_system()` - Check overall system health
- `check_component(component_name)` - Check specific component health

### CryptoExchange.Logging

Structured logging system.

- `set_context(context_map)` - Set context for current process
- `get_context()` - Get current context
- `clear_context()` - Clear current context
- `with_timing(message, metadata, fun)` - Execute function with timing
- `error_with_exception(message, exception, stacktrace, metadata)` - Log exception with stack trace

## Performance

### Target Metrics

- Market data latency: <100ms
- Order placement: <500ms
- Concurrent public streams: 50+
- Concurrent users: 10+
- Memory usage: <50MB under normal load

### Resource Usage

- Efficient message passing with Phoenix.PubSub
- Per-user process isolation
- WebSocket connection pooling
- Automatic resource cleanup on user disconnect

## Security

### Credential Handling

- API keys stored only in GenServer state
- No credential logging (sanitized from logs)
- Environment variable support
- Per-user credential isolation

### API Security

- HMAC-SHA256 signatures for Binance API
- TLS/SSL for all connections
- Request timestamp validation
- Input validation and sanitization

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Format code (`mix format`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/rzcastilho/crypto-exchange.git
cd crypto-exchange

# Install dependencies
mix deps.get

# Run tests
mix test

# Format code
mix format

# Run static analysis (if configured)
mix credo
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Elixir](https://elixir-lang.org/) and OTP
- WebSocket handling via [WebSockex](https://github.com/Azolo/websockex)
- Message distribution via [Phoenix.PubSub](https://github.com/phoenixframework/phoenix_pubsub)
- HTTP client via [Req](https://github.com/wojtekmach/req)
- JSON parsing via [Jason](https://github.com/michalmuskala/jason)

## Support

For issues, questions, or contributions:

- Open an issue on [GitHub Issues](https://github.com/rzcastilho/crypto-exchange/issues)
- Check existing documentation in the `docs/` directory
- Review test files for usage examples

## Roadmap

### Future Enhancements

- [ ] Additional exchange support (Coinbase, Kraken, etc.)
- [ ] Advanced order types (OCO, trailing stop, etc.)
- [x] Historical data retrieval (✅ Implemented with bulk fetching support)
- [ ] WebSocket account updates (user data streams)
- [ ] Advanced credential encryption
- [ ] Telemetry integration
- [ ] GraphQL API
- [ ] Docker deployment support

---

**Built with ❤️ using Elixir/OTP**
