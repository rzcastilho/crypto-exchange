import Config

# Test configuration

config :logger, level: :debug

# Use mock endpoints for testing
config :crypto_exchange,
  binance_ws_url: "ws://localhost:8080/ws",
  binance_api_url: "http://localhost:8080"
