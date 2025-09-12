import Config

# Runtime configuration
# This config file is loaded during releases and allows
# for runtime configuration via environment variables

if config_env() == :prod do
  # Configure Binance URLs from environment variables if available
  binance_ws_url = System.get_env("BINANCE_WS_URL") || "wss://stream.binance.com:9443/ws"
  binance_api_url = System.get_env("BINANCE_API_URL") || "https://api.binance.com"

  config :crypto_exchange,
    binance_ws_url: binance_ws_url,
    binance_api_url: binance_api_url
end
