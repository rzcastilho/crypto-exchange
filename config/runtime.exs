# =============================================================================
# RUNTIME CONFIGURATION FOR RELEASES
# =============================================================================
# This file is loaded at runtime for releases and can access environment
# variables. It's used to configure the application when building releases
# with `mix release`.

import Config
require Logger

# =============================================================================
# ENVIRONMENT DETECTION
# =============================================================================

# Detect the runtime environment
runtime_env = System.get_env("MIX_ENV") || "prod"

Logger.info("Loading runtime configuration for environment: #{runtime_env}")

# =============================================================================
# BINANCE API CONFIGURATION
# =============================================================================

# Configure Binance API endpoints from environment variables
binance_api_url = System.get_env("BINANCE_API_URL") || "https://api.binance.com"
binance_ws_url = System.get_env("BINANCE_WS_URL") || "wss://stream.binance.com:9443/ws"

config :crypto_exchange,
  binance_api_url: binance_api_url,
  binance_ws_url: binance_ws_url

Logger.info("Runtime config - Binance API URL: #{binance_api_url}")
Logger.info("Runtime config - Binance WebSocket URL: #{binance_ws_url}")

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

# Configure logging level from environment
log_level = 
  case System.get_env("LOG_LEVEL") do
    level when level in ["debug", "info", "warning", "error"] ->
      String.to_existing_atom(level)
    nil ->
      :info
    invalid ->
      Logger.warning("Invalid LOG_LEVEL '#{invalid}', defaulting to :info")
      :info
  end

config :logger, level: log_level
Logger.info("Runtime config - Log level set to: #{log_level}")

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

# Configure IP whitelist from environment
ip_whitelist = 
  case System.get_env("IP_WHITELIST") do
    nil -> 
      :any
    "" -> 
      :any
    ips_string ->
      ips_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))
  end

# Validate IP addresses if provided
validated_ip_whitelist = 
  case ip_whitelist do
    :any -> 
      :any
    ips when is_list(ips) ->
      valid_ips = Enum.filter(ips, fn ip ->
        case :inet.parse_address(String.to_charlist(ip)) do
          {:ok, _} -> true
          {:error, _} -> 
            Logger.warning("Invalid IP address in whitelist: #{ip}")
            false
        end
      end)
      
      if Enum.empty?(valid_ips) do
        Logger.warning("No valid IP addresses in whitelist, allowing any IP")
        :any
      else
        valid_ips
      end
  end

# Configure rate limiting
rate_limit = 
  case System.get_env("RATE_LIMIT") do
    nil -> 1200
    limit_str ->
      case Integer.parse(limit_str) do
        {limit, _} when limit > 0 -> limit
        _ ->
          Logger.warning("Invalid RATE_LIMIT '#{limit_str}', defaulting to 1200")
          1200
      end
  end

# Apply security configuration
config :crypto_exchange,
  security_config: [
    validate_signatures: true,
    timestamp_window: 5_000,
    ip_whitelist: validated_ip_whitelist,
    audit_requests: true
  ],
  user_config: [
    max_connections: 10_000,
    session_timeout: 7_200_000,
    idle_cleanup_interval: 600_000,
    rate_limit: rate_limit,
    monitor_activity: true
  ]

Logger.info("Runtime config - IP whitelist: #{inspect(validated_ip_whitelist)}")
Logger.info("Runtime config - Rate limit: #{rate_limit} requests/minute")

# =============================================================================
# MONITORING CONFIGURATION
# =============================================================================

# Configure metrics collection
enable_metrics = 
  case System.get_env("ENABLE_METRICS") do
    "false" -> false
    "0" -> false
    _ -> true
  end

# Configure telemetry
enable_telemetry = 
  case System.get_env("ENABLE_TELEMETRY") do
    "false" -> false
    "0" -> false
    _ -> true
  end

config :crypto_exchange,
  monitoring_config: [
    enable_metrics: enable_metrics,
    metrics_interval: 60_000,
    track_memory: enable_metrics,
    track_processes: enable_metrics
  ],
  telemetry_config: [
    enabled: enable_telemetry,
    events: if enable_telemetry do
      [
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
    else
      []
    end
  ]

Logger.info("Runtime config - Metrics enabled: #{enable_metrics}")
Logger.info("Runtime config - Telemetry enabled: #{enable_telemetry}")

# =============================================================================
# CONNECTION POOL CONFIGURATION
# =============================================================================

# Configure connection pool sizes based on available resources
schedulers = System.schedulers_online()

# WebSocket connection settings
websocket_timeout = 
  case System.get_env("WEBSOCKET_TIMEOUT") do
    nil -> 15_000
    timeout_str ->
      case Integer.parse(timeout_str) do
        {timeout, _} when timeout > 0 -> timeout * 1000  # Convert seconds to milliseconds
        _ ->
          Logger.warning("Invalid WEBSOCKET_TIMEOUT '#{timeout_str}', defaulting to 15 seconds")
          15_000
      end
  end

# HTTP pool configuration
http_pool_size = 
  case System.get_env("HTTP_POOL_SIZE") do
    nil -> min(200, schedulers * 25)
    size_str ->
      case Integer.parse(size_str) do
        {size, _} when size > 0 -> size
        _ ->
          Logger.warning("Invalid HTTP_POOL_SIZE '#{size_str}', using default")
          min(200, schedulers * 25)
      end
  end

config :crypto_exchange,
  websocket_config: [
    connect_timeout: websocket_timeout,
    ping_interval: 20_000,
    max_frame_size: 2_097_152,
    compress: true
  ],
  http_config: [
    timeout: 30_000,
    pool_timeout: 10_000,
    pool_max_connections: http_pool_size,
    retry: true,
    retry_delay: 1_000,
    max_retries: 3
  ]

Logger.info("Runtime config - WebSocket timeout: #{websocket_timeout}ms")
Logger.info("Runtime config - HTTP pool size: #{http_pool_size}")

# =============================================================================
# PUBSUB & REGISTRY CONFIGURATION
# =============================================================================

# Configure PubSub and Registry pool sizes based on system resources
pubsub_pool_size = schedulers * 2
registry_partitions = schedulers * 4

config :crypto_exchange, CryptoExchange.PubSub,
  name: CryptoExchange.PubSub,
  adapter: Phoenix.PubSub.PG2,
  pool_size: pubsub_pool_size

config :crypto_exchange, CryptoExchange.Registry,
  keys: :unique,
  name: CryptoExchange.Registry,
  partitions: registry_partitions

Logger.info("Runtime config - PubSub pool size: #{pubsub_pool_size}")
Logger.info("Runtime config - Registry partitions: #{registry_partitions}")

# =============================================================================
# STREAM CONFIGURATION
# =============================================================================

# Configure stream limits based on environment
max_streams = 
  case System.get_env("MAX_STREAMS") do
    nil -> 1000
    streams_str ->
      case Integer.parse(streams_str) do
        {streams, _} when streams > 0 -> streams
        _ ->
          Logger.warning("Invalid MAX_STREAMS '#{streams_str}', defaulting to 1000")
          1000
      end
  end

max_users = 
  case System.get_env("MAX_USERS") do
    nil -> 10_000
    users_str ->
      case Integer.parse(users_str) do
        {users, _} when users > 0 -> users
        _ ->
          Logger.warning("Invalid MAX_USERS '#{users_str}', defaulting to 10000")
          10_000
      end
  end

config :crypto_exchange,
  stream_config: [
    max_subscriptions: max_streams,
    cleanup_interval: 600_000,
    health_check_interval: 120_000,
    buffer_size: 5000,
    compression: true
  ],
  user_config: [
    max_connections: max_users,
    session_timeout: 7_200_000,
    idle_cleanup_interval: 600_000,
    rate_limit: rate_limit,
    monitor_activity: true
  ]

Logger.info("Runtime config - Max streams: #{max_streams}")
Logger.info("Runtime config - Max users: #{max_users}")

# =============================================================================
# HEALTH CHECK CONFIGURATION
# =============================================================================

# Enable health check endpoint if specified
if System.get_env("ENABLE_HEALTH_CHECK") != "false" do
  health_check_port = 
    case System.get_env("HEALTH_CHECK_PORT") do
      nil -> 4001
      port_str ->
        case Integer.parse(port_str) do
          {port, _} when port > 0 and port < 65536 -> port
          _ ->
            Logger.warning("Invalid HEALTH_CHECK_PORT '#{port_str}', defaulting to 4001")
            4001
        end
    end
  
  # Note: Health check configuration would be used by a Phoenix endpoint if added
  # config :crypto_exchange, CryptoExchangeWeb.Endpoint,
  #   http: [port: health_check_port],
  #   url: [host: "localhost", port: health_check_port]
  
  Logger.info("Runtime config - Health check would be available on port: #{health_check_port}")
end

# =============================================================================
# VALIDATION
# =============================================================================

# Validate critical configuration
unless String.starts_with?(binance_api_url, "http") do
  raise "Invalid BINANCE_API_URL: must start with http:// or https://"
end

unless String.starts_with?(binance_ws_url, "ws") do
  raise "Invalid BINANCE_WS_URL: must start with ws:// or wss://"
end

if rate_limit < 60 do
  Logger.warning("Rate limit is very low (#{rate_limit}), this may cause issues with normal operation")
end

if max_streams > 10_000 do
  Logger.warning("Max streams is very high (#{max_streams}), ensure you have sufficient resources")
end

Logger.info("Runtime configuration loaded successfully")

# =============================================================================
# ENVIRONMENT VARIABLES REFERENCE
# =============================================================================

# This file supports the following environment variables:
#
# Core Configuration:
#   BINANCE_API_URL      - Binance REST API URL (default: https://api.binance.com)
#   BINANCE_WS_URL       - Binance WebSocket URL (default: wss://stream.binance.com:9443/ws)
#   LOG_LEVEL            - Logging level: debug, info, warning, error (default: info)
#
# Security:
#   IP_WHITELIST         - Comma-separated list of allowed IP addresses (default: any)
#   RATE_LIMIT           - API requests per minute per user (default: 1200)
#
# Performance:
#   MAX_STREAMS          - Maximum concurrent stream subscriptions (default: 1000)
#   MAX_USERS            - Maximum concurrent user connections (default: 10000)
#   HTTP_POOL_SIZE       - HTTP connection pool size (default: auto-calculated)
#   WEBSOCKET_TIMEOUT    - WebSocket connection timeout in seconds (default: 15)
#
# Monitoring:
#   ENABLE_METRICS       - Enable metrics collection: true/false (default: true)
#   ENABLE_TELEMETRY     - Enable telemetry events: true/false (default: true)
#   ENABLE_HEALTH_CHECK  - Enable health check endpoint: true/false (default: true)
#   HEALTH_CHECK_PORT    - Health check HTTP port (default: 4001)
#
# Example production startup:
#   BINANCE_API_URL=https://api.binance.com \
#   LOG_LEVEL=info \
#   MAX_USERS=5000 \
#   ENABLE_METRICS=true \
#   ./crypto_exchange start