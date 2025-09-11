defmodule CryptoExchange.Binance do
  @moduledoc """
  Binance exchange adapter implementation.

  This module provides the concrete implementation for Binance API integration,
  including both public WebSocket streams and private REST API operations.

  ## Components

  - **PublicStreams**: WebSocket connection to Binance public streams
  - **PrivateClient**: REST API client for authenticated operations
  - **MessageParser**: Parsing of Binance-specific message formats

  ## Configuration

  Default configuration:

      config :crypto_exchange,
        binance_ws_url: "wss://stream.binance.com:9443/ws",
        binance_api_url: "https://api.binance.com"

  ## WebSocket Streams

  Binance provides various stream types via WebSocket:

  - Individual Symbol Ticker: `<symbol>@ticker`
  - Partial Book Depth: `<symbol>@depth<levels>`
  - Trade Streams: `<symbol>@trade`
  - Combined streams: `/stream?streams=btcusdt@ticker/btcusdt@depth5`

  ## REST API

  Private API operations require:

  - API Key in `X-MBX-APIKEY` header
  - HMAC-SHA256 signature in `signature` parameter
  - Timestamp synchronization

  ## Rate Limits

  Binance enforces various rate limits:

  - REST API: 1200 requests per minute
  - WebSocket: 5 messages per second per connection
  - Order placement: 100 orders per 10 seconds
  """

  # This module will contain submodules for:
  # - PublicStreams (WebSocket client for public data)
  # - PrivateClient (REST client for trading operations)
  # - MessageParser (Binance message format handling)
end