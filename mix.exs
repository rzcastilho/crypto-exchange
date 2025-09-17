defmodule CryptoExchange.MixProject do
  use Mix.Project

  def project do
    [
      app: :crypto_exchange,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:websockex, "~> 0.4.3"},
      {:decimal, "~> 2.0"}
    ]
  end
end
