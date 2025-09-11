defmodule CryptoExchange.Config do
  @moduledoc """
  Configuration management and validation for CryptoExchange.
  
  This module provides centralized configuration access and validation
  to ensure the application is properly configured at startup.
  
  ## Configuration Sources
  
  Configuration is loaded from multiple sources in the following order:
  1. Base configuration in `config/config.exs`
  2. Environment-specific configuration (`dev.exs`, `test.exs`, `prod.exs`)
  3. Runtime configuration in `config/runtime.exs` (for releases)
  4. Environment variables (highest priority)
  
  ## Validation
  
  All configuration is validated at application startup to catch
  configuration errors early and provide helpful error messages.
  
  ## Usage
  
      # Get configuration value
      CryptoExchange.Config.binance_api_url()
      
      # Get configuration with default
      CryptoExchange.Config.get(:custom_setting, "default_value")
      
      # Validate all configuration
      :ok = CryptoExchange.Config.validate()
  """
  
  require Logger
  
  # =============================================================================
  # PUBLIC API
  # =============================================================================
  
  @doc """
  Get the Binance REST API URL.
  
  ## Examples
  
      iex> CryptoExchange.Config.binance_api_url()
      "https://api.binance.com"
  """
  @spec binance_api_url() :: String.t()
  def binance_api_url do
    get(:binance_api_url, "https://api.binance.com")
  end
  
  @doc """
  Get the Binance WebSocket URL.
  
  ## Examples
  
      iex> CryptoExchange.Config.binance_ws_url()
      "wss://stream.binance.com:9443/ws"
  """
  @spec binance_ws_url() :: String.t()
  def binance_ws_url do
    get(:binance_ws_url, "wss://stream.binance.com:9443/ws")
  end
  
  @doc """
  Get the WebSocket configuration.
  """
  @spec websocket_config() :: Keyword.t()
  def websocket_config do
    get(:websocket_config, [
      connect_timeout: 10_000,
      ping_interval: 30_000,
      max_frame_size: 1_048_576,
      compress: true
    ])
  end
  
  @doc """
  Get the HTTP client configuration.
  """
  @spec http_config() :: Keyword.t()
  def http_config do
    get(:http_config, [
      timeout: 30_000,
      pool_timeout: 5_000,
      pool_max_connections: 100,
      retry: true,
      retry_delay: 1_000,
      max_retries: 3
    ])
  end
  
  @doc """
  Get the retry configuration.
  """
  @spec retry_config() :: Keyword.t()
  def retry_config do
    get(:retry_config, [
      initial_delay: 1_000,
      max_delay: 30_000,
      max_retries: :infinity,
      backoff_factor: 2.0,
      jitter: true
    ])
  end
  
  @doc """
  Get the stream configuration.
  """
  @spec stream_config() :: Keyword.t()
  def stream_config do
    get(:stream_config, [
      max_subscriptions: 200,
      cleanup_interval: 300_000,
      health_check_interval: 60_000,
      buffer_size: 1000,
      compression: true
    ])
  end
  
  @doc """
  Get the user connection configuration.
  """
  @spec user_config() :: Keyword.t()
  def user_config do
    get(:user_config, [
      max_connections: 1000,
      session_timeout: 3_600_000,
      idle_cleanup_interval: 300_000,
      rate_limit: 1200,
      monitor_activity: true
    ])
  end
  
  @doc """
  Get the security configuration.
  """
  @spec security_config() :: Keyword.t()
  def security_config do
    get(:security_config, [
      validate_signatures: true,
      timestamp_window: 5_000,
      ip_whitelist: :any,
      audit_requests: false
    ])
  end
  
  @doc """
  Get the monitoring configuration.
  """
  @spec monitoring_config() :: Keyword.t()
  def monitoring_config do
    get(:monitoring_config, [
      enable_metrics: true,
      metrics_interval: 60_000,
      track_memory: true,
      track_processes: true
    ])
  end
  
  @doc """
  Get the telemetry configuration.
  """
  @spec telemetry_config() :: Keyword.t()
  def telemetry_config do
    get(:telemetry_config, [
      enabled: true,
      events: [
        :websocket_connected,
        :websocket_disconnected,
        :market_data_received,
        :order_placed,
        :order_filled,
        :api_request,
        :api_error
      ]
    ])
  end
  
  @doc """
  Get a configuration value by key with optional default.
  
  ## Examples
  
      iex> CryptoExchange.Config.get(:binance_api_url)
      "https://api.binance.com"
      
      iex> CryptoExchange.Config.get(:custom_key, "default")
      "default"
  """
  @spec get(atom(), any()) :: any()
  def get(key, default \\ nil) do
    Application.get_env(:crypto_exchange, key, default)
  end
  
  @doc """
  Get all configuration as a map.
  
  Useful for debugging and configuration inspection.
  """
  @spec all() :: map()
  def all do
    Application.get_all_env(:crypto_exchange)
    |> Enum.into(%{})
  end
  
  @doc """
  Validate all configuration at startup.
  
  Returns `:ok` if configuration is valid, otherwise raises an error
  with a descriptive message.
  
  ## Examples
  
      iex> CryptoExchange.Config.validate()
      :ok
  """
  @spec validate() :: :ok
  def validate do
    Logger.info("Validating CryptoExchange configuration...")
    
    # Validate core configuration
    validate_binance_urls()
    validate_connection_config()
    validate_stream_config()
    validate_user_config()
    validate_security_config()
    validate_monitoring_config()
    validate_environment_consistency()
    
    Logger.info("Configuration validation passed")
    :ok
  end
  
  @doc """
  Check if the application is running in test mode.
  """
  @spec test_mode?() :: boolean()
  def test_mode? do
    get(:test_mode, false) || Mix.env() == :test
  end
  
  @doc """
  Check if external connections are enabled.
  """
  @spec external_connections_enabled?() :: boolean()
  def external_connections_enabled? do
    get(:enable_real_connections, true)
  end
  
  @doc """
  Get the current environment.
  """
  @spec env() :: atom()
  def env do
    Mix.env()
  end
  
  # =============================================================================
  # VALIDATION FUNCTIONS
  # =============================================================================
  
  defp validate_binance_urls do
    api_url = binance_api_url()
    ws_url = binance_ws_url()
    
    # Validate API URL format
    unless is_binary(api_url) and String.match?(api_url, ~r/^https?:\/\//) do
      raise __MODULE__.ConfigError, """
      Invalid binance_api_url configuration: '#{api_url}'
      
      Expected: A valid HTTP/HTTPS URL (e.g., "https://api.binance.com")
      Got: #{inspect(api_url)}
      
      Please check your configuration in config/config.exs or environment variables.
      """
    end
    
    # Validate WebSocket URL format
    unless is_binary(ws_url) and String.match?(ws_url, ~r/^wss?:\/\//) do
      raise __MODULE__.ConfigError, """
      Invalid binance_ws_url configuration: '#{ws_url}'
      
      Expected: A valid WebSocket URL (e.g., "wss://stream.binance.com:9443/ws")
      Got: #{inspect(ws_url)}
      
      Please check your configuration in config/config.exs or environment variables.
      """
    end
    
    # Validate URL consistency in test environment
    if test_mode?() do
      unless String.contains?(api_url, "localhost") do
        Logger.warning("Test environment should use localhost API URL, got: #{api_url}")
      end
      
      unless String.contains?(ws_url, "localhost") do
        Logger.warning("Test environment should use localhost WebSocket URL, got: #{ws_url}")
      end
    end
    
    Logger.debug("URLs validated - API: #{api_url}, WebSocket: #{ws_url}")
  end
  
  defp validate_connection_config do
    ws_config = websocket_config()
    http_config = http_config()
    retry_config = retry_config()
    
    # Validate WebSocket configuration
    validate_positive_integer(ws_config[:connect_timeout], "websocket_config.connect_timeout")
    validate_positive_integer(ws_config[:ping_interval], "websocket_config.ping_interval")
    validate_positive_integer(ws_config[:max_frame_size], "websocket_config.max_frame_size")
    validate_boolean(ws_config[:compress], "websocket_config.compress")
    
    # Validate HTTP configuration
    validate_positive_integer(http_config[:timeout], "http_config.timeout")
    validate_positive_integer(http_config[:pool_timeout], "http_config.pool_timeout")
    validate_positive_integer(http_config[:pool_max_connections], "http_config.pool_max_connections")
    validate_boolean(http_config[:retry], "http_config.retry")
    
    if http_config[:retry] do
      validate_positive_integer(http_config[:retry_delay], "http_config.retry_delay")
      validate_positive_integer(http_config[:max_retries], "http_config.max_retries")
    end
    
    # Validate retry configuration
    validate_positive_integer(retry_config[:initial_delay], "retry_config.initial_delay")
    validate_positive_integer(retry_config[:max_delay], "retry_config.max_delay")
    
    unless retry_config[:max_retries] == :infinity or is_integer(retry_config[:max_retries]) do
      raise __MODULE__.ConfigError, "retry_config.max_retries must be :infinity or a positive integer"
    end
    
    validate_positive_number(retry_config[:backoff_factor], "retry_config.backoff_factor")
    validate_boolean(retry_config[:jitter], "retry_config.jitter")
    
    Logger.debug("Connection configuration validated")
  end
  
  defp validate_stream_config do
    config = stream_config()
    
    validate_positive_integer(config[:max_subscriptions], "stream_config.max_subscriptions")
    validate_positive_integer(config[:cleanup_interval], "stream_config.cleanup_interval")
    validate_positive_integer(config[:health_check_interval], "stream_config.health_check_interval")
    validate_positive_integer(config[:buffer_size], "stream_config.buffer_size")
    validate_boolean(config[:compression], "stream_config.compression")
    
    Logger.debug("Stream configuration validated")
  end
  
  defp validate_user_config do
    config = user_config()
    
    validate_positive_integer(config[:max_connections], "user_config.max_connections")
    validate_positive_integer(config[:session_timeout], "user_config.session_timeout")
    validate_positive_integer(config[:idle_cleanup_interval], "user_config.idle_cleanup_interval")
    validate_positive_integer(config[:rate_limit], "user_config.rate_limit")
    validate_boolean(config[:monitor_activity], "user_config.monitor_activity")
    
    # Validate rate limit is reasonable
    rate_limit = config[:rate_limit]
    if rate_limit > 6000 do  # Binance limit is 6000/minute for some endpoints
      Logger.warning("Rate limit #{rate_limit} exceeds typical Binance limits")
    end
    
    Logger.debug("User configuration validated")
  end
  
  defp validate_security_config do
    config = security_config()
    
    validate_boolean(config[:validate_signatures], "security_config.validate_signatures")
    validate_positive_integer(config[:timestamp_window], "security_config.timestamp_window")
    validate_boolean(config[:audit_requests], "security_config.audit_requests")
    
    # Validate IP whitelist
    case config[:ip_whitelist] do
      :any -> 
        :ok
      ips when is_list(ips) ->
        Enum.each(ips, fn ip ->
          case :inet.parse_address(String.to_charlist(ip)) do
            {:ok, _} -> :ok
            {:error, _} -> 
              raise __MODULE__.ConfigError, "Invalid IP address in security_config.ip_whitelist: #{ip}"
          end
        end)
      invalid ->
        raise __MODULE__.ConfigError, """
        Invalid security_config.ip_whitelist: #{inspect(invalid)}
        Expected: :any or a list of valid IP addresses
        """
    end
    
    # Security warnings for production
    if env() == :prod do
      unless config[:validate_signatures] do
        Logger.error("SECURITY WARNING: Signature validation is disabled in production!")
      end
      
      unless config[:audit_requests] do
        Logger.warning("SECURITY NOTICE: Request auditing is disabled in production")
      end
      
      if config[:ip_whitelist] == :any do
        Logger.warning("SECURITY NOTICE: IP whitelist allows any IP in production")
      end
    end
    
    Logger.debug("Security configuration validated")
  end
  
  defp validate_monitoring_config do
    monitoring = monitoring_config()
    telemetry = telemetry_config()
    
    # Validate monitoring configuration
    validate_boolean(monitoring[:enable_metrics], "monitoring_config.enable_metrics")
    validate_positive_integer(monitoring[:metrics_interval], "monitoring_config.metrics_interval")
    validate_boolean(monitoring[:track_memory], "monitoring_config.track_memory")
    validate_boolean(monitoring[:track_processes], "monitoring_config.track_processes")
    
    # Validate telemetry configuration
    validate_boolean(telemetry[:enabled], "telemetry_config.enabled")
    
    unless is_list(telemetry[:events]) do
      raise __MODULE__.ConfigError, "telemetry_config.events must be a list of atoms"
    end
    
    Enum.each(telemetry[:events], fn event ->
      unless is_atom(event) do
        raise __MODULE__.ConfigError, "Invalid telemetry event: #{inspect(event)} (must be an atom)"
      end
    end)
    
    Logger.debug("Monitoring configuration validated")
  end
  
  defp validate_environment_consistency do
    case env() do
      :test ->
        # Test environment checks
        unless get(:enable_real_connections, true) == false do
          Logger.warning("Test environment should have enable_real_connections: false")
        end
        
      :dev ->
        # Development environment checks  
        api_url = binance_api_url()
        if String.contains?(api_url, "api.binance.com") do
          Logger.warning("Development environment is using production Binance API")
        end
        
      :prod ->
        # Production environment checks
        api_url = binance_api_url()
        unless String.contains?(api_url, "api.binance.com") or 
               String.contains?(api_url, System.get_env("BINANCE_API_URL") || "") do
          Logger.warning("Production environment using non-standard Binance API: #{api_url}")
        end
        
      _ ->
        Logger.warning("Unknown environment: #{env()}")
    end
    
    Logger.debug("Environment consistency validated")
  end
  
  # =============================================================================
  # HELPER FUNCTIONS
  # =============================================================================
  
  defp validate_positive_integer(value, name) do
    unless is_integer(value) and value > 0 do
      raise __MODULE__.ConfigError, "#{name} must be a positive integer, got: #{inspect(value)}"
    end
  end
  
  defp validate_positive_number(value, name) do
    unless is_number(value) and value > 0 do
      raise __MODULE__.ConfigError, "#{name} must be a positive number, got: #{inspect(value)}"
    end
  end
  
  defp validate_boolean(value, name) do
    unless is_boolean(value) do
      raise __MODULE__.ConfigError, "#{name} must be a boolean, got: #{inspect(value)}"
    end
  end
  
  # =============================================================================
  # CONFIGURATION ERROR
  # =============================================================================
  
  defmodule ConfigError do
    @moduledoc """
    Raised when there is a configuration error.
    """
    defexception [:message]
    
    @impl true
    def exception(message) when is_binary(message) do
      %__MODULE__{message: message}
    end
    
    def exception(opts) when is_list(opts) do
      message = Keyword.get(opts, :message, "Configuration error")
      %__MODULE__{message: message}
    end
  end
end