# CryptoExchange

A lightweight Elixir/OTP library for Binance cryptocurrency exchange integration with dual-stream architecture for public data streaming and private user trading operations.

## Overview

CryptoExchange provides two main capabilities:

1. **Public Data Streaming**: Real-time market data (tickers, order books, trades) distributed via Phoenix.PubSub without authentication requirements.
2. **Private User Trading**: Secure user trading operations with isolated user sessions for placing orders, checking balances, and managing accounts.

## Project Status

🚧 **Work in Progress** - This project is currently in initial development phase. The basic project structure has been established with:

- ✅ Mix project setup with proper dependencies
- ✅ OTP application structure with supervision tree
- ✅ Module architecture and organization
- ✅ Configuration system for different environments
- ✅ Basic test suite structure
- ✅ **Data models for market data and trading operations**
- ⏳ Core functionality implementation (in progress)

## Architecture

The system follows a clean separation of concerns:

- `CryptoExchange.API` - Main public interface
- `CryptoExchange.PublicStreams` - Market data streaming
- `CryptoExchange.Trading` - User trading operations  
- `CryptoExchange.Binance` - Exchange adapter implementation
- `CryptoExchange.Models` - Data structures for market and trading data

## Installation

Add `crypto_exchange` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:crypto_exchange, "~> 0.1.0"}
  ]
end
```

## Configuration

Add to your config files:

```elixir
config :crypto_exchange,
  binance_ws_url: "wss://stream.binance.com:9443/ws",
  binance_api_url: "https://api.binance.com"
```

## Data Models

CryptoExchange provides comprehensive data models for all market and trading operations:

### Market Data Models

```elixir
# Ticker - Price and volume information
{:ok, ticker} = CryptoExchange.Models.Ticker.new(%{
  symbol: "BTCUSDT",
  price: 50000.0,
  change: 1.5,
  volume: 1234.56
})

# OrderBook - Bids and asks
{:ok, order_book} = CryptoExchange.Models.OrderBook.new(%{
  symbol: "BTCUSDT",
  bids: [[50000.0, 0.5], [49999.0, 1.0]],
  asks: [[50001.0, 0.3], [50002.0, 0.8]]
})

# Trade - Individual trade execution
{:ok, trade} = CryptoExchange.Models.Trade.new(%{
  symbol: "BTCUSDT",
  price: 50000.0,
  quantity: 0.1,
  side: :buy
})
```

### Trading Data Models

```elixir
# Order - Trading order information
{:ok, order} = CryptoExchange.Models.Order.new(%{
  order_id: "123456",
  symbol: "BTCUSDT",
  side: :buy,
  type: :limit,
  quantity: 0.001,
  price: 50000.0,
  status: :new
})

# Balance - Account balance information
{:ok, balance} = CryptoExchange.Models.Balance.new(%{
  asset: "BTC",
  free: 0.5,
  locked: 0.1
})
```

### Binance Integration

All models support parsing from Binance API responses:

```elixir
# Parse from Binance WebSocket data
binance_ticker = %{
  "s" => "BTCUSDT",
  "c" => "50000.00",
  "P" => "1.50",
  "v" => "1234.56"
}
{:ok, ticker} = CryptoExchange.Models.Ticker.from_binance_json(binance_ticker)

# Parse lists of data
balances_json = [
  %{"asset" => "BTC", "free" => "0.5", "locked" => "0.1"},
  %{"asset" => "ETH", "free" => "10.0", "locked" => "2.0"}
]
{:ok, balances} = CryptoExchange.Models.parse_list(balances_json, &CryptoExchange.Models.Balance.from_binance_json/1)
```

## Usage

### Public Market Data (Planned)

```elixir
# Subscribe to ticker updates
{:ok, topic} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")
Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

# Listen for updates
receive do
  {:market_data, %{type: :ticker, symbol: "BTCUSDT", data: data}} ->
    IO.puts("BTC Price: #{data.price}")
end
```

### User Trading (Planned)

```elixir
# Connect user with Binance credentials
{:ok, _pid} = CryptoExchange.API.connect_user("user1", api_key, secret_key)

# Place a limit order
{:ok, order} = CryptoExchange.API.place_order("user1", %{
  symbol: "BTCUSDT",
  side: "BUY", 
  type: "LIMIT",
  quantity: "0.001",
  price: "50000"
})
```

## Development

```bash
# Get dependencies
mix deps.get

# Compile
mix compile

# Run tests
mix test

# Generate documentation
mix docs
```

## Project Structure

```
├── lib/
│   ├── crypto_exchange.ex              # Main module
│   └── crypto_exchange/
│       ├── api.ex                      # Public API interface
│       ├── application.ex              # OTP Application
│       ├── models.ex                   # Data models (Ticker, OrderBook, Trade, Order, Balance)
│       ├── public_streams.ex           # Market data streaming
│       ├── trading.ex                  # User trading operations
│       └── binance.ex                  # Binance adapter
├── config/                             # Configuration files
├── test/                               # Test suite
└── mix.exs                            # Project configuration
```

## Dependencies

- `phoenix_pubsub ~> 2.1` - Message distribution
- `jason ~> 1.4` - JSON encoding/decoding
- `req ~> 0.4.0` - HTTP client
- `websocket_client ~> 1.5` - WebSocket client

## License

MIT License

## Contributing

This project is in early development. Please refer to `SPECIFICATION.md` for detailed requirements and architecture decisions.