defmodule CryptoExchange.TestSupport.TestCaseTemplate do
  @moduledoc """
  Template module for creating consistent test cases across the CryptoExchange test suite.
  Provides common setup, utilities, and patterns for different types of tests.
  """

  defmacro __using__(opts) do
    test_type = Keyword.get(opts, :type, :unit)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)
      
      import Mox
      import Hammox
      import ExUnit.CaptureLog
      import StreamData
      
      # Import test support modules
      import CryptoExchange.TestHelpers
      import CryptoExchange.TestSupport.Factory
      import CryptoExchange.TestSupport.TestConfig
      import CryptoExchange.TestSupport.HTTPTestHelpers
      import CryptoExchange.TestSupport.PubSubTestHelpers
      
      alias CryptoExchange.TestSupport.WebSocketTestServer
      alias CryptoExchange.Models.{Order, MarketData, UserData}

      # Apply test type specific setup
      unquote(apply_test_type_setup(test_type))
      
      # Common setup for all tests
      setup_all do
        # Ensure test environment is properly configured
        setup_test_env()
        :ok
      end

      setup do
        # Set up mocks for each test
        setup_mocks()
        
        # Verify mocks after each test
        on_exit(fn -> verify_mocks!() end)
        
        # Provide common test context
        context = %{
          test_pid: self(),
          start_time: System.monotonic_time(:millisecond)
        }
        
        unquote(test_type_specific_setup(test_type))
        
        {:ok, context}
      end
    end
  end

  # =============================================================================
  # TEST TYPE SPECIFIC CONFIGURATIONS
  # =============================================================================

  defp apply_test_type_setup(:unit) do
    quote do
      # Unit tests focus on individual modules/functions
      # Fast execution, isolated, no external dependencies
    end
  end

  defp apply_test_type_setup(:integration) do
    quote do
      # Integration tests verify component interactions
      # May use real PubSub, GenServers, but mock external APIs
      @moduletag :integration
      
      import CryptoExchange.TestSupport.IntegrationHelpers
    end
  end

  defp apply_test_type_setup(:websocket) do
    quote do
      # WebSocket tests focus on real-time communication
      # Use WebSocket test server for simulation
      @moduletag :websocket
      
      import CryptoExchange.TestSupport.WebSocketTestHelpers
    end
  end

  defp apply_test_type_setup(:pubsub) do
    quote do
      # PubSub tests verify message publishing/subscribing
      # Focus on message delivery and topic management
      @moduletag :pubsub
    end
  end

  defp apply_test_type_setup(:property) do
    quote do
      # Property-based tests use StreamData for generated inputs
      # Focus on invariants and edge cases
      @moduletag :property
      
      import StreamData
      import ExUnitProperties
    end
  end

  defp apply_test_type_setup(:performance) do
    quote do
      # Performance tests measure timing and resource usage
      # May have longer timeouts and specific metrics
      @moduletag :performance
      @moduletag timeout: 60_000
    end
  end

  defp apply_test_type_setup(:slow) do
    quote do
      # Slow tests that take significant time to execute
      # Excluded by default, run specifically when needed
      @moduletag :slow
      @moduletag timeout: 120_000
    end
  end

  defp apply_test_type_setup(_default) do
    quote do
      # Default unit test setup
    end
  end

  # =============================================================================
  # TEST TYPE SPECIFIC SETUP FUNCTIONS
  # =============================================================================

  defp test_type_specific_setup(:websocket) do
    quote do
      # Start WebSocket test server for each test
      {:ok, ws_server} = start_supervised({WebSocketTestServer, [test_pid: self()]})
      Map.put(context, :ws_server, ws_server)
    end
  end

  defp test_type_specific_setup(:pubsub) do
    quote do
      # Set up unique PubSub topics for test isolation
      test_topics = []
      on_exit(fn -> 
        Enum.each(test_topics, fn topic ->
          Phoenix.PubSub.unsubscribe(CryptoExchange.PubSub, topic)
        end)
      end)
      Map.put(context, :test_topics, test_topics)
    end
  end

  defp test_type_specific_setup(:integration) do
    quote do
      # Start supervised processes needed for integration tests
      # Configure with test-specific names to avoid conflicts
      test_registry = :"test_registry_#{:rand.uniform(10000)}"
      
      {:ok, _registry} = start_supervised({Registry, keys: :unique, name: test_registry})
      
      Map.put(context, :test_registry, test_registry)
    end
  end

  defp test_type_specific_setup(:performance) do
    quote do
      # Set up performance monitoring
      :telemetry.attach_many(
        "test_performance_#{:rand.uniform(1000)}",
        [
          [:crypto_exchange, :api, :request, :stop],
          [:crypto_exchange, :websocket, :message, :received]
        ],
        &__MODULE__.handle_performance_event/4,
        %{test_pid: self()}
      )
      
      performance_metrics = %{
        api_requests: [],
        websocket_messages: [],
        start_time: System.monotonic_time(:microsecond)
      }
      
      Map.put(context, :performance_metrics, performance_metrics)
    end
  end

  defp test_type_specific_setup(_default) do
    quote do
      context
    end
  end
end

# =============================================================================
# HELPER MODULES FOR SPECIFIC TEST TYPES
# =============================================================================

defmodule CryptoExchange.TestSupport.IntegrationHelpers do
  @moduledoc """
  Helpers specifically for integration tests.
  """

  @doc """
  Starts a complete test environment with all supervised processes.
  """
  def start_test_environment(opts \\ []) do
    # Start the main application supervision tree for integration tests
    children = [
      {Phoenix.PubSub, name: :"TestPubSub_#{:rand.uniform(1000)}"},
      {Registry, keys: :unique, name: :"TestRegistry_#{:rand.uniform(1000)}"}
    ]
    
    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
    supervisor
  end

  @doc """
  Waits for all supervised processes to be ready.
  """
  def wait_for_system_ready(supervisor, timeout \\ 5000) do
    :timer.sleep(100) # Give processes time to start
    
    # Check that all expected processes are running
    children = Supervisor.which_children(supervisor)
    all_started = Enum.all?(children, fn {_id, pid, _type, _modules} ->
      is_pid(pid) and Process.alive?(pid)
    end)
    
    if all_started do
      :ok
    else
      if timeout > 0 do
        :timer.sleep(50)
        wait_for_system_ready(supervisor, timeout - 50)
      else
        {:error, :timeout}
      end
    end
  end
end

defmodule CryptoExchange.TestSupport.WebSocketTestHelpers do
  @moduledoc """
  Helpers specifically for WebSocket tests.
  """
  
  import ExUnit.Assertions

  @doc """
  Simulates a complete WebSocket connection lifecycle.
  """
  def simulate_connection_lifecycle(ws_server, messages \\ []) do
    # Simulate connection
    WebSocketTestServer.simulate_connect(ws_server)
    assert_receive {:websocket_connected, server_pid}
    assert is_pid(server_pid)
    
    # Send messages
    Enum.each(messages, fn message ->
      WebSocketTestServer.send_message(ws_server, message)
      :timer.sleep(10) # Small delay between messages
    end)
    
    # Simulate disconnection
    WebSocketTestServer.simulate_disconnect(ws_server)
    assert_receive {:websocket_disconnected, :normal}
  end

  @doc """
  Tests WebSocket message ordering and delivery.
  """
  def test_message_ordering(ws_server, message_count \\ 10) do
    messages = Enum.map(1..message_count, fn i ->
      %{"sequence" => i, "data" => "test_#{i}"}
    end)
    
    # Send all messages rapidly
    Enum.each(messages, fn message ->
      WebSocketTestServer.send_message(ws_server, Jason.encode!(message))
    end)
    
    # Verify they arrive in order
    received_messages = collect_pubsub_messages(message_count, 1000)
    
    assert length(received_messages) == message_count
    
    # Check ordering
    Enum.with_index(received_messages, 1)
    |> Enum.each(fn {message, expected_sequence} ->
      {:websocket_message, json_message} = message
      parsed = Jason.decode!(json_message)
      assert parsed["sequence"] == expected_sequence
    end)
  end
  
  @doc """
  Collects PubSub messages for testing.
  """
  def collect_pubsub_messages(count, timeout \\ 1000) do
    collect_pubsub_messages(count, timeout, [])
  end
  
  defp collect_pubsub_messages(0, _timeout, acc), do: Enum.reverse(acc)
  
  defp collect_pubsub_messages(count, timeout, acc) when count > 0 do
    receive do
      message -> collect_pubsub_messages(count - 1, timeout, [message | acc])
    after
      timeout -> Enum.reverse(acc)
    end
  end
end

defmodule CryptoExchange.TestSupport.PerformanceHelpers do
  @moduledoc """
  Helpers for performance testing.
  """

  @doc """
  Measures execution time of a function.
  """
  def measure_time(fun) when is_function(fun, 0) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time
    
    {result, duration}
  end

  @doc """
  Tests throughput by running a function multiple times.
  """
  def measure_throughput(fun, iterations \\ 1000) when is_function(fun, 0) do
    start_time = System.monotonic_time(:microsecond)
    
    Enum.each(1..iterations, fn _i -> fun.() end)
    
    end_time = System.monotonic_time(:microsecond)
    total_duration = end_time - start_time
    
    %{
      iterations: iterations,
      total_duration_us: total_duration,
      average_duration_us: total_duration / iterations,
      throughput_per_second: (iterations * 1_000_000) / total_duration
    }
  end

  @doc """
  Handles telemetry events for performance measurement.
  """
  def handle_performance_event(event_name, measurements, metadata, config) do
    send(config.test_pid, {:telemetry_event, event_name, measurements, metadata})
  end
end