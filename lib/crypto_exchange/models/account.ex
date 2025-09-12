defmodule CryptoExchange.Models.Account do
  @moduledoc """
  Data model for representing complete account information from Binance.

  This module handles parsing and representation of account data returned
  from Binance account endpoints. It includes account permissions, trading
  status, commission rates, and all asset balances.

  ## Account Status Types

  - **NORMAL**: Account is in good standing and can trade
  - **MARGIN**: Account has margin trading enabled  
  - **FUTURES**: Account has futures trading enabled
  - **LOCKED**: Account is locked (cannot trade)

  ## Usage Examples

  ```elixir
  # Parse account from Binance API response
  binance_data = %{
    "makerCommission" => 10,
    "takerCommission" => 10,
    "buyerCommission" => 0,
    "sellerCommission" => 0,
    "canTrade" => true,
    "canWithdraw" => true,
    "canDeposit" => true,
    "updateTime" => 1640995200000,
    "accountType" => "SPOT",
    "balances" => [
      %{"asset" => "BTC", "free" => "0.50000000", "locked" => "0.10000000"},
      %{"asset" => "ETH", "free" => "10.00000000", "locked" => "2.00000000"}
    ]
  }

  {:ok, account} = Account.parse(binance_data)

  # Get balances for specific assets
  {:ok, btc_balance} = Account.get_balance(account, "BTC")
  {:ok, eth_balance} = Account.get_balance(account, "ETH")

  # Check trading permissions
  Account.can_trade?(account)  # true
  Account.can_withdraw?(account)  # true

  # Get non-zero balances only
  non_zero_balances = Account.non_zero_balances(account)
  ```
  """

  alias CryptoExchange.Models.{Account, Balance}

  @enforce_keys [
    :maker_commission,
    :taker_commission,
    :can_trade,
    :can_withdraw,
    :can_deposit,
    :balances
  ]
  defstruct [
    :maker_commission,
    :taker_commission,
    :buyer_commission,
    :seller_commission,
    :can_trade,
    :can_withdraw,
    :can_deposit,
    :account_type,
    :updated_at,
    :balances
  ]

  @type t :: %Account{
          maker_commission: non_neg_integer(),
          taker_commission: non_neg_integer(),
          buyer_commission: non_neg_integer() | nil,
          seller_commission: non_neg_integer() | nil,
          can_trade: boolean(),
          can_withdraw: boolean(),
          can_deposit: boolean(),
          account_type: String.t() | nil,
          updated_at: DateTime.t() | nil,
          balances: [Balance.t()]
        }

  @doc """
  Parses account data from Binance API response.

  ## Parameters
  - `data`: Map containing account data from Binance API

  ## Returns
  - `{:ok, account}` on successful parsing
  - `{:error, reason}` if parsing fails

  ## Example
  ```elixir
  binance_data = %{
    "makerCommission" => 10,
    "takerCommission" => 10,
    "canTrade" => true,
    "canWithdraw" => true,
    "canDeposit" => true,
    "balances" => [...]
  }

  {:ok, account} = Account.parse(binance_data)
  ```
  """
  def parse(data) when is_map(data) do
    with {:ok, maker_commission} <- extract_integer(data, "makerCommission"),
         {:ok, taker_commission} <- extract_integer(data, "takerCommission"),
         {:ok, can_trade} <- extract_boolean(data, "canTrade"),
         {:ok, can_withdraw} <- extract_boolean(data, "canWithdraw"),
         {:ok, can_deposit} <- extract_boolean(data, "canDeposit"),
         {:ok, balances} <- extract_and_parse_balances(data, "balances") do
      account = %Account{
        maker_commission: maker_commission,
        taker_commission: taker_commission,
        buyer_commission: extract_integer_optional(data, "buyerCommission"),
        seller_commission: extract_integer_optional(data, "sellerCommission"),
        can_trade: can_trade,
        can_withdraw: can_withdraw,
        can_deposit: can_deposit,
        account_type: Map.get(data, "accountType"),
        updated_at: extract_datetime_optional(data, "updateTime"),
        balances: balances
      }

      {:ok, account}
    else
      {:error, _reason} = error ->
        error
    end
  end

  def parse(_), do: {:error, :invalid_data_format}

  @doc """
  Converts an Account struct to a map representation.

  ## Parameters
  - `account`: Account struct to convert

  ## Returns
  Map with account data.

  ## Example
  ```elixir
  account_map = Account.to_map(account)
  ```
  """
  def to_map(%Account{} = account) do
    %{
      maker_commission: account.maker_commission,
      taker_commission: account.taker_commission,
      buyer_commission: account.buyer_commission,
      seller_commission: account.seller_commission,
      can_trade: account.can_trade,
      can_withdraw: account.can_withdraw,
      can_deposit: account.can_deposit,
      account_type: account.account_type,
      updated_at: account.updated_at,
      balances: Enum.map(account.balances, &Balance.to_map/1)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  @doc """
  Gets the balance for a specific asset.

  ## Parameters
  - `account`: Account struct
  - `asset`: Asset symbol to find (e.g., "BTC", "ETH")

  ## Returns
  - `{:ok, balance}` if asset is found
  - `{:error, :not_found}` if asset is not found

  ## Example
  ```elixir
  {:ok, btc_balance} = Account.get_balance(account, "BTC")
  {:error, :not_found} = Account.get_balance(account, "XYZ")
  ```
  """
  def get_balance(%Account{balances: balances}, asset) do
    Balance.find_by_asset(balances, asset)
  end

  @doc """
  Gets all non-zero balances from the account.

  ## Parameters
  - `account`: Account struct

  ## Returns
  List of Balance structs with non-zero totals.

  ## Example
  ```elixir
  active_balances = Account.non_zero_balances(account)
  ```
  """
  def non_zero_balances(%Account{balances: balances}) do
    Balance.filter_non_zero(balances)
  end

  @doc """
  Gets balances sorted by total value (highest first).

  ## Parameters
  - `account`: Account struct

  ## Returns
  List of Balance structs sorted by total value.

  ## Example
  ```elixir
  sorted_balances = Account.balances_by_value(account)
  ```
  """
  def balances_by_value(%Account{balances: balances}) do
    Balance.sort_by_total(balances)
  end

  @doc """
  Checks if the account has trading permissions.

  ## Parameters
  - `account`: Account struct

  ## Returns
  Boolean indicating if trading is allowed.

  ## Example
  ```elixir
  Account.can_trade?(account)  # true or false
  ```
  """
  def can_trade?(%Account{can_trade: can_trade}), do: can_trade

  @doc """
  Checks if the account has withdrawal permissions.

  ## Parameters
  - `account`: Account struct

  ## Returns
  Boolean indicating if withdrawals are allowed.

  ## Example
  ```elixir
  Account.can_withdraw?(account)  # true or false
  ```
  """
  def can_withdraw?(%Account{can_withdraw: can_withdraw}), do: can_withdraw

  @doc """
  Checks if the account has deposit permissions.

  ## Parameters
  - `account`: Account struct

  ## Returns
  Boolean indicating if deposits are allowed.

  ## Example
  ```elixir
  Account.can_deposit?(account)  # true or false
  ```
  """
  def can_deposit?(%Account{can_deposit: can_deposit}), do: can_deposit

  @doc """
  Checks if the account has sufficient balance for a trade.

  ## Parameters
  - `account`: Account struct
  - `asset`: Asset symbol to check
  - `amount`: Required amount as Decimal

  ## Returns
  Boolean indicating if sufficient balance is available.

  ## Example
  ```elixir
  Account.has_sufficient_balance?(account, "BTC", Decimal.new("0.1"))
  # true if BTC free balance >= 0.1
  ```
  """
  def has_sufficient_balance?(%Account{} = account, asset, amount) do
    case get_balance(account, asset) do
      {:ok, balance} -> Balance.has_available_funds?(balance, amount)
      {:error, :not_found} -> false
    end
  end

  @doc """
  Gets the effective commission rate for trading.

  ## Parameters
  - `account`: Account struct
  - `side`: Trading side (":maker" or ":taker")

  ## Returns
  Commission rate as integer (basis points, where 10 = 0.1%).

  ## Example
  ```elixir
  maker_rate = Account.commission_rate(account, :maker)  # 10 (0.1%)
  taker_rate = Account.commission_rate(account, :taker)  # 10 (0.1%)
  ```
  """
  def commission_rate(%Account{maker_commission: rate}, :maker), do: rate
  def commission_rate(%Account{taker_commission: rate}, :taker), do: rate

  @doc """
  Validates account data before parsing.

  ## Parameters
  - `data`: Raw account data to validate

  ## Returns
  - `:ok` if data is valid
  - `{:error, reason}` if validation fails

  ## Example
  ```elixir
  :ok = Account.validate(valid_account_data)
  {:error, :missing_field} = Account.validate(%{"balances" => []})
  ```
  """
  def validate(data) when is_map(data) do
    required_fields = [
      "makerCommission",
      "takerCommission",
      "canTrade",
      "canWithdraw",
      "canDeposit",
      "balances"
    ]

    case check_required_fields(data, required_fields) do
      :ok -> validate_balances(data["balances"])
      error -> error
    end
  end

  def validate(_), do: {:error, :invalid_data_format}

  @doc """
  Summarizes account information in a readable format.

  ## Parameters
  - `account`: Account struct

  ## Returns
  Map with account summary including permission status and balance counts.

  ## Example
  ```elixir
  summary = Account.summary(account)
  # %{
  #   trading_enabled: true,
  #   total_balances: 15,
  #   non_zero_balances: 3,
  #   commission_rates: %{maker: 10, taker: 10}
  # }
  ```
  """
  def summary(%Account{} = account) do
    non_zero = non_zero_balances(account)

    %{
      trading_enabled: can_trade?(account),
      withdrawal_enabled: can_withdraw?(account),
      deposit_enabled: can_deposit?(account),
      total_balances: length(account.balances),
      non_zero_balances: length(non_zero),
      commission_rates: %{
        maker: account.maker_commission,
        taker: account.taker_commission
      },
      account_type: account.account_type,
      last_updated: account.updated_at
    }
  end

  # Private Functions

  defp extract_integer(data, key) do
    case Map.get(data, key) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      nil -> {:error, {:missing_field, key}}
      _ -> {:error, {:invalid_field_type, key}}
    end
  end

  defp extract_integer_optional(data, key) do
    case extract_integer(data, key) do
      {:ok, value} -> value
      {:error, _} -> nil
    end
  end

  defp extract_boolean(data, key) do
    case Map.get(data, key) do
      value when is_boolean(value) -> {:ok, value}
      nil -> {:error, {:missing_field, key}}
      _ -> {:error, {:invalid_field_type, key}}
    end
  end

  defp extract_datetime_optional(data, key) do
    case Map.get(data, key) do
      timestamp when is_integer(timestamp) ->
        DateTime.from_unix!(timestamp, :millisecond)

      _ ->
        nil
    end
  end

  defp extract_and_parse_balances(data, key) do
    case Map.get(data, key) do
      balances_data when is_list(balances_data) ->
        Balance.parse_list(balances_data)

      nil ->
        {:error, {:missing_field, key}}

      _ ->
        {:error, {:invalid_field_type, key}}
    end
  end

  defp check_required_fields(data, required_fields) do
    missing = Enum.filter(required_fields, &(!Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_balances(balances_data) when is_list(balances_data) do
    case Balance.parse_list(balances_data) do
      {:ok, _balances} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_balances(_), do: {:error, :invalid_balances_format}
end
