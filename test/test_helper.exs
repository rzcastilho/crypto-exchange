# Test helper configuration for CryptoExchange

# Configure logging for tests
import ExUnit.CaptureLog

# Configure Mox for mocking
import Mox
import Hammox

# Set up property-based testing
import StreamData

# Set up test environment
CryptoExchange.TestSupport.TestConfig.setup_test_env()

# Start the PubSub system for testing
{:ok, _} = Application.ensure_all_started(:crypto_exchange)

# Configure ExUnit with async capabilities and proper timeout
ExUnit.start(
  capture_log: true,
  assert_receive_timeout: 1000,
  max_failures: 5,
  exclude: [
    :integration,
    :slow,
    :performance
  ]
)

# Configure timeout for tests
ExUnit.configure(timeout: 30_000)

# Define mocks that need to be available globally
Mox.defmock(HTTPoisonMock, for: CryptoExchange.Behaviours.HTTPClientBehaviour)
Mox.defmock(WebSocketMock, for: CryptoExchange.Behaviours.WebSocketClientBehaviour)
Mox.defmock(BinanceMock, for: CryptoExchange.Behaviours.BinanceAPIBehaviour)

# Allow mocks to be used in asynchronous tests
Mox.set_mox_private()