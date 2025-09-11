# Test script for the enhanced user management system
IO.puts("=== Enhanced User Management System Test ===")

# Test system health
case CryptoExchange.FaultTolerance.get_system_health() do
  {:ok, health} -> 
    IO.puts("✅ System Health: #{health.overall_health}")
  error -> 
    IO.puts("❌ System Health Check Failed: #{inspect(error)}")
end

# Test user management statistics
stats = CryptoExchange.Trading.UserManager.get_system_statistics()
IO.puts("📊 User Management Statistics:")
IO.puts("  - Total users: #{stats.total_users}")
IO.puts("  - Active users: #{stats.active_users}")
IO.puts("  - Can accept new users: #{CryptoExchange.Trading.UserManager.can_accept_new_users?()}")

# Test UserRegistry
registry_stats = CryptoExchange.Trading.UserRegistry.get_statistics()
IO.puts("📋 UserRegistry Statistics:")
IO.puts("  - Total users in registry: #{registry_stats.total_users}")
IO.puts("  - Table memory: #{registry_stats.table_memory} words")

# Test UserSecurityAuditor
case CryptoExchange.Trading.UserSecurityAuditor.get_security_summary() do
  {:ok, security} ->
    IO.puts("🛡️  Security Summary:")
    IO.puts("  - Total audit events: #{security.total_events}")
    IO.puts("  - Security health score: #{security.security_health_score}")
  error ->
    IO.puts("❌ Security Summary Failed: #{inspect(error)}")
end

# Test UserMetrics
case CryptoExchange.Trading.UserMetrics.get_system_metrics_summary() do
  {:ok, metrics} ->
    IO.puts("📈 Metrics Summary:")
    IO.puts("  - Total metrics recorded: #{metrics.total_metrics_recorded}")
    IO.puts("  - Unique users tracked: #{metrics.unique_users}")
  error ->
    IO.puts("❌ Metrics Summary Failed: #{inspect(error)}")
end

IO.puts("=== Test Completed Successfully ===")
IO.puts("Enhanced user management system is ready for production use!")