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
      > [ {"foo": {"bar.qux": {"baz": "stuff"} } }, {"foo": {"bar": {"baz": "me"} } } ]
      @bot #{Cog.embedded_bundle}:seed '[{"foo":{"bar.qux":{"baz":"stuff"}}}, {"foo": {"bar":{"baz":"me"}}}]' | #{Cog.embedded_bundle}:filter --path="foo.\\"bar.qux\\".baz""
      > { "foo": {"bar.qux": {"baz": "stuff"} } }

  """

  option "matches", type: "string", required: false
  option "return", type: "list", required: false
  option "path", type: "string", required: false

  def handle_message(req, state) do
    %{cog_env: item, options: options} = req

    result = item
    |> maybe_filter(options)
    |> maybe_pluck(options)

    response = case result do
      {:error, error} ->
        translate_error(error)
      path ->
        path
    end
    {:reply, req.reply_to, response, state}
  end

  defp maybe_filter(item, %{"path" => path, "matches" => matches}) do
    case String.valid?(matches) do
      true ->
        build_path(path)
        |> fetch(item, matches)
      false ->
        {:error, :bad_match}
    end
  end
  defp maybe_filter(item, %{"path" => path}) do
    full_path = build_path(path)
    case get_in(item, full_path) do
      nil -> nil
      _ -> item
    end
  end
  defp maybe_filter(_item, %{"matches" => _matches}),
    do: {:error, :missing_path}
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
      true -> item
      {:error, error} -> {:error, error}
      _ -> fetch(path, item, matches)
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

  defp build_path(path) do
    cond do
      String.contains?(path, "\"") ->
        Regex.split(~r/\.\"|\"\./, path)
      String.contains?(path, "'") ->
        Regex.split(~r/\.\'|\'\./, path)
      true ->
        Regex.split(~r/\./, path)
    end
  end

  defp compile_regex(string) do
    case Regex.run(~r/^\/(.*)\/(.*)$/, string) do
      nil ->
        Regex.compile!(string)
      [_, regex, opts] ->
        Regex.compile!(regex, opts)
    end
  end

  defp translate_error(:missing_path),
    do: "Must specify `--path` with the `--matches` option"
  defp translate_error(:bad_match),
    do: "The regular expression in `--matches` does not compile correctly."
end
