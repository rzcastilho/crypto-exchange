defmodule CryptoExchange.TestHelpers do
  @moduledoc """
  General test helpers for the CryptoExchange test suite.
  Common utilities that don't fit into specialized helper modules.
  """
  
  import ExUnit.Assertions
  import ExUnit.Callbacks

  @doc """
  Sets up the test environment with necessary configurations.
  """
  def setup_test_environment do
    # Configure test environment
    Application.put_env(:crypto_exchange, :environment, :test)
    Application.put_env(:crypto_exchange, :binance_api_url, "https://api.binance.com")
    Application.put_env(:crypto_exchange, :binance_ws_url, "wss://stream.binance.com:9443")
    
    # Disable external HTTP requests in tests by default
    Application.put_env(:crypto_exchange, :http_client, HTTPoisonMock)
    Application.put_env(:crypto_exchange, :websocket_client, WebSocketMock)
    :ok
  end

  @doc """
  Sets up common mocks for tests.
  """
  def setup_mocks do
    # Define all mocks (skip if already defined)
    unless Code.ensure_loaded?(HTTPoisonMock) do
      Mox.defmock(HTTPoisonMock, for: CryptoExchange.Behaviours.HTTPClientBehaviour)
    end
    
    unless Code.ensure_loaded?(WebSocketMock) do
      Mox.defmock(WebSocketMock, for: CryptoExchange.Behaviours.WebSocketClientBehaviour)
    end
    
    unless Code.ensure_loaded?(BinanceMock) do
      Mox.defmock(BinanceMock, for: CryptoExchange.Behaviours.BinanceAPIBehaviour)
    end
    
    # Set global mode for all mocks
    Mox.set_mox_global()
    
    :ok
  rescue
    # Mock may already be defined in some cases
    ArgumentError -> :ok
  end

  @doc """
  Verifies that all mocks have been called as expected.
  """
  def verify_mocks! do
    Mox.verify!()
  end

  @doc """
  Waits for a GenServer to be in a specific state.
  Useful for testing GenServer lifecycle and state management.
  """
  def wait_for_genserver_state(pid, expected_state, timeout \\ 5000) do
    wait_for_genserver_state_with_timeout(pid, expected_state, timeout)
  end

  defp wait_for_genserver_state_with_timeout(pid, expected_state, timeout) when timeout > 0 do
    case GenServer.call(pid, :get_state) do
      ^expected_state -> :ok
      _ -> 
        :timer.sleep(50)
        wait_for_genserver_state_with_timeout(pid, expected_state, timeout - 50)
    end
  catch
    :exit, _ -> {:error, :process_not_alive}
  end

  defp wait_for_genserver_state_with_timeout(_pid, _expected_state, _timeout), do: {:error, :timeout}

  @doc """
  Waits for a process to be registered under a given name.
  """
  def wait_for_process(name, timeout \\ 5000)
  
  def wait_for_process(name, timeout) when timeout > 0 do
    case Process.whereis(name) do
      nil -> 
        :timer.sleep(50)
        wait_for_process(name, timeout - 50)
      pid when is_pid(pid) -> 
        {:ok, pid}
    end
  end

  def wait_for_process(_name, _timeout), do: {:error, :timeout}

  @doc """
  Creates a temporary process for testing purposes.
  The process will automatically exit when the test ends.
  """
  def spawn_test_process(test_pid \\ self()) do
    spawn_link(fn ->
      Process.flag(:trap_exit, true)
      receive do
        :stop -> :ok
        {:EXIT, ^test_pid, _reason} -> :ok
      end
    end)
  end

  @doc """
  Captures messages sent to the current process within a timeout.
  """
  def capture_messages(timeout \\ 1000) do
    capture_messages(timeout, [])
  end

  defp capture_messages(timeout, acc) do
    receive do
      message -> capture_messages(timeout, [message | acc])
    after
      timeout -> Enum.reverse(acc)
    end
  end

  @doc """
  Asserts that a message is received within a specific timeout.
  Similar to assert_receive but with more flexible matching.
  """
  def assert_message_received(pattern, timeout \\ 1000) do
    receive do
      message ->
        if match_pattern?(message, pattern) do
          message
        else
          flunk("Unexpected message received: #{inspect(message)}, expected: #{inspect(pattern)}")
        end
    after
      timeout ->
        flunk("No message matching #{inspect(pattern)} received within #{timeout}ms")
    end
  end

  defp match_pattern?(message, pattern) when is_function(pattern, 1) do
    pattern.(message)
  end

  defp match_pattern?(message, pattern) do
    message == pattern
  end

  @doc """
  Starts a supervised process for testing.
  The process will be properly stopped when the test ends.
  """
  def start_supervised_process(child_spec, opts \\ []) do
    case start_supervised(child_spec, opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Generates random test data for various purposes.
  """
  def random_string(length \\ 10) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64()
    |> String.slice(0, length)
  end

  def random_symbol do
    base = Enum.random(["BTC", "ETH", "BNB", "ADA", "DOT"])
    quote = Enum.random(["USDT", "BUSD", "BTC", "ETH"])
    "#{base}#{quote}"
  end

  def random_price(min \\ 0.00001, max \\ 100000.0) do
    min + :rand.uniform() * (max - min)
  end

  def random_quantity(min \\ 0.001, max \\ 100.0) do
    min + :rand.uniform() * (max - min)
  end
end