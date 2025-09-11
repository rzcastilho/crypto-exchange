# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# =============================================================================
# CRYPTO EXCHANGE CORE CONFIGURATION
# =============================================================================

config :crypto_exchange,
  # ==========================================================================
  # BINANCE API CONFIGURATION
  # ==========================================================================
  
  # Binance WebSocket URL for public market data streams
  # Production: "wss://stream.binance.com:9443/ws"
  # Testnet: "wss://testnet.binance.vision:9443/ws"
  binance_ws_url: "wss://stream.binance.com:9443/ws",
  
  # Binance REST API base URL for trading operations
  # Production: "https://api.binance.com"
  # Testnet: "https://testnet.binance.vision"
  binance_api_url: "https://api.binance.com",
  
  # ==========================================================================
  # CONNECTION & RETRY CONFIGURATION
  # ==========================================================================
  
  # WebSocket connection settings
  websocket_config: [
    # Connection timeout in milliseconds
    connect_timeout: 10_000,
    # Keep-alive ping interval in milliseconds
    ping_interval: 30_000,
    # Maximum frame size for WebSocket messages
    max_frame_size: 1_048_576,  # 1MB
    # Enable compression
    compress: true
  ],
  
  # HTTP client configuration for REST API calls
  http_config: [
    # Request timeout in milliseconds
    timeout: 30_000,
    # Connection pool settings
    pool_timeout: 5_000,
    pool_max_connections: 100,
    # Request retry configuration
    retry: true,
    retry_delay: 1_000,
    max_retries: 3
  ],
  
  # Connection retry configuration with exponential backoff
  retry_config: [
    # Initial delay before first retry (milliseconds)
    initial_delay: 1_000,
    # Maximum delay between retries (milliseconds) 
    max_delay: 30_000,
    # Maximum number of retry attempts (:infinity or integer)
    max_retries: :infinity,
    # Exponential backoff multiplier
    backoff_factor: 2.0,
    # Add random jitter to prevent thundering herd
    jitter: true
  ],
  
  # ==========================================================================
  # STREAM MANAGEMENT CONFIGURATION
  # ==========================================================================
  
  # Public stream management settings
  stream_config: [
    # Maximum number of concurrent stream subscriptions
    max_subscriptions: 200,
    # Automatic stream cleanup interval (milliseconds)
    cleanup_interval: 300_000,  # 5 minutes
    # Stream health check interval (milliseconds)
    health_check_interval: 60_000,  # 1 minute
    # Buffer size for incoming messages
    buffer_size: 1000,
    # Enable stream compression
    compression: true
  ],
  
  # ==========================================================================
  # USER TRADING CONFIGURATION
  # ==========================================================================
  
  # User connection management
  user_config: [
    # Maximum number of concurrent user connections
    max_connections: 1000,
    # User session timeout (milliseconds)
    session_timeout: 3_600_000,  # 1 hour
    # Idle connection cleanup interval (milliseconds)
    idle_cleanup_interval: 300_000,  # 5 minutes
    # Maximum API requests per user per minute
    rate_limit: 1200,
    # Enable user activity monitoring
    monitor_activity: true
  ],
  
  # ==========================================================================
  # SECURITY CONFIGURATION
  # ==========================================================================
  
  # API security settings
  security_config: [
    # Enable request signature validation
    validate_signatures: true,
    # Timestamp window for request validation (milliseconds)
    timestamp_window: 5_000,
    # Enable IP whitelisting (list of allowed IPs or :any)
    ip_whitelist: :any,
    # Enable request logging for security audits
    audit_requests: false
  ],
  
  # ==========================================================================
  # PERFORMANCE & MONITORING
  # ==========================================================================
  
  # Performance monitoring configuration
  monitoring_config: [
    # Enable metrics collection
    enable_metrics: true,
    # Metrics reporting interval (milliseconds)
    metrics_interval: 60_000,  # 1 minute
    # Enable memory usage tracking
    track_memory: true,
    # Enable process count monitoring
    track_processes: true
  ],
  
  # Telemetry configuration
  telemetry_config: [
    # Enable telemetry events
    enabled: true,
    # Events to track
    events: [
      :websocket_connected,
      :websocket_disconnected,
      :market_data_received,
      :order_placed,
      :order_filled,
      :api_request,
      :api_error
    ]
  ]

# =============================================================================
# PHOENIX PUBSUB CONFIGURATION
# =============================================================================

# Configure the main PubSub system for message distribution
config :crypto_exchange, CryptoExchange.PubSub,
  name: CryptoExchange.PubSub,
  adapter: Phoenix.PubSub.PG2,
  # Pool size for PubSub processes
  pool_size: System.schedulers_online()

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

# Configure Elixir's Logger with structured metadata
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :user_id,
    :symbol,
    :exchange,
    :stream_type,
    :order_id,
    :error_type,
    :duration_ms
  ],
  level: :info

# Configure logger backends
config :logger,
  backends: [:console],
  level: :info,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# =============================================================================
# APPLICATION-SPECIFIC SETTINGS
# =============================================================================

# Registry configuration for process registration
config :crypto_exchange, CryptoExchange.Registry,
  keys: :unique,
  name: CryptoExchange.Registry,
  partitions: System.schedulers_online()

# JSON encoding/decoding configuration
config :crypto_exchange, :json,
  library: Jason,
  pretty: false

# =============================================================================
# IMPORT ENVIRONMENT-SPECIFIC CONFIGURATION
# =============================================================================

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# =============================================================================
# COMPILE-TIME VALIDATION (AFTER ENVIRONMENT CONFIG IS LOADED)
# =============================================================================

# Note: Full validation is done at runtime in CryptoExchange.Config.validate()
# This is just basic compile-time validation to catch obvious errors early

# Only validate in non-test environments  
if config_env() != :test do
  try do
    # These will be nil if we're in a release build, so we skip validation
    binance_ws_url = Application.compile_env(:crypto_exchange, :binance_ws_url)
    binance_api_url = Application.compile_env(:crypto_exchange, :binance_api_url)
    
    if binance_ws_url do
      unless is_binary(binance_ws_url) and String.match?(binance_ws_url, ~r/^wss?:\/\//) do
        IO.warn("Invalid binance_ws_url configuration: must be a WebSocket URL starting with 'ws' or 'wss'")
      end
    end
    
    if binance_api_url do
      unless is_binary(binance_api_url) and String.match?(binance_api_url, ~r/^https?:\/\//) do
        IO.warn("Invalid binance_api_url configuration: must be an HTTP URL starting with 'http' or 'https'")
      end
    end
  rescue
    # Ignore compile-time validation errors - they'll be caught at runtime
    _ -> :ok
  end
end