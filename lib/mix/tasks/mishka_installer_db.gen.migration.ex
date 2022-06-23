defmodule Mix.Tasks.MishkaInstaller.Db.Gen.Migration do
  @shortdoc "Generates Guardian.DB's migration"

  use Mix.Task

  import Mix.Ecto
  import Mix.Generator

  @spec run([any]) :: :ok
  @doc false
  def run(args) do
    no_umbrella!("ecto.gen.migration")

    case get_list_of_files() do
      true ->
        repos = parse_repo(args)

        Enum.each(repos, fn repo ->
          ensure_repo(repo, args)
          path = Ecto.Migrator.migrations_path(repo)

          :mishka_installer
          |> Application.app_dir()
          |> Path.join("priv/*.eex")
          |> Path.wildcard()
          |> Enum.reverse()
          |> Enum.map(fn file ->
            generated_file(Path.basename(file), file, path)
            :timer.sleep(2000)
          end)
        end)

      msg ->
        Mix.raise(msg)
    end
  end

  @spec generated_file(binary, binary, binary) :: boolean

  def generated_file(filename, source_path, path) do
    generated_file =
      EEx.eval_file(source_path,
        module_prefix: app_module(),
        db_prefix: prefix()
      )

    target_file = Path.join(path, "#{timestamp()}_#{String.trim(filename, ".exs.eex")}.exs")
    create_directory(path)
    create_file(target_file, generated_file)
  end

  defp app_module do
    Mix.Project.config()
    |> Keyword.fetch!(:app)
    |> to_string()
    |> Macro.camelize()
  end

  @spec timestamp :: binary
  def timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp prefix do
    :mishka_installer
    |> Application.fetch_env!(:basic)
    |> Keyword.get(:prefix, nil)
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  defp get_list_of_files() do
    with {:ls_file, {:ok, files_list}} <- {:ls_file, File.ls("priv/repo/migrations")},
         {:activity, false} <-
           {:activity, Enum.any?(files_list, &String.match?(&1, ~r/_activity_migration.exs/))},
         {:plugin, false} <-
           {:plugin, Enum.any?(files_list, &String.match?(&1, ~r/_plugin_migration.exs/))} do
      true
    else
      {:ls_file, _} ->
        "Please check there is migrations (priv/repo/migrations) folder in your project"

      {:activity, true} ->
        "If you run this script before please delete _activity_migration.exs file"

      {:plugin, true} ->
        "If you run this script before please delete _plugin_migration.exs file"
    end
  end
end
