defmodule CryptoExchange.Application do
  @moduledoc """
  The CryptoExchange Application.

  This module starts the supervision tree for the CryptoExchange application,
  following OTP best practices for fault tolerance and system reliability.

  ## Supervision Tree Structure

  ```
  CryptoExchange.Application
  ├── Registry (CryptoExchange.Registry)
  ├── Phoenix.PubSub (CryptoExchange.PubSub)
  ├── PublicStreams.StreamManager
  └── Trading.UserManager (DynamicSupervisor)
      └── UserConnection (per user)
  ```

  ## Design Decisions

  - **Registry**: Enables process discovery and registration across the system
  - **Phoenix.PubSub**: Provides pub/sub messaging for market data distribution
  - **StreamManager**: GenServer managing public market data streams from exchanges
  - **UserManager**: DynamicSupervisor for isolated user trading connections

  ## Supervision Strategy

  Uses `:one_for_one` strategy where each child is restarted independently.
  This ensures that failure in one component (e.g., a user connection) doesn't
  affect other components (e.g., public data streams).

  ## Restart Strategies

  - **Registry & PubSub**: `:permanent` - critical infrastructure components
  - **StreamManager**: `:permanent` - core functionality for market data
  - **UserManager**: `:permanent` - supervisor must always be available
  - **UserConnections**: `:transient` - only restart on abnormal termination
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting CryptoExchange application")

    children = [
      # Registry for process registration and discovery
      # Restart: :permanent - critical infrastructure component
      %{
        id: Registry,
        start: {Registry, :start_link, [[keys: :unique, name: CryptoExchange.Registry]]},
        restart: :permanent,
        type: :worker
      },

      # Phoenix PubSub for broadcasting market data
      # Restart: :permanent - critical infrastructure component
      %{
        id: Phoenix.PubSub,
        start: {Phoenix.PubSub.Supervisor, :start_link, [[name: CryptoExchange.PubSub]]},
        restart: :permanent,
        type: :supervisor
      },

      # Public market data streaming manager
      # Restart: :permanent - core functionality, should always be available
      %{
        id: CryptoExchange.PublicStreams.StreamManager,
        start: {CryptoExchange.PublicStreams.StreamManager, :start_link, [[]]},
        restart: :permanent,
        type: :worker,
        shutdown: 5000
      },

      # Dynamic supervisor for user trading connections
      # Restart: :permanent - supervisor must always be available
      %{
        id: CryptoExchange.Trading.UserManager,
        start:
          {CryptoExchange.Trading.UserManager, :start_link,
           [[name: CryptoExchange.Trading.UserManager]]},
        restart: :permanent,
        type: :supervisor,
        shutdown: :infinity
      }
    ]

    opts = [
      strategy: :one_for_one,
      name: CryptoExchange.Supervisor,
      # Allow up to 3 restarts within 5 seconds before giving up
      max_restarts: 3,
      max_seconds: 5
    ]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("CryptoExchange application started successfully")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start CryptoExchange application: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping CryptoExchange application")
    :ok
  end
end
