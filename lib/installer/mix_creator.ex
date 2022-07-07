defmodule MishkaInstaller.Installer.MixCreator do
  @moduledoc """
  In version 0.0.2, the MishkaInstaller library was used to download a dependency from the project's own `mix.exs` file,
  so this module was written to edit this file.
  In fact, this module uses the Sourceror library to change the mentioned `mix.exs` file (with `AST`).
  Another use of this module is reading information from the programmer's Git or custom link.

  - Warning: in the next versions of MishkaInstaller, instead of `mix.exs`, the client project will be downloaded directly from
  `Git` or **hex.pm** site. If this update is executed, the original project will not be changed.
  - This module is not going to be deleted in new versions.
  """

  @doc """
  With the help of this function, you can make a backup copy of `mix.exs` and `mix.lock` of your project and keep it in the
  `deployment/extensions` path.
  If this function is used with one input, it targets the `mix.exs` file, and if the second input is `:lock` atom,
  it targets the `mix.lock` file to keep a backup copy.
  With the help of this function, you can make a backup copy of `mix.exs` and `mix.lock` of your project and keep
  it in the `deployment/extensions` path.
  If this function is used with one input, it targets the `mix.exs` file, and if the second input is `:lock` atom,
  it targets the `mix.lock` file to keep a backup copy.

  ## Examples

  ```elixir
  MishkaInstaller.Installer.MixCreator.backup_mix("mix.exs")
  MishkaInstaller.Installer.MixCreator.backup_mix("mix.lock", :lock)
  ```
  """
  @spec backup_mix(binary) :: {:error, atom} | {:ok, non_neg_integer}
  def backup_mix(mix_path), do: File.copy(mix_path, backup_path())

  @doc """
  Read `backup_mix/1` description.
  """
  @spec backup_mix(binary(), :lock) :: {:error, atom} | {:ok, non_neg_integer}
  def backup_mix(lock_path, :lock), do: File.copy(lock_path, backup_path("original_mix.lock"))

  @doc """
  This function is also the same as the `backup_mix/1` function, with the difference that it returns the backed-up version
  to the project path. Both functions use the `File.copy/2` function just to improve the naming and also to warn the programmer
  that it has been replaced in this file.

  ## Examples

  ```elixir
  MishkaInstaller.Installer.MixCreator.restore_mix("mix.exs")
  MishkaInstaller.Installer.MixCreator.restore_mix("mix.lock", :lock)
  ```
  """
  @spec restore_mix(binary) :: {:error, atom} | {:ok, non_neg_integer}
  def restore_mix(mix_path), do: File.copy(backup_path(), mix_path)

  @doc """
  Read `restore_mix/1` description.
  """

  @spec restore_mix(binary(), :lock) :: {:error, atom} | {:ok, non_neg_integer}
  def restore_mix(lock_path, :lock), do: File.copy(backup_path("original_mix.lock"), lock_path)

  @doc """
  This function receives a list of libraries stored in the `extensions.json` file along with the `mix.exs` path of the file
  that needs to be changed, and after that, it changes the `deps` function in `mix.exs` and overwrites it with the new libraries.

  ## Examples

  ```elixir
  mix_path = MishkaInstaller.get_config(:mix)
  MixCreator.create_mix(mix_path.project[:deps], "mix_path")
  ```

  As you see, we pass the current dependencies to let this function merge it with `extensions.json`
  """
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

  defp dep(:in_umbrella, name, value, dep_line) do
    {:__block__, [closing: [line: dep_line], line: dep_line],
     [
       {{:__block__, [line: dep_line], [name]},
        [
          {{:__block__, [format: :keyword, line: dep_line], [:in_umbrella]},
           {:__block__, [delimiter: "\"", line: dep_line], [value]}}
        ]}
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

  defp create_mix_postwalk(app_name, [[in_umbrella: value]], dep_line) do
    dep(:in_umbrella, app_name, value, dep_line)
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
    path = MishkaInstaller.get_config(:project_path)
    Path.join(path, ["deployment/", "extensions/", "#{file_name}"])
  end
end
