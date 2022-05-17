defmodule MishkaInstaller.Installer.MixCreator do

  def backup_mix(_mix_path) do

  end

  def restore_mix(_mix_path) do

  end

  def create_mix(mix_path) do
    content =
      File.read!(mix_path)
      |> Sourceror.parse_string!()
      |> Sourceror.postwalk(fn
        {:defp, meta, [{:deps, _, _} = fun, body]}, state ->
          [{{_, _, [:do]}, block_ast}] = body
          {:__block__, block_meta, [deps]} = block_ast

          dep_line =
            case List.last(deps) do
              {_, meta, _} ->
                meta[:line] || block_meta[:line]

              _ ->
                block_meta[:line]
            end + 1

          # TODO: should create mix deps with typs like {git, path, notmal from hex}
          deps =
            deps ++
              [
                {:__block__, [line: dep_line],
                  [
                    {
                      :mishka_social,
                      {:__block__, [line: dep_line, delimiter: "\""], ["~> " <> "0.0.1"]}
                    }
                  ]
                }
              ] ++
              [
                {:__block__, [line: dep_line],
                  [
                    {:mishka_developer_tools, git: "https://github.com/mishka-group/mishka_developer_tools.git", tag: "0.0.6"}
                  ]
                }
              ]

          ast = {:defp, meta, [fun, [do: {:__block__, block_meta, [deps]}]]}
          {ast, state}

        other, state ->
          {other, state}
      end)
      |> Sourceror.to_string()

    File.write("mix.exs", content)
  end
end
