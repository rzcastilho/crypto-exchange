import Config

# =============================================================================
# TEST ENVIRONMENT CONFIGURATION
# =============================================================================

config :crypto_exchange,
  # ==========================================================================
  # TEST MOCK ENDPOINTS
  # ==========================================================================
  
  # Use localhost mock endpoints for testing - prevents external API calls
  binance_ws_url: "ws://localhost:9999/ws",
  binance_api_url: "http://localhost:9999/api",
  
  # Completely disable real connections during tests
  enable_real_connections: false,
  
  # ==========================================================================
  # TEST-OPTIMIZED CONNECTION SETTINGS
  # ==========================================================================
  
  # Fast WebSocket configuration for tests
  websocket_config: [
    connect_timeout: 1_000,   # 1 second - fast timeout for tests
    ping_interval: 10_000,    # 10 seconds - infrequent pings
    max_frame_size: 65_536,   # 64KB - smaller frames for tests  
    compress: false           # No compression for test clarity
  ],
  
  # Fast HTTP configuration for tests
  http_config: [
    timeout: 5_000,           # 5 second timeout
    pool_timeout: 1_000,      # Fast pool timeout
    pool_max_connections: 2,  # Minimal connections for tests
    retry: false,             # Disable retries in tests for predictability
    retry_delay: 0,
    max_retries: 0
  ],
  
  # Very fast retry configuration for tests
  retry_config: [
    initial_delay: 10,        # 10ms - very fast
    max_delay: 100,           # 100ms max
    max_retries: 3,           # Limited retries
    backoff_factor: 1.5,      # Gentle backoff
    jitter: false             # No jitter for predictable timing
  ],
  
  # ==========================================================================
  # TEST STREAM CONFIGURATION
  # ==========================================================================
  
  # Minimal stream configuration for tests
  stream_config: [
    max_subscriptions: 5,     # Few streams for tests
    cleanup_interval: 1_000,  # Fast cleanup - 1 second
    health_check_interval: 5_000, # 5 second health checks
    buffer_size: 10,          # Small buffer for tests
    compression: false        # No compression for clarity
  ],
  
  # ==========================================================================
  # TEST USER CONFIGURATION
  # ==========================================================================
  
  # Minimal user configuration for tests
  user_config: [
    max_connections: 5,       # Few connections for tests
    session_timeout: 60_000,  # 1 minute timeout for tests
    idle_cleanup_interval: 5_000, # Fast cleanup - 5 seconds
    rate_limit: 1000,         # High rate limit for tests
    monitor_activity: false   # Disable monitoring in tests
  ],
  
  # ==========================================================================
  # TEST SECURITY CONFIGURATION
  # ==========================================================================
  
  # Relaxed security for testing
  security_config: [
    validate_signatures: false, # Disable signature validation in tests
    timestamp_window: 60_000,   # 1 minute window - generous for tests
    ip_whitelist: :any,         # Allow any IP in tests
    audit_requests: false       # No auditing in tests
  ],
  
  # ==========================================================================
  # TEST MONITORING CONFIGURATION
  # ==========================================================================
  
  # Minimal monitoring for tests
  monitoring_config: [
    enable_metrics: false,      # Disable metrics in tests
    metrics_interval: 60_000,   # Not used when disabled
    track_memory: false,        # No memory tracking
    track_processes: false      # No process tracking
  ],
  
  # Minimal telemetry for tests
  telemetry_config: [
    enabled: false,             # Disable telemetry in tests
    events: []                  # No events tracked
  ],
  
  # ==========================================================================
  # TEST-SPECIFIC SETTINGS
  # ==========================================================================
  
  # Enable test mode for conditional logic
  test_mode: true,
  
  # Mock response delays (useful for timing tests)
  mock_delays: [
    websocket_connect: 10,      # 10ms mock connect delay
    api_request: 50,            # 50ms mock API delay
    market_data: 5              # 5ms mock data delay
  ]

# =============================================================================
# TEST PUBSUB CONFIGURATION
# =============================================================================

# Fast PubSub configuration for tests
config :crypto_exchange, CryptoExchange.PubSub,
  name: CryptoExchange.PubSub,
  adapter: Phoenix.PubSub.PG2,
  pool_size: 1  # Single pool for tests

# =============================================================================
# TEST LOGGING CONFIGURATION
# =============================================================================

# Minimal logging for tests - only errors and warnings
config :logger,
  level: :warning,
  backends: [],               # No backends = no log output
  compile_time_purge_matching: [
    [level_lower_than: :warning] # Purge debug/info logs in tests
  ]

# Completely disable console output in tests
config :logger, :console,
  format: "",
  level: :emergency,          # Only emergency level (effectively disabled)
  metadata: []

# =============================================================================
# TEST REGISTRY CONFIGURATION
# =============================================================================

# Single partition registry for tests
config :crypto_exchange, CryptoExchange.Registry,
  keys: :unique,
  name: CryptoExchange.Registry,
  partitions: 1               # Single partition for predictable tests

# =============================================================================
# TEST JSON CONFIGURATION
# =============================================================================

# Pretty JSON for test clarity (when debugging)
config :crypto_exchange, :json,
  library: Jason,
  pretty: true                # Pretty format for test debugging

# =============================================================================
# EXUNIT CONFIGURATION
# =============================================================================

# Configure ExUnit test framework
config :ex_unit,
  capture_log: true,          # Capture logs during tests
  exclude: [:integration],    # Exclude integration tests by default
  formatters: [ExUnit.CLIFormatter],
  colors: [enabled: true],    # Colored test output
  trace: false,               # Set to true for detailed test tracing
  timeout: 60_000,            # 1 minute default test timeout
  max_failures: :infinity     # Run all tests even if some fail

# =============================================================================
# TEST ENVIRONMENT VARIABLES
# =============================================================================

# Support for test-specific environment variables
# Usage: CRYPTO_EXCHANGE_TEST_LOG_LEVEL=debug mix test

if System.get_env("CRYPTO_EXCHANGE_TEST_LOG_LEVEL") do
  level = String.to_existing_atom(System.get_env("CRYPTO_EXCHANGE_TEST_LOG_LEVEL"))
  config :logger, level: level, backends: [:console]
  
  config :logger, :console,
    format: "$time [$level] $message\n",
    level: level,
    metadata: [:test, :user_id, :symbol]
end

if System.get_env("CRYPTO_EXCHANGE_TEST_ENABLE_TELEMETRY") == "true" do
  config :crypto_exchange, 
    telemetry_config: [
      enabled: true,
      events: [:api_request, :api_error, :websocket_connected]
    ]
end

# =============================================================================
# TEST VALIDATION
# =============================================================================

# Note: Full validation is performed at runtime by CryptoExchange.Config.validate()
# Compile-time validation is skipped in test environment to avoid issues with
# configuration loading order