# Mishka Installer is a system plugin(event) manager and run time installer for Elixir.

[![MishkaInstaller CI](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml/badge.svg)](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/badge/hex-0.1.0-blue.svg)](https://hex.pm/packages/mishka_installer) [![GitHub license](https://img.shields.io/badge/apache-2.0-green.svg)](https://raw.githubusercontent.com/mishka-group/mishka_installer/master/LICENSE) ![GitHub issues](https://img.shields.io/github/issues/mishka-group/mishka_installer)

<div align="center">
  <pre style="display: inline-block; text-align: left;">
    💖 Hey there! If you like my work, please <b><a href="https://github.com/sponsors/mishka-group">support me financially!</a></b> 💖
  </pre>
</div>

<br />

<p align="center">
  <a href="https://www.buymeacoffee.com/mishkagroup">
    <img src="https://github.com/user-attachments/assets/f4d4df7e-dcc4-4d1a-80e1-59c4d99725ab" alt="Support Mishka by Buy Me a Coffee" />
  </a>
</p>

## Low Maintenance Warning:

> **This library is in low maintenance mode, which means the author is currently only responding to pull requests.**


## Build purpose
---

Imagine you are going to make an application that will have many plugins built for it in the future.
But the fact that many manipulations will be made on your source code makes it difficult to
maintain the application. For example, you present a content management system for your users,
and now they need to activate a section for registration and `SMS`; the system allows you to
present your desired input/output absolutely plugin oriented to your users and makes it
possible for the developers to write their required applications beyond the core source code.


> **NOTICE**: Do not use the master branch; this library is under heavy development.
> Expect version 0.1.0, and for using the new features, please wait until a new release is out.


##### This library is divided into the following main sections:

- [Events and Hook](#events-and-hook)
- [Plugin management system theory and installation of Elixir libraries at runtime](#plugin-management-system-theory-and-installation-of-elixir-libraries-at-runtime)


### Events and Hook
---

In this section, you can define a series of plugins for each event,
for example: after **successful registration** or **unsuccessful purchase** from “the store”,
and for each event, put a set of callbacks in one module.

After completing this step, when the user wants to create his own plugin,
the Macro `behaviour` and `Hook` module will call you in its action module.

This helps you have a regular and `error-free` system, and the library uses an almost
integrated structure in all of its events.

> In **Mishka Installer** Library, a series of action or hook functions are
given to the developer of the main plugin or software, which helps build plugins **outside**/**inside**
the system and convert software sections into separate events.

**Some of the functions of this module include the following:**

- Retrieves the merged configuration for the hook module.
- Register a plugin for a specific event.
- Start a plugin of a specific event.
- Restart a plugin of a specific event.
- Stop a plugin of a specific event.
- Unregister a plugin of a specific event.
- Retrieves a Plugin `GenServer` state.
- Each plugin has A `GenServer` to do some auto jobs.

> For more information please see the `MishkaInstaller.Event.Hook` module.

##### Example:

```elixir
defmodule RegisterEmailSender do
  use MishkaInstaller.Event.Hook, event: "after_success_login"

  def call(entries) do
    {:reply, entries}
  end
end
```

**If you want to change a series of default information, do this:**

```elixir
use MishkaInstaller.Event.Hook,
  event: "after_success_login",
  initial: %{depends: [SomeEvent], priority: 20}
```

**You can call all plugins of an event:**

```elixir
alias MishkaInstaller.Event.Hook

# Normal call an event plugins
Hook.call("after_success_login", params)

# If you want certain entries not to change
Hook.call("after_success_login", params, [private: something_based_on_your_data])

# If you want the initial entry to be displayed at the end
Hook.call("after_success_login", params, [return: true])
```

**Note: If you want your plugin to execute automatically,
all you need to do is send the name of the module in which you utilized
the `MishkaInstaller.Event.Hook` to the Application module.**

```elixir
children = [
  ...
  RegisterEmailSender
]

...
opts = [strategy: :one_for_one, name: SomeModule.Supervisor]
Supervisor.start_link(children, opts)
```

> This module is a read-only in-memory storage optimized for the fastest possible read times
> not for write strategies.

[![Run in Livebook](https://livebook.dev/badge/v1/pink.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fmishka-group%2Fmishka_installer%2Fblob%2Fmaster%2Fguidance%2Fevent%2Fhook.livemd)

### Plugin management system theory and installation of Elixir libraries at runtime
---

The functionality of this library can be conceptualized as an architectural potential that is
composed of two primary components, which are as follows:

1. Event management (Plugin Hook powered by **Elixir Macro**)
2. Managing removal and installation of Elixir libraries at `runtime`.

When a programmer uses this library for his own software development, we sought to
ensure that in addition to the established capabilities, he also has access to a set of
appropriate standards for software development that are based on preset behaviors that can be applied;
This was our goal.

It streamlines and organizes the work of a group working on a project while also facilitating
the creation of software.
Error control and tree structure, which enable us to develop a system that is robust and trustworthy,
are two of the guiding ideas behind the construction of this library, which has garnered
attention from people all around the world.

The [MishkaInstaller](https://github.com/mishka-group/mishka_installer) library can be created in
various systems, and it provides fundamental capabilities such as the management of plugin states
and the application of standard behaviors.
These features can all be accessed by specified hooks in the library.

> **The installer part is in beta mode, use it carefully and some of its functionality may not work in the Elixir `release`.**

##### Example:

```elixir
alias MishkaInstaller.Installer.Installer

# Normal calling
Installer.install(%__MODULE__{app: "some_name", path: "some_name", type: :hex})

# Normal calling
Installer.uninstall(%__MODULE__{app: "some_name", path: "some_name", type: :hex})

# Normal calling
Installer.async_install(%__MODULE__{app: "some_name", path: "some_name", type: :hex})
```

> For more information please see the `MishkaInstaller.Installer.Installer` module.


## Installing the library:
---

It should be noted that this library must be installed in two parts of the plugin and the
software that wants to display the plugins, and due to its small dependencies, it does
not cause any problems. To install, just add this library to your "mix.exs" in the "deps"
function as follows:

```elixir
def deps do
  [
    {:mishka_installer, "~> 0.1.3"}
  ]
end
```

The docs can be found at https://hexdocs.pm/mishka_installer.

---

# Donate

You can support this project through the "[Sponsor](https://github.com/sponsors/mishka-group)" button on GitHub donations. All our projects are **open-source** and **free**, and we rely on community contributions to enhance and improve them further.
