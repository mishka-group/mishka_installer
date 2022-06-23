defmodule MishkaInstaller.Installer.Live.DepGetter do
  use Phoenix.LiveView
  use Phoenix.HTML
  alias Phoenix.LiveView.JS
  alias MishkaInstaller.Installer.{DepHandler, DepChangesProtector}
  alias MishkaInstaller.Reference.OnChangeDependency
  alias MishkaInstaller.Hook
  @event "on_change_dependency"
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
      <div class="container">
        <%= icon(assigns) %>
        <div class="row mt-4">
          <%= dep_form(@selected_form, assigns) %>
        </div>
      </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    DepChangesProtector.subscribe()
    MishkaInstaller.Installer.RunTimeSourcing.subscribe()
    MishkaInstaller.DepUpdateJob.subscribe()

    socket =
      socket
      |> assign(:selected_form, :upload)
      |> assign(:app_name, nil)
      |> assign(:status_message, {nil, nil})
      |> assign(:log, [])
      |> assign(:loaded_apps, Application.loaded_applications())
      |> assign(
        :started_applications,
        Enum.map(Application.started_applications(), fn {app, _, _} -> app end)
      )
      |> assign(
        :update_list,
        Enum.map(MishkaInstaller.DepUpdateJob.get_all(), fn {app, _type, _url, _ver} -> app end)
      )
      |> assign(:uploaded_files, [])
      |> allow_upload(:dep, accept: ~w(.zip), max_entries: 1)

    {:ok, socket,
     temporary_assigns: [log: [], update_list: [], loaded_apps: [], started_applications: []]}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :dep, ref)}
  end

  @impl Phoenix.LiveView
  def handle_event("form_select", %{"type" => type} = _params, socket) do
    socket =
      socket
      |> assign(:status_message, {nil, nil})
      |> assign(:app_name, nil)
      |> assign(:selected_form, String.to_atom(type))
      |> update_app_list()

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("update_app", %{"type" => type} = _params, socket)
      when type in ["force_update", "soft_update"] do
    if type == "force_update" do
      MishkaInstaller.DepCompileJob.add_job(socket.assigns.app_name, :port)
    else
      Hook.call(
        event: @event,
        state: %OnChangeDependency{app: socket.assigns.app_name, status: :force_update},
        operation: :no_return
      )
    end

    socket =
      socket
      |> assign(
        :status_message,
        {:info,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "Your request was sent, after receiving any changes we send you a notification"
         )}
      )
      |> assign(:app_name, nil)
      |> assign(:selected_form, :upload)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"select_form" => "git", "url" => url, "git_tag" => tag}, socket) do
    res = DepHandler.run(:git, %{url: url, tag: tag}, :port)

    new_socket =
      socket
      |> assign(:app_name, res["app_name"])
      |> assign(:status_message, {res["status_message_type"], res["message"]})
      |> assign(:selected_form, res["selected_form"])
      |> assign(:log, [])

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"select_form" => "hex", "app" => app} = _params, socket) do
    res = DepHandler.run(:hex, app, :port)

    new_socket =
      socket
      |> assign(:app_name, res["app_name"])
      |> assign(:status_message, {res["status_message_type"], res["message"]})
      |> assign(:selected_form, res["selected_form"])
      |> assign(:log, [])

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"select_form" => "upload"} = _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :dep, fn %{path: path}, entry ->
        dest =
          Path.join(MishkaInstaller.get_config(:project_path) || File.cwd!(), [
            "deployment/",
            "extensions/",
            entry.client_name
          ])

        File.cp!(path, dest)
        {:ok, dest}
      end)

    new_socket =
      if uploaded_files != [] do
        res = DepHandler.run(:upload, uploaded_files, :port)

        socket
        |> assign(:app_name, res["app_name"])
        |> assign(:status_message, {res["status_message_type"], res["message"]})
        |> assign(:selected_form, res["selected_form"])
        |> assign(:log, [])
        |> update(:uploaded_files, &(&1 ++ uploaded_files))
      else
        socket
        |> assign(
          :status_message,
          {:danger,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "You should select a file."
           )}
        )
      end

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("clean_error", _params, socket) do
    new_socket =
      socket
      |> assign(:status_message, {nil, nil})

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("tools", %{"type" => "restore"}, socket) do
    mix_path = MishkaInstaller.get_config(:mix_path)

    new_socket =
      case MishkaInstaller.Installer.MixCreator.restore_mix(mix_path) do
        {:ok, _output} ->
          socket
          |> assign(
            :status_message,
            {:info,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "Your request was done"
             )}
          )

        _ ->
          socket
          |> assign(
            :status_message,
            {:danger,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "Your request wasn't done, there is a problem, maybe you did not create backup before, or you have no access to this operation."
             )}
          )
      end

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("tools", %{"type" => "backup"}, socket) do
    mix_path = MishkaInstaller.get_config(:mix_path)

    new_socket =
      case MishkaInstaller.Installer.MixCreator.backup_mix(mix_path) do
        {:ok, _output} ->
          socket
          |> assign(
            :status_message,
            {:info,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "Your request was done"
             )}
          )

        _ ->
          socket
          |> assign(
            :status_message,
            {:danger,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "Your request wasn't done, there is a problem, maybe you have no access to this operation."
             )}
          )
      end

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("tools", %{"type" => "task"}, socket) do
    list_app = length(MishkaInstaller.DepUpdateJob.get_all())

    new_socket =
      socket
      |> assign(
        :status_message,
        {:info,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "%{count} apps need to be updated",
           count: list_app
         )}
      )

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("app_action", %{"operation" => "delete", "app" => app}, socket) do
    MishkaInstaller.Installer.RunTimeSourcing.do_runtime(String.to_atom(app), :uninstall)

    case MishkaInstaller.Dependency.show_by_name(app) do
      {:error, :get_record_by_field, :dependency} ->
        nil

      {:ok, :get_record_by_field, :dependency, record_info} ->
        Task.Supervisor.start_child(MishkaInstaller.Installer.DepHandler, fn ->
          :timer.sleep(1000)
          MishkaInstaller.Installer.DepHandler.create_mix_file()
        end)

        MishkaInstaller.Dependency.delete(record_info.id)
    end

    new_socket =
      socket
      |> assign(
        :status_message,
        {:info,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The %{app} app was deleted",
           app: app
         )}
      )
      |> update_app_list()

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("app_action", %{"operation" => "start", "app" => app}, socket) do
    new_socket =
      case Application.start(String.to_atom(app)) do
        :ok ->
          socket
          |> assign(
            :status_message,
            {:info,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "The %{app} app was started successfully, it should be noted if app terminates, it is reported but no other applications are terminated.",
               app: app
             )}
          )
          |> assign(:loaded_apps, Application.loaded_applications())
          |> update_app_list()

        {:error, {:already_started, _app}} ->
          socket
          |> assign(
            :status_message,
            {:warning,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "Then %{app} apps is already started",
               app: app
             )}
          )

        {:error, _output} ->
          socket
          |> assign(
            :status_message,
            {:danger,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "An unspecified error has occurred"
             )}
          )
      end

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("app_action", %{"operation" => "stop", "app" => app}, socket) do
    new_socket =
      case Application.stop(String.to_atom(app)) do
        :ok ->
          socket
          |> assign(
            :status_message,
            {:info,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "The %{app} app was stopped successfully, it should be noted when stopped, the application is still loaded.",
               app: app
             )}
          )
          |> update_app_list()

        {:error, {:not_started, _app}} ->
          socket
          |> assign(
            :status_message,
            {:warning,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "Then %{app} apps is not started",
               app: app
             )}
          )

        {:error, _output} ->
          socket
          |> assign(
            :status_message,
            {:danger,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "An unspecified error has occurred"
             )}
          )
      end

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("app_action", %{"operation" => "update", "app" => app}, socket) do
    new_socket =
      case MishkaInstaller.DepUpdateJob.get(app) do
        {_app, :hex, _url, _version} ->
          res = DepHandler.run(:hex, app, :port)

          socket
          |> assign(:app_name, res["app_name"])
          |> assign(:status_message, {res["status_message_type"], res["message"]})
          |> assign(:selected_form, res["selected_form"])
          |> assign(:log, [])

        {_app, :git, url, tag} ->
          res = DepHandler.run(:git, %{url: url, tag: tag}, :port)

          socket
          |> assign(:app_name, res["app_name"])
          |> assign(:status_message, {res["status_message_type"], res["message"]})
          |> assign(:selected_form, res["selected_form"])
          |> assign(:log, [])

        _ ->
          socket
          |> assign(
            :status_message,
            {:danger,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "We couldn't find any update for the app you requested, unfortunately."
             )}
          )
          |> update_app_list()
      end

    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:error, :dep_changes_protector, _answer, _app}, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:ok, :dep_changes_protector, _answer, _app}, socket) do
    Task.Supervisor.start_child(MishkaInstaller.Installer.DepHandler, fn ->
      MishkaInstaller.DepUpdateJob.check_added_dependencies_update()
    end)

    Process.send_after(self(), {:dependency_update_check}, 5000)
    {:noreply, update_app_list(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:run_time_sourcing, answer}, socket) when is_binary(answer) do
    {:noreply, update(socket, :log, fn messages -> [messages | ["#{String.trim(answer)}"]] end)}
  end

  @impl Phoenix.LiveView
  def handle_info({:run_time_sourcing, _answer}, socket) do
    {:noreply,
     update(socket, :log, fn messages -> [messages | ["====> Unknown string <===="]] end)}
  end

  @impl Phoenix.LiveView
  def handle_info({:dependency_update_check}, socket) do
    {:noreply, update_app_list(socket)}
  end

  @spec error_to_string(:not_accepted | :too_large | :too_many_files) :: String.t()
  def error_to_string(:too_large),
    do: Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Too large")

  def error_to_string(:not_accepted),
    do:
      Gettext.dgettext(
        MishkaInstaller.gettext(),
        "mishka_installer",
        "You have selected an unacceptable file type"
      )

  def error_to_string(:too_many_files),
    do:
      Gettext.dgettext(
        MishkaInstaller.gettext(),
        "mishka_installer",
        "You have selected too many files"
      )

  defp update_app_list(socket) do
    socket
    |> assign(:loaded_apps, Application.loaded_applications())
    |> assign(
      :started_applications,
      Enum.map(Application.started_applications(), fn {app, _, _} -> app end)
    )
    |> assign(
      :update_list,
      Enum.map(MishkaInstaller.DepUpdateJob.get_all(), fn {app, _type, _url, _ver} -> app end)
    )
  end

  defp dep_form(:upload, assigns) do
    ~H"""
    <section id="dep-getter" class="col-md-6 mx-auto text-center" phx-drop-target={@uploads.dep.ref}>
      <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
        <%= for entry <- @uploads.dep.entries do %>
          <%= for err <- upload_errors(@uploads.dep, entry) do %>
            <p class="alert alert-danger"><%= error_to_string(err) %></p>
            <div class="container h-25 d-inline-block"></div>
          <% end %>
        <% end %>
        <% {status, message} = @status_message %>
        <%= if !is_nil(message) do %>
          <div class="container" id="dep-status-msg">
            <div class={"alert alert-#{status}"} role="alert" phx-click="clean_error"><%= message %></div>
            <div class="container h-25 d-inline-block"></div>
          </div>
        <% end %>
        <svg xmlns="http://www.w3.org/2000/svg" width="80" height="80" fill="currentColor" class="bi bi-cloud-upload" viewBox="0 0 16 16" id="upload-svg" phx-click={JS.dispatch("click", to: "#"<>@uploads.dep.ref)}>
          <path fill-rule="evenodd" d="M4.406 1.342A5.53 5.53 0 0 1 8 0c2.69 0 4.923 2 5.166 4.579C14.758 4.804 16 6.137 16 7.773 16 9.569 14.502 11 12.687 11H10a.5.5 0 0 1 0-1h2.688C13.979 10 15 8.988 15 7.773c0-1.216-1.02-2.228-2.313-2.228h-.5v-.5C12.188 2.825 10.328 1 8 1a4.53 4.53 0 0 0-2.941 1.1c-.757.652-1.153 1.438-1.153 2.055v.448l-.445.049C2.064 4.805 1 5.952 1 7.318 1 8.785 2.23 10 3.781 10H6a.5.5 0 0 1 0 1H3.781C1.708 11 0 9.366 0 7.318c0-1.763 1.266-3.223 2.942-3.593.143-.863.698-1.723 1.464-2.383z"/>
          <path fill-rule="evenodd" d="M7.646 4.146a.5.5 0 0 1 .708 0l3 3a.5.5 0 0 1-.708.708L8.5 5.707V14.5a.5.5 0 0 1-1 0V5.707L5.354 7.854a.5.5 0 1 1-.708-.708l3-3z"/>
        </svg>
        <h2 id="upload-text" class="mt-3 mb-1" phx-click={JS.dispatch("click", to: "#"<>@uploads.dep.ref)}>Drop your file here or Click</h2>
        <%= live_file_input @uploads.dep, class: "d-none" %>
        <%= for entry <- @uploads.dep.entries do %>
          <br>
          <span phx-click="cancel_upload" phx-value-ref={entry.ref} aria-label="cancel">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-file-earmark-zip" viewBox="0 0 16 16">
              <path d="M5 7.5a1 1 0 0 1 1-1h1a1 1 0 0 1 1 1v.938l.4 1.599a1 1 0 0 1-.416 1.074l-.93.62a1 1 0 0 1-1.11 0l-.929-.62a1 1 0 0 1-.415-1.074L5 8.438V7.5zm2 0H6v.938a1 1 0 0 1-.03.243l-.4 1.598.93.62.929-.62-.4-1.598A1 1 0 0 1 7 8.438V7.5z"/>
              <path d="M14 4.5V14a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V2a2 2 0 0 1 2-2h5.5L14 4.5zm-3 0A1.5 1.5 0 0 1 9.5 3V1h-2v1h-1v1h1v1h-1v1h1v1H6V5H5V4h1V3H5V2h1V1H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V4.5h-2z"/>
            </svg>
            <%= entry.client_name %>
          </span>
          <span phx-click="cancel_upload" phx-value-ref={entry.ref} aria-label="cancel">&times;</span>
          <br>
        <% end %>
        <input type="hidden" id="hidden_type" name="select_form" value="upload">
        <%= if @uploads.dep.entries != [] do %>
          <button type="submit" class="btn btn-outline-secondary mt-4 mb-4">Upload .Zip file</button>
        <% else %>
          <button type="submit" class="btn btn-outline-secondary mt-4 mb-4" disabled>Upload .Zip file</button>
        <% end %>
        <br>
        <span class="mt-4 mb-4">
          <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="hex">Get from Hex</a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="git">Or from Git</a>
        </span>
      </form>
    </section>
    """
  end

  defp dep_form(:hex, assigns) do
    ~H"""
      <section id="dep-hex-getter" class="col-md-6 mx-auto text-center">
        <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
          <% {status, message} = @status_message %>
          <%= if !is_nil(message) do %>
            <div class="container" id="dep-status-msg">
              <div class={"alert alert-#{status}"} role="alert" phx-click="clean_error"><%= message %></div>
              <div class="container h-25 d-inline-block"></div>
            </div>
          <% end %>
          <svg xmlns="http://www.w3.org/2000/svg" width="80" height="80" fill="currentColor" class="bi bi-hexagon mb-4" viewBox="0 0 16 16">
            <path d="M14 4.577v6.846L8 15l-6-3.577V4.577L8 1l6 3.577zM8.5.134a1 1 0 0 0-1 0l-6 3.577a1 1 0 0 0-.5.866v6.846a1 1 0 0 0 .5.866l6 3.577a1 1 0 0 0 1 0l6-3.577a1 1 0 0 0 .5-.866V4.577a1 1 0 0 0-.5-.866L8.5.134z"/>
          </svg>
          <div class="container h-25 d-inline-block"></div>
          <input name="app" class="form-control form-control-lg mb-3 w-50 p-3 mx-auto" type="text" placeholder="Input app name like: mishka_installer" required>
          <input type="hidden" id="hidden_type" name="select_form" value="hex">
          <button type="submit" class="btn btn-outline-secondary mt-4 mb-4"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Download/Update from hex") %></button>
          <div class="container h-25 d-inline-block"></div>
          <span class="mt-4 mb-4">
            <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="upload"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Upload") %></a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="git"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Or get from Git") %></a>
          </span>
        </form>
      </section>
    """
  end

  defp dep_form(:git, assigns) do
    ~H"""
      <section id="dep-git-getter" class="col-md-6 mx-auto text-center">
        <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
          <% {status, message} = @status_message %>
          <%= if !is_nil(message) do %>
            <div class="container" id="dep-status-msg">
              <div class={"alert alert-#{status}"} role="alert" phx-click="clean_error"><%= message %></div>
              <div class="container h-25 d-inline-block"></div>
            </div>
          <% end %>
          <svg xmlns="http://www.w3.org/2000/svg" width="80" height="80" fill="currentColor" class="bi bi-git mb-4" viewBox="0 0 16 16">
            <path d="M15.698 7.287 8.712.302a1.03 1.03 0 0 0-1.457 0l-1.45 1.45 1.84 1.84a1.223 1.223 0 0 1 1.55 1.56l1.773 1.774a1.224 1.224 0 0 1 1.267 2.025 1.226 1.226 0 0 1-2.002-1.334L8.58 5.963v4.353a1.226 1.226 0 1 1-1.008-.036V5.887a1.226 1.226 0 0 1-.666-1.608L5.093 2.465l-4.79 4.79a1.03 1.03 0 0 0 0 1.457l6.986 6.986a1.03 1.03 0 0 0 1.457 0l6.953-6.953a1.031 1.031 0 0 0 0-1.457"/>
          </svg>
          <div class="container h-25 d-inline-block"></div>
          <input name="url" class="form-control form-control-lg mb-3 w-75 p-3 mx-auto" type="text" placeholder="Your Git url" required>
          <div class="container h-25 d-inline-block"></div>
          <input name="git_tag" class="form-control form-control-lg mb-3 w-75 p-3 mx-auto" type="text" placeholder="Git tag, Ex: 0.0.2 or master">
          <div class="container h-25 d-inline-block"></div>
          <input type="hidden" id="hidden_type" name="select_form" value="git">
          <button type="submit" class="btn btn-outline-secondary mt-4 mb-4"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Download/Update from Git") %></button>
          <div class="container h-25 d-inline-block"></div>
          <span class="mt-4 mb-4">
            <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="upload"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Upload") %></a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="hex"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Or get from hex") %></a>
          </span>
        </form>
      </section>
    """
  end

  defp dep_form(:registered_app, assigns) do
    ~H"""
      <section id="dep-hex-getter" class="col-md-6 mx-auto text-center">
        <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
          <svg xmlns="http://www.w3.org/2000/svg" width="80" height="80" fill="currentColor" class="bi bi-exclamation-triangle mb-4" viewBox="0 0 16 16">
            <path d="M7.938 2.016A.13.13 0 0 1 8.002 2a.13.13 0 0 1 .063.016.146.146 0 0 1 .054.057l6.857 11.667c.036.06.035.124.002.183a.163.163 0 0 1-.054.06.116.116 0 0 1-.066.017H1.146a.115.115 0 0 1-.066-.017.163.163 0 0 1-.054-.06.176.176 0 0 1 .002-.183L7.884 2.073a.147.147 0 0 1 .054-.057zm1.044-.45a1.13 1.13 0 0 0-1.96 0L.165 13.233c-.457.778.091 1.767.98 1.767h13.713c.889 0 1.438-.99.98-1.767L8.982 1.566z"/>
            <path d="M7.002 12a1 1 0 1 1 2 0 1 1 0 0 1-2 0zM7.1 5.995a.905.905 0 1 1 1.8 0l-.35 3.507a.552.552 0 0 1-1.1 0L7.1 5.995z"/>
          </svg>
          <% {status, message} = @status_message %>
          <%= if !is_nil(message) do %>
            <div class="container" id="dep-status-msg">
              <div class="container h-25 d-inline-block"></div>
              <div class={"alert alert-#{status}"} role="alert" phx-click="clean_error"><%= message %></div>
            </div>
          <% end %>
          <div class="alert alert-secondary text-center prefer-alert">
            <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "We really recommend you to <b>wait for the app concerned response</b>, because maybe there is an important state that you need after updating!!") %>
          </div>
          <div class="container h-25 d-inline-block"></div>
          <button type="button" class="btn btn-outline-success" phx-click="update_app" phx-value-type="soft_update">
            <span class="spinner-grow spinner-grow-sm" role="status" aria-hidden="true"></span>
            <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Wait for the app response!") %>
          </button>
          <button type="button" class="btn btn-outline-danger" phx-click="update_app" phx-value-type="force_update">
          <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Do Force Update now!") %>
          </button>
        </form>
      </section>
    """
  end

  defp dep_form(:compiling_activities, assigns) do
    ~H"""
    <section id="dep-compiling-activities" class="col-md-6 mx-auto text-center">
      <h3 class="mb-3 text-start"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Real-time activities of compiling output:") %></h3>
      <hr class="mb-5 mt-5">
      <%= if @log == [], do: raw("<div class=\"alert alert-warning\">#{Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "No activity is running")}</div>") %>
      <section id="mishka-log-show" class="container mx-auto text-start" style="max-height: 200px; overflow-x: hidden; overflow-y: scroll;" phx-update="append">
        <%= for l <- @log do %>
          <p id={Ecto.UUID.generate} class="mishka-log-p"><%= l %></p>
        <% end %>
      </section>
      <div class="container h-25 d-inline-block"></div>
      <span class="mt-4 mb-4">
        <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="upload"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Upload") %></a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="hex"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Get from Hex") %></a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="git"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Or from Git") %></a>
      </span>
    </section>
    """
  end

  defp dep_form(:installed_plugins, assigns) do
    ~H"""
    <section id="dep-installed-plugins" class="col-md-6 mx-auto">
      <% {status, message} = @status_message %>
        <%= if !is_nil(message) do %>
          <div class="container" id="dep-status-msg">
            <div class={"alert alert-#{status}"} role="alert" phx-click="clean_error"><%= message %></div>
            <div class="container h-25 d-inline-block"></div>
          </div>
      <% end %>
      <div class="bd-callout bd-callout-info mb-5">
        <h3 class="mb-3"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Installed Apps:") %></h3>
        <p>
          <%= raw(Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "It should be noted the <span class=\"text-primary\">blue</span> apps exist in JSON file, and it is added by administrator and another apps exist in core, or they are sub-dependencies.")) %>
          <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Each time a new update comes in for one of the plugins, the") %> <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-cloud-arrow-down text-warning" viewBox="0 0 16 16"><path fill-rule="evenodd" d="M7.646 10.854a.5.5 0 0 0 .708 0l2-2a.5.5 0 0 0-.708-.708L8.5 9.293V5.5a.5.5 0 0 0-1 0v3.793L6.354 8.146a.5.5 0 1 0-.708.708l2 2z"/><path d="M4.406 3.342A5.53 5.53 0 0 1 8 2c2.69 0 4.923 2 5.166 4.579C14.758 6.804 16 8.137 16 9.773 16 11.569 14.502 13 12.687 13H3.781C1.708 13 0 11.366 0 9.318c0-1.763 1.266-3.223 2.942-3.593.143-.863.698-1.723 1.464-2.383zm.653.757c-.757.653-1.153 1.44-1.153 2.056v.448l-.445.049C2.064 6.805 1 7.952 1 9.318 1 10.785 2.23 12 3.781 12h8.906C13.98 12 15 10.988 15 9.773c0-1.216-1.02-2.228-2.313-2.228h-.5v-.5C12.188 4.825 10.328 3 8 3a4.53 4.53 0 0 0-2.941 1.1z"/></svg> <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "image comes next to it") %>
        </p>
      </div>
      <hr class="mb-5 mt-5">
      <div id="all_loaded_app">
        <%= for {app, _des, ver} <- @loaded_apps do %>
          <%= if app in Enum.map(DepHandler.compare_dependencies_with_json(), & &1.app) do %>
              <span id={"#{app}" <> "dropdown-class"} class="dropdown">
                <small id={app} class="d-inline-flex mb-2 px-2 py-1 fw-semibold text-primary bg-primary bg-opacity-10 border border-success border-opacity-10 rounded-2" type="button" data-bs-toggle="dropdown" aria-expanded="false">
                  <%= "#{app}" %> in v<%= "#{ver}" %> &nbsp;
                  <%= if app in @update_list do %>
                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-cloud-arrow-down" viewBox="0 0 16 16">
                      <path fill-rule="evenodd" d="M7.646 10.854a.5.5 0 0 0 .708 0l2-2a.5.5 0 0 0-.708-.708L8.5 9.293V5.5a.5.5 0 0 0-1 0v3.793L6.354 8.146a.5.5 0 1 0-.708.708l2 2z"/>
                      <path d="M4.406 3.342A5.53 5.53 0 0 1 8 2c2.69 0 4.923 2 5.166 4.579C14.758 6.804 16 8.137 16 9.773 16 11.569 14.502 13 12.687 13H3.781C1.708 13 0 11.366 0 9.318c0-1.763 1.266-3.223 2.942-3.593.143-.863.698-1.723 1.464-2.383zm.653.757c-.757.653-1.153 1.44-1.153 2.056v.448l-.445.049C2.064 6.805 1 7.952 1 9.318 1 10.785 2.23 12 3.781 12h8.906C13.98 12 15 10.988 15 9.773c0-1.216-1.02-2.228-2.313-2.228h-.5v-.5C12.188 4.825 10.328 3 8 3a4.53 4.53 0 0 0-2.941 1.1z"/>
                    </svg>
                  <% end %>
                </small>
                <ul id={"#{app}" <> "drop"} class="dropdown-menu" aria-labelledby={app}>
                  <%= if app in @started_applications do %>
                    <li><a id={"#{app}" <> "drop-stop"} class="dropdown-item" phx-click="app_action" phx-value-operation="stop" phx-value-app={app}>Stop app</a></li>
                  <% else %>
                    <li><a id={"#{app}" <> "start-stop"} class="dropdown-item" phx-click="app_action" phx-value-operation="start" phx-value-app={app}>Start app</a></li>
                  <% end %>
                  <li phx-click={JS.hide(to: "#" <> "#{app}")}><a id={"#{app}" <> "drop-delete"} class="dropdown-item" phx-click="app_action" phx-value-operation="delete" phx-value-app={app}>Delete app</a></li>
                  <%= if app in @update_list do %>
                    <li><a id={"#{app}" <> "start-update"} class="dropdown-item" phx-click="app_action" phx-value-operation="update" phx-value-app={app}>Update app</a></li>
                  <% end %>
                </ul>
              </span>
          <% else %>
            <small id={app} class="d-inline-flex mx-1 mb-2 px-2 py-1 fw-semibold text-success bg-success bg-opacity-10 border border-success border-opacity-10 rounded-2">
              <%= "#{app}" %> in v<%= "#{ver}" %>
            </small>
          <% end %>
        <% end %>
      </div>
      <p class="mt-4 mb-4 text-center">
        <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="upload"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Upload") %></a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="hex"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Get from Hex") %></a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="git"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Or from Git") %></a>
      </p>
    </section>
    """
  end

  defp dep_form(:install_tools, assigns) do
    ~H"""
    <section id="dep-install-tools" class="col-md-6 mx-auto">
      <% {status, message} = @status_message %>
        <%= if !is_nil(message) do %>
          <div class="container" id="dep-status-msg">
            <div class={"alert alert-#{status}"} role="alert" phx-click="clean_error"><%= message %></div>
            <div class="container h-25 d-inline-block"></div>
          </div>
      <% end %>
      <h3 class="mb-3"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Tools to manage extensions:") %></h3>
      <hr class="mb-5 mt-5">
      <div class="row">
        <div class="col-sm-4 mb-3">
          <div class="card">
            <div class="card-body">
              <h5 class="card-title"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Backup") %> <code>Mix.exs</code> <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "file") %></h5>
              <p class="card-text"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "With this option, you can create a backup of your") %> <code>Mix.exs</code> <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "file") %></p>
              <a phx-click="tools" phx-value-type="backup" class="btn btn-outline-primary"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Backup") %></a>
            </div>
          </div>
        </div>
        <div class="col-sm-4 mb-3">
          <div class="card">
            <div class="card-body">
              <h5 class="card-title"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Restore") %> <code>Mix.exs</code> <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "file") %></h5>
              <p class="card-text"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "With this option, you can restore your backup of your") %> <code>Mix.exs</code> <%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "file") %></p>
              <a phx-click="tools" phx-value-type="restore" class="btn btn-outline-primary"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Restore") %></a>
            </div>
          </div>
        </div>
        <div class="col-sm-4 mb-3">
          <div class="card">
            <div class="card-body">
              <h5 class="card-title"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Number of required update apps") %></h5>
              <p class="card-text"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "With this option you can count apps update") %></p>
              <a phx-click="tools" phx-value-type="task" class="btn btn-outline-primary"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Recalculate") %></a>
            </div>
          </div>
        </div>
      </div>
      <p class="mt-4 mb-4 text-center">
        <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="upload"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Upload") %></a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="hex">Get from Hex</a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="git"><%= Gettext.dgettext(MishkaInstaller.gettext(), "mishka_installer", "Or from Git") %></a>
      </p>
    </section>
    """
  end

  defp icon(assigns) do
    ~H"""
    <p id="dep-icon-getter" class="col-md-6 mx-auto text-end">
      <span phx-click="form_select" phx-value-type="compiling_activities">
        <svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" fill="currentColor" class="bi bi-activity" viewBox="0 0 16 16">
          <path fill-rule="evenodd" d="M6 2a.5.5 0 0 1 .47.33L10 12.036l1.53-4.208A.5.5 0 0 1 12 7.5h3.5a.5.5 0 0 1 0 1h-3.15l-1.88 5.17a.5.5 0 0 1-.94 0L6 3.964 4.47 8.171A.5.5 0 0 1 4 8.5H.5a.5.5 0 0 1 0-1h3.15l1.88-5.17A.5.5 0 0 1 6 2Z"/>
        </svg>
      </span>
      <span phx-click="form_select" phx-value-type="installed_plugins">
        <svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" fill="currentColor" class="bi bi-plug" viewBox="0 0 16 16">
          <path d="M6 0a.5.5 0 0 1 .5.5V3h3V.5a.5.5 0 0 1 1 0V3h1a.5.5 0 0 1 .5.5v3A3.5 3.5 0 0 1 8.5 10c-.002.434-.01.845-.04 1.22-.041.514-.126 1.003-.317 1.424a2.083 2.083 0 0 1-.97 1.028C6.725 13.9 6.169 14 5.5 14c-.998 0-1.61.33-1.974.718A1.922 1.922 0 0 0 3 16H2c0-.616.232-1.367.797-1.968C3.374 13.42 4.261 13 5.5 13c.581 0 .962-.088 1.218-.219.241-.123.4-.3.514-.55.121-.266.193-.621.23-1.09.027-.34.035-.718.037-1.141A3.5 3.5 0 0 1 4 6.5v-3a.5.5 0 0 1 .5-.5h1V.5A.5.5 0 0 1 6 0zM5 4v2.5A2.5 2.5 0 0 0 7.5 9h1A2.5 2.5 0 0 0 11 6.5V4H5z"/>
        </svg>
      </span>
      <span phx-click="form_select" phx-value-type="install_tools">
        <svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" fill="currentColor" class="bi bi-braces" viewBox="0 0 16 16">
          <path d="M2.114 8.063V7.9c1.005-.102 1.497-.615 1.497-1.6V4.503c0-1.094.39-1.538 1.354-1.538h.273V2h-.376C3.25 2 2.49 2.759 2.49 4.352v1.524c0 1.094-.376 1.456-1.49 1.456v1.299c1.114 0 1.49.362 1.49 1.456v1.524c0 1.593.759 2.352 2.372 2.352h.376v-.964h-.273c-.964 0-1.354-.444-1.354-1.538V9.663c0-.984-.492-1.497-1.497-1.6zM13.886 7.9v.163c-1.005.103-1.497.616-1.497 1.6v1.798c0 1.094-.39 1.538-1.354 1.538h-.273v.964h.376c1.613 0 2.372-.759 2.372-2.352v-1.524c0-1.094.376-1.456 1.49-1.456V7.332c-1.114 0-1.49-.362-1.49-1.456V4.352C13.51 2.759 12.75 2 11.138 2h-.376v.964h.273c.964 0 1.354.444 1.354 1.538V6.3c0 .984.492 1.497 1.497 1.6z"/>
        </svg>
      </span>
    </p>
    <div class="container h-25 d-inline-block"></div>
    """
  end
end
