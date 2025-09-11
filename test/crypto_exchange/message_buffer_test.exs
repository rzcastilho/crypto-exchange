defmodule CryptoExchange.MessageBufferTest do
  use ExUnit.Case, async: true
  
  alias CryptoExchange.MessageBuffer
  
  @moduletag :message_buffer
  
  describe "message buffering" do
    test "buffers messages and flushes on timer" do
      messages_received = []
      
      publisher = fn messages ->
        send(self(), {:batch_published, messages})
        :ok
      end
      
      config = %{
        buffer_size: 100,
        flush_interval: 50,  # 50ms
        batch_size: 10,
        strategy: :time
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Add some messages
      :ok = MessageBuffer.add_message(buffer, {:ticker, "BTCUSDT", %{price: 50000}})
      :ok = MessageBuffer.add_message(buffer, {:ticker, "ETHUSDT", %{price: 3000}})
      :ok = MessageBuffer.add_message(buffer, {:ticker, "ADAUSDT", %{price: 1.2}})
      
      # Should flush after timeout
      assert_receive {:batch_published, messages}, 100
      assert length(messages) == 3
      assert Enum.any?(messages, &match?({:ticker, "BTCUSDT", _}, &1))
      assert Enum.any?(messages, &match?({:ticker, "ETHUSDT", _}, &1))
      assert Enum.any?(messages, &match?({:ticker, "ADAUSDT", _}, &1))
    end
    
    test "flushes when batch size is reached" do
      publisher = fn messages ->
        send(self(), {:batch_published, messages})
        :ok
      end
      
      config = %{
        buffer_size: 100,
        flush_interval: 1000,  # Long interval
        batch_size: 3,         # Small batch size
        strategy: :size
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Add messages up to batch size
      :ok = MessageBuffer.add_message(buffer, {:msg, 1})
      :ok = MessageBuffer.add_message(buffer, {:msg, 2})
      :ok = MessageBuffer.add_message(buffer, {:msg, 3})  # Should trigger flush
      
      # Should flush immediately on size
      assert_receive {:batch_published, messages}, 100
      assert length(messages) == 3
    end
    
    test "hybrid strategy flushes on both size and time" do
      publisher = fn messages ->
        send(self(), {:batch_published, messages, System.monotonic_time(:millisecond)})
        :ok
      end
      
      config = %{
        buffer_size: 100,
        flush_interval: 100,   # 100ms
        batch_size: 5,
        strategy: :hybrid
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # First, test size-based flush
      Enum.each(1..5, fn i ->
        :ok = MessageBuffer.add_message(buffer, {:msg, i})
      end)
      
      # Should flush immediately on size
      assert_receive {:batch_published, messages1, _time1}, 50
      assert length(messages1) == 5
      
      # Then test time-based flush
      :ok = MessageBuffer.add_message(buffer, {:msg, 6})
      :ok = MessageBuffer.add_message(buffer, {:msg, 7})
      
      # Should flush after timeout
      assert_receive {:batch_published, messages2, _time2}, 150
      assert length(messages2) == 2
    end
    
    test "applies backpressure when buffer is nearly full" do
      publisher = fn _messages ->
        # Slow publisher - don't actually publish to fill buffer
        :ok
      end
      
      config = %{
        buffer_size: 10,
        flush_interval: 10000,  # Long interval to prevent flushing
        batch_size: 20,
        backpressure_threshold: 0.8,  # 80% full
        strategy: :size
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Fill buffer to 80% (8 messages)
      Enum.each(1..8, fn i ->
        assert :ok = MessageBuffer.add_message(buffer, {:msg, i})
      end)
      
      # Next message should trigger backpressure
      assert {:error, :buffer_full} = MessageBuffer.add_message(buffer, {:msg, 9})
      
      # Check stats
      stats = MessageBuffer.get_stats(buffer)
      assert stats.backpressure_count == 1
    end
    
    test "handles rate limiting" do
      publisher = fn messages ->
        send(self(), {:batch_published, messages})
        :ok
      end
      
      config = %{
        buffer_size: 100,
        flush_interval: 10,    # Very fast flush
        batch_size: 10,
        rate_limit: 20,        # 20 messages per second
        strategy: :time
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Add many messages quickly
      start_time = System.monotonic_time(:millisecond)
      Enum.each(1..50, fn i ->
        :ok = MessageBuffer.add_message(buffer, {:msg, i})
      end)
      
      # Should receive some batches but not exceed rate limit
      messages_received = []
      
      receive_loop = fn loop ->
        receive do
          {:batch_published, messages} ->
            loop.([messages | messages_received])
        after
          500 -> messages_received  # Stop after 500ms
        end
      end
      
      final_messages = receive_loop.(receive_loop)
      total_messages = final_messages |> List.flatten() |> length()
      
      # Should not exceed rate limit significantly
      elapsed_seconds = (System.monotonic_time(:millisecond) - start_time) / 1000
      actual_rate = total_messages / elapsed_seconds
      
      # Allow some tolerance for timing variations
      assert actual_rate <= config.rate_limit * 1.5
    end
    
    test "provides comprehensive statistics" do
      publisher = fn _messages -> :ok end
      
      config = %{
        buffer_size: 100,
        flush_interval: 50,
        batch_size: 10,
        strategy: :hybrid
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Add some messages
      Enum.each(1..15, fn i ->
        :ok = MessageBuffer.add_message(buffer, {:msg, i})
      end)
      
      # Force flush
      :ok = MessageBuffer.flush_now(buffer)
      
      # Get stats
      stats = MessageBuffer.get_stats(buffer)
      
      # Verify key metrics
      assert stats.messages_added == 15
      assert stats.messages_flushed >= 10  # At least one batch flushed
      assert stats.batches_sent >= 1
      assert stats.flush_manual_count == 1
      assert stats.buffer_utilization >= 0.0
      assert stats.messages_per_second >= 0.0
      assert stats.uptime_seconds >= 0
    end
    
    test "handles publisher failures gracefully" do
      failing_publisher = fn _messages ->
        raise "Publisher failed"
      end
      
      config = %{
        buffer_size: 10,
        flush_interval: 50,
        batch_size: 3,
        strategy: :size
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, failing_publisher)
      
      # Add messages to trigger flush
      :ok = MessageBuffer.add_message(buffer, {:msg, 1})
      :ok = MessageBuffer.add_message(buffer, {:msg, 2})
      :ok = MessageBuffer.add_message(buffer, {:msg, 3})
      
      # Should handle publisher failure and continue
      Process.sleep(100)
      
      # Buffer should still be responsive
      assert :ok = MessageBuffer.add_message(buffer, {:msg, 4})
      
      # Stats should reflect the error
      stats = MessageBuffer.get_stats(buffer)
      assert stats.messages_added == 4
    end
    
    test "updates configuration dynamically" do
      publisher = fn messages ->
        send(self(), {:batch_published, length(messages)})
        :ok
      end
      
      initial_config = %{
        buffer_size: 100,
        flush_interval: 1000,
        batch_size: 10,
        strategy: :time
      }
      
      {:ok, buffer} = MessageBuffer.start_link(initial_config, publisher)
      
      # Add some messages
      Enum.each(1..5, fn i ->
        :ok = MessageBuffer.add_message(buffer, {:msg, i})
      end)
      
      # Update config to smaller batch size and size strategy
      new_config = %{
        batch_size: 3,
        strategy: :size
      }
      
      :ok = MessageBuffer.update_config(buffer, new_config)
      
      # Add more messages to trigger new batch size
      :ok = MessageBuffer.add_message(buffer, {:msg, 6})
      :ok = MessageBuffer.add_message(buffer, {:msg, 7})
      :ok = MessageBuffer.add_message(buffer, {:msg, 8})
      
      # Should flush with new batch size
      assert_receive {:batch_published, batch_size}, 200
      assert batch_size <= 3  # Should respect new batch size
    end
    
    test "handles buffer overflow correctly" do
      publisher = fn _messages ->
        # Don't actually publish to cause overflow
        Process.sleep(1000)  # Slow publisher
        :ok
      end
      
      config = %{
        buffer_size: 5,        # Very small buffer
        flush_interval: 5000,  # Long interval
        batch_size: 10,
        backpressure_threshold: 1.0,  # No backpressure until full
        strategy: :time
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Fill buffer completely
      Enum.each(1..5, fn i ->
        assert :ok = MessageBuffer.add_message(buffer, {:msg, i})
      end)
      
      # Next message should fail
      assert {:error, :buffer_full} = MessageBuffer.add_message(buffer, {:msg, 6})
      
      # Stats should reflect buffer full condition
      stats = MessageBuffer.get_stats(buffer)
      assert stats.buffer_full_count == 1
      assert stats.buffer_utilization == 1.0
    end
    
    test "cleans up properly on termination" do
      messages_received = []
      
      publisher = fn messages ->
        send(self(), {:batch_published, messages})
        :ok
      end
      
      config = %{
        buffer_size: 100,
        flush_interval: 5000,  # Long interval
        batch_size: 10,
        strategy: :time
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Add messages
      :ok = MessageBuffer.add_message(buffer, {:msg, 1})
      :ok = MessageBuffer.add_message(buffer, {:msg, 2})
      :ok = MessageBuffer.add_message(buffer, {:msg, 3})
      
      # Stop the buffer
      GenServer.stop(buffer)
      
      # Should flush remaining messages on shutdown
      assert_receive {:batch_published, messages}, 200
      assert length(messages) == 3
    end
  end
  
  describe "performance characteristics" do
    @tag :performance
    test "handles high message throughput" do
      message_count = 10_000
      batch_sizes = []
      
      publisher = fn messages ->
        send(self(), {:batch_size, length(messages)})
        :ok
      end
      
      config = %{
        buffer_size: 5000,
        flush_interval: 100,
        batch_size: 500,
        rate_limit: 10_000,
        strategy: :hybrid
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Measure throughput
      start_time = System.monotonic_time(:millisecond)
      
      # Add messages as fast as possible
      Enum.each(1..message_count, fn i ->
        :ok = MessageBuffer.add_message(buffer, {:msg, i})
      end)
      
      add_time = System.monotonic_time(:millisecond)
      add_duration = add_time - start_time
      
      # Collect all published batches
      collect_batches = fn collect, acc ->
        receive do
          {:batch_size, size} -> collect.(collect, acc + size)
        after
          1000 -> acc  # Wait up to 1 second for final batches
        end
      end
      
      total_published = collect_batches.(collect_batches, 0)
      end_time = System.monotonic_time(:millisecond)
      
      total_duration = end_time - start_time
      
      # Verify performance characteristics
      add_rate = message_count / add_duration * 1000
      overall_rate = total_published / total_duration * 1000
      
      # Should be able to add messages very quickly
      assert add_rate > 50_000  # More than 50k messages/sec for adding
      
      # Should handle reasonable overall throughput
      assert overall_rate > 5_000  # More than 5k messages/sec overall
      
      # Should have published most or all messages
      assert total_published >= message_count * 0.9  # At least 90%
      
      # Get final stats
      stats = MessageBuffer.get_stats(buffer)
      assert stats.messages_added == message_count
      assert stats.messages_per_second > 1000
    end
    
    @tag :performance
    test "maintains low latency under normal load" do
      latencies = []
      
      publisher = fn messages ->
        # Record latency for each message
        current_time = System.monotonic_time(:microsecond)
        message_latencies = Enum.map(messages, fn {_type, _symbol, timestamp} ->
          current_time - timestamp
        end)
        send(self(), {:latencies, message_latencies})
        :ok
      end
      
      config = %{
        buffer_size: 1000,
        flush_interval: 10,  # Very fast flush
        batch_size: 50,
        strategy: :time
      }
      
      {:ok, buffer} = MessageBuffer.start_link(config, publisher)
      
      # Send messages with timestamps
      Enum.each(1..200, fn i ->
        timestamp = System.monotonic_time(:microsecond)
        :ok = MessageBuffer.add_message(buffer, {:msg, i, timestamp})
        
        # Small delay between messages to simulate realistic load
        if rem(i, 10) == 0, do: Process.sleep(1)
      end)
      
      # Collect latency measurements
      collect_latencies = fn collect, acc ->
        receive do
          {:latencies, batch_latencies} -> 
            collect.(collect, acc ++ batch_latencies)
        after
          500 -> acc
        end
      end
      
      all_latencies = collect_latencies.(collect_latencies, [])
      
      # Analyze latencies (convert to milliseconds)
      latencies_ms = Enum.map(all_latencies, fn us -> us / 1000 end)
      avg_latency = Enum.sum(latencies_ms) / length(latencies_ms)
      max_latency = Enum.max(latencies_ms)
      p95_latency = Enum.at(Enum.sort(latencies_ms), trunc(length(latencies_ms) * 0.95))
      
      # Verify low latency characteristics
      assert avg_latency < 50    # Average latency under 50ms
      assert max_latency < 200   # Max latency under 200ms
      assert p95_latency < 100   # 95th percentile under 100ms
      
      # Should have processed most messages
      assert length(all_latencies) > 150  # At least 75% of messages
    end
  end
end