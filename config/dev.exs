import Config

# =============================================================================
# DEVELOPMENT ENVIRONMENT CONFIGURATION
# =============================================================================

config :crypto_exchange,
  # ==========================================================================
  # DEVELOPMENT BINANCE CONFIGURATION
  # ==========================================================================
  
  # Use Binance testnet for safer development testing
  # Note: Testnet WebSocket streams may have limited availability
  binance_api_url: "https://testnet.binance.vision",
  
  # Use testnet WebSocket URL if available, otherwise use production with caution
  # binance_ws_url: "wss://testnet.binance.vision:9443/ws",  # Testnet (limited)
  binance_ws_url: "wss://stream.binance.com:9443/ws",  # Production (read-only safe)
  
  # ==========================================================================
  # DEVELOPMENT-SPECIFIC OVERRIDES
  # ==========================================================================
  
  # Enable verbose logging in development
  log_level: :debug,
  
  # Relaxed connection settings for development
  websocket_config: [
    connect_timeout: 15_000,  # Longer timeout for development
    ping_interval: 60_000,    # Less frequent pings
    max_frame_size: 1_048_576,
    compress: false           # Disable compression for easier debugging
  ],
  
  # HTTP settings optimized for development
  http_config: [
    timeout: 60_000,          # Longer timeout for debugging
    pool_timeout: 10_000,
    pool_max_connections: 10, # Fewer connections in dev
    retry: true,
    retry_delay: 2_000,       # Slower retry for debugging
    max_retries: 2            # Fewer retries
  ],
  
  # Faster retry configuration for development iteration
  retry_config: [
    initial_delay: 500,       # Faster initial retry
    max_delay: 5_000,         # Shorter max delay
    max_retries: 5,           # Limited retries for faster feedback
    backoff_factor: 1.5,      # Gentler backoff
    jitter: false             # Predictable timing for debugging
  ],
  
  # Development stream configuration
  stream_config: [
    max_subscriptions: 20,    # Fewer streams for development
    cleanup_interval: 60_000, # More frequent cleanup
    health_check_interval: 30_000, # More frequent health checks
    buffer_size: 100,         # Smaller buffer for faster debugging
    compression: false        # Disable compression for clarity
  ],
  
  # Development user configuration
  user_config: [
    max_connections: 10,      # Fewer concurrent users in dev
    session_timeout: 1_800_000, # 30 minutes (shorter than prod)
    idle_cleanup_interval: 60_000, # More frequent cleanup
    rate_limit: 100,          # Lower rate limit for testing
    monitor_activity: true    # Enable monitoring for debugging
  ],
  
  # Relaxed security for development (DO NOT use in production)
  security_config: [
    validate_signatures: true,  # Keep validation enabled
    timestamp_window: 30_000,   # Longer window for debugging
    ip_whitelist: :any,         # Allow any IP in development
    audit_requests: true        # Enable for debugging
  ],
  
  # Enhanced monitoring for development debugging
  monitoring_config: [
    enable_metrics: true,
    metrics_interval: 30_000,   # More frequent metrics
    track_memory: true,
    track_processes: true
  ],
  
  # Comprehensive telemetry for development
  telemetry_config: [
    enabled: true,
    events: [
      :websocket_connected,
      :websocket_disconnected,
      :websocket_message_received,
      :websocket_message_sent,
      :market_data_received,
      :market_data_parsed,
      :pubsub_broadcast,
      :user_connected,
      :user_disconnected,
      :order_placed,
      :order_filled,
      :order_cancelled,
      :api_request,
      :api_response,
      :api_error,
      :process_started,
      :process_terminated
    ]
  ]

# =============================================================================
# DEVELOPMENT LOGGING CONFIGURATION  
# =============================================================================

# Enhanced logging for development with detailed metadata
config :logger, :console,
  format: "\n$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :user_id, 
    :symbol,
    :exchange,
    :stream_type,
    :order_id,
    :error_type,
    :duration_ms,
    :mfa,                     # Module, function, arity for debugging
    :file,                    # Source file
    :line,                    # Source line number
    :pid,                     # Process ID
    :application              # Application name
  ],
  level: :debug,
  colors: [enabled: true],    # Enable colored output in development
  truncate: 8192              # Longer messages for debugging
  
# Configure logger for verbose development output
config :logger,
  backends: [:console],
  level: :debug,
  compile_time_purge_matching: [
    # Don't purge any logs in development
  ]

# =============================================================================
# DEVELOPMENT TOOLS CONFIGURATION
# =============================================================================

# Enable code reloading in development (if Phoenix is added later)
# config :crypto_exchange, CryptoExchangeWeb.Endpoint,
#   code_reloader: true

# Development-specific PubSub configuration
config :crypto_exchange, CryptoExchange.PubSub,
  name: CryptoExchange.PubSub,
  adapter: Phoenix.PubSub.PG2,
  pool_size: 1  # Single pool in development for simplicity

# =============================================================================
# LOCAL DEVELOPMENT OVERRIDES (OPTIONAL)
# =============================================================================

# Uncomment and modify these settings for local testing with mock servers
# This is useful when testing without internet connection or with custom backends

# config :crypto_exchange,
#   # Local mock WebSocket server
#   binance_ws_url: "ws://localhost:8080/ws",
#   # Local mock REST API server  
#   binance_api_url: "http://localhost:8080/api",
#   # Disable real connections when using mocks
#   enable_real_connections: false

# =============================================================================
# DEVELOPMENT ENVIRONMENT VARIABLES
# =============================================================================

# You can override any setting using environment variables in development:
# 
# Example usage:
#   export CRYPTO_EXCHANGE_LOG_LEVEL=info
#   export CRYPTO_EXCHANGE_BINANCE_API_URL=http://localhost:8080
#   mix run --no-halt

if System.get_env("CRYPTO_EXCHANGE_LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(System.get_env("CRYPTO_EXCHANGE_LOG_LEVEL"))
end

if System.get_env("CRYPTO_EXCHANGE_BINANCE_API_URL") do
  config :crypto_exchange, binance_api_url: System.get_env("CRYPTO_EXCHANGE_BINANCE_API_URL")
end

if System.get_env("CRYPTO_EXCHANGE_BINANCE_WS_URL") do
  config :crypto_exchange, binance_ws_url: System.get_env("CRYPTO_EXCHANGE_BINANCE_WS_URL")
end

# =============================================================================
# DEVELOPMENT VALIDATION
# =============================================================================

# Validate development configuration at compile time
if Application.compile_env(:crypto_exchange, :log_level) == :debug do
  IO.puts("[DEV CONFIG] Debug logging enabled - expect verbose output")
  IO.puts("[DEV CONFIG] Using Binance testnet for API calls: #{Application.compile_env(:crypto_exchange, :binance_api_url)}")
  IO.puts("[DEV CONFIG] WebSocket URL: #{Application.compile_env(:crypto_exchange, :binance_ws_url)}")
end