import Config

# Binance API Configuration
config :crypto_exchange,
  binance_ws_url: "wss://stream.binance.com:9443/ws",
  binance_api_url: "https://api.binance.com"

# Import environment specific config files
import_config "#{config_env()}.exs"
