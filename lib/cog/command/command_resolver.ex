defmodule Cog.Command.CommandResolver do

  alias Cog.Repo
  alias Cog.Queries.Command
  alias Cog.Queries.Alias, as: AliasQuery
  alias Piper.Command.SemanticError

  def find_bundle(<<":", _::binary>>=name) do
    find_bundle_or_alias(name)
  end
  def find_bundle(name) when is_binary(name) do
    if String.contains?(name, ":") do
      :identity
    else
      find_bundle_or_alias(name)
    end
  end
  def find_bundle(name) do
    SemanticError.new("#{inspect name}", :no_command)
  end

  # TODO: This is an expensive operation we need to find a more optimal solution
  # especially considering that it can potentially be executed on every invocation
  # in a pipeline.
  defp get_alias_type(name) do
    case Repo.all(AliasQuery.user_alias_by_name(name)) do
      [] ->
        case Repo.all(AliasQuery.site_alias_by_name(name)) do
          [] ->
            nil
          _site_alias ->
            {:ok, "site"}
        end
      _user_alias ->
        {:ok, "user"}
    end
  end

  defp find_bundle_or_alias(name) do
    case Repo.all(Command.bundle_for(name)) do
      [bundle_name] ->
        case get_alias_type(name) do
          {:ok, alias_type} ->
            SemanticError.new(name, {:ambiguous_alias, {bundle_name <> ":" <> name, alias_type <> ":" <> name}})
          nil ->
            {:ok, bundle_name}
        end
      [] ->
        case get_alias_type(name) do
          {:ok, alias_type} ->
            {:ok, alias_type}
          nil ->
            SemanticError.new(name, :no_command)
        end
      bundle_names ->
        SemanticError.new(name, {:ambiguous_command, bundle_names})
    end
  end

end
