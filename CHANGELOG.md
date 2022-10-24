# Changelog for MishkaInstaller 0.0.4

- [x] Improve runtime sourcing module
- [x] Cover version 0.0.3 in the document
- [x] Get and compile a dependency out of user project
- [x] Add `MishkaInstaller.Helper.LibraryMaker` utility module and function
- [x] Connecting GUI LiveView to the database and managing the requested extensions file(compressed and dir)
- [x] Force user to put their Pubsub and add some timeout to check is connected root project Repo or not
- [x] Format project `mix format`
- [x] Add description of each dependency in GUI
- [x] Fix and Improve `MishkaInstaller.DepUpdateJob`
- [ ] Change English README for version 0.0.4
- [ ] Change Persian README for version 0.0.4
- [ ] Add English introduction video version 0.0.4
- [ ] Add Persian introduction video version 0.0.4
- [ ] Add status changer in DepGetter module from state
- [ ] Test version 0.0.4 with credo
- [ ] Create events for each part of MishkaInstaller to let developers extend installer

---

# Changelog for MishkaInstaller 0.0.3

- [x] Create run time updating dependencies
- [x] Prepare a structure to add developer extensions
- [x] Call extensions from ETS
- [x] Add private information into state, read only data
- [x] Add private parameters to event hooks
- [x] Accept developer `git` for installing an extension
- [x] Accept developer `hex` for installing an extension
- [x] Accept admin `upload` file for installing an extension
- [x] Fix no return hook issue [link](https://github.com/mishka-group/mishka_installer/commit/efe33e87e53db414932ba841ddbd908357e21bbf#diff-1f6b2c046b76fb543242be7be8b86cb665a746b9e07ec26b5d421f4931534c2fL171)
- [x] Auto dependencies update checker
- [x] Some types and behaviors added
- [x] Create a README file in Proposals repo for new version of MishkaInstaller
- [x] Create a Quick GUI installer
- [x] Preparing dependencies for force-update and soft-update to keep essential data (like state in updating)
- [x] Add run function for adding a new dep
- [x] Mix deps creator
- [x] Create a simple setting `ets`[#4](https://github.com/mishka-group/mishka_installer/issues/4)
- [x] Make behavior optional in plugin hook
- [x] Queue to install extensions with `Oban`
- [x] Compatible Docker shell with this version
- [x] Compatible MishkaCms with this version
- [x] Make the lib comfortable with external Gettext [#12](https://github.com/mishka-group/mishka_installer/issues/12)
- [x] Create a GUI dashboard to install plugin and component [#5](https://github.com/mishka-group/mishka_installer/issues/5)
- [x] Update MishkaCms docker package for this version(volume `extensions.json`)
- [x] Add Plugin router behavior [#16](https://github.com/mishka-group/mishka_installer/issues/16)
- [x] Support Elixir 1.13.4 and Erlang OTP 25 [#42](https://github.com/mishka-group/mishka_installer/issues/42)

> Accepting zip file of release is not supported in this version