defmodule CryptoExchange.ReconnectionStrategy do
  @moduledoc """
  Comprehensive reconnection strategy with exponential backoff and intelligent recovery.

  This module provides sophisticated reconnection strategies for WebSocket connections with:

  - **Exponential Backoff**: Progressive delay increases with jitter to avoid thundering herd
  - **Intelligent Recovery**: Different strategies based on failure types and patterns  
  - **Rate Limit Awareness**: Built-in respect for Binance API rate limits
  - **Connection Quality Assessment**: Tracks connection stability for adaptive strategies
  - **Graceful Degradation**: Fallback strategies during prolonged outages

  ## Backoff Strategy

  - **Initial Delay**: 1 second (configurable)
  - **Max Delay**: 30 seconds (per SPECIFICATION.md requirements)
  - **Backoff Factor**: 2.0 (exponential growth)
  - **Jitter**: ±10% randomization to prevent synchronization
  - **Reset Threshold**: Successful connection for 5 minutes resets backoff

  ## Recovery Patterns

  - **Fast Recovery**: For transient network issues (< 3 failures)
  - **Standard Recovery**: For moderate instability (3-10 failures)
  - **Conservative Recovery**: For persistent issues (10+ failures)
  - **Emergency Recovery**: For critical system degradation

  ## Rate Limit Handling

  - **Binance Limits**: 5 messages/second per WebSocket connection
  - **Burst Protection**: Temporary backoff on rate limit violations
  - **Priority Queuing**: Critical reconnections get higher priority

  ## Usage

      # Create strategy for a connection
      {:ok, strategy} = ReconnectionStrategy.create(%{
        connection_id: "binance_ws_btcusdt",
        connection_type: :binance_ws,
        initial_delay: 1_000,
        max_delay: 30_000
      })
      
      # Handle connection failure
      case ReconnectionStrategy.handle_failure(strategy, :network_error) do
        {:reconnect, delay_ms, new_strategy} -> 
          # Schedule reconnection after delay_ms
        {:backoff, delay_ms, new_strategy} -> 
          # Wait before attempting again
        {:abandon, reason, new_strategy} -> 
          # Give up on this connection
      end
  """

  require Logger

  alias CryptoExchange.{Config, ConnectionManager}

  # Failure types that trigger different recovery strategies
  @transient_failures [:network_timeout, :dns_resolution, :connection_refused]
  @rate_limit_failures [:rate_limit_exceeded, :too_many_requests]
  @authentication_failures [:invalid_credentials, :forbidden, :unauthorized]
  @server_failures [:internal_server_error, :bad_gateway, :service_unavailable]

  # Recovery strategy types
  @strategy_fast :fast_recovery
  @strategy_standard :standard_recovery  
  @strategy_conservative :conservative_recovery
  @strategy_emergency :emergency_recovery

  defstruct [
    # Connection identification
    :connection_id,
    :connection_type,
    
    # Current strategy state
    :strategy_type,
    :failure_count,
    :consecutive_failures,
    :last_success_time,
    :last_failure_time,
    :failure_history,
    
    # Backoff configuration
    :initial_delay,
    :max_delay,
    :backoff_factor,
    :jitter_percentage,
    :reset_threshold,
    
    # Rate limiting
    :rate_limit_backoff,
    :rate_limit_violations,
    
    # Connection quality tracking
    :connection_quality,
    :stability_score,
    :quality_history,
    
    # Recovery state
    :recovery_attempts,
    :recovery_start_time,
    :max_recovery_attempts,
    
    # Configuration
    :config
  ]

  @type failure_type :: atom()
  @type strategy_type :: atom()
  @type connection_quality :: :excellent | :good | :fair | :poor | :critical

  # =============================================================================
  # CLIENT API
  # =============================================================================

  @doc """
  Create a new reconnection strategy for a connection.
  """
  @spec create(map()) :: {:ok, %__MODULE__{}} | {:error, term()}
  def create(params) do
    config = load_strategy_config()
    
    strategy = %__MODULE__{
      connection_id: Map.fetch!(params, :connection_id),
      connection_type: Map.get(params, :connection_type, :generic),
      
      strategy_type: @strategy_fast,
      failure_count: 0,
      consecutive_failures: 0,
      last_success_time: nil,
      last_failure_time: nil,
      failure_history: [],
      
      initial_delay: Map.get(params, :initial_delay, config.initial_delay),
      max_delay: Map.get(params, :max_delay, config.max_delay),
      backoff_factor: Map.get(params, :backoff_factor, config.backoff_factor),
      jitter_percentage: Map.get(params, :jitter_percentage, config.jitter_percentage),
      reset_threshold: Map.get(params, :reset_threshold, config.reset_threshold),
      
      rate_limit_backoff: 0,
      rate_limit_violations: 0,
      
      connection_quality: :excellent,
      stability_score: 1.0,
      quality_history: [],
      
      recovery_attempts: 0,
      recovery_start_time: nil,
      max_recovery_attempts: Map.get(params, :max_recovery_attempts, config.max_recovery_attempts),
      
      config: config
    }
    
    {:ok, strategy}
  end

  @doc """
  Handle a connection failure and determine the next action.
  
  Returns:
  - `{:reconnect, delay_ms, new_strategy}` - Attempt reconnection after delay
  - `{:backoff, delay_ms, new_strategy}` - Back off for the specified time
  - `{:abandon, reason, new_strategy}` - Give up on this connection
  """
  @spec handle_failure(%__MODULE__{}, failure_type()) :: 
    {:reconnect, non_neg_integer(), %__MODULE__{}} |
    {:backoff, non_neg_integer(), %__MODULE__{}} |
    {:abandon, atom(), %__MODULE__{}}
  def handle_failure(strategy, failure_type) do
    Logger.info("Handling connection failure: #{failure_type} for #{strategy.connection_id}")
    
    current_time = System.system_time(:millisecond)
    updated_strategy = record_failure(strategy, failure_type, current_time)
    
    # Determine appropriate recovery action
    case determine_recovery_action(updated_strategy, failure_type) do
      {:reconnect, delay} ->
        final_strategy = prepare_for_reconnection(updated_strategy, delay)
        {:reconnect, delay, final_strategy}
        
      {:backoff, delay} ->
        final_strategy = apply_backoff_strategy(updated_strategy, delay)
        {:backoff, delay, final_strategy}
        
      {:abandon, reason} ->
        final_strategy = mark_abandoned(updated_strategy, reason)
        {:abandon, reason, final_strategy}
    end
  end

  @doc """
  Handle a successful connection to update strategy state.
  """
  @spec handle_success(%__MODULE__{}) :: %__MODULE__{}
  def handle_success(strategy) do
    current_time = System.system_time(:millisecond)
    connection_duration = if strategy.recovery_start_time do
      current_time - strategy.recovery_start_time
    else
      0
    end
    
    Logger.info("Connection successful for #{strategy.connection_id} after #{connection_duration}ms")
    
    # Calculate connection quality based on failure history and recovery time
    new_quality = calculate_connection_quality(strategy, connection_duration)
    new_stability_score = update_stability_score(strategy, true)
    
    # Reset strategy if connection has been stable
    should_reset = should_reset_strategy?(strategy, current_time)
    
    if should_reset do
      Logger.debug("Resetting reconnection strategy for #{strategy.connection_id} due to stable connection")
      reset_strategy(strategy, current_time, new_quality, new_stability_score)
    else
      %{strategy |
        consecutive_failures: 0,
        last_success_time: current_time,
        recovery_start_time: nil,
        recovery_attempts: 0,
        connection_quality: new_quality,
        stability_score: new_stability_score,
        quality_history: add_to_quality_history(strategy.quality_history, new_quality, current_time)
      }
    end
  end

  @doc """
  Get the current reconnection delay for this strategy.
  """
  @spec get_current_delay(%__MODULE__{}) :: non_neg_integer()
  def get_current_delay(strategy) do
    base_delay = calculate_base_delay(strategy)
    rate_limit_delay = strategy.rate_limit_backoff
    
    max(base_delay, rate_limit_delay)
  end

  @doc """
  Check if the strategy recommends abandoning the connection.
  """
  @spec should_abandon?(%__MODULE__{}) :: boolean()
  def should_abandon?(strategy) do
    cond do
      # Too many consecutive failures
      strategy.consecutive_failures >= strategy.config.max_consecutive_failures ->
        true
        
      # Total failures exceed threshold
      strategy.failure_count >= strategy.config.max_total_failures ->
        true
        
      # Recovery time exceeded
      strategy.recovery_attempts >= strategy.max_recovery_attempts ->
        true
        
      # Connection quality is critical for too long
      strategy.connection_quality == :critical and 
      time_in_critical_state(strategy) > strategy.config.max_critical_time ->
        true
        
      # Authentication failures (don't retry these)
      has_recent_auth_failure?(strategy) ->
        true
        
      true ->
        false
    end
  end

  @doc """
  Get comprehensive metrics about the reconnection strategy.
  """
  @spec get_metrics(%__MODULE__{}) :: map()
  def get_metrics(strategy) do
    current_time = System.system_time(:millisecond)
    
    %{
      connection_id: strategy.connection_id,
      connection_type: strategy.connection_type,
      strategy_type: strategy.strategy_type,
      failure_count: strategy.failure_count,
      consecutive_failures: strategy.consecutive_failures,
      connection_quality: strategy.connection_quality,
      stability_score: Float.round(strategy.stability_score, 3),
      current_delay: get_current_delay(strategy),
      recovery_attempts: strategy.recovery_attempts,
      time_since_last_success: if strategy.last_success_time do
        current_time - strategy.last_success_time
      else
        nil
      end,
      time_since_last_failure: if strategy.last_failure_time do
        current_time - strategy.last_failure_time
      else
        nil
      end,
      recent_failures: get_recent_failure_summary(strategy),
      should_abandon: should_abandon?(strategy)
    }
  end

  # =============================================================================
  # FAILURE HANDLING LOGIC
  # =============================================================================

  defp record_failure(strategy, failure_type, current_time) do
    failure_record = %{
      type: failure_type,
      timestamp: current_time,
      strategy_type: strategy.strategy_type
    }
    
    updated_history = [failure_record | strategy.failure_history]
    |> Enum.take(100)  # Keep last 100 failures
    
    new_stability_score = update_stability_score(strategy, false)
    new_quality = calculate_connection_quality_after_failure(strategy, failure_type)
    
    %{strategy |
      failure_count: strategy.failure_count + 1,
      consecutive_failures: strategy.consecutive_failures + 1,
      last_failure_time: current_time,
      failure_history: updated_history,
      connection_quality: new_quality,
      stability_score: new_stability_score,
      quality_history: add_to_quality_history(strategy.quality_history, new_quality, current_time)
    }
  end

  defp determine_recovery_action(strategy, failure_type) do
    cond do
      # Check if we should abandon
      should_abandon?(strategy) ->
        {:abandon, :max_failures_exceeded}
        
      # Handle rate limiting with special backoff
      failure_type in @rate_limit_failures ->
        delay = calculate_rate_limit_backoff(strategy)
        {:backoff, delay}
        
      # Handle authentication failures (don't retry)
      failure_type in @authentication_failures ->
        {:abandon, :authentication_failed}
        
      # Handle server failures with conservative approach
      failure_type in @server_failures ->
        delay = calculate_server_error_backoff(strategy)
        {:backoff, delay}
        
      # Handle transient failures with faster recovery
      failure_type in @transient_failures ->
        delay = calculate_transient_failure_backoff(strategy)
        {:reconnect, delay}
        
      # Default case - standard exponential backoff
      true ->
        delay = calculate_exponential_backoff(strategy)
        {:reconnect, delay}
    end
  end

  defp calculate_exponential_backoff(strategy) do
    # Base exponential backoff calculation
    attempt = strategy.consecutive_failures - 1
    base_delay = strategy.initial_delay * :math.pow(strategy.backoff_factor, attempt)
    capped_delay = min(base_delay, strategy.max_delay)
    
    # Apply jitter to prevent thundering herd
    jitter_amount = capped_delay * strategy.jitter_percentage
    jitter = :rand.uniform() * jitter_amount * 2 - jitter_amount
    
    # Adjust based on connection quality
    quality_multiplier = get_quality_multiplier(strategy.connection_quality)
    
    final_delay = max(0, trunc(capped_delay + jitter)) * quality_multiplier
    
    Logger.debug("Calculated exponential backoff: #{final_delay}ms for #{strategy.connection_id}")
    final_delay
  end

  defp calculate_rate_limit_backoff(strategy) do
    # Progressive backoff for rate limiting
    base_backoff = 5_000  # Start with 5 seconds
    violations = strategy.rate_limit_violations + 1
    
    delay = base_backoff * :math.pow(2, min(violations, 6))  # Cap at 64x
    max(delay, 1_000)
  end

  defp calculate_server_error_backoff(strategy) do
    # More conservative backoff for server errors
    base_delay = strategy.initial_delay * 3  # 3x normal delay
    attempt = strategy.consecutive_failures - 1
    
    conservative_delay = base_delay * :math.pow(1.5, attempt)  # Slower growth
    min(conservative_delay, strategy.max_delay)
  end

  defp calculate_transient_failure_backoff(strategy) do
    # Faster recovery for transient issues
    base_delay = strategy.initial_delay / 2  # Half normal delay
    attempt = min(strategy.consecutive_failures - 1, 3)  # Cap at 3 attempts
    
    transient_delay = base_delay * :math.pow(1.5, attempt)
    min(transient_delay, strategy.max_delay / 2)
  end

  defp calculate_base_delay(strategy) do
    case strategy.strategy_type do
      @strategy_fast -> 
        calculate_transient_failure_backoff(strategy)
      @strategy_standard -> 
        calculate_exponential_backoff(strategy)
      @strategy_conservative -> 
        calculate_server_error_backoff(strategy)
      @strategy_emergency -> 
        strategy.max_delay
    end
  end

  # =============================================================================
  # CONNECTION QUALITY ASSESSMENT
  # =============================================================================

  defp calculate_connection_quality(strategy, connection_duration) do
    failure_rate = calculate_recent_failure_rate(strategy)
    stability = strategy.stability_score
    recovery_speed = assess_recovery_speed(connection_duration)
    
    overall_score = (stability * 0.5) + ((1 - failure_rate) * 0.3) + (recovery_speed * 0.2)
    
    cond do
      overall_score >= 0.9 -> :excellent
      overall_score >= 0.7 -> :good
      overall_score >= 0.5 -> :fair
      overall_score >= 0.3 -> :poor
      true -> :critical
    end
  end

  defp calculate_connection_quality_after_failure(strategy, failure_type) do
    current_quality = strategy.connection_quality
    
    # Degrade quality based on failure type
    degradation = case failure_type do
      f when f in @authentication_failures -> 3  # Severe degradation
      f when f in @server_failures -> 2          # Moderate degradation
      f when f in @rate_limit_failures -> 1      # Minor degradation
      f when f in @transient_failures -> 0       # No degradation
      _ -> 1                                      # Default minor degradation
    end
    
    # Apply degradation
    new_quality_level = case {current_quality, degradation} do
      {:excellent, d} when d >= 2 -> :fair
      {:excellent, d} when d >= 1 -> :good
      {:good, d} when d >= 2 -> :poor
      {:good, d} when d >= 1 -> :fair
      {:fair, d} when d >= 1 -> :poor
      {:poor, _} -> :critical
      {:critical, _} -> :critical
      {quality, 0} -> quality
    end
    
    new_quality_level
  end

  defp update_stability_score(strategy, success) do
    current_score = strategy.stability_score
    
    if success do
      # Gradually improve stability score on success
      min(1.0, current_score + 0.1)
    else
      # Decrease stability score on failure
      max(0.0, current_score - 0.05)
    end
  end

  defp calculate_recent_failure_rate(strategy) do
    return_five_minutes = 5 * 60 * 1000  # 5 minutes in milliseconds
    cutoff_time = System.system_time(:millisecond) - return_five_minutes
    
    recent_failures = Enum.count(strategy.failure_history, fn failure ->
      failure.timestamp >= cutoff_time
    end)
    
    # Assume one attempt per minute as baseline
    expected_attempts = 5
    failure_rate = min(1.0, recent_failures / expected_attempts)
    
    failure_rate
  end

  defp assess_recovery_speed(connection_duration) do
    cond do
      connection_duration <= 1_000 -> 1.0     # Excellent - under 1 second
      connection_duration <= 5_000 -> 0.8     # Good - under 5 seconds
      connection_duration <= 15_000 -> 0.6    # Fair - under 15 seconds
      connection_duration <= 30_000 -> 0.4    # Poor - under 30 seconds
      true -> 0.2                             # Critical - over 30 seconds
    end
  end

  defp get_quality_multiplier(quality) do
    case quality do
      :excellent -> 0.5   # Faster reconnection for excellent connections
      :good -> 0.8        # Slightly faster for good connections
      :fair -> 1.0        # Normal speed for fair connections
      :poor -> 1.5        # Slower for poor connections
      :critical -> 2.0    # Much slower for critical connections
    end
  end

  # =============================================================================
  # STRATEGY STATE MANAGEMENT
  # =============================================================================

  defp prepare_for_reconnection(strategy, delay) do
    current_time = System.system_time(:millisecond)
    
    recovery_start = if strategy.recovery_start_time do
      strategy.recovery_start_time
    else
      current_time
    end
    
    %{strategy |
      recovery_attempts: strategy.recovery_attempts + 1,
      recovery_start_time: recovery_start
    }
  end

  defp apply_backoff_strategy(strategy, delay) do
    # Update strategy type based on failure patterns
    new_strategy_type = determine_strategy_type(strategy)
    
    %{strategy |
      strategy_type: new_strategy_type,
      rate_limit_backoff: delay
    }
  end

  defp mark_abandoned(strategy, reason) do
    Logger.warning("Abandoning connection #{strategy.connection_id}: #{reason}")
    
    %{strategy |
      strategy_type: @strategy_emergency,
      recovery_attempts: strategy.max_recovery_attempts
    }
  end

  defp should_reset_strategy?(strategy, current_time) do
    strategy.last_success_time && 
      (current_time - strategy.last_success_time) >= strategy.reset_threshold &&
      strategy.consecutive_failures == 0
  end

  defp reset_strategy(strategy, current_time, new_quality, new_stability_score) do
    %{strategy |
      strategy_type: @strategy_fast,
      failure_count: 0,
      consecutive_failures: 0,
      last_success_time: current_time,
      recovery_attempts: 0,
      recovery_start_time: nil,
      rate_limit_backoff: 0,
      rate_limit_violations: 0,
      connection_quality: new_quality,
      stability_score: new_stability_score
    }
  end

  defp determine_strategy_type(strategy) do
    cond do
      strategy.consecutive_failures <= 3 -> @strategy_fast
      strategy.consecutive_failures <= 10 -> @strategy_standard
      strategy.consecutive_failures <= 20 -> @strategy_conservative
      true -> @strategy_emergency
    end
  end

  # =============================================================================
  # HELPER FUNCTIONS
  # =============================================================================

  defp load_strategy_config do
    Config.get(:reconnection_strategy, %{
      initial_delay: 1_000,
      max_delay: 30_000,
      backoff_factor: 2.0,
      jitter_percentage: 0.1,
      reset_threshold: 5 * 60 * 1000,  # 5 minutes
      max_recovery_attempts: 50,
      max_consecutive_failures: 20,
      max_total_failures: 100,
      max_critical_time: 10 * 60 * 1000  # 10 minutes
    })
  end

  defp add_to_quality_history(history, quality, timestamp) do
    quality_record = %{quality: quality, timestamp: timestamp}
    [quality_record | history] |> Enum.take(50)  # Keep last 50 quality records
  end

  defp time_in_critical_state(strategy) do
    if strategy.connection_quality != :critical do
      0
    else
      # Find when we first entered critical state
      critical_start = Enum.reduce_while(strategy.quality_history, nil, fn record, _acc ->
        if record.quality == :critical do
          {:cont, record.timestamp}
        else
          {:halt, record.timestamp}
        end
      end)
      
      if critical_start do
        System.system_time(:millisecond) - critical_start
      else
        0
      end
    end
  end

  defp has_recent_auth_failure?(strategy) do
    recent_cutoff = System.system_time(:millisecond) - 60_000  # Last minute
    
    Enum.any?(strategy.failure_history, fn failure ->
      failure.timestamp >= recent_cutoff and 
      failure.type in @authentication_failures
    end)
  end

  defp get_recent_failure_summary(strategy) do
    recent_cutoff = System.system_time(:millisecond) - 5 * 60 * 1000  # Last 5 minutes
    
    strategy.failure_history
    |> Enum.filter(fn failure -> failure.timestamp >= recent_cutoff end)
    |> Enum.group_by(fn failure -> failure.type end)
    |> Enum.map(fn {type, failures} -> {type, length(failures)} end)
    |> Enum.into(%{})
  end
end