defmodule Tapestry.Serializer do
  @moduledoc """
  Zero-dependency serialization for Tapestry projects.

  Uses Erlang's external term format by default. Fast, compact, and
  preserves all Elixir types (atoms, dates, tuples) perfectly.

  ## Examples

      # Serialize
      blob = Tapestry.Serializer.to_term(loom)
      # => <<131, 104, 3, ...>>

      # Deserialize
      loom = Tapestry.Serializer.from_term(blob)
      # => %Tapestry{...}

  For JSON serialization, use `Yog.IO.JSON` directly if you have
  the `:jason` dependency available in your application.
  """

  alias Tapestry

  @doc """
  Serialize a Tapestry project to a binary using Erlang's external term format.
  """
  @spec to_term(Tapestry.t()) :: binary()
  def to_term(%Tapestry{} = loom) do
    :erlang.term_to_binary(loom)
  end

  @doc """
  Deserialize a binary back to a Tapestry project.

  Uses `:safe` mode to prevent atom exhaustion when loading
  untrusted data.
  """
  @spec from_term(binary()) :: Tapestry.t()
  def from_term(binary) when is_binary(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %Tapestry{} = loom -> loom
      other -> raise ArgumentError, "expected a Tapestry struct, got: #{inspect(other)}"
    end
  end
end
