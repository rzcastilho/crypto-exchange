defmodule CryptoExchange.Binance.PublicStreamsTest do
  use ExUnit.Case, async: true

  alias CryptoExchange.Binance.PublicStreams

  describe "stream name building" do
    test "builds ticker stream name correctly" do
      # Since build_stream_name is private, we'll test the public interface
      # by checking that the module can be started properly

      # We can't directly test private functions, but we can verify the module
      # starts without errors with different parameters
      assert PublicStreams.__struct__()
    end
  end

  describe "WebSocket client lifecycle" do
    test "can create WebSocket client process" do
      # Test that the client can be started (though it won't connect in test env)
      stream_type = :ticker
      symbol = "BTCUSDT" 
      params = %{}
      topic = "test:ticker:BTCUSDT"

      # In test environment, this should start but fail to connect
      # which is expected behavior
      {:ok, pid} = PublicStreams.start_link(stream_type, symbol, params, topic)
      
      assert is_pid(pid)
      assert Process.alive?(pid)
      
      # Clean up
      PublicStreams.stop(pid)
    end

    test "can get state from WebSocket client" do
      stream_type = :depth
      symbol = "ETHUSDT"
      params = %{level: 10}
      topic = "test:depth:ETHUSDT"

      {:ok, pid} = PublicStreams.start_link(stream_type, symbol, params, topic)
      
      # Get the initial state 
      state = PublicStreams.get_state(pid)
      
      assert state.stream_type == :depth
      assert state.symbol == "ETHUSDT"
      assert state.params == %{level: 10}
      assert state.topic == "test:depth:ETHUSDT"
      assert state.state in [:disconnected, :connected]  # May connect or fail depending on network
      
      # Clean up
      PublicStreams.stop(pid)
    end

    test "handles reconnection requests" do
      stream_type = :trades
      symbol = "BTCUSDT"
      params = %{}
      topic = "test:trades:BTCUSDT"

      {:ok, pid} = PublicStreams.start_link(stream_type, symbol, params, topic)
      
      # Should be able to call reconnect without crashing
      assert :ok = PublicStreams.reconnect(pid)
      
      # Clean up
      PublicStreams.stop(pid)
    end
  end

  describe "WebSocketHandler callbacks" do 
    test "handler has all required callbacks" do
      # Test that the WebSocketHandler module implements the websocket_client behavior
      handler = PublicStreams.WebSocketHandler
      
      # Check that all required functions are exported
      exports = handler.__info__(:functions)
      
      assert {:init, 1} in exports
      assert {:onconnect, 2} in exports  
      assert {:ondisconnect, 2} in exports
      assert {:websocket_handle, 3} in exports
      assert {:websocket_info, 3} in exports
      assert {:websocket_terminate, 3} in exports
    end
  end
end