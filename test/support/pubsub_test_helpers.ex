defmodule CryptoExchange.TestSupport.PubSubTestHelpers do
  @moduledoc """
  Test helpers for PubSub message testing.
  Provides utilities for testing publish/subscribe patterns safely.
  """

  import ExUnit.Assertions
  
  alias Phoenix.PubSub

  # =============================================================================
  # SUBSCRIPTION HELPERS
  # =============================================================================

  @doc """
  Subscribes to a topic and returns a function to unsubscribe.
  Ensures proper cleanup after tests.
  """
  def subscribe_with_cleanup(pubsub, topic, test_pid \\ self()) do
    :ok = PubSub.subscribe(pubsub, topic)
    
    cleanup_fn = fn ->
      PubSub.unsubscribe(pubsub, topic)
    end
    
    {topic, cleanup_fn}
  end

  @doc """
  Subscribes to multiple topics and returns cleanup functions.
  """
  def subscribe_multiple(pubsub, topics, test_pid \\ self()) do
    Enum.map(topics, fn topic ->
      subscribe_with_cleanup(pubsub, topic, test_pid)
    end)
  end

  @doc """
  Creates a unique test topic name to avoid interference between tests.
  """
  def unique_test_topic(base_topic, test_module \\ nil) do
    module_suffix = if test_module, do: "_#{test_module}", else: ""
    random_suffix = :rand.uniform(10000)
    "test_#{base_topic}#{module_suffix}_#{random_suffix}"
  end

  # =============================================================================
  # MESSAGE ASSERTION HELPERS
  # =============================================================================

  @doc """
  Asserts that a specific message is received within timeout.
  More flexible than ExUnit's assert_receive for complex messages.
  """
  def assert_pubsub_message(expected_pattern, timeout \\ 1000) do
    receive do
      message when message == expected_pattern ->
        message
      message ->
        flunk("Expected #{inspect(expected_pattern)}, got #{inspect(message)}")
    after
      timeout ->
        flunk("Expected message #{inspect(expected_pattern)} not received within #{timeout}ms")
    end
  end

  @doc """
  Asserts that a message matching a pattern is received.
  """
  def assert_pubsub_message_matches(pattern_fun, timeout \\ 1000) when is_function(pattern_fun, 1) do
    receive do
      message ->
        if pattern_fun.(message) do
          message
        else
          flunk("Received message #{inspect(message)} does not match expected pattern")
        end
    after
      timeout ->
        flunk("No message matching pattern received within #{timeout}ms")
    end
  end

  @doc """
  Asserts that NO message is received within timeout.
  """
  def refute_pubsub_message(timeout \\ 100) do
    receive do
      message ->
        flunk("Expected no message but received: #{inspect(message)}")
    after
      timeout ->
        :ok
    end
  end

  @doc """
  Waits for and collects multiple messages up to a count or timeout.
  """
  def collect_pubsub_messages(count, timeout \\ 1000) do
    collect_messages([], count, timeout)
  end

  defp collect_messages(messages, 0, _timeout), do: Enum.reverse(messages)
  
  defp collect_messages(messages, remaining, timeout) do
    receive do
      message ->
        collect_messages([message | messages], remaining - 1, timeout)
    after
      timeout ->
        Enum.reverse(messages)
    end
  end

  # =============================================================================
  # PUBLISHING HELPERS
  # =============================================================================

  @doc """
  Publishes a message and waits briefly to ensure delivery.
  """
  def publish_and_wait(pubsub, topic, message, wait_ms \\ 10) do
    :ok = PubSub.broadcast(pubsub, topic, message)
    if wait_ms > 0, do: :timer.sleep(wait_ms)
    :ok
  end

  @doc """
  Publishes multiple messages in sequence with optional delays.
  """
  def publish_sequence(pubsub, topic, messages, delay_ms \\ 10) do
    Enum.each(messages, fn message ->
      publish_and_wait(pubsub, topic, message, delay_ms)
    end)
  end

  @doc """
  Publishes messages to multiple topics simultaneously.
  """
  def broadcast_to_multiple(pubsub, topic_message_pairs) do
    Enum.each(topic_message_pairs, fn {topic, message} ->
      PubSub.broadcast(pubsub, topic, message)
    end)
    :timer.sleep(10) # Brief wait for message delivery
  end

  # =============================================================================
  # TESTING UTILITIES
  # =============================================================================

  @doc """
  Flushes all PubSub messages from the mailbox.
  Useful for cleanup between test scenarios.
  """
  def flush_pubsub_messages do
    receive do
      _ -> flush_pubsub_messages()
    after
      0 -> :ok
    end
  end

  @doc """
  Creates a test scenario where messages are published after a delay.
  Useful for testing async message handling.
  """
  def delayed_publish(pubsub, topic, message, delay_ms) do
    test_pid = self()
    
    spawn(fn ->
      :timer.sleep(delay_ms)
      PubSub.broadcast(pubsub, topic, message)
      send(test_pid, :delayed_publish_complete)
    end)
  end

  @doc """
  Subscribes to a topic, runs a function, then unsubscribes.
  Ensures proper cleanup even if the function raises.
  """
  def with_subscription(pubsub, topic, fun) when is_function(fun, 0) do
    :ok = PubSub.subscribe(pubsub, topic)
    
    try do
      fun.()
    after
      PubSub.unsubscribe(pubsub, topic)
    end
  end

  @doc """
  Tests message delivery performance by measuring timing.
  """
  def measure_delivery_time(pubsub, topic, message) do
    :ok = PubSub.subscribe(pubsub, topic)
    
    start_time = System.monotonic_time(:microsecond)
    :ok = PubSub.broadcast(pubsub, topic, message)
    
    receive do
      ^message ->
        end_time = System.monotonic_time(:microsecond)
        delivery_time = end_time - start_time
        PubSub.unsubscribe(pubsub, topic)
        {:ok, delivery_time}
    after
      1000 ->
        PubSub.unsubscribe(pubsub, topic)
        {:error, :timeout}
    end
  end

  # =============================================================================
  # MARKET DATA SPECIFIC HELPERS
  # =============================================================================

  @doc """
  Creates a test market data message for PubSub testing.
  """
  def market_data_message(type, symbol, data \\ %{}) do
    {:market_data, %{
      type: type,
      symbol: symbol,
      data: data,
      timestamp: System.system_time(:millisecond)
    }}
  end

  @doc """
  Creates a test trading event message for PubSub testing.
  """
  def trading_event_message(event_type, user_id, data \\ %{}) do
    {:trading_event, %{
      event: event_type,
      user_id: user_id,
      data: data,
      timestamp: System.system_time(:millisecond)
    }}
  end

  @doc """
  Tests that market data messages are properly formatted.
  """
  def assert_valid_market_data_message({:market_data, data}) do
    assert Map.has_key?(data, :type)
    assert Map.has_key?(data, :symbol)
    assert Map.has_key?(data, :timestamp)
    assert is_binary(data.symbol)
    assert is_integer(data.timestamp)
    data
  end

  def assert_valid_market_data_message(message) do
    flunk("Expected market data message, got: #{inspect(message)}")
  end
end