defmodule Tapestry.Serializer do
  @moduledoc """
  Zero-dependency serialization for Tapestry projects.

  Uses Erlang's external term format by default. Fast, compact, and
  preserves all Elixir types (atoms, dates, tuples) perfectly.

  ## Examples

      iex> tapestry = Tapestry.new("Project")
      iex> blob = Tapestry.Serializer.to_term(tapestry)
      iex> is_binary(blob)
      true
      iex> Tapestry.Serializer.from_term(blob) == tapestry
      true

  For JSON serialization, use `Yog.IO.JSON` directly if you have
  the `:jason` dependency available in your application.
  """

  alias Tapestry

  @doc """
  Serialize a Tapestry project to a binary using Erlang's external term format.
  """
  @spec to_term(Tapestry.t()) :: binary()
  def to_term(%Tapestry{} = tapestry) do
    :erlang.term_to_binary(tapestry)
  end

  @doc """
  Deserialize a binary back to a Tapestry project.

  Uses `:safe` mode to prevent atom exhaustion when loading
  untrusted data.
  """
  @spec from_term(binary()) :: Tapestry.t()
  def from_term(binary) when is_binary(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %Tapestry{} = tapestry -> tapestry
      other -> raise ArgumentError, "expected a Tapestry struct, got: #{inspect(other)}"
    end
  end
end
