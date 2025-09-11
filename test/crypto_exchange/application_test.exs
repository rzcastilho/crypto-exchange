defmodule CryptoExchange.ApplicationTest do
  @moduledoc """
  Comprehensive unit tests for the CryptoExchange.Application module.
  Tests supervision tree, lifecycle management, and fault tolerance.
  """

  use CryptoExchange.TestSupport.TestCaseTemplate

  alias CryptoExchange.Application

  describe "Application.start/2" do
    test "starts successfully with valid configuration" do
      # Skip if already started
      if Process.whereis(CryptoExchange.Supervisor) do
        # Application already running
        assert true
      else
        # Test application start
        assert {:ok, pid} = Application.start(:normal, [])
        assert is_pid(pid)
        assert Process.alive?(pid)
        
        # Verify supervisor is named correctly
        assert Process.whereis(CryptoExchange.Supervisor) == pid
        
        # Stop application cleanly
        Supervisor.stop(pid, :normal)
      end
    end

    test "handles configuration validation" do
      # Test that configuration validation is attempted
      # We don't mock this as it should succeed with default test config
      assert :ok = CryptoExchange.Config.validate()
    rescue
      error ->
        # If config validation fails, ensure it's handled properly
        assert %ArgumentError{} = error
    end

    test "starts all required children processes" do
      supervisor_pid = Process.whereis(CryptoExchange.Supervisor) || begin
        {:ok, pid} = Application.start(:normal, [])
        pid
      end
      
      children = Supervisor.which_children(supervisor_pid)
      child_ids = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)
      
      # Verify core children are started (at minimum)
      core_children = [
        Registry,
        Phoenix.PubSub
      ]
      
      Enum.each(core_children, fn child_id ->
        assert child_id in child_ids, "Expected child #{child_id} not found in supervision tree"
      end)
      
      # Verify running children are alive
      running_children = Enum.filter(children, fn {_id, pid, _type, _modules} ->
        is_pid(pid)
      end)
      
      Enum.each(running_children, fn {id, pid, _type, _modules} ->
        assert Process.alive?(pid), "Child process #{id} is not alive"
      end)
      
      # Only stop if we started it
      if supervisor_pid != Process.whereis(CryptoExchange.Supervisor) do
        Supervisor.stop(supervisor_pid, :normal)
      end
    end

    test "supervision strategy is configured correctly" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      # Test supervision strategy by checking restart behavior
      # Get a non-critical child process
      children = Supervisor.which_children(supervisor_pid)
      {health_monitor_id, health_monitor_pid, _, _} = 
        Enum.find(children, fn {id, _pid, _type, _modules} -> 
          id == CryptoExchange.HealthMonitor
        end)
      
      # Kill the health monitor
      Process.exit(health_monitor_pid, :kill)
      
      # Wait for restart
      :timer.sleep(100)
      
      # Verify it was restarted
      new_children = Supervisor.which_children(supervisor_pid)
      {^health_monitor_id, new_health_monitor_pid, _, _} = 
        Enum.find(new_children, fn {id, _pid, _type, _modules} -> 
          id == CryptoExchange.HealthMonitor
        end)
      
      assert new_health_monitor_pid != health_monitor_pid
      assert Process.alive?(new_health_monitor_pid)
      
      Supervisor.stop(supervisor_pid, :normal)
    end
  end

  describe "Application.stop/1" do
    test "stops gracefully" do
      assert {:ok, pid} = Application.start(:normal, [])
      assert :ok = Application.stop([])
      
      # Verify the application is stopped but we can't easily test the supervisor
      # since it's managed by the application controller in real scenarios
    end
  end

  describe "Application.prep_stop/1" do
    test "gracefully disconnects users before shutdown" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      # Mock user manager
      expect(CryptoExchange.Trading.UserManager, :list_connected_users, fn ->
        ["user1", "user2", "user3"]
      end)
      
      expect(CryptoExchange.Trading.UserManager, :disconnect_user, 3, fn user_id ->
        assert user_id in ["user1", "user2", "user3"]
        :ok
      end)
      
      state = %{some: :state}
      assert ^state = Application.prep_stop(state)
      
      Supervisor.stop(supervisor_pid, :normal)
    end

    test "handles errors during graceful shutdown" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      # Mock failing user manager
      expect(CryptoExchange.Trading.UserManager, :list_connected_users, fn ->
        raise RuntimeError, "User manager error"
      end)
      
      # Should not crash
      state = %{some: :state}
      assert ^state = Application.prep_stop(state)
      
      Supervisor.stop(supervisor_pid, :normal)
    end

    test "handles partial user disconnection failures" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      expect(CryptoExchange.Trading.UserManager, :list_connected_users, fn ->
        ["user1", "user2"]
      end)
      
      expect(CryptoExchange.Trading.UserManager, :disconnect_user, fn
        "user1" -> :ok
        "user2" -> {:error, :timeout}
      end)
      
      state = %{some: :state}
      assert ^state = Application.prep_stop(state)
      
      Supervisor.stop(supervisor_pid, :normal)
    end
  end

  describe "Application.health_check/0" do
    test "returns health status when supervisor is running" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      # Mock external dependencies
      expect(CryptoExchange.Trading.UserManager, :list_connected_users, fn ->
        ["user1", "user2"]
      end)
      
      expect(CryptoExchange.PublicStreams.StreamManager, :list_streams, fn ->
        [%{symbol: "BTCUSDT", type: :ticker}]
      end)
      
      assert {:ok, status} = Application.health_check()
      
      assert status.supervisor == :ok
      assert is_list(status.children)
      assert status.connected_users == 2
      assert status.active_streams == 1
      
      # Verify all children are reported
      assert length(status.children) > 0
      Enum.each(status.children, fn child ->
        assert Map.has_key?(child, :id)
        assert Map.has_key?(child, :status)
        assert child.status in [:ok, :error]
      end)
      
      Supervisor.stop(supervisor_pid, :normal)
    end

    test "handles errors in connected users count" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      # Mock failing user manager
      expect(CryptoExchange.Trading.UserManager, :list_connected_users, fn ->
        raise RuntimeError, "User manager error"
      end)
      
      expect(CryptoExchange.PublicStreams.StreamManager, :list_streams, fn ->
        []
      end)
      
      assert {:ok, status} = Application.health_check()
      assert status.connected_users == 0
      assert status.active_streams == 0
      
      Supervisor.stop(supervisor_pid, :normal)
    end

    test "returns error when supervisor is not running" do
      # Make sure supervisor is not running
      supervisor_pid = Process.whereis(CryptoExchange.Supervisor)
      if supervisor_pid && Process.alive?(supervisor_pid) do
        Supervisor.stop(supervisor_pid, :normal)
        :timer.sleep(100)
      end
      
      assert {:error, :supervisor_not_running} = Application.health_check()
    end
  end

  describe "Application.supervision_info/0" do
    test "returns detailed supervision information" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      expect(CryptoExchange.Trading.UserManager, :list_connected_users, fn ->
        ["user1"]
      end)
      
      expect(CryptoExchange.PublicStreams.StreamManager, :list_streams, fn ->
        [%{symbol: "ETHUSDT", type: :trades}]
      end)
      
      assert {:ok, info} = Application.supervision_info()
      
      assert info.application == :crypto_exchange
      assert info.supervisor == CryptoExchange.Supervisor
      assert info.strategy == :one_for_one
      assert is_list(info.children)
      
      # Verify metrics
      metrics = info.metrics
      assert metrics.connected_users == 1
      assert metrics.active_streams == 1
      assert is_integer(metrics.uptime_seconds)
      assert metrics.uptime_seconds >= 0
      
      Supervisor.stop(supervisor_pid, :normal)
    end

    test "propagates health check errors" do
      # Make sure supervisor is not running
      supervisor_pid = Process.whereis(CryptoExchange.Supervisor)
      if supervisor_pid && Process.alive?(supervisor_pid) do
        Supervisor.stop(supervisor_pid, :normal)
        :timer.sleep(100)
      end
      
      assert {:error, :supervisor_not_running} = Application.supervision_info()
    end
  end

  describe "fault tolerance" do
    test "supervisor restarts failed children" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      # Get registry process
      children = Supervisor.which_children(supervisor_pid)
      {_, registry_pid, _, _} = 
        Enum.find(children, fn {id, _pid, _type, _modules} -> id == Registry end)
      
      original_pid = registry_pid
      
      # Kill registry
      Process.exit(registry_pid, :kill)
      
      # Wait for supervisor to restart it
      :timer.sleep(200)
      
      # Verify registry was restarted
      new_children = Supervisor.which_children(supervisor_pid)
      {_, new_registry_pid, _, _} = 
        Enum.find(new_children, fn {id, _pid, _type, _modules} -> id == Registry end)
      
      assert new_registry_pid != original_pid
      assert Process.alive?(new_registry_pid)
      
      Supervisor.stop(supervisor_pid, :normal)
    end

    test "supervisor handles multiple child failures" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      children = Supervisor.which_children(supervisor_pid)
      
      # Kill multiple children
      processes_to_kill = Enum.take(children, 3)
      original_pids = Enum.map(processes_to_kill, fn {_id, pid, _type, _modules} -> pid end)
      
      Enum.each(original_pids, fn pid ->
        if is_pid(pid), do: Process.exit(pid, :kill)
      end)
      
      # Wait for restarts
      :timer.sleep(300)
      
      # Verify all are alive again
      new_children = Supervisor.which_children(supervisor_pid)
      alive_children = Enum.filter(new_children, fn {_id, pid, _type, _modules} ->
        is_pid(pid) and Process.alive?(pid)
      end)
      
      # Should have at least as many children as we started with
      assert length(alive_children) >= length(children)
      
      Supervisor.stop(supervisor_pid, :normal)
    end
  end

  describe "process registration" do
    test "registry is properly configured and accessible" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      # Test registry functionality
      test_key = {:test_process, self()}
      assert {:ok, _} = Registry.register(CryptoExchange.Registry, test_key, :test_value)
      
      # Verify registration
      assert [{pid, :test_value}] = Registry.lookup(CryptoExchange.Registry, test_key)
      assert pid == self()
      
      Supervisor.stop(supervisor_pid, :normal)
    end

    test "pubsub is properly configured and accessible" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      # Test PubSub functionality
      topic = "test_topic_#{:rand.uniform(1000)}"
      assert :ok = Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)
      
      # Publish message
      message = {:test_message, System.monotonic_time()}
      assert :ok = Phoenix.PubSub.broadcast(CryptoExchange.PubSub, topic, message)
      
      # Verify message received
      assert_receive ^message, 1000
      
      Supervisor.stop(supervisor_pid, :normal)
    end
  end

  describe "initialization logging" do
    test "logs supervision tree information on start" do
      log = capture_log(fn ->
        assert {:ok, supervisor_pid} = Application.start(:normal, [])
        Supervisor.stop(supervisor_pid, :normal)
      end)
      
      assert log =~ "Starting CryptoExchange application"
      assert log =~ "CryptoExchange application started successfully"
      assert log =~ "CryptoExchange enhanced supervision tree"
      assert log =~ "Registry"
      assert log =~ "Phoenix.PubSub"
      assert log =~ "ConnectionManager"
      assert log =~ "Comprehensive Fault Tolerance Features"
    end

    test "logs configuration validation errors" do
      # Mock config validation failure
      expect(CryptoExchange.Config, :validate, fn ->
        raise ArgumentError, "Test configuration error"
      end)
      
      log = capture_log(fn ->
        assert {:error, _} = Application.start(:normal, [])
      end)
      
      assert log =~ "Configuration validation failed"
      assert log =~ "Test configuration error"
    end

    test "logs stop and prep_stop messages" do
      assert {:ok, supervisor_pid} = Application.start(:normal, [])
      
      expect(CryptoExchange.Trading.UserManager, :list_connected_users, fn -> [] end)
      
      log = capture_log(fn ->
        _ = Application.prep_stop(%{})
        _ = Application.stop([])
      end)
      
      assert log =~ "Preparing to stop CryptoExchange application"
      assert log =~ "Disconnecting 0 users before shutdown"
      assert log =~ "Stopping CryptoExchange application"
      
      Supervisor.stop(supervisor_pid, :normal)
    end
  end
end