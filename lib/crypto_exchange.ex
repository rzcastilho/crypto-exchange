defmodule CryptoExchange do
  @moduledoc """
  CryptoExchange is a lightweight Elixir/OTP library for Binance cryptocurrency 
  exchange integration with dual-stream architecture.

  ## Overview

  The library provides two main capabilities:

  1. **Public Data Streaming**: Real-time market data (tickers, order books, trades) 
     distributed via Phoenix.PubSub without authentication requirements.

  2. **Private User Trading**: Secure user trading operations with isolated user 
     sessions for placing orders, checking balances, and managing accounts.

  ## Architecture

  The system follows a clean separation of concerns:

  - `CryptoExchange.API` - Main public interface
  - `CryptoExchange.PublicStreams` - Market data streaming
  - `CryptoExchange.Trading` - User trading operations  
  - `CryptoExchange.Binance` - Exchange adapter implementation

  ## Usage

  ### Public Market Data

      # Subscribe to ticker updates
      {:ok, topic} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")
      Phoenix.PubSub.subscribe(CryptoExchange.PubSub, topic)

      # Listen for updates
      receive do
        {:market_data, %{type: :ticker, symbol: "BTCUSDT", data: data}} ->
          IO.puts("BTC Price: \#{data.price}")
      end

  ### User Trading

      # Connect user with Binance credentials
      {:ok, _pid} = CryptoExchange.API.connect_user("user1", api_key, secret_key)

      # Place a limit order
      {:ok, order} = CryptoExchange.API.place_order("user1", %{
        symbol: "BTCUSDT",
        side: "BUY", 
        type: "LIMIT",
        quantity: "0.001",
        price: "50000"
      })

  ## Configuration

  Add to your config files:

      config :crypto_exchange,
        binance_ws_url: "wss://stream.binance.com:9443/ws",
        binance_api_url: "https://api.binance.com"

  """

  @doc """
  Returns the version of the CryptoExchange library.
  """
  def version, do: Application.spec(:crypto_exchange)[:vsn] |> to_string()

  @doc """
  Returns the current status of the CryptoExchange application.
  """
  def status do
    case Application.ensure_all_started(:crypto_exchange) do
      {:ok, _} -> :running
      {:error, reason} -> {:error, reason}
    end
  end
end