defmodule CryptoExchange.Models.Balance do
  @moduledoc """
  Data model for representing account balances from Binance.

  This module handles parsing and representation of balance data returned
  from Binance account information endpoints. It provides a structured way
  to work with asset balances including available and locked amounts.

  ## Balance Structure

  Each balance contains:
  - **Asset**: The cryptocurrency symbol (e.g., "BTC", "ETH", "USDT")
  - **Free**: Available balance that can be used for trading
  - **Locked**: Balance that is currently locked in open orders

  Total balance = Free + Locked

  ## Usage Examples

  ```elixir
  # Parse balance from Binance API response
  binance_data = %{
    "asset" => "BTC",
    "free" => "0.50000000",
    "locked" => "0.10000000"
  }

  {:ok, balance} = Balance.parse(binance_data)
  # %Balance{
  #   asset: "BTC",
  #   free: Decimal.new("0.5"),
  #   locked: Decimal.new("0.1"),
  #   total: Decimal.new("0.6")
  # }

  # Get total balance
  total = Balance.total(balance)
  # Decimal.new("0.6")

  # Check if balance has available funds
  Balance.has_available_funds?(balance, Decimal.new("0.3"))
  # true (0.5 free > 0.3)

  # Convert to map
  balance_map = Balance.to_map(balance)
  ```

  ## Filtering and Utilities

  ```elixir
  # Filter out zero balances
  balances = [btc_balance, usdt_balance, eth_zero_balance]
  non_zero = Balance.filter_non_zero(balances)

  # Find specific asset balance
  btc_balance = Balance.find_by_asset(balances, "BTC")
  ```
  """

  alias CryptoExchange.Models.Balance

  @enforce_keys [:asset, :free, :locked]
  defstruct [:asset, :free, :locked, :total]

  @type t :: %Balance{
          asset: String.t(),
          free: Decimal.t(),
          locked: Decimal.t(),
          total: Decimal.t()
        }

  @doc """
  Parses balance data from Binance API response.

  ## Parameters
  - `data`: Map containing balance data from Binance API

  ## Returns
  - `{:ok, balance}` on successful parsing
  - `{:error, reason}` if parsing fails

  ## Example
  ```elixir
  binance_data = %{
    "asset" => "BTC",
    "free" => "0.50000000",
    "locked" => "0.10000000"
  }

  {:ok, balance} = Balance.parse(binance_data)
  ```
  """
  def parse(data) when is_map(data) do
    with {:ok, asset} <- extract_string(data, "asset"),
         {:ok, free} <- extract_decimal(data, "free"),
         {:ok, locked} <- extract_decimal(data, "locked") do
      total = Decimal.add(free, locked)

      balance = %Balance{
        asset: asset,
        free: free,
        locked: locked,
        total: total
      }

      {:ok, balance}
    else
      {:error, _reason} = error ->
        error
    end
  end

  def parse(_), do: {:error, :invalid_data_format}

  @doc """
  Parses a list of balances from Binance account response.

  ## Parameters
  - `balances_data`: List of balance maps from Binance API

  ## Returns
  - `{:ok, balances}` list of parsed Balance structs
  - `{:error, reason}` if any parsing fails

  ## Example
  ```elixir
  balances_data = [
    %{"asset" => "BTC", "free" => "0.5", "locked" => "0.1"},
    %{"asset" => "ETH", "free" => "10.0", "locked" => "2.0"},
    %{"asset" => "USDT", "free" => "1000.0", "locked" => "0.0"}
  ]

  {:ok, balances} = Balance.parse_list(balances_data)
  ```
  """
  def parse_list(balances_data) when is_list(balances_data) do
    balances_data
    |> Enum.with_index()
    |> Enum.reduce({:ok, []}, fn
      {balance_data, _index}, {:ok, acc} ->
        case parse(balance_data) do
          {:ok, balance} -> {:ok, [balance | acc]}
          {:error, reason} -> {:error, reason}
        end

      _item, error ->
        error
    end)
    |> case do
      {:ok, balances} -> {:ok, Enum.reverse(balances)}
      error -> error
    end
  end

  def parse_list(_), do: {:error, :invalid_balances_format}

  @doc """
  Converts a Balance struct to a map representation.

  ## Parameters
  - `balance`: Balance struct to convert

  ## Returns
  Map with balance data.

  ## Example
  ```elixir
  balance_map = Balance.to_map(balance)
  # %{
  #   asset: "BTC",
  #   free: "0.5",
  #   locked: "0.1",
  #   total: "0.6"
  # }
  ```
  """
  def to_map(%Balance{} = balance) do
    %{
      asset: balance.asset,
      free: to_string(balance.free),
      locked: to_string(balance.locked),
      total: to_string(balance.total)
    }
  end

  @doc """
  Calculates the total balance (free + locked).

  ## Parameters
  - `balance`: Balance struct

  ## Returns
  Decimal representing total balance.

  ## Example
  ```elixir
  total = Balance.total(balance)
  # Decimal.new("0.6")
  ```
  """
  def total(%Balance{total: total}), do: total

  @doc """
  Checks if the balance has sufficient available (free) funds.

  ## Parameters
  - `balance`: Balance struct
  - `required_amount`: Decimal amount needed

  ## Returns
  Boolean indicating if sufficient funds are available.

  ## Example
  ```elixir
  Balance.has_available_funds?(balance, Decimal.new("0.3"))
  # true if free balance >= 0.3
  ```
  """
  def has_available_funds?(%Balance{free: free}, required_amount) do
    Decimal.compare(free, required_amount) != :lt
  end

  @doc """
  Checks if the balance is effectively zero (both free and locked are zero).

  ## Parameters
  - `balance`: Balance struct

  ## Returns
  Boolean indicating if balance is zero.

  ## Example
  ```elixir
  Balance.zero?(balance)
  # true if both free and locked are 0
  ```
  """
  def zero?(%Balance{free: free, locked: locked}) do
    Decimal.equal?(free, 0) and Decimal.equal?(locked, 0)
  end

  @doc """
  Filters out zero balances from a list of balances.

  ## Parameters
  - `balances`: List of Balance structs

  ## Returns
  List of non-zero balances.

  ## Example
  ```elixir
  non_zero_balances = Balance.filter_non_zero(all_balances)
  ```
  """
  def filter_non_zero(balances) when is_list(balances) do
    Enum.reject(balances, &zero?/1)
  end

  @doc """
  Finds a balance for a specific asset.

  ## Parameters
  - `balances`: List of Balance structs
  - `asset`: Asset symbol to find (case-sensitive)

  ## Returns
  - `{:ok, balance}` if asset is found
  - `{:error, :not_found}` if asset is not found

  ## Example
  ```elixir
  {:ok, btc_balance} = Balance.find_by_asset(balances, "BTC")
  {:error, :not_found} = Balance.find_by_asset(balances, "XYZ")
  ```
  """
  def find_by_asset(balances, asset) when is_list(balances) and is_binary(asset) do
    case Enum.find(balances, fn %Balance{asset: balance_asset} -> balance_asset == asset end) do
      %Balance{} = balance -> {:ok, balance}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Groups balances by their status (zero vs non-zero).

  ## Parameters
  - `balances`: List of Balance structs

  ## Returns
  Map with `:zero` and `:non_zero` keys containing respective balance lists.

  ## Example
  ```elixir
  grouped = Balance.group_by_status(balances)
  # %{
  #   zero: [zero_balance1, zero_balance2],
  #   non_zero: [btc_balance, eth_balance]
  # }
  ```
  """
  def group_by_status(balances) when is_list(balances) do
    Enum.group_by(balances, fn balance ->
      if zero?(balance), do: :zero, else: :non_zero
    end)
    |> Map.put_new(:zero, [])
    |> Map.put_new(:non_zero, [])
  end

  @doc """
  Sorts balances by total value in descending order.

  ## Parameters
  - `balances`: List of Balance structs

  ## Returns
  List of balances sorted by total value (highest first).

  ## Example
  ```elixir
  sorted_balances = Balance.sort_by_total(balances)
  # [highest_balance, medium_balance, lowest_balance]
  ```
  """
  def sort_by_total(balances) when is_list(balances) do
    Enum.sort(balances, fn %Balance{total: total1}, %Balance{total: total2} ->
      Decimal.compare(total1, total2) == :gt
    end)
  end

  @doc """
  Validates balance data before parsing.

  ## Parameters
  - `data`: Raw balance data to validate

  ## Returns
  - `:ok` if data is valid
  - `{:error, reason}` if validation fails

  ## Example
  ```elixir
  :ok = Balance.validate(valid_balance_data)
  {:error, :missing_asset} = Balance.validate(%{"free" => "0.5"})
  ```
  """
  def validate(data) when is_map(data) do
    with {:ok, _asset} <- extract_string(data, "asset"),
         {:ok, _free} <- extract_decimal(data, "free"),
         {:ok, _locked} <- extract_decimal(data, "locked") do
      :ok
    else
      {:error, _reason} = error ->
        error
    end
  end

  def validate(_), do: {:error, :invalid_data_format}

  # Private Functions

  defp extract_string(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      nil -> {:error, {:missing_field, key}}
      _ -> {:error, {:invalid_field_type, key}}
    end
  end

  defp extract_decimal(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) ->
        case Decimal.parse(value) do
          {decimal, ""} -> {:ok, decimal}
          _ -> {:error, {:invalid_decimal, key}}
        end

      value when is_number(value) ->
        {:ok, Decimal.from_float(value)}

      nil ->
        {:error, {:missing_field, key}}

      _ ->
        {:error, {:invalid_field_type, key}}
    end
  end
end
