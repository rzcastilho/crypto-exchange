defmodule CryptoExchange.API.ErrorCatalog do
  @moduledoc """
  Comprehensive error catalog and documentation for the CryptoExchange API.
  
  This module provides complete documentation of all possible API errors,
  their causes, resolution steps, and examples. It serves as a reference
  for developers integrating with the CryptoExchange API.
  
  ## Error Categories
  
  - **Validation Errors**: Input format and content validation failures
  - **Authentication Errors**: API credential and permission issues
  - **Business Logic Errors**: Trading rules and constraint violations
  - **Service Errors**: External service and connectivity issues
  - **System Errors**: Internal system failures and timeouts
  - **Rate Limiting**: API usage limit violations
  
  ## Error Format
  
  All errors follow a consistent format:
  - Simple: `{:error, :error_reason}`
  - Detailed: `{:error, %{reason: :atom, message: string(), suggestions: [string()]}}`
  """

  @doc """
  Returns comprehensive documentation for all API errors.
  
  Provides detailed information about each error including description,
  common causes, resolution steps, and examples.
  """
  @spec get_error_documentation() :: map()
  def get_error_documentation do
    %{
      validation_errors: validation_errors(),
      authentication_errors: authentication_errors(),
      business_logic_errors: business_logic_errors(),
      service_errors: service_errors(),
      system_errors: system_errors(),
      rate_limiting_errors: rate_limiting_errors()
    }
  end

  @doc """
  Gets detailed documentation for a specific error reason.
  """
  @spec get_error_details(atom()) :: map() | nil
  def get_error_details(error_reason) do
    all_errors = get_error_documentation()
    
    Enum.find_value(all_errors, fn {_category, errors} ->
      Enum.find(errors, fn error -> error.reason == error_reason end)
    end)
  end

  @doc """
  Returns a list of all possible error reasons for API validation.
  """
  @spec get_all_error_reasons() :: [atom()]
  def get_all_error_reasons do
    all_errors = get_error_documentation()
    
    Enum.flat_map(all_errors, fn {_category, errors} ->
      Enum.map(errors, & &1.reason)
    end)
  end

  @doc """
  Returns troubleshooting guide for common error scenarios.
  """
  @spec get_troubleshooting_guide() :: map()
  def get_troubleshooting_guide do
    %{
      quick_fixes: quick_fixes(),
      common_scenarios: common_scenarios(),
      debugging_steps: debugging_steps(),
      best_practices: best_practices()
    }
  end

  # Validation Errors Documentation
  defp validation_errors do
    [
      %{
        reason: :invalid_symbol,
        category: "Validation",
        description: "Trading symbol format is invalid",
        common_causes: [
          "Symbol is too short (less than 3 characters)",
          "Symbol is too long (more than 20 characters)",
          "Symbol contains lowercase letters",
          "Symbol contains special characters",
          "Symbol is empty or nil"
        ],
        resolution_steps: [
          "Use valid trading pair symbols (e.g., 'BTCUSDT', 'ETHUSDT')",
          "Ensure symbol is uppercase",
          "Check symbol length (3-20 characters)",
          "Use only letters and numbers",
          "Verify symbol exists on the exchange"
        ],
        examples: %{
          invalid: ["BT", "btcusdt", "BTC-USDT", "", nil],
          valid: ["BTCUSDT", "ETHUSDT", "ADAUSDT", "DOTUSDT"]
        }
      },
      %{
        reason: :invalid_level,
        category: "Validation",
        description: "Order book depth level is invalid",
        common_causes: [
          "Depth level is not 5, 10, or 20",
          "Depth level is not an integer",
          "Depth level is negative or zero"
        ],
        resolution_steps: [
          "Use supported depth levels: 5, 10, or 20",
          "Ensure level is a positive integer",
          "Default level is 5 if not specified"
        ],
        examples: %{
          invalid: [3, 15, 25, 0, -5, "5"],
          valid: [5, 10, 20]
        }
      },
      %{
        reason: :invalid_user_id,
        category: "Validation",
        description: "User ID format is invalid",
        common_causes: [
          "User ID is too short (less than 3 characters)",
          "User ID is too long (more than 32 characters)",
          "User ID contains invalid characters",
          "User ID is empty or nil"
        ],
        resolution_steps: [
          "Use 3-32 character user IDs",
          "Use alphanumeric characters, underscores, and hyphens only",
          "Avoid spaces and special characters",
          "Ensure user ID is not empty"
        ],
        examples: %{
          invalid: ["x", "user with spaces", "user@domain.com", ""],
          valid: ["user123", "trader_001", "user-abc", "client_123"]
        }
      },
      %{
        reason: :invalid_credentials,
        category: "Validation", 
        description: "API credentials format is invalid",
        common_causes: [
          "API key or secret is too short (less than 32 characters)",
          "API key or secret is too long (more than 128 characters)",
          "Credentials contain invalid characters",
          "Credentials are empty or nil"
        ],
        resolution_steps: [
          "Use valid Binance API credentials",
          "Ensure credentials are 32-128 characters long",
          "Use only alphanumeric characters",
          "Check credentials from Binance account settings"
        ],
        examples: %{
          invalid: ["short", "key with spaces", "", nil],
          valid: ["valid_32_character_api_key_example", "another_valid_64_character_secret_key_example_string"]
        }
      },
      %{
        reason: :invalid_order_params,
        category: "Validation",
        description: "Order parameters are invalid or missing",
        common_causes: [
          "Missing required fields (symbol, side, type, quantity)",
          "Invalid parameter types or formats",
          "Required price missing for LIMIT orders",
          "Parameters contain null or empty values"
        ],
        resolution_steps: [
          "Include all required fields: symbol, side, type, quantity",
          "Provide price for LIMIT orders",
          "Use correct parameter types (strings for most fields)",
          "Ensure no fields are null or empty"
        ],
        examples: %{
          invalid: [
            %{"symbol" => "BTCUSDT", "side" => "BUY"},  # Missing type and quantity
            %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "0.001"},  # Missing price
            %{"symbol" => "BTCUSDT", "side" => "INVALID", "type" => "MARKET", "quantity" => "0.001"}  # Invalid side
          ],
          valid: [
            %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET", "quantity" => "0.001"},
            %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "0.001", "price" => "50000"}
          ]
        }
      },
      %{
        reason: :invalid_quantity,
        category: "Validation",
        description: "Order quantity format or value is invalid",
        common_causes: [
          "Quantity is not a numeric string",
          "Quantity is negative or zero",
          "Quantity has invalid decimal format",
          "Quantity precision exceeds limits"
        ],
        resolution_steps: [
          "Use positive numeric strings for quantity",
          "Use decimal format (e.g., '0.001', '1.5')",
          "Avoid scientific notation",
          "Check symbol's lot size filters"
        ],
        examples: %{
          invalid: [-0.001, "abc", "", nil, 0],
          valid: ["0.001", "1", "1.5", "100.0"]
        }
      },
      %{
        reason: :invalid_price,
        category: "Validation",
        description: "Order price format or value is invalid",
        common_causes: [
          "Price is not a numeric string",
          "Price is negative or zero",
          "Price has invalid decimal format",
          "Price precision exceeds limits"
        ],
        resolution_steps: [
          "Use positive numeric strings for price",
          "Use decimal format (e.g., '50000', '1234.56')",
          "Required for LIMIT orders",
          "Check symbol's price filters"
        ],
        examples: %{
          invalid: [-50000, "abc", "", nil, 0],
          valid: ["50000", "1234.56", "0.001", "99999.99"]
        }
      },
      %{
        reason: :invalid_order_id,
        category: "Validation",
        description: "Order ID format is invalid",
        common_causes: [
          "Order ID is empty",
          "Order ID is too long (over 100 characters)",
          "Order ID contains invalid characters"
        ],
        resolution_steps: [
          "Use valid order ID from previous API responses",
          "Ensure order ID is not empty",
          "Check order ID format and length"
        ],
        examples: %{
          invalid: ["", nil, String.duplicate("a", 200)],
          valid: ["12345678", "my_order_001", "client_order_abc123"]
        }
      },
      %{
        reason: :invalid_options,
        category: "Validation",
        description: "Query options format or types are invalid",
        common_causes: [
          "Options is not a map",
          "Option values have wrong types",
          "Invalid option keys",
          "Out of range option values"
        ],
        resolution_steps: [
          "Use a map for options parameter",
          "Check option value types (boolean, integer, string)",
          "Use only supported option keys",
          "Ensure values are within valid ranges"
        ],
        examples: %{
          invalid: ["options", %{"limit" => "invalid"}, %{"unknown_key" => true}],
          valid: [%{}, %{"limit" => 100}, %{"force_refresh" => true, "include_zero" => false}]
        }
      }
    ]
  end

  # Authentication Errors Documentation
  defp authentication_errors do
    [
      %{
        reason: :authentication_failed,
        category: "Authentication",
        description: "API credentials were rejected by the exchange",
        common_causes: [
          "Invalid API key or secret",
          "API key permissions insufficient",
          "API key restrictions (IP whitelist)",
          "Expired or revoked credentials"
        ],
        resolution_steps: [
          "Verify API key and secret from Binance account",
          "Check API key permissions include required access",
          "Verify IP address is whitelisted (if enabled)",
          "Generate new API credentials if expired"
        ],
        examples: %{
          scenarios: [
            "First-time connection with wrong credentials",
            "API key permissions changed after connection",
            "IP whitelist updated excluding current IP"
          ]
        }
      }
    ]
  end

  # Business Logic Errors Documentation
  defp business_logic_errors do
    [
      %{
        reason: :user_not_connected,
        category: "Business Logic",
        description: "User session is not active",
        common_causes: [
          "User was never connected",
          "User was disconnected due to inactivity",
          "User session terminated due to error",
          "Different user ID used"
        ],
        resolution_steps: [
          "Connect user first using connect_user/3",
          "Check user ID spelling and format",
          "Verify user hasn't been disconnected",
          "Check session status before operations"
        ],
        examples: %{
          fix: "CryptoExchange.API.connect_user(\"user123\", api_key, secret_key)"
        }
      },
      %{
        reason: :user_already_connected,
        category: "Business Logic",
        description: "User session already exists",
        common_causes: [
          "Multiple connection attempts with same user ID",
          "Previous session not properly cleaned up",
          "Concurrent connection attempts"
        ],
        resolution_steps: [
          "Use a different user ID",
          "Disconnect existing session first",
          "Check if another process is using this user ID",
          "Wait and retry if concurrent access"
        ],
        examples: %{
          fix: "CryptoExchange.API.disconnect_user(\"user123\") before reconnecting"
        }
      },
      %{
        reason: :insufficient_funds,
        category: "Business Logic",
        description: "Account balance insufficient for the operation",
        common_causes: [
          "Account balance too low for order value",
          "Insufficient balance for trading fees",
          "Orders already consuming available balance",
          "Wrong base/quote asset calculation"
        ],
        resolution_steps: [
          "Check account balance before placing orders",
          "Reduce order quantity or price",
          "Account for trading fees in calculations",
          "Cancel other orders to free up balance"
        ],
        examples: %{
          check: "CryptoExchange.API.get_balance(user_id) to verify available funds"
        }
      },
      %{
        reason: :minimum_notional_not_met,
        category: "Business Logic",
        description: "Order value is below the minimum required amount",
        common_causes: [
          "Order quantity too small",
          "Order price too low",
          "Combined order value below minimum",
          "Symbol-specific minimum requirements"
        ],
        resolution_steps: [
          "Increase order quantity",
          "Use higher price for LIMIT orders",
          "Check symbol's minimum notional requirements",
          "Use market price for better value calculation"
        ],
        examples: %{
          typical_minimums: "BTCUSDT: $10, ETHUSDT: $10, Most symbols: $10-20"
        }
      },
      %{
        reason: :order_not_found,
        category: "Business Logic",
        description: "Specified order does not exist",
        common_causes: [
          "Order ID is incorrect",
          "Order was already filled or cancelled",
          "Order belongs to different user",
          "Order has expired"
        ],
        resolution_steps: [
          "Verify order ID is correct",
          "Check order status before cancellation",
          "Ensure order belongs to the correct user",
          "Get recent orders to find valid order IDs"
        ],
        examples: %{
          check: "CryptoExchange.API.get_orders(user_id) to see current orders"
        }
      },
      %{
        reason: :order_not_cancellable,
        category: "Business Logic",
        description: "Order cannot be cancelled in its current state",
        common_causes: [
          "Order is already filled",
          "Order has expired",
          "Order is being processed",
          "Order is already cancelled"
        ],
        resolution_steps: [
          "Check order status before cancellation",
          "Allow time for order processing to complete",
          "Use get_orders to see current order state",
          "Accept that filled orders cannot be cancelled"
        ],
        examples: %{
          statuses: "NEW: cancellable, FILLED: not cancellable, EXPIRED: not cancellable"
        }
      },
      %{
        reason: :price_filter_violation,
        category: "Business Logic",
        description: "Order price violates exchange price filters",
        common_causes: [
          "Price doesn't match tick size",
          "Price outside min/max bounds",
          "Price precision too high",
          "Price increment incorrect"
        ],
        resolution_steps: [
          "Round price to valid tick size",
          "Check symbol's price filters",
          "Use exchange info API for filter details",
          "Adjust price to meet requirements"
        ],
        examples: %{
          typical_tick_sizes: "BTCUSDT: 0.01, ETHUSDT: 0.01, small coins: 0.0001"
        }
      },
      %{
        reason: :quantity_filter_violation,
        category: "Business Logic",
        description: "Order quantity violates exchange quantity filters",
        common_causes: [
          "Quantity below minimum",
          "Quantity above maximum", 
          "Quantity doesn't match step size",
          "Quantity precision too high"
        ],
        resolution_steps: [
          "Use minimum quantity or higher",
          "Round quantity to valid step size",
          "Check symbol's lot size filters",
          "Adjust quantity precision"
        ],
        examples: %{
          typical_step_sizes: "BTCUSDT: 0.00001, ETHUSDT: 0.0001, varies by symbol"
        }
      },
      %{
        reason: :market_closed,
        category: "Business Logic",
        description: "Trading is disabled for the symbol",
        common_causes: [
          "Symbol is temporarily disabled",
          "Maintenance period active",
          "Symbol is delisted",
          "Trading halt due to volatility"
        ],
        resolution_steps: [
          "Check symbol trading status",
          "Wait for trading to resume",
          "Use alternative trading pairs",
          "Check exchange announcements"
        ],
        examples: %{
          check: "Symbol status in exchange info or announcements"
        }
      }
    ]
  end

  # Service Errors Documentation
  defp service_errors do
    [
      %{
        reason: :service_unavailable,
        category: "Service",
        description: "External service or system component is unavailable",
        common_causes: [
          "Exchange API downtime",
          "Network connectivity issues",
          "Internal service restart",
          "High system load"
        ],
        resolution_steps: [
          "Wait and retry the operation",
          "Check system status page",
          "Verify network connectivity",
          "Contact support if persistent"
        ],
        examples: %{
          retry_strategy: "Exponential backoff: 1s, 2s, 4s, 8s delays"
        }
      },
      %{
        reason: :connection_failed,
        category: "Service",
        description: "Failed to establish connection to external service",
        common_causes: [
          "Network connectivity problems",
          "Firewall blocking connections",
          "DNS resolution issues",
          "Exchange endpoint changes"
        ],
        resolution_steps: [
          "Check internet connection",
          "Verify firewall settings",
          "Test DNS resolution",
          "Check for service announcements"
        ],
        examples: %{
          network_test: "ping api.binance.com to test connectivity"
        }
      },
      %{
        reason: :connection_timeout,
        category: "Service",
        description: "Connection attempt timed out",
        common_causes: [
          "Slow network connection",
          "High server load",
          "Intermediate proxy delays",
          "Geographic distance"
        ],
        resolution_steps: [
          "Retry with longer timeout",
          "Check network speed",
          "Use closer geographic endpoints",
          "Reduce concurrent connections"
        ],
        examples: %{
          timeout_adjustment: "Increase timeout from 5s to 10s or 15s"
        }
      }
    ]
  end

  # System Errors Documentation
  defp system_errors do
    [
      %{
        reason: :user_limit_exceeded,
        category: "System",
        description: "Maximum number of concurrent users reached",
        common_causes: [
          "Too many active user sessions",
          "Resource consumption limits",
          "System capacity constraints",
          "Memory or connection limits"
        ],
        resolution_steps: [
          "Disconnect unused user sessions",
          "Wait for other users to disconnect",
          "Contact support for limit increases",
          "Optimize session usage patterns"
        ],
        examples: %{
          cleanup: "CryptoExchange.API.list_connected_users() to see active sessions"
        }
      },
      %{
        reason: :disconnect_timeout,
        category: "System",
        description: "User disconnection process timed out",
        common_causes: [
          "Pending operations during disconnect",
          "System resource cleanup delays",
          "Network issues during cleanup",
          "Unresponsive user session"
        ],
        resolution_steps: [
          "Wait for automatic cleanup completion",
          "Retry disconnection after delay",
          "Use different user ID temporarily",
          "Contact support if persistent"
        ],
        examples: %{
          wait_time: "Allow 30-60 seconds for cleanup completion"
        }
      }
    ]
  end

  # Rate Limiting Errors Documentation
  defp rate_limiting_errors do
    [
      %{
        reason: :rate_limit_exceeded,
        category: "Rate Limiting",
        description: "API rate limits have been exceeded",
        common_causes: [
          "Too many API calls in short time",
          "Burst request patterns",
          "Multiple concurrent operations",
          "Inefficient polling patterns"
        ],
        resolution_steps: [
          "Reduce API call frequency",
          "Implement exponential backoff",
          "Use WebSocket streams for real-time data",
          "Cache responses to reduce calls"
        ],
        examples: %{
          limits: "Order endpoints: 10/second, Account info: 5/second, varies by endpoint",
          best_practice: "Use WebSocket for market data instead of REST polling"
        }
      }
    ]
  end

  # Quick Fixes for Common Issues
  defp quick_fixes do
    %{
      "Symbol format errors" => [
        "Use uppercase: 'BTCUSDT' not 'btcusdt'",
        "No special characters: 'BTCUSDT' not 'BTC-USDT'",
        "Check spelling: 'BTCUSDT' not 'BTCUSD'"
      ],
      "Connection issues" => [
        "Check internet connectivity",
        "Verify API credentials are correct",
        "Ensure IP whitelist includes your IP (if enabled)"
      ],
      "Order placement failures" => [
        "Include all required fields: symbol, side, type, quantity",
        "Add price for LIMIT orders",
        "Check account balance is sufficient"
      ],
      "User session problems" => [
        "Connect user before trading operations",
        "Use unique user IDs for different sessions",
        "Disconnect properly when done"
      ]
    }
  end

  # Common Scenarios and Solutions
  defp common_scenarios do
    %{
      "First time setup" => %{
        problem: "Getting authentication errors on first connection",
        solution: [
          "Generate new API key/secret from Binance",
          "Enable required permissions (spot trading, reading)",
          "Test with simple balance query first",
          "Check IP whitelist if enabled"
        ],
        example: """
        # Test basic connection
        {:ok, _pid} = CryptoExchange.API.connect_user("test_user", api_key, secret_key)
        {:ok, balance} = CryptoExchange.API.get_balance("test_user")
        """
      },
      "Order placement issues" => %{
        problem: "Orders failing with various validation errors",
        solution: [
          "Check symbol is valid and tradable",
          "Verify account has sufficient balance",
          "Use correct price/quantity formats",
          "Check exchange trading rules for symbol"
        ],
        example: """
        # Proper order format
        order_params = %{
          "symbol" => "BTCUSDT",
          "side" => "BUY",
          "type" => "LIMIT",
          "quantity" => "0.001",
          "price" => "50000",
          "timeInForce" => "GTC"
        }
        {:ok, order} = CryptoExchange.API.place_order("user123", order_params)
        """
      },
      "Rate limiting" => %{
        problem: "Getting rate limit exceeded errors",
        solution: [
          "Reduce API call frequency",
          "Use WebSocket streams for market data",
          "Implement proper retry logic with backoff",
          "Cache responses when possible"
        ],
        example: """
        # Use WebSocket instead of polling
        {:ok, topic} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")
        Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
        """
      }
    }
  end

  # Debugging Steps
  defp debugging_steps do
    [
      "Enable detailed error messages for development",
      "Check API credentials are correctly configured",
      "Verify network connectivity to exchange endpoints",
      "Test with simple operations before complex ones",
      "Check system logs for additional error context",
      "Use get_session_info/1 to check user session state",
      "Verify input parameters match expected formats",
      "Check exchange announcements for service issues"
    ]
  end

  # Best Practices
  defp best_practices do
    %{
      input_validation: [
        "Always validate inputs before API calls",
        "Use type checking and format validation",
        "Sanitize user-provided data",
        "Handle edge cases (null, empty, malformed)"
      ],
      error_handling: [
        "Implement proper retry logic with exponential backoff",
        "Handle specific error cases differently",
        "Log errors for debugging and monitoring",
        "Provide user-friendly error messages"
      ],
      performance: [
        "Use WebSocket streams for real-time data",
        "Cache frequently accessed data",
        "Batch operations when possible",
        "Monitor and respect rate limits"
      ],
      security: [
        "Secure API credential storage",
        "Use IP whitelisting when possible",
        "Implement proper session management",
        "Log security-relevant events"
      ],
      reliability: [
        "Implement health checks for user sessions",
        "Handle network failures gracefully",
        "Use circuit breaker patterns for external calls",
        "Monitor system resources and limits"
      ]
    }
  end
end