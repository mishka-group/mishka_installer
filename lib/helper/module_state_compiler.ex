defmodule MishkaInstaller.Helper.ModuleStateCompiler do
  @state_dir "MishkaInstaller.Helper.ModuleStateCompiler.State."

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  def create(plugins, event) do
    module = module_event_name(event)
    escaped_plugins = Macro.escape(plugins)

    ast =
      quote do
        defmodule unquote(module) do
          def call(state, args \\ []) do
            private = Keyword.get(args, :private)
            return_status = Keyword.get(args, :return)

            performed =
              unquote(Macro.escape(plugins))
              |> MishkaInstaller.Helper.ModuleStateCompiler.perform({:reply, state})

            if !is_nil(return_status) do
              state
            else
              case performed do
                {:ok, data} when is_list(data) ->
                  if Keyword.keyword?(data) and !is_nil(private),
                    do: {:ok, Keyword.merge(data, private)},
                    else: {:ok, data}

                {:ok, data} when is_map(data) ->
                  {:ok, if(!is_nil(private), do: Map.merge(data, private), else: data)}

                {:error, _errors} = errors ->
                  errors

                data when is_list(data) ->
                  if Keyword.keyword?(data) and !is_nil(private),
                    do: Keyword.merge(data, private),
                    else: data

                data when is_map(data) ->
                  if !is_nil(private), do: Map.merge(data, private), else: data
              end
            end
          rescue
            _e -> state
          end

          def initialize?(), do: true

          def initialize() do
            %{module: unquote(module), plugins: unquote(escaped_plugins)}
          end

          def is_changed?([]) do
            [] != unquote(escaped_plugins)
          end

          def is_changed?(new_plugins) do
            !Enum.all?(new_plugins, &(&1 in unquote(escaped_plugins)))
          end

          def is_initialized?(new_plugin) do
            Enum.member?(unquote(escaped_plugins), new_plugin)
          end
        end
      end

    [{^module, _}] = Code.compile_quoted(ast, "nofile")
    {:module, ^module} = Code.ensure_loaded(module)
    :ok
  rescue
    e in CompileError ->
      {:error, [%{message: e.description, field: :event, action: :compile}]}

    _ ->
      {:error, [%{message: "Unexpected error", field: :event, action: :compile}]}
  end

  def purge_create(plugins, event) do
    purge(event)
    create(plugins, event)
  end

  def purge(events) when is_list(events) do
    Enum.each(events, &purge(&1))
    :ok
  end

  def purge(event) do
    module = module_event_name(event)
    :code.purge(module)
    :code.delete(module)
    :ok
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  def module_event_name(event) do
    event
    |> String.trim()
    |> String.replace(" ", "_")
    |> then(&Regex.replace(~r/^\d+/, &1, ""))
    |> Macro.camelize()
    |> then(&String.to_atom(@state_dir <> &1))
    |> then(&Module.concat([&1]))
  end

  def initialize?(event), do: module_event_name(event).initialize?

  def rescue_initialize?(event) do
    module = module_event_name(event)
    module.initialize?
  rescue
    _ -> false
  end

  def compile_initialize?(event) do
    module = module_event_name(event)
    Code.ensure_loaded?(module)
  end

  def safe_initialize?(event) do
    module = module_event_name(event)
    function_exported?(module, :initialize?, 0)
  end

  def perform([], {:reply, state}), do: state

  def perform(_plugins, {:reply, :halt, state}), do: state

  def perform([h | t], {:reply, state}) do
    new_state = apply(h.name, :call, [state])
    perform(t, new_state)
  end
end
