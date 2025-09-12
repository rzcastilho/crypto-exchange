#!/usr/bin/env elixir

# Examples of using the CryptoExchange.Models for parsing Binance data
#
# Run this file with: elixir examples/models_usage.exs
#
# Note: This is a standalone example script that can be run to see
# how the models work with real Binance message data.

Code.require_file("lib/crypto_exchange/models/ticker.ex")
Code.require_file("lib/crypto_exchange/models/order_book.ex")
Code.require_file("lib/crypto_exchange/models/trade.ex")

IO.puts("=== CryptoExchange.Models Usage Examples ===\n")

# Example 1: Parsing Ticker Data
IO.puts("1. Ticker Model Example")
IO.puts("-" |> String.duplicate(25))

ticker_data = %{
  "e" => "24hrTicker",
  "E" => 1640995200000,
  "s" => "BTCUSDT",
  "p" => "1500.00000000",
  "P" => "3.210",
  "c" => "48200.50000000",
  "b" => "48200.00000000",
  "a" => "48201.00000000",
  "h" => "49000.00000000",
  "l" => "46500.00000000",
  "v" => "12345.67890000",
  "n" => 324
}

{:ok, ticker} = CryptoExchange.Models.Ticker.parse(ticker_data)

IO.puts("Parsed Ticker:")
IO.puts("  Symbol: #{ticker.symbol}")
IO.puts("  Last Price: #{ticker.last_price}")
IO.puts("  24h Change: #{ticker.price_change} (#{ticker.price_change_percent}%)")
IO.puts("  Best Bid: #{ticker.best_bid_price}")
IO.puts("  Best Ask: #{ticker.best_ask_price}")
IO.puts("  24h High: #{ticker.high_price}")
IO.puts("  24h Low: #{ticker.low_price}")
IO.puts("  24h Volume: #{ticker.total_traded_base_asset_volume}")
IO.puts("  Trades: #{ticker.total_number_of_trades}")
IO.puts()

# Example 2: Parsing Order Book Data
IO.puts("2. Order Book Model Example")
IO.puts("-" |> String.duplicate(30))

order_book_data = %{
  "e" => "depthUpdate",
  "E" => 1640995200000,
  "s" => "BTCUSDT",
  "U" => 157,
  "u" => 160,
  "b" => [
    ["48200.00000000", "1.50000000"],
    ["48199.00000000", "2.30000000"],
    ["48198.00000000", "0.50000000"]
  ],
  "a" => [
    ["48201.00000000", "0.80000000"],
    ["48202.00000000", "1.20000000"],
    ["48203.00000000", "0.75000000"]
  ]
}

{:ok, order_book} = CryptoExchange.Models.OrderBook.parse(order_book_data)

IO.puts("Parsed Order Book:")
IO.puts("  Symbol: #{order_book.symbol}")
IO.puts("  Update ID: #{order_book.first_update_id} -> #{order_book.final_update_id}")

{:ok, best_bid} = CryptoExchange.Models.OrderBook.best_bid(order_book)
{:ok, best_ask} = CryptoExchange.Models.OrderBook.best_ask(order_book)
{:ok, spread} = CryptoExchange.Models.OrderBook.spread(order_book)

IO.puts("  Best Bid: #{Enum.at(best_bid, 0)} (#{Enum.at(best_bid, 1)})")
IO.puts("  Best Ask: #{Enum.at(best_ask, 0)} (#{Enum.at(best_ask, 1)})")
IO.puts("  Spread: #{spread}")

IO.puts("  All Bids:")
Enum.each(order_book.bids, fn [price, qty] ->
  IO.puts("    #{price} @ #{qty}")
end)

IO.puts("  All Asks:")
Enum.each(order_book.asks, fn [price, qty] ->
  IO.puts("    #{price} @ #{qty}")
end)
IO.puts()

# Example 3: Parsing Trade Data
IO.puts("3. Trade Model Example")
IO.puts("-" |> String.duplicate(22))

# Buy-side trade (buyer is taker)
buy_trade_data = %{
  "e" => "trade",
  "E" => 1640995200000,
  "s" => "BTCUSDT",
  "t" => 12345,
  "p" => "48200.50000000",
  "q" => "0.12500000",
  "b" => 88,
  "a" => 50,
  "T" => 1640995199950,
  "m" => false  # Buyer is taker (buy-side)
}

{:ok, buy_trade} = CryptoExchange.Models.Trade.parse(buy_trade_data)

IO.puts("Buy Trade:")
IO.puts("  Symbol: #{buy_trade.symbol}")
IO.puts("  Price: #{buy_trade.price}")
IO.puts("  Quantity: #{buy_trade.quantity}")
IO.puts("  Trade Side: #{CryptoExchange.Models.Trade.trade_side(buy_trade)}")
IO.puts("  Buyer Market Maker: #{buy_trade.is_buyer_market_maker}")

{:ok, buy_value} = CryptoExchange.Models.Trade.trade_value(buy_trade)
IO.puts("  Trade Value: #{buy_value}")

{:ok, is_large} = CryptoExchange.Models.Trade.is_large_trade?(buy_trade, "1000")
IO.puts("  Large Trade (>$1000): #{is_large}")
IO.puts()

# Sell-side trade (buyer is market maker)
sell_trade_data = %{
  "e" => "trade",
  "E" => 1640995210000,
  "s" => "BTCUSDT",
  "t" => 12346,
  "p" => "48199.00000000",
  "q" => "0.05000000",
  "b" => 89,
  "a" => 51,
  "T" => 1640995209950,
  "m" => true  # Buyer is market maker (sell-side)
}

{:ok, sell_trade} = CryptoExchange.Models.Trade.parse(sell_trade_data)

IO.puts("Sell Trade:")
IO.puts("  Symbol: #{sell_trade.symbol}")
IO.puts("  Price: #{sell_trade.price}")
IO.puts("  Quantity: #{sell_trade.quantity}")
IO.puts("  Trade Side: #{CryptoExchange.Models.Trade.trade_side(sell_trade)}")
IO.puts("  Buyer Market Maker: #{sell_trade.is_buyer_market_maker}")

{:ok, sell_value} = CryptoExchange.Models.Trade.trade_value(sell_trade)
IO.puts("  Trade Value: #{sell_value}")
IO.puts()

# Example 4: Error Handling
IO.puts("4. Error Handling Examples")
IO.puts("-" |> String.duplicate(28))

# Invalid ticker data
case CryptoExchange.Models.Ticker.parse("not a map") do
  {:error, reason} -> IO.puts("Ticker Error: #{reason}")
end

# Invalid order book data
case CryptoExchange.Models.OrderBook.parse(%{"invalid" => "data"}) do
  {:ok, _} -> IO.puts("Order book parsed successfully with minimal data")
end

# Invalid trade calculation
invalid_trade = %CryptoExchange.Models.Trade{
  price: "invalid_price",
  quantity: "1.00000000"
}

case CryptoExchange.Models.Trade.trade_value(invalid_trade) do
  {:error, reason} -> IO.puts("Trade Value Error: #{reason}")
end

IO.puts()
IO.puts("=== All examples completed successfully! ===")