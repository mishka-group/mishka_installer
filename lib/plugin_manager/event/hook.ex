defmodule MishkaInstaller.Hook do
  @moduledoc """
  In addition to being one of the most significant modules of the MishkaInstaller library,
  the Hook module gives you the ability to make the library as a whole,
  as well as the projects that make use of this library, more modular.

  It is essential to comprehend that you may treat any action performed independently
  as an event and register an unlimited number of plugins for that event.

  You can do this by considering that action to be done separately.
  Each plugin has the potential to have its own individual inputs and outputs,
  and depending on the architecture of the area that you want to use Hook in,
  you may even be able to change the output and send it to other plugins.

  Throughout all of the many parts that have been built for this module,
  it has been attempted to have a flexible approach to dealing with errors
  and to provide the programmer with a wide variety of options.

  With the additional functions at her disposal, the programmer can actually create a
  gateway in their projects, where the data flow must pass through several gates,
  whether it changes or remains unchanged, and a series of operations are performed.

  For illustration's sake, let's suppose you want the registration system to allow users
  to sign up for social networks on Twitter and Google.

  When you use this library, it is conceivable that you can quickly display HTML
  or even operate in the background before registering after registering.

  This is a significant improvement over the standard practice,
  in which you are required to modify the primary codes of your project. Create a separate plugin.

  It is interesting to notice that these facilities are quite basic and convenient for the admin user.

  If this opportunity is provided, the management can manage its own plugins in different ways if it has a dashboard.

  It is crucial to highlight that each plugin is its own Genserver; in addition,
  it is dynamically supervised, and the information is stored in the database as well as in ETS.

  Furthermore, this section is very useful even if the programmer wants to perform many tasks
  that are not associated with Perform defined functions.

  The fact that the programmers have to introduce each plugin to the system based on a specific
  behavior is one of the exciting aspects of using this section. Additionally,
  the system has prepared some default behaviors to force the programmers
  to introduce the plugins in the order specified by the system.

  The use of custom behaviors on the part of the programmer and MishkaInstaller itself makes debugging easier;
  however, this library does not leave the programmer to fend for themselves in this significant matter;
  rather, a straightforward error storage system is prepared based on the particular activities being performed.

  Should prevent any unpredictable behavior at any costs.

  ## Build purpose
  ---

  Imagine you are going to make an application that will have many plugins built for it in the future.
  But the fact that many manipulations will be made on your source code makes it difficult to maintain the application.
  For example, you present a content management system for your users,
  and now they need to activate a section for registration and SMS;
  the system allows you to present your desired input/output absolutely plugin oriented to your users and makes
  it possible for the developers to write their required applications beyond the core source code.

  > We have used this library in the [Mishka content management system](https://github.com/mishka-group/mishka-cms).

  ## Plugin management system implementation theory
  ---

  The library categorizes your whole software design structure into many parts;
  and has an appropriate dependency that is optional with Genserver;
  it considers a monitoring branch for each of your plugins, which results in fewer errors and `downtime`. The considered part:

  1. Behaviors and events
  2. Recalling or `Hook` with priority
  3. `State` management and links to the database (`PostgreSQL` support)

  Except from the 1st item, which can be redefined based on the developer's needs in his/her personal systems,
  the remaining items are almost constant, and a lot of functions will be handed to the developer to manage each plugin.

  ## Behaviors and events
  ---

  In this section, you can define a series of events for each `event`,
  for example: after `successful registration` or `unsuccessful purchase` from “the store”,
  and for each `event`, put a set of `callbacks` in one module. After completing this step,
  when the user wants to create his own plugin, the `@behaviour` module will call you in its action module.
  This helps you have a regular and error-free system, and the library uses an almost integrated structure in all of its events.

  ## `Hook` with priority
  ---

  In Mishka Elixir Plugin Management Library, a series of action or `hook` functions are given to the developer of the main plugin or software,
  which helps build plugins outside the system and convert software sections into separate `events`.
  Some of the functions of this module include the following:

  1. Registering a plugin outside of the system in database and ram `state`
  2. Removing plugin from database and `state`
  3. Restoring plugin
  4. Successful pause of plugin
  5. `Hook` plugin
  6. Search among the `events`

  And other functions that help both the mother software become an event-driven system and the developer
  can build the desired plugin or extension for different parts of the software and install it on the system as a separate package.
  This package can also be published in `hex`.

  ## State management and links to the database supporting `PostgreSQL`
  ---


  The `Hook` module manages a large part of this part, and the developer of the external plugin usually does not need it much.
  Still, this part creates a `state` on RAM for each plugin that is activated in a specific event and a dynamic supervisor for it.
  This allows us in case of an error in each plugin;
  the other plugins in the different events face no errors, and the system will try to restart with various strategies.
  It should be noted for more stability and data storage after registering a plugin in the system;
  This section also maintains a backup copy of the database and strategies for recall in the event in case of an error.
  But to speed up the calling of each plugin, the website always uses `state`.

  ## Using the library:
  ---

  After installing this library, you must first install the required database of this package on your website,
  for which a `mix task` has been created, which is enough to load it once in your terminal, in the project path before the start.

  ```elixir
  mix mishka_installer.db.gen.migration
  ```

  After implementing the above sections, you must first implement events in your main software and place
  the `call` function from the `Hook` module there to call all the plugins activated in the event you want based on priority.
  And give the `state` you want, to these plugins in order, and the output you expect will eventually be generated.

  For example, you can see the mentioned description in a function controller in phoenix after a successful registration as the following:

  ```elixir
  def login(conn, %{"user" => %{"email" => email, "password" => password}} = _params) do
    # If your conditions are passed we call an event and pass it a struct of entries
    # which our developers need to create plugin with this information
    state = %MishkaInstaller.Reference.OnUserAfterLogin{
        conn: conn,
        endpoint: :html,
        ip: user_ip, type: :email,
        user_info: user_info
     }

    hook = MishkaInstaller.Hook.call(event: "on_user_after_login", state: state)

    hook.conn
    |> renew_session()
    |> put_session(:user_id, user_info.id)
    |> put_flash(:info, "You entered to our world, well played.")
    |> redirect(to: "/home")
  end
  ```

  Now the event is ready in the part where you need to allow the developer to make his own plugins for it.
  And it's time to write a plugin for this section. This is very simple. Consider the following example:

  ```elixir
  defmodule MishkaUser.SuccessLogin do
   alias MishkaInstaller.Reference.OnUserAfterLogin
   use MishkaInstaller.Hook,
      module: __MODULE__,
      behaviour: OnUserAfterLogin,
      event: :on_user_after_login,
      initial: []

   @spec initial(list()) :: {:ok, OnUserAfterLogin.ref(), list()}
   def initial(args) do
      event = %PluginState{name: "MishkaUser.SuccessLogin", event: Atom.to_string(@ref), priority: 1}
      Hook.register(event: event)
      {:ok, @ref, args}
   end

   @spec call(OnUserAfterLogin.t()) :: {:reply, OnUserAfterLogin.t()}
   def call(%OnUserAfterLogin{} = state) do
      new_state = Your_Code_Or_Function
      {:reply, new_state}
   end
  end
  ```

  > As you can see in the above, we used `MishkaInstaller.Reference.OnUserAfterLogin` in order to activate `behavior` which has a few `callback` in it,
  > and you can see [here](https://github.com/mishka-group/mishka_installer/blob/master/lib/plugin_manager/event/reference/on_user_after_login.ex).

  ---

  > There should be two main functions in each plugin, namely `initial` and also `call`. In the first function,
  > we introduce our plugin, and in the second function, whenever the action function calls this special event for which the plugin is written,
  > based on priority. This plugin is also called. But what is important is the final output of the `call` function.
  > This output may be the input of other plugins with higher priorities.
  > The order of the plugins is from small to large, and if several plugins are registered for a number,
  > it is sorted by name in the second parameter. And it should be noted that in any case,
  > if you did not want this `state` to go to other plugins and the last output is returned in the same plugin,
  > and you can replace `{:reply, :halt, new_state}` with `{:reply, new_state}`.

  Subsequent plugins with higher priorities are not counted, and the loop ends here.
  Notice that a Genserver will be made based on each plugin name without a supervisor,
  which can be used for temporary memory in the case when the ` __using__` function is used as above,
  which results in the following option:

  ```elixir
  use MishkaInstaller.Hook,
      module: __MODULE__,
      behaviour: OnUserAfterLogin,
      event: :on_user_after_login,
      initial: []
  ```

  The last two step to use the plugin you have to put it in your `Application` module so that whenever the server is turned off and on,
  the plugin is run again and if it is not registered, a copy of its support will be provided once in the database.

  ```elixir
  children = [
    %{id: YOUR_PLUGIN_MODULE, start: {YOUR_PLUGIN_MODULE, :start_link, [[]]}}
  ]
  ```

  And add these config in your project like `/config/config.exs`

  ```elixir
  config :mishka_installer, :basic,
    repo: YOUR_Repo,
    pubsub: YOUR_PUBSUB or nil,
    html_router: YOUR_WEBSITE_ROUTER_MODULE
  ```


  ---

  ## Module communication process of MishkaInstaller.Hook

  ### 1. call plugins

  ```

                                      +--------------+
                                      |  Application |
                                      +------+-------+
                                             |
                                      +------v------+
                                      |  Supervisor |
                                      +------+------+
                                             |
                                             |
  +---------------------------+ +------------v----------------+
  |                           | |                             |
  | MishkaInstaller.PluginETS | | MishkaInstaller.PluginState |
  |                           | |                             |
  +---------------+-----------+ +-------------+---------------+
                  |                           |
                  |                           |
              +---v---------------------------v-----+
              |                                     |
              |      MishkaInstaller.Hook.call      |
              |                                     |
              +-------------------------------------+

  ```
  ---

  ### 2. Register plugin

  ```
                                      +--------------+
                                      |  Application |
                                      +------+-------+
                                             |
                                      +------v------+
                                      |  Supervisor |
                                      +-------+-----+
                                              |
                                              |
  +---------------------------+ +-------------v---------------+
  |                           | |                             |
  | MishkaInstaller.PluginETS | | MishkaInstaller.PluginState |
  |                           | |                             |
  +-----------------^---------+ +-------------^---------------+
                    |                         |
                    |                         |
              +-----+-------------------------+-----+
              |                                     |
              |    MishkaInstaller.Hook.register    |
              |                                     |
              +-------------------^-----------------+
                                  |
                                  |
                    +-------------+----------------+
                    | Developer's plugin Genserver |
                    +-------------^----------------+
                                  |
                                  |
                    +-------------+----------------+
                    |                              |
                    |Developer's plugin Application|
                    |                              |
                    +------------------------------+
  ```
  """
  alias MishkaInstaller.PluginState
  alias MishkaInstaller.PluginStateDynamicSupervisor, as: PSupervisor
  alias MishkaInstaller.Plugin
  alias MishkaInstaller.PluginETS
  @allowed_fields [:name, :event, :priority, :status, :depend_type, :depends, :extra, :id]

  @typedoc "This type can be used when you want to introduce an event"
  @type event() :: String.t()
  @typedoc "This type can be used when you want to introduce an plugin"
  @type plugin() :: event()

  @doc """
  """
  @spec register([{:depends, :force} | {:event, MishkaInstaller.PluginState.t()}]) ::
          {:error, :register, any} | {:ok, :register, :activated | :force}
  def register(event: %PluginState{} = event) do
    extra = (event.extra || []) ++ [%{operations: :hook}, %{fun: :register}]

    register_status =
      with {:ok, :ensure_event, _msg} <- ensure_event(event, :debug),
           {:error, :get_record_by_field, :plugin} <- Plugin.show_by_name("#{event.name}"),
           {:ok, :add, :plugin, _record_info} <- Plugin.create(event, @allowed_fields) do
        # Create a Genserver with DynamicSupervisor
        PluginState.push_call(event)
        # Save all event info into ETS, Existed-key is overwritten
        PluginETS.push(event)
        {:ok, :register, :activated}
      else
        {:error, :ensure_event, %{errors: check_data}} ->
          MishkaInstaller.plugin_activity(
            "add",
            Map.merge(event, %{extra: extra}),
            "high",
            "error"
          )

          {:error, :register, check_data}

        {:ok, :get_record_by_field, :plugin, record_info} ->
          # Create a Genserver with DynamicSupervisor
          PluginState.push_call(plugin_state_struct(record_info))
          # Save all event info into ETS, Existed-key is overwritten
          PluginETS.push(plugin_state_struct(record_info))
          {:ok, :register, :activated}

        {:error, :add, :plugin, repo_error} ->
          MishkaInstaller.plugin_activity(
            "add",
            Map.merge(event, %{extra: extra}),
            "high",
            "error"
          )

          {:error, :register, repo_error}
      end

    register_status
  end

  def register(event: %PluginState{} = event, depends: :force) do
    # Create a Genserver with DynamicSupervisor
    PluginState.push_call(event)
    # Save all event info into ETS
    PluginETS.push(event)
    {:ok, :register, :force}
  end

  @doc """
  """
  @spec start([{:depends, :force} | {:event, event()} | {:module, plugin()}]) ::
          list | {:error, :start, any()} | {:ok, :start, :force | String.t()}
  def start(module: module_name) do
    with {:ok, :get_record_by_field, :plugin, record_info} <-
           Plugin.show_by_name("#{module_name}"),
         {:ok, :ensure_event, _msg} <- ensure_event(plugin_state_struct(record_info), :debug) do
      # Create a Genserver with DynamicSupervisor
      PluginState.push_call(plugin_state_struct(record_info) |> Map.merge(%{status: :started}))
      # Save all event info into ETS, Existed-key is overwritten
      PluginETS.push(plugin_state_struct(record_info) |> Map.merge(%{status: :started}))

      {:ok, :start,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The module's status was changed"
       )}
    else
      {:error, :get_record_by_field, :plugin} ->
        {:error, :start,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the database."
         )}

      {:error, :ensure_event, %{errors: check_data}} ->
        {:error, :start, check_data}
    end
  end

  def start(module: module_name, depends: :force) do
    with {:ok, :get_record_by_field, :plugin, record_info} <-
           Plugin.show_by_name("#{module_name}") do
      # Create a Genserver with DynamicSupervisor
      PluginState.push_call(plugin_state_struct(record_info) |> Map.merge(%{status: :started}))
      # Save all event info into ETS, Existed-key is overwritten
      PluginETS.push(plugin_state_struct(record_info) |> Map.merge(%{status: :started}))
      {:ok, :start, :force}
    else
      {:error, :get_record_by_field, :plugin} ->
        {:error, :start,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the database."
         )}
    end
  end

  def start(event: event) do
    Plugin.plugins(event: event)
    |> Enum.map(&start(module: &1.name))
  end

  def start(event: event, depends: :force) do
    Plugin.plugins(event: event)
    |> Enum.map(&start(module: &1.name, depends: :force))
  end

  @doc """
  """
  @spec restart([{:depends, :force} | {:event, event()} | {:module, plugin()}]) ::
          list | {:error, :restart, any()} | {:ok, :restart, String.t()}
  def restart(module: module_name) do
    with {:ok, :delete} <- PluginState.delete(module: module_name),
         {:ok, :get_record_by_field, :plugin, record_info} <-
           Plugin.show_by_name("#{module_name}"),
         {:ok, :ensure_event, _msg} <- ensure_event(plugin_state_struct(record_info), :debug) do
      # Create a Genserver with DynamicSupervisor
      PluginState.push_call(plugin_state_struct(record_info))
      # Save all event info into ETS, Existed-key is overwritten
      PluginETS.push(plugin_state_struct(record_info))

      {:ok, :restart,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The module concerned was restarted"
       )}
    else
      {:error, :delete, :not_found} ->
        {:error, :restart,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the state."
         )}

      {:error, :ensure_event, %{errors: check_data}} ->
        {:error, :restart, check_data}

      {:error, :get_record_by_field, :plugin} ->
        {:error, :restart,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the database."
         )}
    end
  end

  def restart(module: module_name, depends: :force) do
    with {:ok, :delete} <- PluginState.delete(module: module_name),
         {:ok, :get_record_by_field, :plugin, record_info} <-
           Plugin.show_by_name("#{module_name}") do
      # Create a Genserver with DynamicSupervisor
      PluginState.push_call(plugin_state_struct(record_info))
      # Save all event info into ETS, Existed-key is overwritten
      PluginETS.push(plugin_state_struct(record_info))

      {:ok, :restart,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The module concerned was restarted"
       )}
    else
      {:error, :delete, :not_found} ->
        {:error, :restart,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the state."
         )}

      {:error, :get_record_by_field, :plugin} ->
        {:error, :restart,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the database."
         )}
    end
  end

  def restart(event: event_name) do
    Plugin.plugins(event: event_name)
    |> Enum.map(&restart(module: &1.name))
  end

  def restart(event: event_name, depends: :force) do
    Plugin.plugins(event: event_name)
    |> Enum.map(&restart(module: &1.name, depends: :force))
  end

  def restart(depends: :force) do
    Plugin.plugins()
    |> Enum.map(&restart(module: &1.name, depends: :force))
  end

  def restart() do
    Plugin.plugins()
    |> Enum.map(&restart(module: &1.name))
  end

  @doc """
  """
  @spec stop([{:event, event()} | {:module, plugin()}]) ::
          list | {:error, :stop, String.t()} | {:ok, :stop, String.t()}
  def stop(module: module_name) do
    case PluginState.stop(module: module_name) do
      {:ok, :stop} ->
        PluginETS.delete(module: module_name)

        {:ok, :stop,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned was stopped"
         )}

      {:error, :stop, :not_found} ->
        {:error, :stop,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in database."
         )}
    end
  end

  def stop(event: event_name) do
    PSupervisor.running_imports(event_name)
    |> Enum.map(&stop(module: &1.id))
  end

  @doc """
  """
  @spec delete([{:event, event()} | {:module, plugin()}]) ::
          list | {:error, :delete, String.t()} | {:ok, :delete, String.t()}
  def delete(module: module_name) do
    case PluginState.delete(module: module_name) do
      {:ok, :delete} ->
        PluginETS.delete(module: module_name)

        {:ok, :delete,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module's state (%{name}) was deleted",
           name: module_name
         )}

      {:error, :delete, :not_found} ->
        {:error, :delete,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned (%{name}) doesn't exist in the state.",
           name: module_name
         )}
    end
  end

  def delete(event: event_name) do
    PSupervisor.running_imports(event_name)
    |> Enum.map(&delete(module: &1.id))
  end

  @doc """
  """
  @spec unregister([{:event, event()} | {:module, plugin()}]) ::
          list | {:error, :unregister, any} | {:ok, :unregister, Stream.timer()}
  def unregister(module: module_name) do
    with {:ok, :delete, _msg} <- delete(module: module_name),
         {:ok, :get_record_by_field, :plugin, record_info} <- Plugin.show_by_name(module_name),
         {:ok, :delete, :plugin, _} <- Plugin.delete(record_info.id) do
      Plugin.delete_plugins(module_name)

      {:ok, :unregister,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The module concerned (%{name}) and its dependencies were unregister",
         name: module_name
       )}
    else
      {:error, :delete, msg} ->
        {:error, :unregister, msg}

      {:error, :get_record_by_field, :plugin} ->
        {:error, :unregister,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The %{name} module doesn't exist in the database.",
           name: module_name
         )}

      {:error, :delete, status, _error_tag}
      when status in [:uuid, :get_record_by_id, :forced_to_delete] ->
        {:error, :unregister,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "There is a problem to find or delete the record in the database %{status}, module: %{name}",
           status: status,
           name: module_name
         )}

      {:error, :delete, :plugin, repo_error} ->
        {:error, :unregister, repo_error}
    end
  end

  def unregister(event: event_name) do
    Plugin.plugins(event: event_name)
    |> Enum.map(&unregister(module: &1.name))
  end

  @doc """
  """
  def call(event: event_name, state: state, operation: :no_return) do
    call(event: event_name, state: state)
    state
  end

  def call(event: event_name, state: state) do
    call_output =
      PluginETS.get_all(event: event_name)
      |> sorted_plugins()
      |> run_plugin_state({:reply, state})

    if !is_nil(Map.get(state, :private)),
      do: Map.merge(call_output, %{private: state.private}),
      else: call_output
  rescue
    _e -> state
  end

  @spec ensure_event?(PluginState.t()) :: boolean
  def ensure_event?(%PluginState{depend_type: :hard, depends: depends} = event) do
    check_data = check_dependencies(depends, event.name)

    Enum.any?(check_data, fn {status, _error_atom, _event, _msg} -> status == :error end)
    |> case do
      true -> false
      false -> true
    end
  end

  @doc """
  """
  def ensure_event?(%PluginState{} = _event), do: true

  @spec ensure_event(PluginState.t(), :debug) ::
          {:error, :ensure_event, %{errors: list}} | {:ok, :ensure_event, String.t()}
  def ensure_event(%PluginState{depend_type: :hard, depends: depends} = event, :debug)
      when depends != [] do
    check_data = check_dependencies(depends, event.name)

    Enum.any?(check_data, fn {status, _error_atom, _event, _msg} -> status == :error end)
    |> case do
      true ->
        {:error, :ensure_event, %{errors: check_data}}

      false ->
        {:ok, :ensure_event,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The modules concerned are activated"
         )}
    end
  end

  def ensure_event(%PluginState{depend_type: :hard} = _event, :debug),
    do:
      {:ok, :ensure_event,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The modules concerned are activated"
       )}

  def ensure_event(%PluginState{} = _event, :debug),
    do: {:ok, :ensure_event, "The modules concerned are activated"}

  defp run_plugin_state([], {:reply, state}), do: state

  defp run_plugin_state(_plugins, {:reply, :halt, state}), do: state

  defp run_plugin_state([h | t], {:reply, state}) do
    new_state = apply(String.to_atom("Elixir.#{h.name}"), :call, [state])
    run_plugin_state(t, new_state)
  end

  defp sorted_plugins(plugins) do
    plugins
    |> Enum.map(fn event ->
      case ensure_event(event, :debug) do
        {:error, :ensure_event, %{errors: _check_data}} ->
          extra = event.extra ++ [%{operations: :hook}, %{fun: :call}]

          MishkaInstaller.plugin_activity(
            "read",
            Map.merge(event, %{extra: extra}),
            "high",
            "error"
          )

          []

        {:ok, :ensure_event, _msg} ->
          %{name: event.name, priority: event.priority, status: event.status}
      end
    end)
    |> Enum.filter(&(&1 != [] and &1.status == :started))
    |> Enum.sort_by(fn item -> {item.priority, item.name} end)
  end

  defp check_dependencies(depends, event_name) do
    Enum.map(depends, fn evn ->
      with {:ensure_loaded, true} <-
             {:ensure_loaded, Code.ensure_loaded?(String.to_atom("Elixir.#{evn}"))},
           plugin_state <- PluginETS.get(module: evn),
           {:plugin_state?, true, _state} <-
             {:plugin_state?, is_struct(plugin_state), plugin_state},
           {:activated_plugin, true, _state} <-
             {:activated_plugin, Map.get(plugin_state, :status) == :started, plugin_state} do
        {:ok, :ensure_event, evn, "The module concerned is activated"}
      else
        {:ensure_loaded, false} ->
          {:error, :ensure_loaded, evn,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "The module concerned doesn't exist."
           )}

        {:plugin_state?, false, _state} ->
          {:error, :plugin_state?, evn,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "The event concerned doesn't exist in state."
           )}

        {:activated_plugin, false, _state} ->
          {:error, :activated_plugin, evn,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "The event concerned is not activated."
           )}
      end
    end) ++
      [string_ensure_loaded(event_name)]
  end

  defp string_ensure_loaded(event_name) do
    case Code.ensure_loaded?(String.to_atom("Elixir.#{event_name}")) do
      true ->
        {:ok, :ensure_event, event_name,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned is activated"
         )}

      false ->
        {:error, :ensure_loaded, event_name,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist."
         )}
    end
  end

  defp plugin_state_struct(output) do
    %PluginState{
      name: output.name,
      event: output.event,
      priority: output.priority,
      status: output.status,
      depend_type: output.depend_type,
      depends: Map.get(output, :depends) || [],
      extra: Map.get(output, :extra) || [],
      parent_pid: Map.get(output, :parent_pid)
    }
  end

  @doc false
  defmacro __using__(opts) do
    quote(bind_quoted: [opts: opts]) do
      import MishkaInstaller.Hook
      use GenServer, restart: :transient
      require Logger
      alias MishkaInstaller.{PluginState, Hook}
      module_selected = Keyword.get(opts, :module)
      initial_entry = Keyword.get(opts, :initial)
      behaviour = Keyword.get(opts, :behaviour)
      event = Keyword.get(opts, :event)

      @ref event
      @behaviour behaviour

      # Start registering with Genserver and set this in application file of MishkaInstaller
      def start_link(_args) do
        GenServer.start_link(unquote(module_selected), %{id: "#{unquote(module_selected)}"},
          name: unquote(module_selected)
        )
      end

      def init(state) do
        if Mix.env() != :test, do: {:ok, state, 300}, else: {:ok, state, 3000}
      end

      # This part helps us to wait for database and completing PubSub either
      def handle_info(:timeout, state) do
        cond do
          !is_nil(MishkaInstaller.get_config(:pubsub)) &&
              is_nil(Process.whereis(MishkaInstaller.get_config(:pubsub))) ->
            {:noreply, state, 100}

          !is_nil(MishkaInstaller.get_config(:pubsub)) ->
            unquote(module_selected).initial(unquote(initial_entry))
            {:noreply, state}

          true ->
            unquote(module_selected).initial(unquote(initial_entry))
            {:noreply, state}
        end
      end
    end
  end
end
