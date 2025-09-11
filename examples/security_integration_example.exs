#!/usr/bin/env elixir

# CryptoExchange Security Integration Example
# This example demonstrates all the advanced security features implemented
# in the enhanced credential management system.

Mix.install([
  {:crypto_exchange, path: "."}
])

defmodule SecurityIntegrationExample do
  @moduledoc """
  Comprehensive example demonstrating all security features of CryptoExchange.
  
  This example shows how to:
  1. Set up environment variable credentials
  2. Configure security monitoring
  3. Use credential safe logging
  4. Implement secure memory management
  5. Monitor compliance and security metrics
  6. Handle security incidents
  7. Perform security audits
  """
  
  require Logger
  
  def run_complete_security_demo do
    IO.puts """
    
    ═══════════════════════════════════════════════════════════════
                     CryptoExchange Security Demo
    ═══════════════════════════════════════════════════════════════
    
    This demo showcases the comprehensive security features:
    • Environment variable credential management
    • Zero-credential logging system
    • Secure memory management
    • Real-time security monitoring
    • Compliance checking and reporting
    • Security incident response
    • Credential lifecycle management
    
    """
    
    # Step 1: Start the application with security components
    start_security_components()
    
    # Step 2: Set up environment credentials (simulated)
    setup_environment_credentials()
    
    # Step 3: Demonstrate credential management
    demonstrate_credential_management()
    
    # Step 4: Show safe logging in action
    demonstrate_safe_logging()
    
    # Step 5: Demonstrate secure memory management
    demonstrate_secure_memory()
    
    # Step 6: Show security monitoring
    demonstrate_security_monitoring()
    
    # Step 7: Perform compliance checks
    demonstrate_compliance_checking()
    
    # Step 8: Simulate security incident response
    demonstrate_incident_response()
    
    # Step 9: Generate security reports
    generate_security_reports()
    
    IO.puts """
    
    ═══════════════════════════════════════════════════════════════
                        Demo Complete!
    ═══════════════════════════════════════════════════════════════
    
    The demo has shown all major security features in action.
    Check the logs above to see how credentials are protected
    and security events are monitored without exposing sensitive data.
    
    """
  end
  
  defp start_security_components do
    IO.puts "\n🔐 Step 1: Starting Security Components"
    IO.puts "─────────────────────────────────────────"
    
    # In a real application, these would be started by the Application supervisor
    # For this demo, we'll simulate their availability
    
    # Start credential safe logger
    {:ok, _} = CryptoExchange.Trading.CredentialSafeLogger.start_link([
      mode: :strict,
      audit_enabled: true,
      performance_monitoring: true
    ])
    
    # Start security compliance monitor  
    {:ok, _} = CryptoExchange.Trading.SecurityComplianceMonitor.start_link()
    
    # Start secure memory manager
    {:ok, _} = CryptoExchange.Trading.SecureMemoryManager.start_link([
      default_security_level: :high,
      audit_enabled: true
    ])
    
    # Start user security auditor
    {:ok, _} = CryptoExchange.Trading.UserSecurityAuditor.start_link()
    
    IO.puts "✅ All security components started successfully"
    Process.sleep(1000)
  end
  
  defp setup_environment_credentials do
    IO.puts "\n🌍 Step 2: Setting Up Environment Credentials"
    IO.puts "────────────────────────────────────────────"
    
    # Simulate environment variables (in production these would be real env vars)
    fake_api_key = generate_fake_api_key()
    fake_secret_key = generate_fake_secret_key()
    
    # In a real application, you would set these as environment variables:
    # System.put_env("BINANCE_API_KEY", fake_api_key)
    # System.put_env("BINANCE_SECRET_KEY", fake_secret_key)
    
    IO.puts "✅ Environment credentials configured"
    IO.puts "   • API Key length: #{String.length(fake_api_key)} characters"
    IO.puts "   • Secret Key length: #{String.length(fake_secret_key)} characters"
    IO.puts "   • Pattern: Single-user deployment"
    
    Process.sleep(500)
  end
  
  defp demonstrate_credential_management do
    IO.puts "\n🔑 Step 3: Credential Management Demo"
    IO.puts "───────────────────────────────────────"
    
    # Generate demo credentials
    api_key = generate_fake_api_key()
    secret_key = generate_fake_secret_key()
    user_id = "demo_user_#{:rand.uniform(1000)}"
    
    # Start credential manager with explicit credentials
    {:ok, _pid} = CryptoExchange.Trading.CredentialManager.start_link({
      :user_id, user_id,
      :api_key, api_key,
      :secret_key, secret_key
    })
    
    IO.puts "✅ Credential manager started for user: #{user_id}"
    
    # Demonstrate credential operations
    {:ok, retrieved_api_key} = CryptoExchange.Trading.CredentialManager.get_api_key(user_id)
    IO.puts "✅ API key retrieved successfully (length: #{String.length(retrieved_api_key)})"
    
    # Generate a signature
    query_string = "symbol=BTCUSDT&side=BUY&type=LIMIT&quantity=0.001&timestamp=#{System.system_time(:millisecond)}"
    {:ok, signature} = CryptoExchange.Trading.CredentialManager.sign_request(user_id, query_string)
    IO.puts "✅ Request signature generated (length: #{String.length(signature)})"
    
    # Check credential health
    {:ok, health} = CryptoExchange.Trading.CredentialManager.check_credential_health(user_id)
    IO.puts "✅ Credential health check: #{health.overall_status}"
    
    # Get security status
    {:ok, security_status} = CryptoExchange.Trading.CredentialManager.get_security_status(user_id)
    IO.puts "✅ Security level: #{security_status.security_level}"
    IO.puts "✅ Compliance score: #{security_status.compliance_score}%"
    
    Process.sleep(1000)
  end
  
  defp demonstrate_safe_logging do
    IO.puts "\n📝 Step 4: Safe Logging Demo"
    IO.puts "──────────────────────────────"
    
    # Configure the safe logger
    :ok = CryptoExchange.Trading.CredentialSafeLogger.configure([
      mode: :strict,
      audit_enabled: true
    ])
    
    # Demonstrate logging with credentials (they should be filtered)
    fake_api_key = generate_fake_api_key()
    fake_secret = generate_fake_secret_key()
    
    IO.puts "\n📍 Attempting to log sensitive data..."
    
    # This will be filtered automatically
    CryptoExchange.Trading.CredentialSafeLogger.info(
      "User authentication attempt", 
      user_id: "test_user",
      api_key: fake_api_key,
      secret: fake_secret,
      bearer_token: "Bearer abc123def456",
      status: "success"
    )
    
    # Check if content contains credentials
    test_content = "API key: #{fake_api_key} and secret: #{fake_secret}"
    contains_creds = CryptoExchange.Trading.CredentialSafeLogger.contains_credentials?(test_content)
    IO.puts "✅ Credential detection working: #{contains_creds}"
    
    # Sanitize content
    {:ok, sanitized} = CryptoExchange.Trading.CredentialSafeLogger.sanitize(test_content)
    IO.puts "✅ Content sanitized: #{String.slice(sanitized, 0, 50)}..."
    
    # Get filtering statistics
    {:ok, stats} = CryptoExchange.Trading.CredentialSafeLogger.get_filter_stats()
    IO.puts "✅ Logs processed: #{stats.total_logs_processed}"
    IO.puts "✅ Credentials filtered: #{stats.total_credentials_filtered}"
    IO.puts "✅ Filter rate: #{Float.round(stats.filter_rate, 2)}%"
    
    Process.sleep(1000)
  end
  
  defp demonstrate_secure_memory do
    IO.puts "\n🧠 Step 5: Secure Memory Management Demo"
    IO.puts "───────────────────────────────────────────"
    
    # Create a secure memory region
    {:ok, region_id} = CryptoExchange.Trading.SecureMemoryManager.create_secure_region([
      security_level: :high,
      encryption_enabled: true,
      audit_enabled: true
    ])
    
    IO.puts "✅ Secure memory region created: #{region_id}"
    
    # Store sensitive data
    sensitive_data = generate_fake_secret_key()
    {:ok, handle} = CryptoExchange.Trading.SecureMemoryManager.store_secure(region_id, sensitive_data)
    IO.puts "✅ Sensitive data stored securely with handle: #{String.slice(handle, 0, 20)}..."
    
    # Retrieve the data
    {:ok, retrieved_data} = CryptoExchange.Trading.SecureMemoryManager.retrieve_secure(handle)
    data_matches = retrieved_data == sensitive_data
    IO.puts "✅ Data retrieved successfully, integrity: #{data_matches}"
    
    # Get memory statistics
    {:ok, stats} = CryptoExchange.Trading.SecureMemoryManager.get_memory_stats()
    IO.puts "✅ Total regions: #{stats.total_regions}"
    IO.puts "✅ Total handles: #{stats.total_handles}"
    IO.puts "✅ Memory used: #{stats.total_memory_used} bytes"
    
    # Perform health check
    {:ok, health} = CryptoExchange.Trading.SecureMemoryManager.health_check()
    IO.puts "✅ Memory health: #{health.overall_health}"
    
    # Securely clear the data
    :ok = CryptoExchange.Trading.SecureMemoryManager.secure_clear(handle)
    IO.puts "✅ Sensitive data securely cleared"
    
    Process.sleep(1000)
  end
  
  defp demonstrate_security_monitoring do
    IO.puts "\n🔍 Step 6: Security Monitoring Demo"
    IO.puts "──────────────────────────────────────"
    
    # Get current security score
    {:ok, score} = CryptoExchange.Trading.SecurityComplianceMonitor.get_security_score()
    IO.puts "✅ Overall security score: #{score.overall_score}/100"
    IO.puts "✅ Risk level: #{score.risk_level}"
    
    # Get security metrics
    {:ok, metrics} = CryptoExchange.Trading.SecurityComplianceMonitor.get_security_metrics()
    IO.puts "✅ Active sessions: #{metrics.active_sessions}"
    IO.puts "✅ Security events (24h): #{metrics.security_events_24h}"
    
    # Report a security violation (for demo purposes)
    CryptoExchange.Trading.SecurityComplianceMonitor.report_violation(
      "demo_user",
      :weak_credential,
      %{details: "Demo violation for testing", severity: :medium}
    )
    
    IO.puts "✅ Security violation reported (demo)"
    
    # Get active alerts
    {:ok, alerts} = CryptoExchange.Trading.SecurityComplianceMonitor.get_active_alerts()
    IO.puts "✅ Active alerts: #{length(alerts)}"
    
    Process.sleep(1000)
  end
  
  defp demonstrate_compliance_checking do
    IO.puts "\n📋 Step 7: Compliance Checking Demo"
    IO.puts "──────────────────────────────────────"
    
    # Run a comprehensive compliance check
    {:ok, report} = CryptoExchange.Trading.SecurityComplianceMonitor.run_compliance_check()
    IO.puts "✅ Compliance check completed"
    IO.puts "✅ Overall status: #{report.overall_status}"
    IO.puts "✅ Violations found: #{report.violations_found}"
    IO.puts "✅ Duration: #{report.duration_ms}ms"
    
    # Check specific compliance standards
    standards = [:sox, :pci_dss, :gdpr, :iso_27001]
    
    Enum.each(standards, fn standard ->
      {:ok, status} = CryptoExchange.Trading.SecurityComplianceMonitor.get_compliance_status(standard)
      IO.puts "✅ #{String.upcase(Atom.to_string(standard))} compliance: #{status.status}"
    end)
    
    Process.sleep(1000)
  end
  
  defp demonstrate_incident_response do
    IO.puts "\n🚨 Step 8: Security Incident Response Demo"
    IO.puts "─────────────────────────────────────────────"
    
    # Simulate a security incident
    CryptoExchange.Trading.SecurityComplianceMonitor.report_incident(
      "demo_user",
      :credential_compromise,
      :high,
      %{
        source: "demo_simulation",
        attack_vector: "simulated_phishing",
        affected_systems: ["credential_manager"],
        timestamp: System.system_time(:millisecond)
      }
    )
    
    IO.puts "✅ Security incident reported (simulated)"
    
    # Check active alerts after incident
    Process.sleep(100)  # Allow incident processing
    {:ok, alerts} = CryptoExchange.Trading.SecurityComplianceMonitor.get_active_alerts()
    IO.puts "✅ Alerts generated: #{length(alerts)}"
    
    if not Enum.empty?(alerts) do
      alert = List.first(alerts)
      IO.puts "✅ Alert type: #{alert.type}"
      
      # Acknowledge the alert
      if Map.has_key?(alert, :id) do
        :ok = CryptoExchange.Trading.SecurityComplianceMonitor.acknowledge_alert(
          alert.id, 
          "security_demo_team"
        )
        IO.puts "✅ Alert acknowledged by demo team"
      end
    end
    
    Process.sleep(1000)
  end
  
  defp generate_security_reports do
    IO.puts "\n📊 Step 9: Security Reporting Demo"
    IO.puts "─────────────────────────────────────"
    
    # Generate comprehensive compliance report
    {:ok, report} = CryptoExchange.Trading.SecurityComplianceMonitor.generate_compliance_report([
      period: :current,
      include_recommendations: true
    ])
    
    IO.puts "✅ Compliance report generated"
    IO.puts "✅ Security score: #{report.security_score.overall_score}/100"
    IO.puts "✅ Recent violations: #{length(report.recent_violations)}"
    IO.puts "✅ Recent incidents: #{length(report.recent_incidents)}"
    IO.puts "✅ Active alerts: #{length(report.active_alerts)}"
    
    # Get audit summary
    {:ok, audit_summary} = CryptoExchange.Trading.UserSecurityAuditor.get_security_summary()
    IO.puts "✅ Total audit events: #{audit_summary.total_events}"
    IO.puts "✅ Security health score: #{audit_summary.security_health_score}/100"
    
    # Get memory audit
    {:ok, memory_audit} = CryptoExchange.Trading.SecureMemoryManager.get_security_audit()
    IO.puts "✅ Memory security posture: #{memory_audit.security_posture}"
    IO.puts "✅ Encryption status: #{memory_audit.encryption_status.all_regions_encrypted}"
    
    # Get logging statistics
    {:ok, logging_stats} = CryptoExchange.Trading.CredentialSafeLogger.get_filter_stats()
    IO.puts "✅ Logging filter rate: #{Float.round(logging_stats.filter_rate, 2)}%"
    IO.puts "✅ Avg processing time: #{Float.round(logging_stats.average_processing_time_us, 2)}μs"
    
    Process.sleep(1000)
  end
  
  # Helper functions for generating fake credentials (for demo purposes only)
  
  defp generate_fake_api_key do
    # Generate a 64-character alphanumeric string that looks like a Binance API key
    1..64
    |> Enum.map(fn _ -> 
      chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      Enum.at(chars, :rand.uniform(length(chars)) - 1)
    end)
    |> List.to_string()
  end
  
  defp generate_fake_secret_key do
    # Generate a 64-character secret key
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end
end

# Run the demo if this file is executed directly
if __ENV__.file == System.argv() |> List.first() do
  SecurityIntegrationExample.run_complete_security_demo()
end