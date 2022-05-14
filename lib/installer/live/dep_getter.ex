defmodule MishkaInstaller.Installer.Live.DepGetter do
  use Phoenix.LiveView
  alias Phoenix.LiveView.JS
  alias MishkaInstaller.Installer.DepHandler

  @impl true
  def render(assigns) do
    ~H"""
      <div class="container">
        <div class="row mt-4">
          <%= dep_form(@selected_form, assigns) %>
        </div>
      </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:selected_form, :upload)
      |> assign(:status_message, {nil, nil})
      |> assign(:uploaded_files, [])
      |> allow_upload(:dep, accept: ~w(.jpg .jpeg .png), max_entries: 1)
    {:ok, socket}
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
  def handle_event("save", %{"select_form" => "upload"} = _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :dep, fn %{path: path}, _entry ->
        dest = Path.join([:code.priv_dir(:my_app), "static", "uploads", Path.basename(path)])
        # The `static/uploads` directory must exist for `File.cp!/2` to work.
        File.cp!(path, dest)
        {:ok, Routes.static_path(socket, "/uploads/#{Path.basename(dest)}")}
      end)
    {:noreply, update(socket, :uploaded_files, &(&1 ++ uploaded_files))}
  end

  @impl Phoenix.LiveView
  def handle_event("form_select", %{"type" => type} = _params, socket) when type in ["upload", "hex", "git"] do
    socket =
      socket
      |> assign(:status_message, {nil, nil})
      |> assign(:selected_form, String.to_atom(type))
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"select_form" => "git"} = _params, socket) do
    # TODO: if this pkg does not exist so install and add to do compile queue
    # TODO: do not send if this info exists and it is same version, you can notice user he/her is trying to send duplicated-package
    # TODO: note: if your app developer registerd a plugin to keep some esential state we just notice it, and the app you want to update shoud start updating
    # TODO: if it is master do not update db and the other places
    # TODO: make a way to force update with admin
    # TODO: after creating all these TODO, please move the code in dephandler module as a main action
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"select_form" => "hex", "app" => name} = _params, socket) do
    socket =
      MishkaInstaller.Helper.Sender.package("hex", %{"app" => name})
      |> check_app_exist?(:hex)
      |> case do
        {:ok, :no_state, msg} ->
          socket
          |> assign(:status_message, {:success, msg})
        {:ok, :registered_app, msg} ->
          # TODO: create html with a tag to ask user force update or not
          socket
          |> assign(:status_message, {:info, msg})
        {:error, msg} ->
          socket
          |> assign(:status_message, {:danger, msg})
      end
    {:noreply, socket}
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
  def error_to_string(:too_many_files), do: "You have selected too many files"

  defp check_app_exist?({:ok, :package, pkg}, :hex) do
    json_find = fn (json, app_name) -> Enum.find(json, &(&1["app"] == app_name)) end
    with {:ok, :check_or_create_deps_json, exist_json} <- DepHandler.check_or_create_deps_json(),
         {:new_app?, true, nil} <- {:new_app?, is_nil(json_find.(Jason.decode!(exist_json), pkg["name"])), json_find.(Jason.decode!(exist_json), pkg["name"])},
         app_info <- create_app_info_from_hex(pkg),
         {:ok, :add_new_app, _repo_data} <- DepHandler.add_new_app(app_info),
         {:ok, :dependency_changes_notifier, :no_state, msg} <- DepHandler.dependency_changes_notifier(pkg["name"]) do
          {:ok, :no_state, msg}
    else
      {:error, :check_or_create_deps_json, msg} -> {:error, msg}
      {:new_app?, false, app} ->
        if app["version"] == pkg["latest_stable_version"] do
          {:error, "You have already installed this library and the installed version is the same as the latest version of the Hex site. Please take action when a new version of this app is released"}
        else
          MishkaInstaller.Dependency.update_app_version(app["app"], pkg["latest_stable_version"])
          case DepHandler.dependency_changes_notifier(pkg["name"]) do
            {:ok, :dependency_changes_notifier, :no_state, msg} -> {:ok, :no_state, msg}
            {:ok, :dependency_changes_notifier, :registered_app, msg} -> {:ok, :registered_app, msg}
            {:error, :dependency_changes_notifier, msg} -> {:error, msg}
          end
        end
      {:error, :add_new_app, :file, msg} -> {:error, msg}
      {:error, :add_new_app, :changeset, _repo_error} ->
        # TODO: log this error in activity section
        {:error, "This error occurs when you can not add a new plugin to the database. If repeated, please contact support."}
      {:error, :dependency_changes_notifier, msg} -> {:error, msg}
      {:ok, :dependency_changes_notifier, :registered_app, msg} ->
        {:ok, :registered_app, msg}
    end
  end

  defp check_app_exist?({:error, :package, status}, _) do
    msg = if status == :not_found, do: "Are you sure you have entered the package name correctly?", else: "Unfortunately, we cannot connect to Hex server now, please try other time!"
    {:error, msg}
  end

  defp create_app_info_from_hex(pkg) do
    %DepHandler{
      app: pkg["name"],
      version: pkg["latest_stable_version"],
      type: "hex",
      url: pkg["html_url"],
      dependency_type: "force_update",
      dependencies: []
    }
  end

  defp dep_form(:upload, assigns) do
    ~H"""
    <section id="dep-getter" class="col-md-6 mx-auto" phx-drop-target={@uploads.dep.ref}>
      <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
        <%= for err <- upload_errors(@uploads.dep) do %>
          <p class="alert alert-danger"><%= error_to_string(err) %></p>
          <div class="container h-25 d-inline-block"></div>
        <% end %>
        <% {status, message} = @status_message %>
        <%= if !is_nil(message) do %>
          <div class="container" id="dep-status-msg">
            <div class={"alert alert-#{status}"} role="alert" phx-click={JS.hide(to: "#dep-status-msg")}><%= message %></div>
            <div class="container h-25 d-inline-block"></div>
          </div>
        <% end %>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" fill="currentColor" class="bi bi-cloud-upload" viewBox="0 0 16 16" id="upload-svg" phx-click={JS.dispatch("click", to: "#"<>@uploads.dep.ref)}>
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
        <button type="submit" class="btn btn-outline-secondary mt-4 mb-4">Upload .Zip file</button>
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
      <section id="dep-hex-getter" class="col-md-6 mx-auto">
      <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
        <% {status, message} = @status_message %>
        <%= if !is_nil(message) do %>
          <div class="container" id="dep-status-msg">
            <div class={"alert alert-#{status}"} role="alert" phx-click={JS.hide(to: "#dep-status-msg")}><%= message %></div>
            <div class="container h-25 d-inline-block"></div>
          </div>
        <% end %>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" fill="currentColor" class="bi bi-hexagon mb-4" viewBox="0 0 16 16">
          <path d="M14 4.577v6.846L8 15l-6-3.577V4.577L8 1l6 3.577zM8.5.134a1 1 0 0 0-1 0l-6 3.577a1 1 0 0 0-.5.866v6.846a1 1 0 0 0 .5.866l6 3.577a1 1 0 0 0 1 0l6-3.577a1 1 0 0 0 .5-.866V4.577a1 1 0 0 0-.5-.866L8.5.134z"/>
        </svg>
        <div class="container h-25 d-inline-block"></div>
        <input name="app" class="form-control form-control-lg mb-3 w-50 p-3 mx-auto" type="text" placeholder="Input app name like: mishka_installer" required>
        <input type="hidden" id="hidden_type" name="select_form" value="hex">
        <button type="submit" class="btn btn-outline-secondary mt-4 mb-4">Download/Update from hex</button>
        <div class="container h-25 d-inline-block"></div>
        <span class="mt-4 mb-4">
          <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="upload">Upload</a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="git">Or get from Git</a>
        </span>
      </form>
      </section>
    """
  end

  defp dep_form(:git, assigns) do
    ~H"""
      <section id="dep-hex-getter" class="col-md-6 mx-auto">
      <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
        <% {status, message} = @status_message %>
        <%= if !is_nil(message) do %>
          <div class="container" id="dep-status-msg">
            <div class={"alert alert-#{status}"} role="alert" phx-click={JS.hide(to: "#dep-status-msg")}><%= message %></div>
            <div class="container h-25 d-inline-block"></div>
          </div>
        <% end %>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" fill="currentColor" class="bi bi-git mb-4" viewBox="0 0 16 16">
          <path d="M15.698 7.287 8.712.302a1.03 1.03 0 0 0-1.457 0l-1.45 1.45 1.84 1.84a1.223 1.223 0 0 1 1.55 1.56l1.773 1.774a1.224 1.224 0 0 1 1.267 2.025 1.226 1.226 0 0 1-2.002-1.334L8.58 5.963v4.353a1.226 1.226 0 1 1-1.008-.036V5.887a1.226 1.226 0 0 1-.666-1.608L5.093 2.465l-4.79 4.79a1.03 1.03 0 0 0 0 1.457l6.986 6.986a1.03 1.03 0 0 0 1.457 0l6.953-6.953a1.031 1.031 0 0 0 0-1.457"/>
        </svg>
        <div class="container h-25 d-inline-block"></div>
        <input name="app" class="form-control form-control-lg mb-3" type="text" placeholder="App name" required>
        <div class="container h-25 d-inline-block"></div>
        <input name="url" class="form-control form-control-lg mb-3" type="text" placeholder="Your Git url" required>
        <div class="container h-25 d-inline-block"></div>
        <input name="git_tag" class="form-control form-control-lg mb-3" type="text" placeholder="Git tag, Ex: 0.0.2 or master">
        <div class="container h-25 d-inline-block"></div>
        <input name="update_server" class="form-control form-control-lg mb-3" type="text" placeholder="Update server, Ex: https://your_url.com/server.json">
        <div class="container h-25 d-inline-block"></div>
        <input type="hidden" id="hidden_type" name="select_form" value="git">
        <button type="submit" class="btn btn-outline-secondary mt-4 mb-4">Download/Update from Git</button>
        <div class="container h-25 d-inline-block"></div>
        <span class="mt-4 mb-4">
          <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="upload">Upload</a> - <a class="dep-link text-decoration-none" phx-click="form_select" phx-value-type="hex">Or get from hex</a>
        </span>
      </form>
      </section>
    """
  end
end
