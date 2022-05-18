defmodule MishkaInstaller.Installer.MixCreator do

  def backup_mix(_mix_path) do

  end

  def restore_mix(_mix_path) do

  end

  def create_mix(list_of_deps, mix_path) do
    content =
      File.read!(mix_path)
      |> Sourceror.parse_string!()
      |> Sourceror.postwalk(fn
        {:defp, meta, [{:deps, _, _} = fun, [{{_, _, [:do]}, {:__block__, block_meta, [deps]}}]]}, state ->
            MishkaInstaller.Installer.DepHandler.append_mix(list_of_deps)
            |> Enum.map(fn item ->
              [app_name | [h | other_options]] = Tuple.to_list(item)
              cond do
                Keyword.take(h, [:path]) != [] -> dep(:path, app_name, "/x/#{app_name}", dep_line(deps, block_meta))
                Keyword.take(h, [:git]) != [] and Keyword.take(h, [:tag]) != [] -> dep(:git, app_name, h[:git], other_options[:tag], dep_line(deps, block_meta))
                Keyword.take(h, [:git]) != [] -> dep(:git, app_name, h[:git], dep_line(deps, block_meta))
                true -> dep(app_name, h, dep_line(deps, block_meta))
              end
            end)
            |> IO.inspect()
          {{:defp, meta, [fun, [do: {:__block__, block_meta, [deps]}]]}, state}
        other, state ->
          {other, state}
      end)
      |> Sourceror.to_string()

    File.write("/Users/shahryar/Desktop/dvote/deployment/mix.exs", content)
  end

  defp dep(:git, name, url, tag, dep_line) do
    {:__block__, [closing: [line: dep_line], line: dep_line],
      [
        {{:__block__, [line: dep_line], [String.to_atom(name)]},
        [
          {{:__block__, [format: :keyword, line: dep_line], [:git]}, {:__block__, [delimiter: "\"", line: dep_line,], [url]}},
          {{:__block__, [format: :keyword, line: dep_line], [:tag]}, {:__block__, [delimiter: "\"", line: dep_line], [tag]}}

          # {{:__block__,[format: :keyword, line: dep_line], [:only]}, {:__block__, [line: dep_line],[:dev]}}
        ]}
      ]
    }
  end

  defp dep(:git, name, url, dep_line) do
    {:__block__, [closing: [line: dep_line], line: dep_line],
      [
        {{:__block__, [line: dep_line], [String.to_atom(name)]},
        [
          {{:__block__, [format: :keyword, line: dep_line], [:git]}, {:__block__, [delimiter: "\"", line: dep_line,], [url]}}
        ]}
      ]
    }
  end

  defp dep(:path, name, path, dep_line) do
    {:__block__, [closing: [line: dep_line], line: dep_line],
      [
        {{:__block__, [line: dep_line], [String.to_atom(name)]},
        [
          {{:__block__, [format: :keyword, line: dep_line], [:path]}, {:__block__, [delimiter: "\"", line: dep_line,], [path]}}
        ]}
      ]
    }
  end

  defp dep(name, version, dep_line) do
    {:__block__, [line: dep_line], [{String.to_atom(name), {:__block__, [line: dep_line, delimiter: "\""], ["~> " <> version]}}]}
  end

  defp dep_line(deps, block_meta) do
    case List.last(deps) do
      {_, meta, _} ->
        meta[:line] || block_meta[:line]

      _ ->
        block_meta[:line]
    end + 1
  end
end
