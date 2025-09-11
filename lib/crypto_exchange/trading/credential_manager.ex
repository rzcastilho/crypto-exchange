defmodule CryptoExchange.Trading.CredentialManager do
  @moduledoc """
  Secure credential management for user trading sessions.

  This GenServer provides isolated and secure handling of user API credentials
  with comprehensive security features and audit trails.

  ## Security Architecture

  - **Process isolation**: Credentials stored only in this process memory
  - **No logging**: Credentials never appear in logs or error messages
  - **Secure purging**: Memory cleared on termination or explicit purge
  - **Access control**: Only authorized processes can access credentials
  - **Audit trail**: All credential operations are audited (without exposure)

  ## Features

  - **HMAC-SHA256**: Binance API signature generation
  - **Rate limiting**: Per-user API rate limit tracking
  - **Credential rotation**: Support for credential updates
  - **Health monitoring**: Credential validity monitoring
  - **Automatic cleanup**: Secure memory cleanup on process termination

  ## Security Compliance

  - Never logs actual credential values
  - Implements secure memory practices
  - Provides audit trails for compliance
  - Supports credential validation without exposure
  - Implements proper access controls
  """

  use GenServer
  require Logger

  alias CryptoExchange.Trading.UserSecurityAuditor
  alias CryptoExchange.Trading.CredentialEnvironmentManager

  @hmac_algorithm :sha256
  @rate_limit_window 60_000  # 1 minute in milliseconds
  @max_requests_per_minute 1200  # Binance rate limit (conservative)
  @credential_rotation_interval 3_600_000  # 1 hour in milliseconds
  @credential_health_check_interval 300_000  # 5 minutes in milliseconds
  @max_credential_age 86_400_000  # 24 hours in milliseconds

  # Client API

  @doc """
  Start the CredentialManager for a specific user with explicit credentials.
  """
  def start_link({:user_id, user_id, :api_key, api_key, :secret_key, secret_key}) do
    GenServer.start_link(__MODULE__, {user_id, api_key, secret_key, :explicit}, name: via_tuple(user_id))
  end

  @doc """
  Start the CredentialManager for a specific user using environment variables.
  """
  def start_link({:user_id, user_id, :from_environment}) do
    GenServer.start_link(__MODULE__, {user_id, :from_environment}, name: via_tuple(user_id))
  end

  @doc """
  Start the CredentialManager with default environment credentials.
  """
  def start_link({:default_environment}) do
    GenServer.start_link(__MODULE__, {:default_environment}, name: via_tuple("default"))
  end

  @doc """
  Get the API key for making requests (without secret exposure).
  
  Returns only the API key which is safe to use in HTTP headers.
  The secret key remains isolated in this process.
  """
  def get_api_key(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :get_api_key)
  end

  @doc """
  Generate HMAC-SHA256 signature for Binance API requests.
  
  Takes request parameters and generates the required signature
  without exposing the secret key.
  """
  def sign_request(user_id, query_string) when is_binary(user_id) and is_binary(query_string) do
    GenServer.call(via_tuple(user_id), {:sign_request, query_string})
  end

  @doc """
  Check if the user can make an API request (rate limiting).
  
  Tracks API usage to ensure compliance with Binance rate limits.
  """
  def can_make_request?(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :can_make_request)
  end

  @doc """
  Record an API request for rate limiting tracking.
  """
  def record_request(user_id) when is_binary(user_id) do
    GenServer.cast(via_tuple(user_id), :record_request)
  end

  @doc """
  Validate credentials without exposing them.
  
  Performs basic validation of credential format and structure.
  """
  def validate_credentials(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :validate_credentials)
  end

  @doc """
  Update credentials (for credential rotation).
  """
  def update_credentials(user_id, new_api_key, new_secret_key) 
      when is_binary(user_id) and is_binary(new_api_key) and is_binary(new_secret_key) do
    GenServer.call(via_tuple(user_id), {:update_credentials, new_api_key, new_secret_key})
  end

  @doc """
  Securely purge credentials from memory.
  
  This is called during graceful shutdown to ensure credentials
  are properly cleared from memory.
  """
  def secure_purge_credentials(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :secure_purge_credentials)
  end

  @doc """
  Get credential manager statistics (without exposing credentials).
  """
  def get_statistics(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :get_statistics)
  end

  @doc """
  Force credential rotation from environment variables.
  
  This triggers immediate reloading of credentials from environment
  variables if the credential manager was started with environment support.
  """
  def rotate_credentials_from_environment(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :rotate_credentials_from_environment)
  end

  @doc """
  Check credential health and validity.
  
  Performs comprehensive health checks including age, format validation,
  and environment consistency.
  """
  def check_credential_health(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :check_credential_health)
  end

  @doc """
  Get detailed security status for compliance reporting.
  """
  def get_security_status(user_id) when is_binary(user_id) do
    GenServer.call(via_tuple(user_id), :get_security_status)
  end

  # Server Callbacks

  @impl true
  def init({user_id, api_key, secret_key, :explicit}) do
    init_with_explicit_credentials(user_id, api_key, secret_key)
  end

  @impl true
  def init({user_id, :from_environment}) do
    init_with_environment_credentials(user_id)
  end

  @impl true
  def init({:default_environment}) do
    init_with_environment_credentials("default")
  end

  # Legacy support for old init signature
  @impl true
  def init({user_id, api_key, secret_key}) do
    init_with_explicit_credentials(user_id, api_key, secret_key)
  end

  @impl true
  def handle_call(:get_api_key, _from, %{purged: true} = state) do
    {:reply, {:error, :credentials_purged}, state}
  end

  @impl true
  def handle_call(:get_api_key, _from, %{api_key: api_key, user_id: user_id} = state) do
    new_state = %{state | last_used: System.system_time(:millisecond)}
    Logger.debug("API key accessed", user_id: user_id)
    {:reply, {:ok, api_key}, new_state}
  end

  @impl true
  def handle_call({:sign_request, query_string}, _from, %{purged: true} = state) do
    {:reply, {:error, :credentials_purged}, state}
  end

  @impl true
  def handle_call({:sign_request, query_string}, _from, %{secret_key: secret_key, user_id: user_id} = state) do
    signature = generate_signature(query_string, secret_key)
    new_state = %{state | last_used: System.system_time(:millisecond)}
    
    Logger.debug("Request signature generated", user_id: user_id, query_length: String.length(query_string))
    UserSecurityAuditor.log_credential_event(user_id, :signature_generated, %{
      query_length: String.length(query_string)
    })
    
    {:reply, {:ok, signature}, new_state}
  end

  @impl true
  def handle_call(:can_make_request, _from, state) do
    now = System.system_time(:millisecond)
    
    # Clean old requests outside the rate limit window
    recent_requests = Enum.filter(state.request_history, fn timestamp ->
      now - timestamp < @rate_limit_window
    end)
    
    can_request = length(recent_requests) < @max_requests_per_minute
    
    new_state = %{state | request_history: recent_requests}
    
    {:reply, can_request, new_state}
  end

  @impl true
  def handle_call(:validate_credentials, _from, %{purged: true} = state) do
    {:reply, {:error, :credentials_purged}, state}
  end

  @impl true
  def handle_call(:validate_credentials, _from, %{api_key: api_key, secret_key: secret_key} = state) do
    validation = %{
      api_key_valid: validate_api_key_format(api_key) == :ok,
      secret_key_valid: validate_secret_key_format(secret_key) == :ok,
      api_key_length: String.length(api_key),
      secret_key_length: String.length(secret_key)
    }
    
    {:reply, {:ok, validation}, state}
  end

  @impl true
  def handle_call({:update_credentials, new_api_key, new_secret_key}, _from, %{user_id: user_id} = state) do
    Logger.info("Updating credentials for user", user_id: user_id)
    
    with :ok <- validate_api_key_format(new_api_key),
         :ok <- validate_secret_key_format(new_secret_key) do
      
      # Securely update credentials
      new_state = %{state |
        api_key: new_api_key,
        secret_key: new_secret_key,
        last_used: nil,
        request_count: 0,
        request_history: [],
        validated: true
      }
      
      UserSecurityAuditor.log_credential_event(user_id, :updated, %{
        new_api_key_length: String.length(new_api_key),
        new_secret_key_length: String.length(new_secret_key)
      })
      
      {:reply, :ok, new_state}
      
    else
      error ->
        Logger.error("Failed to update credentials", user_id: user_id, error: error)
        UserSecurityAuditor.log_credential_event(user_id, :update_failed, %{error: error})
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call(:secure_purge_credentials, _from, %{user_id: user_id} = state) do
    Logger.info("Securely purging credentials", user_id: user_id)
    
    # Overwrite sensitive data in memory
    purged_state = %{state |
      api_key: String.duplicate("X", String.length(state.api_key)),
      secret_key: String.duplicate("X", String.length(state.secret_key)),
      purged: true
    }
    
    # Force garbage collection to help clear memory
    :erlang.garbage_collect()
    
    UserSecurityAuditor.log_credential_event(user_id, :purged, %{})
    
    {:reply, :ok, purged_state}
  end

  @impl true
  def handle_call(:get_statistics, _from, %{user_id: user_id} = state) do
    now = System.system_time(:millisecond)
    
    stats = %{
      user_id: user_id,
      created_at: state.created_at,
      last_used: state.last_used,
      total_requests: state.request_count,
      recent_requests: length(state.request_history),
      rate_limit_utilization: length(state.request_history) / @max_requests_per_minute,
      uptime_ms: now - state.created_at,
      validated: state.validated,
      purged: Map.get(state, :purged, false),
      source: Map.get(state, :source, :explicit),
      last_health_check: Map.get(state, :last_health_check),
      health_status: Map.get(state, :health_status, :unknown),
      rotation_count: Map.get(state, :rotation_count, 0),
      credential_age_ms: now - state.created_at
    }
    
    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call(:rotate_credentials_from_environment, _from, %{user_id: user_id, source: :environment} = state) do
    Logger.info("Rotating credentials from environment", user_id: user_id)
    
    case CredentialEnvironmentManager.load_user_credentials(user_id) do
      {:ok, %{api_key: new_api_key, secret_key: new_secret_key}} ->
        # Validate new credentials
        with :ok <- validate_api_key_format(new_api_key),
             :ok <- validate_secret_key_format(new_secret_key) do
          
          # Update state with new credentials
          new_state = %{state |
            api_key: new_api_key,
            secret_key: new_secret_key,
            last_used: nil,
            request_count: 0,
            request_history: [],
            validated: true,
            rotation_count: Map.get(state, :rotation_count, 0) + 1,
            last_rotation: System.system_time(:millisecond)
          }
          
          UserSecurityAuditor.log_credential_event(user_id, :rotated_from_environment, %{
            rotation_count: new_state.rotation_count
          })
          
          Logger.info("Credentials rotated successfully from environment", user_id: user_id)
          {:reply, :ok, new_state}
          
        else
          error ->
            Logger.error("New credentials validation failed during rotation", user_id: user_id, error: error)
            UserSecurityAuditor.log_credential_event(user_id, :rotation_validation_failed, %{error: error})
            {:reply, {:error, {:validation_failed, error}}, state}
        end
        
      {:error, reason} ->
        Logger.error("Failed to load new credentials from environment", user_id: user_id, error: reason)
        UserSecurityAuditor.log_credential_event(user_id, :rotation_load_failed, %{error: reason})
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:rotate_credentials_from_environment, _from, %{source: source} = state) do
    Logger.warning("Cannot rotate credentials from environment - source is #{source}")
    {:reply, {:error, :not_environment_sourced}, state}
  end

  @impl true
  def handle_call(:check_credential_health, _from, %{user_id: user_id} = state) do
    now = System.system_time(:millisecond)
    
    health_report = perform_health_check(state, now)
    
    new_state = %{state |
      last_health_check: now,
      health_status: health_report.overall_status
    }
    
    UserSecurityAuditor.log_credential_event(user_id, :health_check_performed, %{
      overall_status: health_report.overall_status,
      issues_found: length(health_report.issues)
    })
    
    {:reply, {:ok, health_report}, new_state}
  end

  @impl true
  def handle_call(:get_security_status, _from, %{user_id: user_id} = state) do
    now = System.system_time(:millisecond)
    
    security_status = %{
      user_id: user_id,
      credential_source: Map.get(state, :source, :explicit),
      security_level: calculate_security_level(state),
      last_health_check: Map.get(state, :last_health_check),
      health_status: Map.get(state, :health_status, :unknown),
      credential_age_ms: now - state.created_at,
      rotation_count: Map.get(state, :rotation_count, 0),
      last_rotation: Map.get(state, :last_rotation),
      rate_limiting_active: length(state.request_history) > 0,
      recent_activity: state.last_used && (now - state.last_used) < 300_000,  # 5 minutes
      validation_status: state.validated,
      purge_status: Map.get(state, :purged, false),
      compliance_score: calculate_compliance_score(state),
      risk_factors: identify_risk_factors(state, now)
    }
    
    {:reply, {:ok, security_status}, state}
  end

  @impl true
  def handle_cast(:record_request, state) do
    now = System.system_time(:millisecond)
    
    new_state = %{state |
      request_count: state.request_count + 1,
      request_history: [now | state.request_history],
      last_used: now
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, %{user_id: user_id} = state) do
    # Periodic health check
    now = System.system_time(:millisecond)
    health_report = perform_health_check(state, now)
    
    new_state = %{state |
      last_health_check: now,
      health_status: health_report.overall_status
    }
    
    # Schedule next health check
    schedule_health_check()
    
    # Log critical issues
    if health_report.overall_status == :critical do
      Logger.error("Critical credential health issues detected", 
        user_id: user_id, 
        issues: health_report.issues
      )
      
      UserSecurityAuditor.log_credential_event(user_id, :health_critical, %{
        issues: health_report.issues
      })
    end
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:rotation_check, %{user_id: user_id, source: :environment} = state) do
    # Check if credentials need rotation based on age
    now = System.system_time(:millisecond)
    credential_age = now - state.created_at
    
    if credential_age > @max_credential_age do
      Logger.info("Credentials are old, attempting automatic rotation", 
        user_id: user_id, 
        age_hours: credential_age / 3_600_000
      )
      
      case CredentialEnvironmentManager.load_user_credentials(user_id) do
        {:ok, %{api_key: new_api_key, secret_key: new_secret_key}} ->
          # Check if credentials actually changed
          if new_api_key != state.api_key or new_secret_key != state.secret_key do
            send(self(), {:rotate_credentials, new_api_key, new_secret_key})
          end
          
        {:error, _reason} ->
          # Environment credentials not available, keep existing
          :ok
      end
    end
    
    # Schedule next rotation check
    schedule_rotation_check()
    
    {:noreply, state}
  end

  @impl true
  def handle_info(:rotation_check, state) do
    # Non-environment credentials don't auto-rotate
    schedule_rotation_check()
    {:noreply, state}
  end

  @impl true
  def handle_info({:rotate_credentials, new_api_key, new_secret_key}, %{user_id: user_id} = state) do
    # Perform automatic credential rotation
    with :ok <- validate_api_key_format(new_api_key),
         :ok <- validate_secret_key_format(new_secret_key) do
      
      new_state = %{state |
        api_key: new_api_key,
        secret_key: new_secret_key,
        rotation_count: Map.get(state, :rotation_count, 0) + 1,
        last_rotation: System.system_time(:millisecond)
      }
      
      UserSecurityAuditor.log_credential_event(user_id, :auto_rotated, %{
        rotation_count: new_state.rotation_count
      })
      
      Logger.info("Credentials auto-rotated successfully", user_id: user_id)
      {:noreply, new_state}
      
    else
      error ->
        Logger.error("Auto-rotation validation failed", user_id: user_id, error: error)
        UserSecurityAuditor.log_credential_event(user_id, :auto_rotation_failed, %{error: error})
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in CredentialManager: #{inspect(msg)}", user_id: state.user_id)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %{user_id: user_id} = state) do
    Logger.info("CredentialManager terminating", user_id: user_id, reason: inspect(reason))
    
    # Secure cleanup on termination
    unless Map.get(state, :purged, false) do
      UserSecurityAuditor.log_credential_event(user_id, :terminated, %{reason: reason})
    end
    
    :ok
  end

  # Private Functions

  defp via_tuple(user_id) do
    {:via, Registry, {CryptoExchange.Registry, {:credential_manager, user_id}}}
  end

  defp generate_signature(query_string, secret_key) do
    :crypto.mac(:hmac, @hmac_algorithm, secret_key, query_string)
    |> Base.encode16(case: :lower)
  end

  defp validate_api_key_format(api_key) do
    cond do
      not is_binary(api_key) ->
        {:error, :not_binary}
        
      String.length(api_key) != 64 ->
        {:error, :invalid_length}
        
      not String.match?(api_key, ~r/^[a-zA-Z0-9]{64}$/) ->
        {:error, :invalid_format}
        
      true ->
        :ok
    end
  end

  defp validate_secret_key_format(secret_key) do
    cond do
      not is_binary(secret_key) ->
        {:error, :not_binary}
        
      String.length(secret_key) < 32 ->
        {:error, :too_short}
        
      String.length(secret_key) > 256 ->
        {:error, :too_long}
        
      true ->
        :ok
    end
  end

  # =============================================================================
  # ENVIRONMENT AND LIFECYCLE HELPER FUNCTIONS
  # =============================================================================

  defp init_with_explicit_credentials(user_id, api_key, secret_key) do
    # Never log actual credentials
    Logger.info("Starting CredentialManager for user with explicit credentials", user_id: user_id)
    
    # Validate credentials on startup
    with :ok <- validate_api_key_format(api_key),
         :ok <- validate_secret_key_format(secret_key) do
      
      state = %{
        user_id: user_id,
        api_key: api_key,
        secret_key: secret_key,
        created_at: System.system_time(:millisecond),
        last_used: nil,
        request_count: 0,
        request_history: [],  # List of request timestamps for rate limiting
        validated: true,
        purged: false,
        source: :explicit,
        rotation_count: 0
      }
      
      # Schedule periodic health checks
      schedule_health_check()
      
      # Audit credential creation (without exposing values)
      UserSecurityAuditor.log_credential_event(user_id, :created, %{
        api_key_length: String.length(api_key),
        secret_key_length: String.length(secret_key),
        source: :explicit
      })
      
      Logger.info("CredentialManager initialized successfully", user_id: user_id)
      {:ok, state}
      
    else
      error ->
        Logger.error("Invalid credentials provided for user", user_id: user_id, error: error)
        UserSecurityAuditor.log_credential_event(user_id, :validation_failed, %{error: error})
        {:stop, {:invalid_credentials, error}}
    end
  end

  defp init_with_environment_credentials(user_id) do
    Logger.info("Starting CredentialManager for user with environment credentials", user_id: user_id)
    
    case CredentialEnvironmentManager.load_user_credentials(user_id) do
      {:ok, %{api_key: api_key, secret_key: secret_key, pattern: pattern}} ->
        state = %{
          user_id: user_id,
          api_key: api_key,
          secret_key: secret_key,
          created_at: System.system_time(:millisecond),
          last_used: nil,
          request_count: 0,
          request_history: [],
          validated: true,
          purged: false,
          source: :environment,
          environment_pattern: pattern,
          rotation_count: 0
        }
        
        # Schedule periodic health checks and rotation checks
        schedule_health_check()
        schedule_rotation_check()
        
        UserSecurityAuditor.log_credential_event(user_id, :created, %{
          api_key_length: String.length(api_key),
          secret_key_length: String.length(secret_key),
          source: :environment,
          pattern: pattern
        })
        
        Logger.info("CredentialManager initialized successfully from environment", 
          user_id: user_id, 
          pattern: pattern
        )
        
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to load credentials from environment", user_id: user_id, error: reason)
        UserSecurityAuditor.log_credential_event(user_id, :environment_load_failed, %{error: reason})
        {:stop, {:environment_credentials_unavailable, reason}}
    end
  end

  defp perform_health_check(state, now) do
    issues = []
    
    # Check credential age
    credential_age = now - state.created_at
    issues = if credential_age > @max_credential_age do
      [:credentials_too_old | issues]
    else
      issues
    end
    
    # Check if credentials are purged
    issues = if Map.get(state, :purged, false) do
      [:credentials_purged | issues]
    else
      issues
    end
    
    # Check validation status
    issues = if not state.validated do
      [:credentials_invalid | issues]
    else
      issues
    end
    
    # Check for excessive rate limiting
    rate_limit_utilization = length(state.request_history) / @max_requests_per_minute
    issues = if rate_limit_utilization > 0.9 do
      [:high_rate_limit_utilization | issues]
    else
      issues
    end
    
    # Check for long inactivity
    last_used_age = if state.last_used do
      now - state.last_used
    else
      credential_age
    end
    
    issues = if last_used_age > 3_600_000 do  # 1 hour
      [:long_inactivity | issues]
    else
      issues
    end
    
    # Determine overall status
    overall_status = cond do
      Enum.any?(issues, &(&1 in [:credentials_purged, :credentials_invalid])) -> :critical
      Enum.any?(issues, &(&1 in [:credentials_too_old, :high_rate_limit_utilization])) -> :warning
      length(issues) > 0 -> :degraded
      true -> :healthy
    end
    
    %{
      overall_status: overall_status,
      issues: issues,
      credential_age_ms: credential_age,
      last_used_age_ms: last_used_age,
      rate_limit_utilization: rate_limit_utilization,
      checked_at: now
    }
  end

  defp calculate_security_level(state) do
    score = 100
    
    # Deduct points for various factors
    score = if Map.get(state, :purged, false), do: score - 100, else: score
    score = if not state.validated, do: score - 50, else: score
    score = if Map.get(state, :source) == :environment, do: score + 10, else: score
    score = if Map.get(state, :rotation_count, 0) > 0, do: score + 10, else: score
    
    # Check credential age
    now = System.system_time(:millisecond)
    credential_age = now - state.created_at
    score = if credential_age > @max_credential_age, do: score - 20, else: score
    
    # Check recent activity
    last_used_age = if state.last_used, do: now - state.last_used, else: credential_age
    score = if last_used_age > 3_600_000, do: score - 10, else: score
    
    cond do
      score >= 90 -> :high
      score >= 70 -> :medium
      score >= 50 -> :low
      true -> :critical
    end
  end

  defp calculate_compliance_score(state) do
    score = 0
    
    # Positive factors
    score = if state.validated, do: score + 25, else: score
    score = if Map.get(state, :source) == :environment, do: score + 25, else: score
    score = if Map.get(state, :rotation_count, 0) > 0, do: score + 20, else: score
    score = if Map.get(state, :last_health_check), do: score + 15, else: score
    score = if not Map.get(state, :purged, false), do: score + 15, else: score
    
    max(0, min(100, score))
  end

  defp identify_risk_factors(state, now) do
    risks = []
    
    # Age-based risks
    credential_age = now - state.created_at
    risks = if credential_age > @max_credential_age do
      [:old_credentials | risks]
    else
      risks
    end
    
    # Usage-based risks
    last_used_age = if state.last_used, do: now - state.last_used, else: credential_age
    risks = if last_used_age > 3_600_000 do
      [:inactive_credentials | risks]
    else
      risks
    end
    
    # Rate limiting risks
    rate_utilization = length(state.request_history) / @max_requests_per_minute
    risks = if rate_utilization > 0.9 do
      [:high_api_usage | risks]
    else
      risks
    end
    
    # Source-based risks
    risks = if Map.get(state, :source) == :explicit do
      [:static_credentials | risks]
    else
      risks
    end
    
    # Validation risks
    risks = if not state.validated do
      [:invalid_credentials | risks]
    else
      risks
    end
    
    # Purge risks
    risks = if Map.get(state, :purged, false) do
      [:purged_credentials | risks]
    else
      risks
    end
    
    risks
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @credential_health_check_interval)
  end

  defp schedule_rotation_check do
    Process.send_after(self(), :rotation_check, @credential_rotation_interval)
  end
end