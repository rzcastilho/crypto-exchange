#!/usr/bin/env elixir

# Example demonstrating the Binance WebSocket client usage
# Run with: elixir examples/websocket_client_example.exs

Mix.install([
  {:crypto_exchange, path: "."}
])

defmodule WebSocketClientExample do
  @moduledoc """
  Example demonstrating how to use the CryptoExchange Binance WebSocket client
  for real-time market data streaming.
  """
  
  require Logger
  
  def run do
    Logger.info("Starting Binance WebSocket client example...")
    
    # Start the CryptoExchange application manually for this example
    {:ok, _} = Application.ensure_all_started(:crypto_exchange)
    
    # Subscribe to ticker data for BTCUSDT
    Logger.info("Subscribing to BTCUSDT ticker data...")
    {:ok, ticker_topic} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")
    Phoenix.PubSub.subscribe(CryptoExchange.PubSub, ticker_topic)
    
    # Subscribe to order book depth data for ETHUSDT  
    Logger.info("Subscribing to ETHUSDT depth data...")
    {:ok, depth_topic} = CryptoExchange.API.subscribe_to_depth("ETHUSDT", 5)
    Phoenix.PubSub.subscribe(CryptoExchange.PubSub, depth_topic)
    
    # Subscribe to trade data for ADAUSDT
    Logger.info("Subscribing to ADAUSDT trade data...")  
    {:ok, trades_topic} = CryptoExchange.API.subscribe_to_trades("ADAUSDT")
    Phoenix.PubSub.subscribe(CryptoExchange.PubSub, trades_topic)
    
    Logger.info("Listening for market data... (Press Ctrl+C to stop)")
    Logger.info("Topics: #{ticker_topic}, #{depth_topic}, #{trades_topic}")
    
    # Listen for market data updates
    listen_for_updates()
  end
  
  defp listen_for_updates do
    receive do
      {:market_data, %{type: :ticker, symbol: symbol, data: ticker}} ->
        Logger.info("TICKER #{symbol}: Price=${ticker.price}, Change=${ticker.change}%, Volume=${ticker.volume}")
        
      {:market_data, %{type: :depth, symbol: symbol, data: order_book}} ->
        best_bid = CryptoExchange.Models.OrderBook.best_bid(order_book)
        best_ask = CryptoExchange.Models.OrderBook.best_ask(order_book)
        spread = CryptoExchange.Models.OrderBook.spread(order_book)
        Logger.info("DEPTH #{symbol}: Bid=${best_bid}, Ask=${best_ask}, Spread=${spread}")
        
      {:market_data, %{type: :trades, symbol: symbol, data: trade}} ->
        side_str = String.upcase(to_string(trade.side))
        notional = CryptoExchange.Models.Trade.notional_value(trade)
        Logger.info("TRADE #{symbol}: #{side_str} #{trade.quantity} @ $#{trade.price} (${notional})")
        
      other ->
        Logger.debug("Received other message: #{inspect(other)}")
    end
    
    # Continue listening
    listen_for_updates()
  end
end

# Run the example
WebSocketClientExample.run()