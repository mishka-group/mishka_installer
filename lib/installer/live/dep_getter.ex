defmodule MishkaInstaller.Installer.Live.DepGetter do
  use Phoenix.LiveView
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
        <div class="row mt-4">
          <%= dep_form(@selected_form, assigns) %>
        </div>
      </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    DepChangesProtector.subscribe()
    socket =
      socket
      |> assign(:selected_form, :upload)
      |> assign(:app_name, nil)
      |> assign(:status_message, {nil, nil})
      |> assign(:uploaded_files, [])
      |> allow_upload(:dep, accept: ~w(.zip), max_entries: 1)
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
  def handle_event("form_select", %{"type" => type} = _params, socket) when type in ["upload", "hex", "git"] do
    socket =
      socket
      |> assign(:status_message, {:nil, nil})
      |> assign(:app_name, nil)
      |> assign(:selected_form, String.to_atom(type))
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("update_app", %{"type" => type} = _params, socket) when type in ["force_update", "soft_update"] do
    if type == "force_update" do
      DepHandler.create_mix_file_and_start_compile(socket.assigns.app_name)
    else
      Hook.call(event: @event, state: %OnChangeDependency{app: socket.assigns.app_name, status: :force_update}, operation: :no_return)
    end
    socket =
      socket
      |> assign(:status_message, {:info, "Your request was sent, after receiving any changes we send you a notification"})
      |> assign(:app_name, nil)
      |> assign(:selected_form, :upload)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"select_form" => "git", "url" => url, "git_tag" => tag}, socket) do
    res = DepHandler.run(:git, %{url: url, tag: tag})
    new_socket =
      socket
      |> assign(:app_name, res["app_name"])
      |> assign(:status_message, {res["status_message_type"], res["message"]})
      |> assign(:selected_form, res["selected_form"])
    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"select_form" => "hex", "app" => app} = _params, socket) do
    res = DepHandler.run(:hex, app)
    new_socket =
      socket
      |> assign(:app_name, res["app_name"])
      |> assign(:status_message, {res["status_message_type"], res["message"]})
      |> assign(:selected_form, res["selected_form"])
    {:noreply, new_socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"select_form" => "upload"} = _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :dep, fn %{path: path}, entry ->
        dest = Path.join(MishkaInstaller.get_config(:project_path) || File.cwd!(), ["deployment/", "extensions/", entry.client_name])
        File.cp!(path, dest)
        {:ok, dest}
      end)

    new_socket =
      if uploaded_files != [] do
        res = DepHandler.run(:upload, uploaded_files)
        socket
        |> assign(:app_name, res["app_name"])
        |> assign(:status_message, {res["status_message_type"], res["message"]})
        |> assign(:selected_form, res["selected_form"])
        |> update(:uploaded_files, &(&1 ++ uploaded_files))
      else
        socket
        |> assign(:status_message, {:danger, "You should select a file."})
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
  def handle_info({:error, :dep_changes_protector, _answer, _app}, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:ok, :dep_changes_protector, _answer, _app}, socket) do
    {:noreply, socket}
  end

  @spec error_to_string(:not_accepted | :too_large | :too_many_files) :: String.t()
  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
  def error_to_string(:too_many_files), do: "You have selected too many files"

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
      <section id="dep-git-getter" class="col-md-6 mx-auto text-center">
        <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
          <% {status, message} = @status_message %>
          <%= if !is_nil(message) do %>
            <div class="container" id="dep-status-msg">
              <div class={"alert alert-#{status}"} role="alert" phx-click="clean_error"><%= message %></div>
              <div class="container h-25 d-inline-block"></div>
            </div>
          <% end %>
          <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" fill="currentColor" class="bi bi-git mb-4" viewBox="0 0 16 16">
            <path d="M15.698 7.287 8.712.302a1.03 1.03 0 0 0-1.457 0l-1.45 1.45 1.84 1.84a1.223 1.223 0 0 1 1.55 1.56l1.773 1.774a1.224 1.224 0 0 1 1.267 2.025 1.226 1.226 0 0 1-2.002-1.334L8.58 5.963v4.353a1.226 1.226 0 1 1-1.008-.036V5.887a1.226 1.226 0 0 1-.666-1.608L5.093 2.465l-4.79 4.79a1.03 1.03 0 0 0 0 1.457l6.986 6.986a1.03 1.03 0 0 0 1.457 0l6.953-6.953a1.031 1.031 0 0 0 0-1.457"/>
          </svg>
          <div class="container h-25 d-inline-block"></div>
          <input name="url" class="form-control form-control-lg mb-3" type="text" placeholder="Your Git url" required>
          <div class="container h-25 d-inline-block"></div>
          <input name="git_tag" class="form-control form-control-lg mb-3" type="text" placeholder="Git tag, Ex: 0.0.2 or master">
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

  defp dep_form(:registered_app, assigns) do
    ~H"""
      <section id="dep-hex-getter" class="col-md-6 mx-auto text-center">
        <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
          <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" fill="currentColor" class="bi bi-exclamation-triangle mb-4" viewBox="0 0 16 16">
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
            We really recommend you to <b>wait for the app concerned response</b>, because maybe there is an important state that you need after updating!!
          </div>
          <div class="container h-25 d-inline-block"></div>
          <button type="button" class="btn btn-outline-success" phx-click="update_app" phx-value-type="soft_update">
            <span class="spinner-grow spinner-grow-sm" role="status" aria-hidden="true"></span>
            Wait for the app response!
          </button>
          <button type="button" class="btn btn-outline-danger" phx-click="update_app" phx-value-type="force_update">
           Do Force Update now!
          </button>
        </form>
      </section>
    """
  end
end
