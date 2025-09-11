import Config

# =============================================================================
# PRODUCTION ENVIRONMENT CONFIGURATION
# =============================================================================

config :crypto_exchange,
  # ==========================================================================
  # PRODUCTION BINANCE CONFIGURATION  
  # ==========================================================================
  
  # Production Binance URLs - these can be overridden via environment variables
  binance_ws_url: "wss://stream.binance.com:9443/ws",
  binance_api_url: "https://api.binance.com",
  
  # ==========================================================================
  # PRODUCTION CONNECTION SETTINGS
  # ==========================================================================
  
  # Optimized WebSocket configuration for production
  websocket_config: [
    connect_timeout: 15_000,    # 15 seconds - robust timeout
    ping_interval: 20_000,      # 20 seconds - regular keepalive
    max_frame_size: 2_097_152,  # 2MB - larger frames for efficiency
    compress: true              # Enable compression for bandwidth
  ],
  
  # Production HTTP configuration
  http_config: [
    timeout: 30_000,            # 30 second timeout
    pool_timeout: 10_000,       # 10 second pool timeout
    pool_max_connections: 200,  # More connections for production load
    retry: true,                # Enable retries
    retry_delay: 1_000,         # 1 second retry delay
    max_retries: 3              # Up to 3 retries
  ],
  
  # Production retry configuration with exponential backoff
  retry_config: [
    initial_delay: 2_000,       # 2 second initial delay
    max_delay: 60_000,          # 1 minute max delay
    max_retries: :infinity,     # Infinite retries for production
    backoff_factor: 2.0,        # Exponential backoff
    jitter: true                # Add jitter to prevent thundering herd
  ],
  
  # ==========================================================================
  # PRODUCTION STREAM CONFIGURATION
  # ==========================================================================
  
  # Production stream settings for high throughput
  stream_config: [
    max_subscriptions: 1000,    # High capacity for production
    cleanup_interval: 600_000,  # 10 minutes cleanup
    health_check_interval: 120_000, # 2 minute health checks
    buffer_size: 5000,          # Large buffer for high throughput
    compression: true           # Enable compression
  ],
  
  # ==========================================================================
  # PRODUCTION USER CONFIGURATION
  # ==========================================================================
  
  # Production user settings
  user_config: [
    max_connections: 10_000,    # High capacity for production
    session_timeout: 7_200_000, # 2 hours session timeout
    idle_cleanup_interval: 600_000, # 10 minutes cleanup
    rate_limit: 1200,           # Binance rate limit per minute
    monitor_activity: true      # Enable monitoring
  ],
  
  # ==========================================================================
  # PRODUCTION SECURITY CONFIGURATION
  # ==========================================================================
  
  # Strict security settings for production
  security_config: [
    validate_signatures: true,  # Always validate signatures
    timestamp_window: 5_000,    # 5 second timestamp window
    ip_whitelist: :any,         # Configure via environment if needed
    audit_requests: true        # Enable audit logging
  ],
  
  # ==========================================================================
  # PRODUCTION MONITORING CONFIGURATION
  # ==========================================================================
  
  # Comprehensive monitoring for production
  monitoring_config: [
    enable_metrics: true,       # Enable metrics collection
    metrics_interval: 60_000,   # 1 minute metrics reporting
    track_memory: true,         # Track memory usage
    track_processes: true       # Track process counts
  ],
  
  # Full telemetry for production monitoring
  telemetry_config: [
    enabled: true,
    events: [
      :websocket_connected,
      :websocket_disconnected,
      :websocket_error,
      :market_data_received,
      :market_data_latency,
      :user_connected,
      :user_disconnected,
      :order_placed,
      :order_filled,
      :order_cancelled,
      :order_error,
      :api_request,
      :api_response,
      :api_error,
      :api_rate_limit,
      :system_memory,
      :system_processes
    ]
  ],
  
  # Production logging level
  log_level: :info

# =============================================================================
# PRODUCTION LOGGING CONFIGURATION
# =============================================================================

# Production logger configuration - structured and efficient
config :logger,
  level: :info,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]   # Remove debug logs in production
  ]

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
    :duration_ms,
    :node                       # Include node name for distributed systems
  ],
  level: :info,
  colors: [enabled: false],     # Disable colors in production logs
  truncate: 4096                # Truncate very long messages

# =============================================================================
# PRODUCTION PUBSUB CONFIGURATION
# =============================================================================

# Optimized PubSub for production load
config :crypto_exchange, CryptoExchange.PubSub,
  name: CryptoExchange.PubSub,
  adapter: Phoenix.PubSub.PG2,
  pool_size: System.schedulers_online() * 2  # More pools for production

# =============================================================================
# PRODUCTION REGISTRY CONFIGURATION
# =============================================================================

# Optimized registry for production
config :crypto_exchange, CryptoExchange.Registry,
  keys: :unique,
  name: CryptoExchange.Registry,
  partitions: System.schedulers_online() * 4  # More partitions for less contention

# =============================================================================
# PRODUCTION JSON CONFIGURATION
# =============================================================================

# Optimized JSON for production
config :crypto_exchange, :json,
  library: Jason,
  pretty: false               # Compact JSON for efficiency

# =============================================================================
# ENVIRONMENT VARIABLE CONFIGURATION
# =============================================================================

# Production environment variable overrides
# These allow configuration via environment variables without code changes

# Binance endpoint configuration
if binance_api_url = System.get_env("BINANCE_API_URL") do
  config :crypto_exchange, binance_api_url: binance_api_url
end

if binance_ws_url = System.get_env("BINANCE_WS_URL") do
  config :crypto_exchange, binance_ws_url: binance_ws_url
end

# Logging level override
if log_level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(log_level)
end

# Security configuration
if ip_whitelist = System.get_env("IP_WHITELIST") do
  # Parse comma-separated IP list
  ips = ip_whitelist |> String.split(",") |> Enum.map(&String.trim/1)
  
  config :crypto_exchange,
    security_config: [
      validate_signatures: true,
      timestamp_window: 5_000,
      ip_whitelist: ips,
      audit_requests: true
    ]
end

# Rate limiting configuration
if rate_limit = System.get_env("RATE_LIMIT") do
  {rate_limit_int, _} = Integer.parse(rate_limit)
  
  config :crypto_exchange,
    user_config: [
      max_connections: 10_000,
      session_timeout: 7_200_000,
      idle_cleanup_interval: 600_000,
      rate_limit: rate_limit_int,
      monitor_activity: true
    ]
end

# Monitoring configuration
if System.get_env("ENABLE_METRICS") == "false" do
  config :crypto_exchange,
    monitoring_config: [
      enable_metrics: false,
      metrics_interval: 60_000,
      track_memory: false,
      track_processes: false
    ]
end

if System.get_env("ENABLE_TELEMETRY") == "false" do
  config :crypto_exchange,
    telemetry_config: [enabled: false, events: []]
end

# =============================================================================
# PRODUCTION VALIDATION
# =============================================================================

# Validate production configuration
if config_env() == :prod do
  # Ensure we're using production Binance URLs
  api_url = Application.compile_env(:crypto_exchange, :binance_api_url)
  ws_url = Application.compile_env(:crypto_exchange, :binance_ws_url)
  
  unless String.contains?(api_url, "api.binance.com") or 
         String.contains?(api_url, System.get_env("BINANCE_API_URL") || "") do
    IO.warn("[PROD CONFIG] Warning: Using non-production Binance API URL: #{api_url}")
  end
  
  unless String.contains?(ws_url, "stream.binance.com") or 
         String.contains?(ws_url, System.get_env("BINANCE_WS_URL") || "") do
    IO.warn("[PROD CONFIG] Warning: Using non-production Binance WebSocket URL: #{ws_url}")
  end
  
  # Warn about security settings
  security_config = Application.compile_env(:crypto_exchange, :security_config)
  
  unless Keyword.get(security_config, :validate_signatures, true) do
    IO.warn("[PROD CONFIG] Warning: Signature validation is disabled in production!")
  end
  
  unless Keyword.get(security_config, :audit_requests, false) do
    IO.warn("[PROD CONFIG] Warning: Request auditing is disabled in production!")
  end
end

# =============================================================================
# RUNTIME CONFIGURATION REFERENCE
# =============================================================================

# The following environment variables can be used to configure the application
# at runtime without rebuilding:
#
# Required for user trading:
#   - BINANCE_API_KEY (per user, managed by application)
#   - BINANCE_SECRET_KEY (per user, managed by application)
#
# Optional configuration:
#   - BINANCE_API_URL (default: https://api.binance.com)
#   - BINANCE_WS_URL (default: wss://stream.binance.com:9443/ws)
#   - LOG_LEVEL (default: info)
#   - IP_WHITELIST (comma-separated IPs, default: any)
#   - RATE_LIMIT (requests per minute, default: 1200)
#   - ENABLE_METRICS (true/false, default: true)
#   - ENABLE_TELEMETRY (true/false, default: true)
#
# Example production startup:
#   LOG_LEVEL=info ENABLE_METRICS=true ./crypto_exchange start