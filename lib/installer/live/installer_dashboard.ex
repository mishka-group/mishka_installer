defmodule MishkaInstaller.Installer.Live.DepGetter do
  use Phoenix.LiveView

  @impl true
  def render(assigns) do
    ~H"""
      <div class="container">
        <div class="row mt-4">
          <section id="dep-getter" class="col-md-6 mx-auto" phx-drop-target={@uploads.dep.ref}>
            <form id="extensions-upload-form" phx-submit="save" phx-change="validate">
              <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" fill="currentColor" class="bi bi-cloud-upload" viewBox="0 0 16 16">
                <path fill-rule="evenodd" d="M4.406 1.342A5.53 5.53 0 0 1 8 0c2.69 0 4.923 2 5.166 4.579C14.758 4.804 16 6.137 16 7.773 16 9.569 14.502 11 12.687 11H10a.5.5 0 0 1 0-1h2.688C13.979 10 15 8.988 15 7.773c0-1.216-1.02-2.228-2.313-2.228h-.5v-.5C12.188 2.825 10.328 1 8 1a4.53 4.53 0 0 0-2.941 1.1c-.757.652-1.153 1.438-1.153 2.055v.448l-.445.049C2.064 4.805 1 5.952 1 7.318 1 8.785 2.23 10 3.781 10H6a.5.5 0 0 1 0 1H3.781C1.708 11 0 9.366 0 7.318c0-1.763 1.266-3.223 2.942-3.593.143-.863.698-1.723 1.464-2.383z"/>
                <path fill-rule="evenodd" d="M7.646 4.146a.5.5 0 0 1 .708 0l3 3a.5.5 0 0 1-.708.708L8.5 5.707V14.5a.5.5 0 0 1-1 0V5.707L5.354 7.854a.5.5 0 1 1-.708-.708l3-3z"/>
              </svg>
              <h2 class="mb-1">Drop your file here or</h2>
              <%= live_file_input @uploads.dep, class: "d-none" %>
              <%= for entry <- @uploads.dep.entries do %>
                <br>
                <span phx-click="cancel-upload" phx-value-ref={entry.ref} aria-label="cancel">
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-file-earmark-zip" viewBox="0 0 16 16">
                    <path d="M5 7.5a1 1 0 0 1 1-1h1a1 1 0 0 1 1 1v.938l.4 1.599a1 1 0 0 1-.416 1.074l-.93.62a1 1 0 0 1-1.11 0l-.929-.62a1 1 0 0 1-.415-1.074L5 8.438V7.5zm2 0H6v.938a1 1 0 0 1-.03.243l-.4 1.598.93.62.929-.62-.4-1.598A1 1 0 0 1 7 8.438V7.5z"/>
                    <path d="M14 4.5V14a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V2a2 2 0 0 1 2-2h5.5L14 4.5zm-3 0A1.5 1.5 0 0 1 9.5 3V1h-2v1h-1v1h1v1h-1v1h1v1H6V5H5V4h1V3H5V2h1V1H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V4.5h-2z"/>
                  </svg>
                  <%= entry.client_name %>
                </span>
                <span phx-click="cancel-upload" phx-value-ref={entry.ref} aria-label="cancel">&times;</span>
                <br>
              <% end %>
              <button type="submit" class="btn btn-outline-secondary mt-4 mb-4">Upload .Zip file</button>
              <br>
              <span class="mt-4 mb-4 ">
                <a class="dep-link text-decoration-none">Install from Hex</a> - <a class="dep-link text-decoration-none">Install from Git</a>
              </span>
            </form>
            <%= for err <- upload_errors(@uploads.dep) do %>
              <p class="alert alert-danger"><%= error_to_string(err) %></p>
            <% end %>
          </section>
        </div>
      </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:uploaded_files, [])
      |> allow_upload(:dep, accept: ~w(.jpg .jpeg .png), max_entries: 1)
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :dep, ref)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :dep, fn %{path: path}, _entry ->
        dest = Path.join([:code.priv_dir(:my_app), "static", "uploads", Path.basename(path)])
        # The `static/uploads` directory must exist for `File.cp!/2` to work.
        File.cp!(path, dest)
        {:ok, Routes.static_path(socket, "/uploads/#{Path.basename(dest)}")}
      end)
    {:noreply, update(socket, :uploaded_files, &(&1 ++ uploaded_files))}
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
  def error_to_string(:too_many_files), do: "You have selected too many files"
end
