defmodule Cog.Commands.Filter do
  use Spanner.GenCommand.Base, bundle: Cog.embedded_bundle, enforcing: false, calling_convention: :all

  @moduledoc """
  Filters a collection where the `path` equals the `matches`.
  The `path` option is the key that you would like to focus on;
  The `matches` option is the value that you are searching for.

  ## Example

      @bot #{Cog.embedded_bundle}:rules --list --for-command="#{Cog.embedded_bundle}:permissions" | #{Cog.embedded_bundle}:filter --path="rule" --return="id, command" --matches="/manage_users/"
      > { "id": "91edb472-04cf-4bca-ba05-e51b63f26758",
          "command": "operable:permissions" }
      @bot #{Cog.embedded_bundle}:seed --list --for-command="#{Cog.embedded_bundle}:permissions" | #{Cog.embedded_bundle}:filter --path="rule" --return="id, command" --matches="/manage_users/"
      > { "id": "91edb472-04cf-4bca-ba05-e51b63f26758",
          "command": "operable:permissions" }
      @bot #{Cog.embedded_bundle}:seed '[{"foo":{"bar.qux":{"baz":"stuff"}}}, {"foo": {"bar":{"baz":"me"}}}]' | #{Cog.embedded_bundle}:filter --path="foo.bar.baz""
      > { "baz": "me" }
      @bot #{Cog.embedded_bundle}:seed '[{"foo":{"bar.qux":{"baz":"stuff"}}}, {"foo": {"bar":{"baz":"me"}}}]' | #{Cog.embedded_bundle}:filter --path="foo.\\"bar.qux\\".baz""
      > { "baz": "stuff" }

  """

  option "matches", type: "string", required: false
  option "return", type: "list", required: false
  option "path", type: "string", required: false

  def handle_message(req, state) do
    %{cog_env: item, options: options} = req

    result = item
    |> maybe_filter(options)
    |> maybe_pluck(options)

    {:reply, req.reply_to, result, state}
  end

  defp maybe_filter(item, %{"path" => path, "matches" => matches}) do
    build_path(String.split(path, "."), [], [])
    |> fetch(item, matches)
  end
  defp maybe_filter(item, %{"path" => path}) do
    full_path = build_path(String.split(path, "."), [], [])
    case get_in(item, full_path) do
      nil -> nil
      _ -> item
    end
  end
  defp maybe_filter(_item, %{"matches" => _matches}),
    do: %{error: "Please include a `path` to match with"}
  defp maybe_filter(item, _) do
    item
  end

  defp fetch([], item, matches) do
    match_str = Regex.compile!(matches)
    match = Regex.match?(match_str, to_string(item))
    fetch_match(match, item)
  end
  defp fetch(_, nil, _), do: nil
  defp fetch([key|path], item, matches) do
  match = with {:ok, value} <- Access.fetch(item, key),
      regex = compile_regex(matches),
      path_string = to_string(value),
      do: String.match?(path_string, regex)
     case match do
       true ->
         item
       _ ->
         fetch(path, item, matches)
     end
  end

  defp fetch_match(true, item), do: item
  defp fetch_match(_, _item), do: nil

  defp maybe_pluck(item, %{"return" => []}),
    do: item
  defp maybe_pluck(item, %{"return" => fields}) when is_map(item),
    do: Map.take(item, fields)
  defp maybe_pluck(item, _),
    do: item

  defp build_path([], [], path), do: path
  defp build_path([key|remaining], acc, path) do
    {path, acc} = cond do
                    String.starts_with?(key, ["\"", "'"]) ->
                      new_key = String.replace_leading(key, "\"", "")
                      |> String.replace_leading("'", "")

                      {path, acc ++ [new_key]}
                    String.ends_with?(key, ["\"", "'"]) ->
                      new_key = String.replace_trailing(key, "\"", "")
                      |> String.replace_trailing("'", "")

                      acc = acc ++ [new_key]
                      full_key = Enum.join(acc, ".")
                      {path ++ [full_key], []}
                    acc != [] ->
                      {path, acc ++ [key]}
                    true ->
                      {path ++ [key], acc}
                  end
    build_path(remaining, acc, path)
  end

  defp compile_regex(string) do
    case Regex.run(~r/^\/(.*)\/(.*)$/, string) do
      nil ->
        Regex.compile!(string)
      [_, regex, opts] ->
        Regex.compile!(regex, opts)
    end
  end
end
