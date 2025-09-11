defmodule CryptoExchange.Models do
  @moduledoc """
  Data models for the CryptoExchange library.

  This module defines all data structures used throughout the library, including
  market data models (Ticker, OrderBook, Trade) and trading data models (Order, Balance).

  All models support JSON parsing/encoding and include comprehensive validation
  and transformation utilities.

  ## Market Data Models

  - `CryptoExchange.Models.Ticker` - Price and volume information for a trading pair
  - `CryptoExchange.Models.OrderBook` - Order book with bids and asks
  - `CryptoExchange.Models.Trade` - Individual trade information

  ## Trading Data Models

  - `CryptoExchange.Models.Order` - Order information and status
  - `CryptoExchange.Models.Balance` - Account balance information

  ## Usage

  ### Creating Models from JSON

      # Parse ticker from Binance API response
      ticker_json = %{
        "symbol" => "BTCUSDT",
        "price" => "50000.0",
        "priceChange" => "750.0",
        "volume" => "1234.56"
      }
      {:ok, ticker} = CryptoExchange.Models.Ticker.from_binance_json(ticker_json)

  ### Converting to JSON

      # Convert model to JSON
      json_data = CryptoExchange.Models.Ticker.to_json(ticker)

  ### Validation

      # Validate model fields
      {:ok, valid_ticker} = CryptoExchange.Models.Ticker.validate(ticker_data)
  """

  defmodule Ticker do
    @moduledoc """
    Represents ticker data for a trading pair.

    Contains current price, price change, and volume information.
    """

    @type t :: %__MODULE__{
            symbol: String.t(),
            price: float(),
            change: float(),
            volume: float()
          }

    defstruct [:symbol, :price, :change, :volume]

    @doc """
    Creates a new Ticker struct with validation.

    ## Parameters

    - `attrs` - Map containing ticker attributes

    ## Examples

        iex> CryptoExchange.Models.Ticker.new(%{
        ...>   symbol: "BTCUSDT",
        ...>   price: 50000.0,
        ...>   change: 1.5,
        ...>   volume: 1234.56
        ...> })
        {:ok, %CryptoExchange.Models.Ticker{...}}

        iex> CryptoExchange.Models.Ticker.new(%{symbol: nil})
        {:error, :invalid_symbol}
    """
    @spec new(map()) :: {:ok, t()} | {:error, atom()}
    def new(attrs) when is_map(attrs) do
      with {:ok, symbol} <- validate_symbol(attrs[:symbol]),
           {:ok, price} <- validate_price(attrs[:price]),
           {:ok, change} <- validate_number(attrs[:change], :change),
           {:ok, volume} <- validate_number(attrs[:volume], :volume) do
        ticker = %__MODULE__{
          symbol: symbol,
          price: price,
          change: change,
          volume: volume
        }

        {:ok, ticker}
      end
    end

    def new(_), do: {:error, :invalid_input}

    @doc """
    Creates a Ticker from Binance WebSocket/API response.

    Handles the specific field mappings from Binance format.

    ## Examples

        iex> binance_data = %{
        ...>   "s" => "BTCUSDT",
        ...>   "c" => "50000.00",
        ...>   "P" => "1.50",
        ...>   "v" => "1234.56"
        ...> }
        iex> CryptoExchange.Models.Ticker.from_binance_json(binance_data)
        {:ok, %CryptoExchange.Models.Ticker{...}}
    """
    @spec from_binance_json(map()) :: {:ok, t()} | {:error, term()}
    def from_binance_json(%{"s" => symbol, "c" => price, "P" => change, "v" => volume}) do
      new(%{
        symbol: symbol,
        price: parse_float(price),
        change: parse_float(change),
        volume: parse_float(volume)
      })
    end

    def from_binance_json(%{"symbol" => symbol, "price" => price, "priceChange" => change, "volume" => volume}) do
      new(%{
        symbol: symbol,
        price: parse_float(price),
        change: parse_float(change),
        volume: parse_float(volume)
      })
    end

    def from_binance_json(_), do: {:error, :invalid_binance_format}

    @doc """
    Converts a Ticker to JSON representation.
    """
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = ticker) do
      %{
        "symbol" => ticker.symbol,
        "price" => ticker.price,
        "change" => ticker.change,
        "volume" => ticker.volume
      }
    end

    @doc """
    Validates ticker data.
    """
    @spec validate(t()) :: {:ok, t()} | {:error, term()}
    def validate(%__MODULE__{} = ticker) do
      new(Map.from_struct(ticker))
    end

    def validate(_), do: {:error, :not_a_ticker}

    # Private validation functions
    defp validate_symbol(symbol) when is_binary(symbol) and symbol != "", do: {:ok, symbol}
    defp validate_symbol(_), do: {:error, :invalid_symbol}

    defp validate_price(price) when is_number(price) and price > 0, do: {:ok, price}
    defp validate_price(_), do: {:error, :invalid_price}

    defp validate_number(num, _field) when is_number(num), do: {:ok, num}
    defp validate_number(_, field), do: {:error, :"invalid_#{field}"}

    defp parse_float(str) when is_binary(str) do
      case Float.parse(str) do
        {float_val, ""} -> float_val
        _ -> 0.0
      end
    end

    defp parse_float(num) when is_number(num), do: num
    defp parse_float(_), do: 0.0
  end

  defmodule OrderBook do
    @moduledoc """
    Represents an order book with bids and asks.

    Contains the current order book state for a trading pair.
    """

    @type price_level :: [float(), ...]
    @type t :: %__MODULE__{
            symbol: String.t(),
            bids: [price_level()],
            asks: [price_level()]
          }

    defstruct [:symbol, :bids, :asks]

    @doc """
    Creates a new OrderBook struct with validation.

    ## Examples

        iex> CryptoExchange.Models.OrderBook.new(%{
        ...>   symbol: "BTCUSDT",
        ...>   bids: [[50000.0, 0.5], [49999.0, 1.0]],
        ...>   asks: [[50001.0, 0.3], [50002.0, 0.8]]
        ...> })
        {:ok, %CryptoExchange.Models.OrderBook{...}}
    """
    @spec new(map()) :: {:ok, t()} | {:error, atom()}
    def new(attrs) when is_map(attrs) do
      with {:ok, symbol} <- validate_symbol(attrs[:symbol]),
           {:ok, bids} <- validate_price_levels(attrs[:bids], :bids),
           {:ok, asks} <- validate_price_levels(attrs[:asks], :asks) do
        order_book = %__MODULE__{
          symbol: symbol,
          bids: bids,
          asks: asks
        }

        {:ok, order_book}
      end
    end

    def new(_), do: {:error, :invalid_input}

    @doc """
    Creates an OrderBook from Binance WebSocket/API response.
    """
    @spec from_binance_json(map()) :: {:ok, t()} | {:error, term()}
    def from_binance_json(%{"s" => symbol, "b" => bids, "a" => asks}) do
      new(%{
        symbol: symbol,
        bids: parse_price_levels(bids),
        asks: parse_price_levels(asks)
      })
    end

    def from_binance_json(%{"symbol" => symbol, "bids" => bids, "asks" => asks}) do
      new(%{
        symbol: symbol,
        bids: parse_price_levels(bids),
        asks: parse_price_levels(asks)
      })
    end

    def from_binance_json(_), do: {:error, :invalid_binance_format}

    @doc """
    Converts an OrderBook to JSON representation.
    """
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = order_book) do
      %{
        "symbol" => order_book.symbol,
        "bids" => order_book.bids,
        "asks" => order_book.asks
      }
    end

    @doc """
    Gets the best bid price.
    """
    @spec best_bid(t()) :: float() | nil
    def best_bid(%__MODULE__{bids: []}), do: nil
    def best_bid(%__MODULE__{bids: [[price | _] | _]}), do: price

    @doc """
    Gets the best ask price.
    """
    @spec best_ask(t()) :: float() | nil
    def best_ask(%__MODULE__{asks: []}), do: nil
    def best_ask(%__MODULE__{asks: [[price | _] | _]}), do: price

    @doc """
    Calculates the spread between best bid and ask.
    """
    @spec spread(t()) :: float() | nil
    def spread(%__MODULE__{} = order_book) do
      case {best_ask(order_book), best_bid(order_book)} do
        {ask, bid} when is_number(ask) and is_number(bid) -> ask - bid
        _ -> nil
      end
    end

    # Private validation functions
    defp validate_symbol(symbol) when is_binary(symbol) and symbol != "", do: {:ok, symbol}
    defp validate_symbol(_), do: {:error, :invalid_symbol}

    defp validate_price_levels(levels, _field) when is_list(levels) do
      if Enum.all?(levels, &valid_price_level?/1) do
        {:ok, levels}
      else
        {:error, :invalid_price_levels}
      end
    end

    defp validate_price_levels(_, field), do: {:error, :"invalid_#{field}"}

    defp valid_price_level?([price, quantity])
         when is_number(price) and price > 0 and is_number(quantity) and quantity > 0,
         do: true

    defp valid_price_level?(_), do: false

    defp parse_price_levels(levels) when is_list(levels) do
      Enum.map(levels, fn
        [price_str, quantity_str] ->
          [parse_float(price_str), parse_float(quantity_str)]

        level ->
          level
      end)
    end

    defp parse_price_levels(_), do: []

    defp parse_float(str) when is_binary(str) do
      case Float.parse(str) do
        {float_val, ""} -> float_val
        _ -> 0.0
      end
    end

    defp parse_float(num) when is_number(num), do: num
    defp parse_float(_), do: 0.0
  end

  defmodule Trade do
    @moduledoc """
    Represents a trade execution.

    Contains information about a completed trade.
    """

    @type side :: :buy | :sell
    @type t :: %__MODULE__{
            symbol: String.t(),
            price: float(),
            quantity: float(),
            side: side()
          }

    defstruct [:symbol, :price, :quantity, :side]

    @doc """
    Creates a new Trade struct with validation.

    ## Examples

        iex> CryptoExchange.Models.Trade.new(%{
        ...>   symbol: "BTCUSDT",
        ...>   price: 50000.0,
        ...>   quantity: 0.1,
        ...>   side: :buy
        ...> })
        {:ok, %CryptoExchange.Models.Trade{...}}
    """
    @spec new(map()) :: {:ok, t()} | {:error, atom()}
    def new(attrs) when is_map(attrs) do
      with {:ok, symbol} <- validate_symbol(attrs[:symbol]),
           {:ok, price} <- validate_price(attrs[:price]),
           {:ok, quantity} <- validate_quantity(attrs[:quantity]),
           {:ok, side} <- validate_side(attrs[:side]) do
        trade = %__MODULE__{
          symbol: symbol,
          price: price,
          quantity: quantity,
          side: side
        }

        {:ok, trade}
      end
    end

    def new(_), do: {:error, :invalid_input}

    @doc """
    Creates a Trade from Binance WebSocket/API response.
    """
    @spec from_binance_json(map()) :: {:ok, t()} | {:error, term()}
    def from_binance_json(%{"s" => symbol, "p" => price, "q" => quantity, "m" => is_buyer_maker}) do
      side = if is_buyer_maker, do: :sell, else: :buy

      new(%{
        symbol: symbol,
        price: parse_float(price),
        quantity: parse_float(quantity),
        side: side
      })
    end

    def from_binance_json(%{"symbol" => symbol, "price" => price, "qty" => quantity, "isBuyerMaker" => is_buyer_maker}) do
      side = if is_buyer_maker, do: :sell, else: :buy

      new(%{
        symbol: symbol,
        price: parse_float(price),
        quantity: parse_float(quantity),
        side: side
      })
    end

    def from_binance_json(_), do: {:error, :invalid_binance_format}

    @doc """
    Converts a Trade to JSON representation.
    """
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = trade) do
      %{
        "symbol" => trade.symbol,
        "price" => trade.price,
        "quantity" => trade.quantity,
        "side" => Atom.to_string(trade.side)
      }
    end

    @doc """
    Calculates the notional value of the trade.
    """
    @spec notional_value(t()) :: float()
    def notional_value(%__MODULE__{price: price, quantity: quantity}) do
      price * quantity
    end

    # Private validation functions
    defp validate_symbol(symbol) when is_binary(symbol) and symbol != "", do: {:ok, symbol}
    defp validate_symbol(_), do: {:error, :invalid_symbol}

    defp validate_price(price) when is_number(price) and price > 0, do: {:ok, price}
    defp validate_price(_), do: {:error, :invalid_price}

    defp validate_quantity(quantity) when is_number(quantity) and quantity > 0, do: {:ok, quantity}
    defp validate_quantity(_), do: {:error, :invalid_quantity}

    defp validate_side(side) when side in [:buy, :sell], do: {:ok, side}
    defp validate_side("BUY"), do: {:ok, :buy}
    defp validate_side("SELL"), do: {:ok, :sell}
    defp validate_side(_), do: {:error, :invalid_side}

    defp parse_float(str) when is_binary(str) do
      case Float.parse(str) do
        {float_val, ""} -> float_val
        _ -> 0.0
      end
    end

    defp parse_float(num) when is_number(num), do: num
    defp parse_float(_), do: 0.0
  end

  defmodule Order do
    @moduledoc """
    Represents a trading order.

    Contains order information, status, and trading parameters.
    """

    @type side :: :buy | :sell
    @type order_type :: :market | :limit | :stop_loss | :stop_loss_limit | :take_profit | :take_profit_limit
    @type status :: :new | :partially_filled | :filled | :canceled | :rejected | :expired
    @type t :: %__MODULE__{
            order_id: String.t(),
            symbol: String.t(),
            side: side(),
            type: order_type(),
            quantity: float(),
            price: float() | nil,
            status: status()
          }

    defstruct [:order_id, :symbol, :side, :type, :quantity, :price, :status]

    @doc """
    Creates a new Order struct with validation.

    ## Examples

        iex> CryptoExchange.Models.Order.new(%{
        ...>   order_id: "123456",
        ...>   symbol: "BTCUSDT",
        ...>   side: :buy,
        ...>   type: :limit,
        ...>   quantity: 0.001,
        ...>   price: 50000.0,
        ...>   status: :new
        ...> })
        {:ok, %CryptoExchange.Models.Order{...}}
    """
    @spec new(map()) :: {:ok, t()} | {:error, atom()}
    def new(attrs) when is_map(attrs) do
      with {:ok, order_id} <- validate_order_id(attrs[:order_id]),
           {:ok, symbol} <- validate_symbol(attrs[:symbol]),
           {:ok, side} <- validate_side(attrs[:side]),
           {:ok, type} <- validate_order_type(attrs[:type]),
           {:ok, quantity} <- validate_quantity(attrs[:quantity]),
           {:ok, price} <- validate_order_price(attrs[:price], attrs[:type]),
           {:ok, status} <- validate_status(attrs[:status]) do
        order = %__MODULE__{
          order_id: order_id,
          symbol: symbol,
          side: side,
          type: type,
          quantity: quantity,
          price: price,
          status: status
        }

        {:ok, order}
      end
    end

    def new(_), do: {:error, :invalid_input}

    @doc """
    Creates an Order from Binance API response.
    """
    @spec from_binance_json(map()) :: {:ok, t()} | {:error, term()}
    def from_binance_json(%{
          "orderId" => order_id,
          "symbol" => symbol,
          "side" => side,
          "type" => type,
          "origQty" => quantity,
          "price" => price,
          "status" => status
        }) do
      new(%{
        order_id: to_string(order_id),
        symbol: symbol,
        side: parse_side(side),
        type: parse_order_type(type),
        quantity: parse_float(quantity),
        price: parse_order_price(price),
        status: parse_status(status)
      })
    end

    def from_binance_json(_), do: {:error, :invalid_binance_format}

    @doc """
    Converts an Order to JSON representation.
    """
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = order) do
      %{
        "order_id" => order.order_id,
        "symbol" => order.symbol,
        "side" => Atom.to_string(order.side) |> String.upcase(),
        "type" => Atom.to_string(order.type) |> String.upcase(),
        "quantity" => order.quantity,
        "price" => order.price,
        "status" => Atom.to_string(order.status) |> String.upcase()
      }
    end

    @doc """
    Checks if the order is active (can be canceled or modified).
    """
    @spec active?(t()) :: boolean()
    def active?(%__MODULE__{status: status}) do
      status in [:new, :partially_filled]
    end

    @doc """
    Checks if the order is completed (filled or canceled).
    """
    @spec completed?(t()) :: boolean()
    def completed?(%__MODULE__{status: status}) do
      status in [:filled, :canceled, :rejected, :expired]
    end

    @doc """
    Calculates the notional value of the order.
    """
    @spec notional_value(t()) :: float() | nil
    def notional_value(%__MODULE__{price: nil}), do: nil
    def notional_value(%__MODULE__{price: price, quantity: quantity}) do
      price * quantity
    end

    # Private validation functions
    defp validate_order_id(order_id) when is_binary(order_id) and order_id != "", do: {:ok, order_id}
    defp validate_order_id(order_id) when is_integer(order_id), do: {:ok, to_string(order_id)}
    defp validate_order_id(_), do: {:error, :invalid_order_id}

    defp validate_symbol(symbol) when is_binary(symbol) and symbol != "", do: {:ok, symbol}
    defp validate_symbol(_), do: {:error, :invalid_symbol}

    defp validate_side(side) when side in [:buy, :sell], do: {:ok, side}
    defp validate_side(_), do: {:error, :invalid_side}

    defp validate_order_type(type) when type in [:market, :limit, :stop_loss, :stop_loss_limit, :take_profit, :take_profit_limit] do
      {:ok, type}
    end

    defp validate_order_type(_), do: {:error, :invalid_order_type}

    defp validate_quantity(quantity) when is_number(quantity) and quantity > 0, do: {:ok, quantity}
    defp validate_quantity(_), do: {:error, :invalid_quantity}

    defp validate_order_price(price, :market) when is_nil(price), do: {:ok, nil}
    defp validate_order_price(price, _type) when is_number(price) and price > 0, do: {:ok, price}
    defp validate_order_price(nil, type) when type != :market, do: {:error, :price_required_for_limit_orders}
    defp validate_order_price(_, _), do: {:error, :invalid_price}

    defp validate_status(status) when status in [:new, :partially_filled, :filled, :canceled, :rejected, :expired] do
      {:ok, status}
    end

    defp validate_status(_), do: {:error, :invalid_status}

    defp parse_side("BUY"), do: :buy
    defp parse_side("SELL"), do: :sell
    defp parse_side(side) when is_atom(side), do: side
    defp parse_side(_), do: :buy

    defp parse_order_type("MARKET"), do: :market
    defp parse_order_type("LIMIT"), do: :limit
    defp parse_order_type("STOP_LOSS"), do: :stop_loss
    defp parse_order_type("STOP_LOSS_LIMIT"), do: :stop_loss_limit
    defp parse_order_type("TAKE_PROFIT"), do: :take_profit
    defp parse_order_type("TAKE_PROFIT_LIMIT"), do: :take_profit_limit
    defp parse_order_type(type) when is_atom(type), do: type
    defp parse_order_type(_), do: :limit

    defp parse_status("NEW"), do: :new
    defp parse_status("PARTIALLY_FILLED"), do: :partially_filled
    defp parse_status("FILLED"), do: :filled
    defp parse_status("CANCELED"), do: :canceled
    defp parse_status("REJECTED"), do: :rejected
    defp parse_status("EXPIRED"), do: :expired
    defp parse_status(status) when is_atom(status), do: status
    defp parse_status(_), do: :new

    defp parse_order_price("0.00000000"), do: nil
    defp parse_order_price(price), do: parse_float(price)

    defp parse_float(str) when is_binary(str) do
      case Float.parse(str) do
        {float_val, ""} -> float_val
        _ -> 0.0
      end
    end

    defp parse_float(num) when is_number(num), do: num
    defp parse_float(_), do: 0.0
  end

  defmodule Balance do
    @moduledoc """
    Represents account balance for a specific asset.

    Contains free and locked amounts for a cryptocurrency asset.
    """

    @type t :: %__MODULE__{
            asset: String.t(),
            free: float(),
            locked: float()
          }

    defstruct [:asset, :free, :locked]

    @doc """
    Creates a new Balance struct with validation.

    ## Examples

        iex> CryptoExchange.Models.Balance.new(%{
        ...>   asset: "BTC",
        ...>   free: 0.5,
        ...>   locked: 0.1
        ...> })
        {:ok, %CryptoExchange.Models.Balance{...}}
    """
    @spec new(map()) :: {:ok, t()} | {:error, atom()}
    def new(attrs) when is_map(attrs) do
      with {:ok, asset} <- validate_asset(attrs[:asset]),
           {:ok, free} <- validate_amount(attrs[:free], :free),
           {:ok, locked} <- validate_amount(attrs[:locked], :locked) do
        balance = %__MODULE__{
          asset: asset,
          free: free,
          locked: locked
        }

        {:ok, balance}
      end
    end

    def new(_), do: {:error, :invalid_input}

    @doc """
    Creates a Balance from Binance API response.
    """
    @spec from_binance_json(map()) :: {:ok, t()} | {:error, term()}
    def from_binance_json(%{"asset" => asset, "free" => free, "locked" => locked}) do
      new(%{
        asset: asset,
        free: parse_float(free),
        locked: parse_float(locked)
      })
    end

    def from_binance_json(_), do: {:error, :invalid_binance_format}

    @doc """
    Converts a Balance to JSON representation.
    """
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = balance) do
      %{
        "asset" => balance.asset,
        "free" => balance.free,
        "locked" => balance.locked
      }
    end

    @doc """
    Calculates the total balance (free + locked).
    """
    @spec total(t()) :: float()
    def total(%__MODULE__{free: free, locked: locked}) do
      free + locked
    end

    @doc """
    Checks if the balance has sufficient free amount.
    """
    @spec sufficient_free?(t(), float()) :: boolean()
    def sufficient_free?(%__MODULE__{free: free}, required_amount) when is_number(required_amount) do
      free >= required_amount
    end

    def sufficient_free?(_, _), do: false

    @doc """
    Checks if the balance is non-zero (has any free or locked amount).
    """
    @spec non_zero?(t()) :: boolean()
    def non_zero?(%__MODULE__{free: free, locked: locked}) do
      free > 0 or locked > 0
    end

    # Private validation functions
    defp validate_asset(asset) when is_binary(asset) and asset != "", do: {:ok, asset}
    defp validate_asset(_), do: {:error, :invalid_asset}

    defp validate_amount(amount, _field) when is_number(amount) and amount >= 0, do: {:ok, amount}
    defp validate_amount(_, field), do: {:error, :"invalid_#{field}_amount"}

    defp parse_float(str) when is_binary(str) do
      case Float.parse(str) do
        {float_val, ""} -> float_val
        _ -> 0.0
      end
    end

    defp parse_float(num) when is_number(num), do: num
    defp parse_float(_), do: 0.0
  end

  @doc """
  Parses a list of models from Binance JSON responses.

  ## Examples

      iex> balances_json = [
      ...>   %{"asset" => "BTC", "free" => "0.5", "locked" => "0.1"},
      ...>   %{"asset" => "ETH", "free" => "10.0", "locked" => "2.0"}
      ...> ]
      iex> CryptoExchange.Models.parse_list(balances_json, &Balance.from_binance_json/1)
      {:ok, [%CryptoExchange.Models.Balance{...}, ...]}
  """
  @spec parse_list([map()], (map() -> {:ok, term()} | {:error, term()})) :: 
          {:ok, [term()]} | {:error, term()}
  def parse_list(json_list, parser_fn) when is_list(json_list) and is_function(parser_fn, 1) do
    results =
      json_list
      |> Enum.map(parser_fn)
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, item}, {:ok, acc} -> {:cont, {:ok, [item | acc]}}
        {:error, reason}, _acc -> {:halt, {:error, reason}}
      end)

    case results do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  def parse_list(_, _), do: {:error, :invalid_input}

  @doc """
  Converts a list of models to JSON.

  ## Examples

      iex> balances = [balance1, balance2]
      iex> CryptoExchange.Models.to_json_list(balances, &Balance.to_json/1)
      [%{"asset" => "BTC", ...}, %{"asset" => "ETH", ...}]
  """
  @spec to_json_list([term()], (term() -> map())) :: [map()]
  def to_json_list(models, converter_fn) when is_list(models) and is_function(converter_fn, 1) do
    Enum.map(models, converter_fn)
  end

  def to_json_list(_, _), do: []
end