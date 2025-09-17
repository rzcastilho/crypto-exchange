defmodule CryptoExchange.Binance.Errors do
  @moduledoc """
  Comprehensive error handling and classification for Binance API responses.

  This module provides structured error mapping, classification, and handling
  for all possible error conditions that can occur when interacting with
  Binance APIs. It categorizes errors by type and severity to enable
  appropriate retry strategies and user-friendly error messages.

  ## Error Categories

  - **Authentication Errors**: Invalid API keys, signature errors, IP restrictions
  - **Rate Limiting**: Request frequency violations, order rate limits
  - **Trading Errors**: Insufficient balance, invalid symbols, market restrictions
  - **Network Errors**: Connection timeouts, service unavailable
  - **Validation Errors**: Invalid parameters, missing required fields
  - **System Errors**: Exchange maintenance, internal server errors

  ## Retry Strategies

  Different error types support different retry strategies:
  - **Retryable**: Temporary network issues, rate limits (with backoff)
  - **Non-Retryable**: Authentication failures, insufficient funds
  - **Backoff Required**: Rate limiting errors require exponential backoff

  ## Usage Examples

  ```elixir
  # Parse error from API response
  error_response = %{
    "code" => -1021,
    "msg" => "Timestamp for this request is outside the recvWindow."
  }

  {:error, parsed_error} = Errors.parse_api_error(error_response)
  # %ErrorInfo{
  #   code: -1021,
  #   message: "Timestamp for this request is outside the recvWindow.",
  #   category: :authentication,
  #   severity: :error,
  #   retryable: false,
  #   user_message: "Request timestamp is invalid. Please sync your system clock."
  # }

  # Check if error should be retried
  if Errors.retryable?(parsed_error) do
    # Implement retry logic
    backoff_ms = Errors.calculate_backoff(attempt_count, parsed_error)
    Process.sleep(backoff_ms)
  end
  ```
  """

  defstruct [
    :code,
    :message,
    :category,
    :severity,
    :retryable,
    :user_message,
    :retry_after,
    :context
  ]

  @type t :: %__MODULE__{
          code: integer() | atom(),
          message: String.t(),
          category: error_category(),
          severity: error_severity(),
          retryable: boolean(),
          user_message: String.t(),
          retry_after: integer() | nil,
          context: map() | nil
        }

  @type error_category ::
          :authentication
          | :rate_limiting
          | :trading
          | :validation
          | :network
          | :system
          | :unknown

  @type error_severity ::
          :info
          | :warning
          | :error
          | :critical

  @type api_response :: map()
  @type http_status :: integer()

  # Binance API Error Codes Mapping
  # Reference: https://binance-docs.github.io/apidocs/spot/en/#error-codes
  @error_mappings %{
    # Authentication Errors (-1000 to -1099)
    -1000 => %{
      category: :system,
      severity: :error,
      retryable: false,
      user_message: "An unknown error occurred while processing the request."
    },
    -1001 => %{
      category: :system,
      severity: :error,
      retryable: false,
      user_message: "Internal server error occurred. Please try again later."
    },
    -1002 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "You are not authorized to execute this request."
    },
    -1003 => %{
      category: :rate_limiting,
      severity: :warning,
      retryable: true,
      user_message: "Too many requests sent. Please slow down and try again."
    },
    -1006 => %{
      category: :system,
      severity: :warning,
      retryable: true,
      user_message: "An unexpected response was received. Please try again."
    },
    -1007 => %{
      category: :network,
      severity: :warning,
      retryable: true,
      user_message: "Request timeout. Please check your connection and try again."
    },
    -1014 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Unsupported order combination."
    },
    -1015 => %{
      category: :rate_limiting,
      severity: :warning,
      retryable: true,
      user_message: "Too many new orders. Please wait and try again."
    },
    -1016 => %{
      category: :system,
      severity: :error,
      retryable: false,
      user_message: "This service is no longer available."
    },
    -1020 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "This operation is not supported."
    },
    -1021 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "Request timestamp is invalid. Please sync your system clock."
    },
    -1022 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "Invalid signature. Please check your API credentials."
    },
    -1100 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Invalid parameters provided."
    },
    -1101 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Too many parameters provided."
    },
    -1102 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Required parameter is missing."
    },
    -1103 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Unknown parameter provided."
    },
    -1104 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Not all required parameters were sent."
    },
    -1105 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Parameter value is empty or invalid."
    },
    -1106 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Parameter sent when not required."
    },
    -1111 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Precision value is over the maximum defined for this asset."
    },
    -1112 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "No orders on book for symbol."
    },
    -1114 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "TimeInForce parameter sent when not required."
    },
    -1115 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Invalid timeInForce value."
    },
    -1116 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Invalid orderType."
    },
    -1117 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Invalid side."
    },
    -1118 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "New client order ID is empty."
    },
    -1119 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Original client order ID is empty."
    },
    -1120 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Invalid interval."
    },
    -1121 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Invalid symbol."
    },
    -1125 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "This listenKey does not exist."
    },
    -1127 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Lookup interval is too big."
    },
    -1128 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Optional parameters are combined incorrectly."
    },
    -1130 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Invalid data sent for parameter."
    },
    # Trading Errors (-2000 to -2099)
    -2010 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Order would immediately match and take."
    },
    -2011 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Order cancel was rejected."
    },
    -2013 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Order does not exist."
    },
    -2014 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "API key format invalid."
    },
    -2015 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "Invalid API key, IP, or permissions for action."
    },
    -2016 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "No trading window could be found for the symbol."
    },
    -2018 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Balance is insufficient."
    },
    -2019 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Margin is insufficient."
    },
    -2020 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Unable to fill."
    },
    -2021 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Order would immediately trigger."
    },
    -2022 => %{
      category: :rate_limiting,
      severity: :warning,
      retryable: true,
      user_message: "Order cancel/replace is partially successful."
    },
    -2025 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Order canceled but new order was not placed."
    },
    -2026 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Order was not canceled."
    },
    -2027 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Order cancel is being processed."
    },
    -2028 => %{
      category: :trading,
      severity: :error,
      retryable: false,
      user_message: "Order cancel request is not supported."
    }
  }

  # HTTP Status Code Mappings
  @http_error_mappings %{
    400 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "Bad request. Please check your parameters."
    },
    401 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "Authentication failed. Please check your API credentials."
    },
    403 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "Access forbidden. Please check your API permissions."
    },
    404 => %{
      category: :validation,
      severity: :error,
      retryable: false,
      user_message: "The requested resource was not found."
    },
    418 => %{
      category: :authentication,
      severity: :error,
      retryable: false,
      user_message: "IP has been auto-banned for continuing to send requests after receiving 429 codes."
    },
    429 => %{
      category: :rate_limiting,
      severity: :warning,
      retryable: true,
      user_message: "Too many requests. Please wait before trying again."
    },
    500 => %{
      category: :system,
      severity: :error,
      retryable: true,
      user_message: "Internal server error. Please try again later."
    },
    502 => %{
      category: :system,
      severity: :error,
      retryable: true,
      user_message: "Bad gateway. Please try again later."
    },
    503 => %{
      category: :system,
      severity: :error,
      retryable: true,
      user_message: "Service temporarily unavailable. Please try again later."
    },
    504 => %{
      category: :network,
      severity: :warning,
      retryable: true,
      user_message: "Gateway timeout. Please try again."
    }
  }

  @doc """
  Parses an error from Binance API response.

  ## Parameters
  - `response`: Map containing error response from API

  ## Returns
  - `{:ok, error_info}` on successful parsing
  - `{:error, reason}` if parsing fails

  ## Example
  ```elixir
  response = %{"code" => -1021, "msg" => "Timestamp outside recvWindow"}
  {:ok, error} = Errors.parse_api_error(response)
  ```
  """
  @spec parse_api_error(api_response()) :: {:ok, t()} | {:error, term()}
  def parse_api_error(%{"code" => code, "msg" => message} = response) when is_integer(code) do
    error_info = build_error_info(code, message, response)
    {:ok, error_info}
  end

  def parse_api_error(%{"code" => code} = response) when is_integer(code) do
    message = Map.get(response, "message", "Unknown error")
    error_info = build_error_info(code, message, response)
    {:ok, error_info}
  end

  def parse_api_error(response) when is_map(response) do
    message = Map.get(response, "msg") || Map.get(response, "message") || "Unknown error"
    error_info = build_error_info(:unknown, message, response)
    {:ok, error_info}
  end

  def parse_api_error(_), do: {:error, :invalid_error_format}

  @doc """
  Parses HTTP status code errors.

  ## Parameters
  - `status_code`: HTTP status code
  - `response_body`: Optional response body for additional context

  ## Returns
  - `{:ok, error_info}` on successful parsing
  - `{:error, reason}` if parsing fails
  """
  @spec parse_http_error(http_status(), binary() | nil) :: {:ok, t()} | {:error, term()}
  def parse_http_error(status_code, response_body \\ nil) when is_integer(status_code) do
    case Map.get(@http_error_mappings, status_code) do
      %{} = error_config ->
        error_info = %__MODULE__{
          code: status_code,
          message: "HTTP #{status_code}",
          category: error_config.category,
          severity: error_config.severity,
          retryable: error_config.retryable,
          user_message: error_config.user_message,
          context: %{response_body: response_body}
        }

        {:ok, error_info}

      nil ->
        error_info = %__MODULE__{
          code: status_code,
          message: "HTTP #{status_code}",
          category: if(status_code >= 500, do: :system, else: :unknown),
          severity: :error,
          retryable: status_code >= 500,
          user_message: "An error occurred while processing your request.",
          context: %{response_body: response_body}
        }

        {:ok, error_info}
    end
  end

  @doc """
  Checks if an error is retryable.

  ## Parameters
  - `error`: ErrorInfo struct

  ## Returns
  Boolean indicating if the error should be retried.
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{retryable: retryable}), do: retryable

  @doc """
  Calculates backoff delay for retryable errors.

  ## Parameters
  - `attempt`: Current attempt number (1-based)
  - `error`: ErrorInfo struct
  - `opts`: Optional configuration

  ## Options
  - `:base_delay`: Base delay in milliseconds (default: 1000)
  - `:max_delay`: Maximum delay in milliseconds (default: 32000)
  - `:jitter`: Add random jitter (default: true)

  ## Returns
  Backoff delay in milliseconds.
  """
  @spec calculate_backoff(pos_integer(), t(), keyword()) :: pos_integer()
  def calculate_backoff(attempt, error, opts \\ [])

  def calculate_backoff(_attempt, %__MODULE__{category: :rate_limiting, retry_after: retry_after}, opts)
      when is_integer(retry_after) do
    base_delay = Keyword.get(opts, :base_delay, 1000)
    max_delay = Keyword.get(opts, :max_delay, 32000)
    jitter = Keyword.get(opts, :jitter, true)

    # Use retry_after from headers if available, otherwise exponential backoff
    delay = max(retry_after * 1000, base_delay)
    delay = min(delay, max_delay)

    if jitter do
      add_jitter(delay)
    else
      delay
    end
  end

  def calculate_backoff(attempt, %__MODULE__{category: :rate_limiting}, opts) do
    # Rate limiting requires aggressive backoff
    base_delay = Keyword.get(opts, :base_delay, 2000)
    max_delay = Keyword.get(opts, :max_delay, 64000)
    jitter = Keyword.get(opts, :jitter, true)

    delay = base_delay * :math.pow(2, attempt - 1)
    delay = min(trunc(delay), max_delay)

    if jitter do
      add_jitter(delay)
    else
      delay
    end
  end

  def calculate_backoff(attempt, %__MODULE__{category: category}, opts)
      when category in [:network, :system] do
    # Standard exponential backoff for network/system errors
    base_delay = Keyword.get(opts, :base_delay, 1000)
    max_delay = Keyword.get(opts, :max_delay, 16000)
    jitter = Keyword.get(opts, :jitter, true)

    delay = base_delay * :math.pow(2, attempt - 1)
    delay = min(trunc(delay), max_delay)

    if jitter do
      add_jitter(delay)
    else
      delay
    end
  end

  def calculate_backoff(_attempt, _error, opts) do
    # Default delay for other error types
    Keyword.get(opts, :base_delay, 1000)
  end

  @doc """
  Gets user-friendly error message.

  ## Parameters
  - `error`: ErrorInfo struct

  ## Returns
  User-friendly error message string.
  """
  @spec user_message(t()) :: String.t()
  def user_message(%__MODULE__{user_message: message}), do: message

  @doc """
  Gets error severity level.

  ## Parameters
  - `error`: ErrorInfo struct

  ## Returns
  Severity atom (`:info`, `:warning`, `:error`, `:critical`).
  """
  @spec severity(t()) :: error_severity()
  def severity(%__MODULE__{severity: severity}), do: severity

  @doc """
  Gets error category.

  ## Parameters
  - `error`: ErrorInfo struct

  ## Returns
  Category atom.
  """
  @spec category(t()) :: error_category()
  def category(%__MODULE__{category: category}), do: category

  @doc """
  Checks if error indicates authentication failure.

  ## Parameters
  - `error`: ErrorInfo struct

  ## Returns
  Boolean indicating authentication failure.
  """
  @spec authentication_error?(t()) :: boolean()
  def authentication_error?(%__MODULE__{category: :authentication}), do: true
  def authentication_error?(_), do: false

  @doc """
  Checks if error indicates rate limiting.

  ## Parameters
  - `error`: ErrorInfo struct

  ## Returns
  Boolean indicating rate limiting.
  """
  @spec rate_limit_error?(t()) :: boolean()
  def rate_limit_error?(%__MODULE__{category: :rate_limiting}), do: true
  def rate_limit_error?(_), do: false

  @doc """
  Checks if error indicates insufficient balance.

  ## Parameters
  - `error`: ErrorInfo struct

  ## Returns
  Boolean indicating insufficient balance.
  """
  @spec insufficient_balance?(t()) :: boolean()
  def insufficient_balance?(%__MODULE__{code: -2018}), do: true
  def insufficient_balance?(%__MODULE__{code: -2019}), do: true
  def insufficient_balance?(_), do: false

  # Private Functions

  defp build_error_info(code, message, context) do
    error_config = Map.get(@error_mappings, code, default_error_config())

    %__MODULE__{
      code: code,
      message: message,
      category: error_config.category,
      severity: error_config.severity,
      retryable: error_config.retryable,
      user_message: error_config.user_message,
      context: context
    }
  end

  defp default_error_config do
    %{
      category: :unknown,
      severity: :error,
      retryable: false,
      user_message: "An unexpected error occurred. Please try again later."
    }
  end

  defp add_jitter(delay) do
    jitter_amount = trunc(delay * 0.1)
    delay + :rand.uniform(jitter_amount)
  end
end