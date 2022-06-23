defmodule MishkaInstaller.Installer.MixCreator do
  @spec backup_mix(binary) :: {:error, atom} | {:ok, non_neg_integer}
  def backup_mix(mix_path), do: File.copy(mix_path, backup_path())

  @spec backup_mix(binary(), :lock) :: {:error, atom} | {:ok, non_neg_integer}
  def backup_mix(lock_path, :lock), do: File.copy(lock_path, backup_path("original_mix.lock"))

  @spec restore_mix(binary) :: {:error, atom} | {:ok, non_neg_integer}
  def restore_mix(mix_path), do: File.copy(backup_path(), mix_path)

  @spec restore_mix(binary(), :lock) :: {:error, atom} | {:ok, non_neg_integer}
  def restore_mix(lock_path, :lock), do: File.copy(backup_path("original_mix.lock"), lock_path)

  @spec create_mix([tuple()], binary()) :: :ok | {:error, atom}
  def create_mix(list_of_deps, mix_path) do
    content =
      File.read!(mix_path)
      |> Sourceror.parse_string!()
      |> Sourceror.postwalk(fn
        {:defp, meta, [{:deps, _, _} = fun, [{{_, _, [:do]}, {:__block__, block_meta, [deps]}}]]},
        state ->
          deps =
            MishkaInstaller.Installer.DepHandler.append_mix(list_of_deps)
            |> Enum.map(fn item ->
              [app_name | options] = Tuple.to_list(item)
              create_mix_postwalk(app_name, options, dep_line(deps, block_meta))
            end)

          {{:defp, meta, [fun, [do: {:__block__, block_meta, [deps]}]]}, state}

        other, state ->
          {other, state}
      end)
      |> Sourceror.to_string()

    File.write(mix_path, content)
  end

  defp dep(:git, name, url, dep_line, other_options) do
    {:__block__, [closing: [line: dep_line], line: dep_line],
     [
       {{:__block__, [line: dep_line], [name]},
        [
          {{:__block__, [format: :keyword, line: dep_line], [:git]},
           {:__block__, [delimiter: "\"", line: dep_line], [url]}}
        ] ++ implement_other_options(other_options, dep_line)}
     ]}
  end

  defp dep(:path, name, path, dep_line, other_options) do
    {:__block__, [closing: [line: dep_line], line: dep_line],
     [
       {{:__block__, [line: dep_line], [name]},
        [
          {{:__block__, [format: :keyword, line: dep_line], [:path]},
           {:__block__, [delimiter: "\"", line: dep_line], [path]}}
        ] ++ implement_other_options(other_options, dep_line)}
     ]}
  end

  defp dep(name, full_version, dep_line, other_options) do
    {:{},
     [trailing_comments: [], leading_comments: [], closing: [line: dep_line], line: dep_line],
     [
       {:__block__, [trailing_comments: [], leading_comments: [], line: dep_line], [name]},
       {:__block__,
        [trailing_comments: [], leading_comments: [], delimiter: "\"", line: dep_line],
        clean_mix_version(full_version)},
       implement_other_options(other_options, dep_line, :nested)
     ]}
  end

  defp dep(name, full_version, dep_line) do
    {:__block__, [line: dep_line],
     [{name, {:__block__, [line: dep_line, delimiter: "\""], clean_mix_version(full_version)}}]}
  end

  defp create_mix_postwalk(app_name, [[{:path, value} | other_options] = h | _t], dep_line)
       when is_list(h) do
    dep(:path, app_name, value, dep_line, other_options)
  end

  defp create_mix_postwalk(app_name, [[{:git, value} | other_options] = h | _t], dep_line)
       when is_list(h) do
    dep(:git, app_name, value, dep_line, other_options)
  end

  defp create_mix_postwalk(app_name, [version | t], dep_line)
       when is_binary(version) and t == [] do
    dep(app_name, version, dep_line)
  end

  defp create_mix_postwalk(app_name, [version | [other_options]], dep_line)
       when is_binary(version) and is_list(other_options) do
    dep(app_name, version, dep_line, other_options)
  end

  defp implement_other_options(other_options, dep_line) do
    Enum.map(other_options, fn {key, value} ->
      {{:__block__, [format: :keyword, line: dep_line], [key]},
       {:__block__, [delimiter: "\"", line: dep_line], [value]}}
    end)
  end

  defp implement_other_options(other_options, dep_line, :nested) do
    Enum.map(other_options, fn {key, value} ->
      {{:__block__,
        [trailing_comments: [], leading_comments: [], format: :keyword, line: dep_line], [key]},
       {:__block__, [trailing_comments: [], leading_comments: [], line: dep_line], [value]}}
    end)
  end

  defp dep_line(deps, block_meta) do
    case List.last(deps) do
      {_, meta, _} -> meta[:line] || block_meta[:line]
      _ -> block_meta[:line]
    end + 1
  end

  defp clean_mix_version(full_version) do
    case String.trim(full_version) |> String.split(" ") do
      [type, version] ->
        ["#{type} " <> version]

      _ ->
        full_version =
          full_version
          |> String.replace("~>", "")
          |> String.replace(">=", "")
          |> String.trim()

        ["~> " <> full_version]
    end
  end

  defp backup_path(file_name \\ "original_mix.exs") do
    path = MishkaInstaller.get_config(:project_path) || File.cwd!()
    Path.join(path, ["deployment/", "extensions/", "#{file_name}"])
  end
end
