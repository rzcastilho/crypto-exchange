defmodule CryptoExchange.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :crypto_exchange,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "CryptoExchange",
      source_url: "https://github.com/rzcastilho/crypto-exchange"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CryptoExchange.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.4.0"},
      {:websocket_client, "~> 1.5"},
      
      # Development and testing dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  defp description do
    """
    A lightweight Elixir/OTP library for Binance cryptocurrency exchange integration 
    with dual-stream architecture for public data streaming and private user trading operations.
    """
  end

  defp package do
    [
      name: "crypto_exchange",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/rzcastilho/crypto-exchange"},
      maintainers: ["Your Name"]
    ]
  end

  defp docs do
    [
      main: "CryptoExchange",
      extras: ["README.md", "SPECIFICATION.md"]
    ]
  end
end