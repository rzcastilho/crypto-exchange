# Elixir Crypto Exchange Library Specification (Simplified)

## 1. Executive Summary

### 1.1 Project Overview
A lightweight Elixir/OTP library for Binance cryptocurrency exchange integration with clear separation between public market data streaming and private user trading operations.

### 1.2 Key Features
- **Dual-Stream Architecture**: Separate public data streams from user trading operations
- **Real-Time Market Data**: WebSocket streaming with Phoenix.PubSub distribution
- **Secure User Trading**: Basic credential management with isolated user sessions
- **Binance Integration**: Complete Binance API integration (public + private)
- **Simple & Extensible**: Clean architecture ready for future exchange additions

### 1.3 Scope
- **Initial Target**: Binance only
- **Future**: Extensible architecture for additional exchanges
- **Core Focus**: Market data streaming + basic trading operations

---

## 2. System Architecture

### 2.1 Core Components

```
┌─────────────────────────────────────────────────────────┐
│                 CryptoExchange.API                      │
├─────────────────────────────────────────────────────────┤
│    PublicStreams         │         Trading              │
│  ┌───────────────────┐   │   ┌───────────────────────┐  │
│  │   StreamManager   │   │   │   UserManager         │  │
│  │   Broadcaster     │   │   │   UserConnection      │  │
│  └───────────────────┘   │   └───────────────────────┘  │
├─────────────────────────────────────────────────────────┤
│                    Binance Adapter                      │
│            PublicStreams + PrivateClient                │
├─────────────────────────────────────────────────────────┤
│   Phoenix.PubSub    │    Registry    │   WebSocket      │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Process Supervision Tree

```
CryptoExchange.Application
├── Registry
├── Phoenix.PubSub
├── PublicStreams.StreamManager
└── Trading.UserManager (DynamicSupervisor)
    └── UserConnection (per user)
```

---

## 3. Core Components

### 3.1 Public Data Streaming

#### 3.1.1 Stream Manager
```elixir
defmodule CryptoExchange.PublicStreams.StreamManager do
  use GenServer

  # Client API
  def subscribe_to_ticker(symbol), do: subscribe(:ticker, symbol)
  def subscribe_to_depth(symbol, level \\ 5), do: subscribe(:depth, symbol, %{level: level})
  def subscribe_to_trades(symbol), do: subscribe(:trades, symbol)
  def unsubscribe(symbol), do: GenServer.call(__MODULE__, {:unsubscribe, symbol})

  # Returns Phoenix.PubSub topic for listening
  defp subscribe(stream_type, symbol, params \\ %{}) do
    GenServer.call(__MODULE__, {:subscribe, stream_type, symbol, params})
  end
end
```

#### 3.1.2 Topic Structure
- **Ticker**: `binance:ticker:BTCUSDT`
- **Order Book**: `binance:depth:BTCUSDT`
- **Trades**: `binance:trades:BTCUSDT`

#### 3.1.3 Message Format
```elixir
{:market_data, %{
  type: :ticker,
  symbol: "BTCUSDT",
  data: %{
    price: 50000.0,
    volume: 1234.56,
    change: 1.5
  }
}}
```

### 3.2 User Trading System

#### 3.2.1 User Manager
```elixir
defmodule CryptoExchange.Trading.UserManager do
  use DynamicSupervisor

  def connect_user(user_id, credentials) do
    spec = {CryptoExchange.Trading.UserConnection, {user_id, credentials}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def disconnect_user(user_id) do
    # Find and terminate user connection
  end
end
```

#### 3.2.2 User Connection
```elixir
defmodule CryptoExchange.Trading.UserConnection do
  use GenServer

  # Trading operations
  def place_order(user_id, order_params)
  def cancel_order(user_id, order_id)
  def get_balance(user_id)
  def get_orders(user_id)
end
```

### 3.3 Binance Adapter

#### 3.3.1 Public Streams
```elixir
defmodule CryptoExchange.Binance.PublicStreams do
  # WebSocket connection to wss://stream.binance.com:9443/ws
  def connect()
  def subscribe(stream_type, symbol, params)
  def parse_message(raw_message)
end
```

#### 3.3.2 Private Client
```elixir
defmodule CryptoExchange.Binance.PrivateClient do
  # REST API client for trading operations
  def new(api_key, secret_key)
  def place_order(client, params)
  def cancel_order(client, order_id)
  def get_balance(client)
  def get_orders(client)
end
```

---

## 4. Public API

### 4.1 Main API Module

```elixir
defmodule CryptoExchange.API do
  # Public Data (no authentication)
  def subscribe_to_ticker(symbol)
  def subscribe_to_depth(symbol, level \\ 5)
  def subscribe_to_trades(symbol)
  def unsubscribe_from_public_data(symbol)

  # User Trading (requires Binance credentials)
  def connect_user(user_id, api_key, secret_key)
  def disconnect_user(user_id)
  def place_order(user_id, order_params)
  def cancel_order(user_id, order_id)
  def get_balance(user_id)
  def get_orders(user_id)
end
```

### 4.2 Usage Examples

#### 4.2.1 Public Data
```elixir
# Subscribe to ticker
{:ok, topic} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")
Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

# Listen for updates
receive do
  {:market_data, %{type: :ticker, symbol: "BTCUSDT", data: ticker}} ->
    IO.puts("BTC Price: #{ticker.price}")
end
```

#### 4.2.2 User Trading
```elixir
# Connect user
{:ok, _pid} = CryptoExchange.API.connect_user("user1", api_key, secret_key)

# Place order
{:ok, order} = CryptoExchange.API.place_order("user1", %{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "LIMIT",
  quantity: "0.001",
  price: "50000"
})

# Check balance
{:ok, balances} = CryptoExchange.API.get_balance("user1")
```

---

## 5. Data Models

### 5.1 Market Data

#### 5.1.1 Ticker
```elixir
%{
  symbol: "BTCUSDT",
  price: 50000.0,
  change: 1.5,
  volume: 1234.56
}
```

#### 5.1.2 Order Book
```elixir
%{
  symbol: "BTCUSDT",
  bids: [[50000.0, 0.5], [49999.0, 1.0]],
  asks: [[50001.0, 0.3], [50002.0, 0.8]]
}
```

#### 5.1.3 Trade
```elixir
%{
  symbol: "BTCUSDT",
  price: 50000.0,
  quantity: 0.1,
  side: "BUY"
}
```

### 5.2 Trading Data

#### 5.2.1 Order
```elixir
%{
  order_id: "123456",
  symbol: "BTCUSDT",
  side: "BUY",
  type: "LIMIT",
  quantity: 0.001,
  price: 50000.0,
  status: "NEW"
}
```

#### 5.2.2 Balance
```elixir
%{
  asset: "BTC",
  free: 0.5,
  locked: 0.1
}
```

---

## 6. Configuration

### 6.1 Basic Configuration
```elixir
# config/config.exs
config :crypto_exchange,
  binance_ws_url: "wss://stream.binance.com:9443/ws",
  binance_api_url: "https://api.binance.com"
```

### 6.2 Dependencies
```elixir
defp deps do
  [
    {:phoenix_pubsub, "~> 2.1"},
    {:jason, "~> 1.4"},
    {:req, "~> 0.4.0"},
    {:websocket_client, "~> 1.5"}
  ]
end
```

---

## 7. Error Handling

### 7.1 Error Types
```elixir
# Connection errors
{:error, :connection_failed}
{:error, :websocket_closed}

# API errors
{:error, :invalid_credentials}
{:error, :insufficient_balance}
{:error, :invalid_symbol}

# Rate limiting
{:error, :rate_limit_exceeded}
```

### 7.2 Retry Logic
- **WebSocket reconnection**: Exponential backoff (1s, 2s, 4s, max 30s)
- **API rate limits**: Respect Binance rate limits with built-in delays
- **Failed orders**: Return error immediately, no automatic retry

---

## 8. Testing

### 8.1 Test Structure
```
test/
├── public_streams_test.exs
├── user_trading_test.exs
├── binance_adapter_test.exs
└── integration_test.exs
```

### 8.2 Test Strategy
- **Unit Tests**: Mock Binance API responses
- **Integration Tests**: Use Binance testnet when available
- **Property Tests**: Input validation and parsing
- **Manual Testing**: Real Binance sandbox testing

---

## 9. Performance Targets

### 9.1 Simple Targets
- **Market Data Latency**: <100ms
- **Order Placement**: <500ms
- **Concurrent Public Streams**: 50+
- **Concurrent Users**: 10+

### 9.2 Resource Usage
- **Memory**: <50MB under normal load
- **CPU**: <50% under normal load

---

## 10. Security (Basic)

### 10.1 Credential Handling
- Store API keys in GenServer state only
- Never log credentials
- Support for environment variables

### 10.2 API Security
- HMAC-SHA256 signatures for Binance API
- TLS for all connections
- Basic input validation

---

## 11. Deployment

### 11.1 Mix Project Setup
```elixir
defmodule CryptoExchange.MixProject do
  use Mix.Project

  def project do
    [
      app: :crypto_exchange,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CryptoExchange.Application, []}
    ]
  end
end
```

### 11.2 Basic Monitoring
- Elixir Logger for basic logging
- Process monitoring via Observer
- Simple health check endpoint

---

## 12. Success Criteria

### 12.1 MVP Requirements
- ✅ Stream Binance ticker, depth, trades data
- ✅ Place/cancel orders on Binance
- ✅ Get account balance
- ✅ Basic error handling and reconnection
- ✅ Working examples and basic docs

### 12.2 Quality Gates
- ✅ >90% test coverage
- ✅ No hardcoded credentials
- ✅ Basic documentation
- ✅ Working integration tests

---

## 13. Future Extensions

### 13.1 Phase 2 (Optional)
- Additional exchanges (Coinbase, etc.)
- Advanced order types
- Historical data
- Better credential encryption

### 13.2 Extensibility Design
The current architecture supports future extensions:
- Adapter pattern ready for new exchanges
- Separation of concerns allows isolated additions
- PubSub topics can scale to multiple exchanges

---

## 14. Implementation Timeline

### 14.1 Minimal Viable Product (4-6 weeks)
- **Week 1**: Project setup + Binance public streams
- **Week 2**: User trading operations
- **Week 3**: Error handling + reconnection
- **Week 4**: Testing + documentation
- **Week 5-6**: Polish + integration testing

### 14.2 Team
- 1-2 Elixir developers
- Part-time testing/QA

---

## 15. Conclusion

This simplified specification focuses on delivering a working Binance integration with clean architecture that can be extended later. By avoiding over-engineering, we can deliver value quickly while maintaining code quality and extensibility for future enhancements.

The dual-stream architecture provides clear separation of concerns, and the simple API makes the library easy to use and understand.
