# PubSub Debugging Guide

## Overview

This guide explains how to debug PubSub data flow in the CryptoExchange application, showing the journey of market data from Binance WebSocket streams through to Phoenix.PubSub subscribers.

## Data Flow Architecture

### Complete Flow Path:
```
Binance WebSocket Server
         ↓
WebSocketHandler (receives raw messages)
         ↓
PublicStreams (JSON parsing)
         ↓
Model Parsers (Ticker, OrderBook, Trade, Kline)
         ↓
broadcast_market_data/1 [WITH DEBUG LOGGING]
         ↓
Phoenix.PubSub.broadcast/3
         ↓
Subscribed Processes
```

## Debug Logging Added

### Location: `lib/crypto_exchange/binance/public_streams.ex:764-817`

The `broadcast_market_data/1` function now includes comprehensive debug logging:

#### Before Broadcast (Lines 775-783):
```elixir
Logger.debug("""
[PUBSUB BROADCAST - BEFORE]
Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}
Topic: #{topic}
Type: #{market_data.type}
Symbol: #{market_data.symbol}
Data: #{inspect(market_data.data, pretty: true, limit: :infinity)}
Full Message: #{inspect({:market_data, market_data}, pretty: true, limit: :infinity)}
""")
```

#### After Broadcast (Lines 794-814):
```elixir
case result do
  :ok ->
    Logger.debug("""
    [PUBSUB BROADCAST - AFTER SUCCESS]
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    Topic: #{topic}
    Type: #{market_data.type}
    Symbol: #{market_data.symbol}
    Result: Successfully broadcast to PubSub
    """)

  {:error, reason} ->
    Logger.error("""
    [PUBSUB BROADCAST - AFTER ERROR]
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    Topic: #{topic}
    Type: #{market_data.type}
    Symbol: #{market_data.symbol}
    Error: #{inspect(reason)}
    """)
end
```

## Debugging Tools

### 1. PubSub Debug Subscriber

**File:** `lib/crypto_exchange/debug/pubsub_subscriber.ex`

A GenServer that subscribes to PubSub topics and logs all received messages with detailed information.

#### Usage:

```elixir
# Start the subscriber
{:ok, pid} = CryptoExchange.Debug.PubSubSubscriber.start_link()

# Subscribe to a specific topic
CryptoExchange.Debug.PubSubSubscriber.subscribe("binance:ticker:BTCUSDT")

# Check message count
count = CryptoExchange.Debug.PubSubSubscriber.message_count()

# Get last N messages
messages = CryptoExchange.Debug.PubSubSubscriber.get_messages(10)

# Get status
status = CryptoExchange.Debug.PubSubSubscriber.status()
# Returns: %{
#   subscribed_topics: [...],
#   total_messages: 42,
#   stored_messages: 42,
#   uptime_seconds: 120
# }

# Clear message history
CryptoExchange.Debug.PubSubSubscriber.clear_messages()
```

### 2. PubSub Broadcast Tests

**File:** `test/crypto_exchange/debug/pubsub_broadcast_test.exs`

Unit tests that verify PubSub broadcasting works correctly for all data types.

#### Running the tests:

```bash
MIX_ENV=test mix test test/crypto_exchange/debug/pubsub_broadcast_test.exs
```

#### What's tested:
- ✅ Ticker data broadcasts to correct topic
- ✅ Depth data broadcasts to correct topic
- ✅ Trade data broadcasts to correct topic
- ✅ Kline data broadcasts to correct topic (with interval)
- ✅ Topic isolation (different symbols go to different topics)

## Topic Format

### Standard Topics:
- Ticker: `binance:ticker:SYMBOL` (e.g., `binance:ticker:BTCUSDT`)
- Depth: `binance:depth:SYMBOL` (e.g., `binance:depth:ETHUSDT`)
- Trades: `binance:trades:SYMBOL` (e.g., `binance:trades:BNBUSDT`)
- Klines: `binance:klines:SYMBOL:INTERVAL` (e.g., `binance:klines:BTCUSDT:1m`)

### Important Notes:
- Symbol is always **UPPERCASE** in the topic
- Binance stream names use lowercase (e.g., `btcusdt@ticker`)
- Topic conversion happens in `extract_symbol_from_stream/2`

## Message Format

All market data is broadcast in the same format:

```elixir
{:market_data, %{
  type: :ticker | :depth | :trades | :klines,
  symbol: "BTCUSDT",
  data: %Ticker{} | %OrderBook{} | %Trade{} | %Kline{},
  interval: "1m"  # Only for klines
}}
```

## How to Debug PubSub Issues

### Step 1: Enable Debug Logging

Set the log level to debug in your config:

```elixir
config :logger, level: :debug
```

### Step 2: Start the Debug Subscriber

```elixir
# In IEx
{:ok, _} = CryptoExchange.Debug.PubSubSubscriber.start_link()
CryptoExchange.Debug.PubSubSubscriber.subscribe("binance:ticker:BTCUSDT")
```

### Step 3: Trigger a Data Flow

```elixir
# Subscribe to Binance stream
CryptoExchange.PublicStreams.StreamManager.subscribe_to_ticker("BTCUSDT")
```

### Step 4: Check the Logs

Look for log patterns:

1. **WebSocket message received:**
   ```
   [debug] Received stream data: btcusdt@ticker
   ```

2. **Before PubSub broadcast:**
   ```
   [debug] [PUBSUB BROADCAST - BEFORE]
   Timestamp: 2025-10-08T23:20:52.000000Z
   Topic: binance:ticker:BTCUSDT
   Type: ticker
   Symbol: BTCUSDT
   Data: %CryptoExchange.Models.Ticker{...}
   ```

3. **After PubSub broadcast:**
   ```
   [debug] [PUBSUB BROADCAST - AFTER SUCCESS]
   Timestamp: 2025-10-08T23:20:52.001000Z
   Topic: binance:ticker:BTCUSDT
   Result: Successfully broadcast to PubSub
   ```

4. **Subscriber receives message:**
   ```
   [info] [PUBSUB DEBUG - MESSAGE RECEIVED]
   Timestamp: 2025-10-08T23:20:52.002000Z
   Type: ticker
   Symbol: BTCUSDT
   Data: %CryptoExchange.Models.Ticker{...}
   ```

### Step 5: Verify Message Count

```elixir
# Check if messages are being received
CryptoExchange.Debug.PubSubSubscriber.message_count()
# Should return > 0 if data is flowing

# Get actual messages
CryptoExchange.Debug.PubSubSubscriber.get_messages(5)
```

## Common Issues and Solutions

### Issue 1: No messages received

**Symptoms:** `message_count()` returns 0

**Debugging:**
1. Check if PublicStreams is connected: `CryptoExchange.Binance.PublicStreams.status()`
2. Verify stream subscription exists
3. Check topic name matches exactly (case-sensitive)
4. Look for `[PUBSUB BROADCAST - BEFORE]` logs

**Solution:** Ensure proper subscription to both Binance stream AND PubSub topic

### Issue 2: Wrong topic name

**Symptoms:** Messages broadcast but not received

**Debugging:**
1. Compare topic in `[PUBSUB BROADCAST - BEFORE]` log with your subscription
2. Verify symbol case (should be UPPERCASE in topic)

**Solution:** Use exact topic format from documentation

### Issue 3: Data structure mismatch

**Symptoms:** Messages received but data is not as expected

**Debugging:**
1. Check `Data:` field in `[PUBSUB BROADCAST - BEFORE]` log
2. Verify Model parser is working correctly
3. Check for parsing errors in logs

**Solution:** Fix Model.parse/1 function or message format

## Test Results

All PubSub broadcast tests passing ✅:

```
Finished in 0.8 seconds (0.00s async, 0.8s sync)
5 tests, 0 failures

✅ ticker data broadcasts to correct topic
✅ depth data broadcasts to correct topic
✅ trade data broadcasts to correct topic
✅ kline data broadcasts to correct topic with interval
✅ different symbols broadcast to different topics
```

## StreamManager Integration

**Important Finding:** StreamManager does NOT subscribe to PubSub topics automatically!

### What StreamManager Does:
- Manages Binance WebSocket stream subscriptions
- Tracks which streams are active
- Returns topic names for manual subscription

### What Users Must Do:
```elixir
# 1. Subscribe via StreamManager (creates Binance stream subscription)
{:ok, topic} = CryptoExchange.PublicStreams.StreamManager.subscribe_to_ticker("BTCUSDT")

# 2. Manually subscribe to PubSub topic
Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

# 3. Receive messages
receive do
  {:market_data, data} -> IO.inspect(data)
end
```

## Files Modified/Created

### Modified:
- `lib/crypto_exchange/binance/public_streams.ex`
  - Added debug logging to broadcast_market_data/1 (lines 774-817)
  - **Fixed kline parsing bug** in parse_kline_data/3 (lines 670-696)
  - Added debug logging to handle_binance_message/1 (line 496)

### Created:
- `lib/crypto_exchange/debug/pubsub_subscriber.ex` - Debug subscriber GenServer
- `test/crypto_exchange/debug/pubsub_broadcast_test.exs` - Unit tests for PubSub broadcasting
- `test/crypto_exchange/debug/pubsub_integration_test.exs` - Integration tests (for reference)
- `PUBSUB_DEBUG_GUIDE.md` - This documentation

## Bug Found and Fixed

### Issue: Kline Data Was Empty in PubSub Messages

**Problem:**
When kline data was broadcast to PubSub, all fields were `nil`:
```elixir
%CryptoExchange.Models.Kline{
  event_type: nil,
  event_time: nil,
  symbol: "BTCUSDT",  # Only symbol was set
  kline_start_time: nil,
  close_price: nil,
  # ... all other fields nil
}
```

**Root Cause:**
The `parse_kline_data/3` function was passing stream data directly to `Kline.parse/1`, but:
- Stream format: `{"stream": "btcusdt@kline_1m", "data": {kline fields...}}`
- `Kline.parse/1` expects: `{"e": "kline", "E": timestamp, "s": "BTCUSDT", "k": {kline fields...}}`

The kline data from streams is already **flat** (all fields at top level), but `Kline.parse/1` expects them nested under a `"k"` key.

**Fix Applied:**
Modified `parse_kline_data/3` in `lib/crypto_exchange/binance/public_streams.ex:670-696` to wrap the stream data correctly:

```elixir
defp parse_kline_data(symbol, interval, data) do
  # Wrap stream data in the format Kline.parse expects
  wrapped_data = %{
    "e" => Map.get(data, "e", "kline"),
    "E" => Map.get(data, "E"),
    "s" => symbol,
    "k" => data  # ← Nest the kline data under "k" key
  }

  case Kline.parse(wrapped_data) do
    {:ok, kline} -> {:ok, %{type: :klines, symbol: symbol, interval: interval, data: kline}}
    {:error, reason} -> {:error, reason}
  end
end
```

**Note:** Ticker, OrderBook, and Trade parsers don't need this wrapping because they expect flat data (which is what streams provide).

## Summary

The PubSub data flow is now working correctly:
1. ✅ WebSocket receives messages from Binance
2. ✅ Messages are parsed by Model parsers (with proper data format conversion)
3. ✅ Data is broadcast to PubSub with correct topics and **full data**
4. ✅ Subscribers receive messages successfully with populated fields
5. ✅ All data types (ticker, depth, trades, klines) work correctly
6. ✅ Topic isolation works (different symbols → different topics)
7. ✅ **Kline data is now fully populated** (previously was all nil)

Debug logging now provides full visibility into the data flow before and after PubSub broadcast.
