defmodule CryptoExchange.TestSupport.TestConfig do
  @moduledoc """
  Test configuration module for managing test environment settings.
  Provides utilities for configuring test scenarios and environments.
  """

  # =============================================================================
  # TEST ENVIRONMENT CONFIGURATION
  # =============================================================================

  @doc """
  Sets up test environment with mock configurations.
  """
  def setup_test_env(opts \\ []) do
    # Override application configuration for testing
    Application.put_env(:crypto_exchange, :enable_real_connections, false)
    
    # Set test-specific URLs
    Application.put_env(:crypto_exchange, :binance_ws_url, "ws://localhost:9999/ws")
    Application.put_env(:crypto_exchange, :binance_api_url, "http://localhost:9999/api")
    
    # Configure fast timeouts for tests
    configure_test_timeouts(opts)
    
    # Disable telemetry and monitoring in tests
    configure_test_monitoring(opts)
    
    :ok
  end

  @doc """
  Configures test timeouts for fast test execution.
  """
  def configure_test_timeouts(opts \\ []) do
    timeout_config = [
      connect_timeout: Keyword.get(opts, :connect_timeout, 1_000),
      request_timeout: Keyword.get(opts, :request_timeout, 5_000),
      ping_interval: Keyword.get(opts, :ping_interval, 10_000),
      retry_delay: Keyword.get(opts, :retry_delay, 10),
      max_retries: Keyword.get(opts, :max_retries, 3)
    ]
    
    Application.put_env(:crypto_exchange, :websocket_config, [
      connect_timeout: timeout_config[:connect_timeout],
      ping_interval: timeout_config[:ping_interval],
      max_frame_size: 65_536,
      compress: false
    ])
    
    Application.put_env(:crypto_exchange, :http_config, [
      timeout: timeout_config[:request_timeout],
      pool_timeout: 1_000,
      pool_max_connections: 2,
      retry: false,
      retry_delay: 0,
      max_retries: 0
    ])
    
    Application.put_env(:crypto_exchange, :retry_config, [
      initial_delay: timeout_config[:retry_delay],
      max_delay: 100,
      max_retries: timeout_config[:max_retries],
      backoff_factor: 1.5,
      jitter: false
    ])
  end

  @doc """
  Disables monitoring and telemetry for tests.
  """
  def configure_test_monitoring(opts \\ []) do
    enable_monitoring = Keyword.get(opts, :enable_monitoring, false)
    
    Application.put_env(:crypto_exchange, :monitoring_config, [
      enable_metrics: enable_monitoring,
      metrics_interval: 60_000,
      track_memory: enable_monitoring,
      track_processes: enable_monitoring
    ])
    
    Application.put_env(:crypto_exchange, :telemetry_config, [
      enabled: enable_monitoring,
      events: if(enable_monitoring, do: [:api_request, :api_error], else: [])
    ])
  end

  # =============================================================================
  # MOCK SERVER CONFIGURATION
  # =============================================================================

  @doc """
  Sets up mock server configurations for different test scenarios.
  """
  def setup_mock_config(scenario) do
    case scenario do
      :success ->
        setup_success_scenario()
      :network_error ->
        setup_network_error_scenario()
      :rate_limit ->
        setup_rate_limit_scenario()
      :timeout ->
        setup_timeout_scenario()
      :partial_failure ->
        setup_partial_failure_scenario()
      _ ->
        setup_success_scenario()
    end
  end

  defp setup_success_scenario do
    %{
      http_responses: %{
        "/api/v3/exchangeInfo" => {:ok, 200, exchange_info_response()},
        "/api/v3/account" => {:ok, 200, account_response()},
        "/api/v3/order" => {:ok, 200, order_response()}
      },
      websocket_messages: [
        ticker_message("BTCUSDT"),
        kline_message("BTCUSDT", "1m"),
        depth_message("BTCUSDT")
      ],
      delays: %{
        http: 50,
        websocket: 10
      }
    }
  end

  defp setup_network_error_scenario do
    %{
      http_responses: %{
        "/api/v3/exchangeInfo" => {:error, :connection_refused},
        "/api/v3/account" => {:error, :timeout},
        "/api/v3/order" => {:error, :network_unreachable}
      },
      websocket_messages: [],
      delays: %{
        http: 0,
        websocket: 0
      }
    }
  end

  defp setup_rate_limit_scenario do
    %{
      http_responses: %{
        "/api/v3/exchangeInfo" => {:ok, 429, rate_limit_response()},
        "/api/v3/account" => {:ok, 429, rate_limit_response()},
        "/api/v3/order" => {:ok, 429, rate_limit_response()}
      },
      websocket_messages: [],
      delays: %{
        http: 100,
        websocket: 10
      }
    }
  end

  defp setup_timeout_scenario do
    %{
      http_responses: %{
        "/api/v3/exchangeInfo" => {:timeout, 5000},
        "/api/v3/account" => {:timeout, 5000},
        "/api/v3/order" => {:timeout, 5000}
      },
      websocket_messages: [],
      delays: %{
        http: 5000,
        websocket: 10
      }
    }
  end

  defp setup_partial_failure_scenario do
    %{
      http_responses: %{
        "/api/v3/exchangeInfo" => {:ok, 200, exchange_info_response()},
        "/api/v3/account" => {:error, :timeout},
        "/api/v3/order" => {:ok, 400, order_error_response()}
      },
      websocket_messages: [
        ticker_message("BTCUSDT"),
        error_message(-1, "Invalid symbol")
      ],
      delays: %{
        http: 50,
        websocket: 10
      }
    }
  end

  # =============================================================================
  # RESPONSE TEMPLATES
  # =============================================================================

  defp exchange_info_response do
    %{
      "timezone" => "UTC",
      "serverTime" => System.system_time(:millisecond),
      "symbols" => [
        %{
          "symbol" => "BTCUSDT",
          "status" => "TRADING",
          "baseAsset" => "BTC",
          "quoteAsset" => "USDT",
          "baseAssetPrecision" => 8,
          "quotePrecision" => 8,
          "orderTypes" => ["LIMIT", "MARKET"],
          "icebergAllowed" => true,
          "ocoAllowed" => true,
          "isSpotTradingAllowed" => true,
          "isMarginTradingAllowed" => true,
          "filters" => []
        }
      ]
    }
  end

  defp account_response do
    %{
      "makerCommission" => 15,
      "takerCommission" => 15,
      "buyerCommission" => 0,
      "sellerCommission" => 0,
      "canTrade" => true,
      "canWithdraw" => true,
      "canDeposit" => true,
      "updateTime" => System.system_time(:millisecond),
      "accountType" => "SPOT",
      "balances" => [
        %{"asset" => "BTC", "free" => "1.00000000", "locked" => "0.00000000"},
        %{"asset" => "USDT", "free" => "10000.00000000", "locked" => "0.00000000"}
      ],
      "permissions" => ["SPOT"]
    }
  end

  defp order_response do
    %{
      "symbol" => "BTCUSDT",
      "orderId" => 12345,
      "clientOrderId" => "test_order_123",
      "transactTime" => System.system_time(:millisecond),
      "price" => "50000.00000000",
      "origQty" => "0.00100000",
      "executedQty" => "0.00000000",
      "status" => "NEW",
      "timeInForce" => "GTC",
      "type" => "LIMIT",
      "side" => "BUY"
    }
  end

  defp order_error_response do
    %{
      "code" => -1013,
      "msg" => "Filter failure: PRICE_FILTER"
    }
  end

  defp rate_limit_response do
    %{
      "code" => -1003,
      "msg" => "Too many requests"
    }
  end

  defp ticker_message(symbol) do
    %{
      "e" => "24hrTicker",
      "E" => System.system_time(:millisecond),
      "s" => symbol,
      "c" => "50000.00",
      "P" => "2.50",
      "h" => "51000.00",
      "l" => "48000.00",
      "v" => "1000.123"
    }
  end

  defp kline_message(symbol, interval) do
    %{
      "e" => "kline",
      "E" => System.system_time(:millisecond),
      "s" => symbol,
      "k" => %{
        "i" => interval,
        "o" => "49500.00",
        "h" => "50500.00",
        "l" => "49000.00",
        "c" => "50000.00",
        "v" => "100.123",
        "t" => System.system_time(:millisecond) - 60_000,
        "T" => System.system_time(:millisecond)
      }
    }
  end

  defp depth_message(symbol) do
    %{
      "e" => "depthUpdate",
      "s" => symbol,
      "b" => [["49900.00", "1.000"]],
      "a" => [["50100.00", "1.500"]]
    }
  end

  defp error_message(code, msg) do
    %{
      "error" => %{
        "code" => code,
        "msg" => msg
      }
    }
  end

  # =============================================================================
  # TEST DATA CLEANUP
  # =============================================================================

  @doc """
  Cleans up test configuration and resets to defaults.
  """
  def cleanup_test_env do
    # Reset application configuration
    Application.delete_env(:crypto_exchange, :test_mode)
    
    # Clear any test-specific ETS tables
    cleanup_test_tables()
    
    # Reset PubSub subscriptions
    cleanup_pubsub_subscriptions()
    
    :ok
  end

  defp cleanup_test_tables do
    # List all ETS tables that might have been created during tests
    test_tables = :ets.all()
    |> Enum.filter(fn table ->
      case :ets.info(table, :name) do
        name when is_atom(name) ->
          name |> Atom.to_string() |> String.contains?("test")
        _ ->
          false
      end
    end)
    
    Enum.each(test_tables, fn table ->
      try do
        :ets.delete(table)
      rescue
        _ -> :ok
      end
    end)
  end

  defp cleanup_pubsub_subscriptions do
    # This would typically involve tracking and cleaning up
    # any PubSub subscriptions created during tests
    # For now, we rely on process cleanup
    :ok
  end

  # =============================================================================
  # TEST ENVIRONMENT UTILITIES
  # =============================================================================

  @doc """
  Checks if running in test environment.
  """
  def test_env? do
    Mix.env() == :test
  end

  @doc """
  Gets test-specific configuration value.
  """
  def get_test_config(key, default \\ nil) do
    if test_env?() do
      Application.get_env(:crypto_exchange, key, default)
    else
      default
    end
  end

  @doc """
  Sets test-specific configuration value.
  """
  def put_test_config(key, value) do
    if test_env?() do
      Application.put_env(:crypto_exchange, key, value)
    end
  end

  @doc """
  Temporarily overrides configuration for a test.
  """
  def with_test_config(config_overrides, fun) when is_function(fun, 0) do
    original_config = Enum.map(config_overrides, fn {key, _value} ->
      {key, Application.get_env(:crypto_exchange, key)}
    end)
    
    try do
      Enum.each(config_overrides, fn {key, value} ->
        Application.put_env(:crypto_exchange, key, value)
      end)
      
      fun.()
    after
      Enum.each(original_config, fn {key, value} ->
        if value do
          Application.put_env(:crypto_exchange, key, value)
        else
          Application.delete_env(:crypto_exchange, key)
        end
      end)
    end
  end
end