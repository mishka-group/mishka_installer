defmodule MishkaInstaller.Installer.Installer do
  use GuardedStruct

  @type download_type ::
          :hex
          | :github
          | :github_latest_release
          | :github_latest_tag
          | :github_release
          | :github_tag
          | :url

  @type dep_type :: :none | :force_update

  ####################################################################################
  ########################## (▰˘◡˘▰) Schema (▰˘◡˘▰) ############################
  ####################################################################################
  guardedstruct do
    @ext_type "hex::github::github_latest_release::github_latest_tag::github_release::github_tag::url"
    @dep_type "enum=Atom[none::force_update]"

    field(:app, String.t(), enforce: true, derive: "validate(not_empty_string)")
    field(:version, String.t(), enforce: true, derive: "validate(not_empty_string)")
    field(:type, download_type(), enforce: true, derive: "validate(enum=Atom[#{@ext_type}])")
    field(:path, String.t(), derive: "validate(either=[not_empty_string, url])")
    field(:tag, String.t(), derive: "validate(not_empty_string)")
    field(:custom_command, String.t(), derive: "validate(not_empty_string)")
    field(:dependency_type, dep_type(), default: :none, derive: "validate(#{@dep_type})")
    field(:depends, list(String.t()), default: [], derive: "validate(list)")
    field(:checksum, String.t(), derive: "validate(not_empty_string)")
  end

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
end
