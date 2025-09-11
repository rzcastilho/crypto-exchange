defmodule CryptoExchange.TestSupport.WebSocketTestServer do
  @moduledoc """
  A test WebSocket server for mocking Binance WebSocket connections.
  Provides utilities for testing WebSocket behavior without external dependencies.
  """

  use GenServer
  require Logger

  defstruct [:socket, :test_pid, :messages, :connected]

  # =============================================================================
  # PUBLIC API
  # =============================================================================

  @doc """
  Starts a test WebSocket server that can simulate Binance WebSocket behavior.
  """
  def start_link(opts \\ []) do
    test_pid = Keyword.get(opts, :test_pid, self())
    GenServer.start_link(__MODULE__, %{test_pid: test_pid}, opts)
  end

  @doc """
  Simulates sending a message from the WebSocket server to connected clients.
  """
  def send_message(server, message) do
    GenServer.call(server, {:send_message, message})
  end

  @doc """
  Simulates a WebSocket connection event.
  """
  def simulate_connect(server) do
    GenServer.call(server, :simulate_connect)
  end

  @doc """
  Simulates a WebSocket disconnection event.
  """
  def simulate_disconnect(server, reason \\ :normal) do
    GenServer.call(server, {:simulate_disconnect, reason})
  end

  @doc """
  Gets all messages that were sent to the server.
  """
  def get_messages(server) do
    GenServer.call(server, :get_messages)
  end

  @doc """
  Clears all stored messages.
  """
  def clear_messages(server) do
    GenServer.call(server, :clear_messages)
  end

  # =============================================================================
  # GENSERVER CALLBACKS
  # =============================================================================

  @impl true
  def init(%{test_pid: test_pid}) do
    state = %__MODULE__{
      test_pid: test_pid,
      messages: [],
      connected: false
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    # Simulate sending message to connected client
    if state.connected do
      send(state.test_pid, {:websocket_message, message})
    end
    
    updated_state = %{state | messages: [message | state.messages]}
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(:simulate_connect, _from, state) do
    send(state.test_pid, {:websocket_connected, self()})
    updated_state = %{state | connected: true}
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:simulate_disconnect, reason}, _from, state) do
    send(state.test_pid, {:websocket_disconnected, reason})
    updated_state = %{state | connected: false}
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, Enum.reverse(state.messages), state}
  end

  @impl true
  def handle_call(:clear_messages, _from, state) do
    updated_state = %{state | messages: []}
    {:reply, :ok, updated_state}
  end

  # =============================================================================
  # MESSAGE SIMULATION HELPERS
  # =============================================================================

  @doc """
  Creates a simulated Binance ticker message.
  """
  def ticker_message(symbol, price \\ "50000.00") do
    %{
      "e" => "24hrTicker",
      "s" => symbol,
      "c" => price,
      "P" => "2.50",
      "h" => "51000.00",
      "l" => "48000.00",
      "v" => "1000.123"
    }
    |> Jason.encode!()
  end

  @doc """
  Creates a simulated Binance kline message.
  """
  def kline_message(symbol, interval \\ "1m") do
    %{
      "e" => "kline",
      "s" => symbol,
      "k" => %{
        "i" => interval,
        "o" => "49500.00",
        "h" => "50500.00",
        "l" => "49000.00",
        "c" => "50000.00",
        "v" => "100.123",
        "t" => 1234567890000,
        "T" => 1234567950000
      }
    }
    |> Jason.encode!()
  end

  @doc """
  Creates a simulated Binance depth message.
  """
  def depth_message(symbol) do
    %{
      "e" => "depthUpdate",
      "s" => symbol,
      "b" => [["49900.00", "1.000"], ["49800.00", "2.000"]],
      "a" => [["50100.00", "1.500"], ["50200.00", "0.800"]]
    }
    |> Jason.encode!()
  end

  @doc """
  Creates a simulated error message.
  """
  def error_message(code, msg) do
    %{
      "error" => %{
        "code" => code,
        "msg" => msg
      }
    }
    |> Jason.encode!()
  end

  @doc """
  Creates a simulated user data stream message.
  """
  def user_data_message(event_type, data \\ %{}) do
    base_message = %{
      "e" => event_type,
      "E" => System.system_time(:millisecond)
    }
    
    message = case event_type do
      "executionReport" ->
        Map.merge(base_message, %{
          "s" => "BTCUSDT",
          "c" => "test_client_order_id",
          "i" => 12345,
          "x" => "NEW",
          "X" => "NEW",
          "z" => "0.00000000",
          "p" => "50000.00000000",
          "q" => "0.00100000"
        })
      "outboundAccountPosition" ->
        Map.merge(base_message, %{
          "B" => [
            %{"a" => "BTC", "f" => "1.00000000", "l" => "0.00000000"}
          ]
        })
      _ ->
        Map.merge(base_message, data)
    end
    
    Jason.encode!(message)
  end
end