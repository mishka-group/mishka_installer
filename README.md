# Mishka Installer is a system plugin(event) manager and run time installer for Elixir.

[![MishkaInstaller CI](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml/badge.svg)](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/badge/hex-0.1.0-blue.svg)](https://hex.pm/packages/mishka_installer) [![GitHub license](https://img.shields.io/badge/apache-2.0-green.svg)](https://raw.githubusercontent.com/mishka-group/mishka_installer/master/LICENSE) ![GitHub issues](https://img.shields.io/github/issues/mishka-group/mishka_installer)

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

In this section, you can define a series of events for each event,
for example: after **successful registration** or **unsuccessful purchase** from “the store”,
and for each event, put a set of callbacks in one module.

After completing this step, when the user wants to create his own plugin,
the Macro `behaviour` and `Hook` module will call you in its action module.

This helps you have a regular and `error-free` system, and the library uses an almost
integrated structure in all of its events.

In **Mishka Installer** Library, a series of action or hook functions are
given to the developer of the main plugin or software, which helps build plugins outside/inside
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
the `MishkaInstaller.Event.Hook` to the Application module.***

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

### Plugin management system theory and installation of Elixir libraries at runtime
---

The functionality of this library can be conceptualized as an architectural potential that is
composed of two primary components, which are as follows:

1. Event management (Plugin Hook powered by **Elixir Macro**)
2. Managing removal and installation of Elixir libraries at `runtime`.

When a programmer uses this library for his own software development, we sought to
ensure that in addition to the established capabilities, he also has access to a set of
appropriate standards for software development that are based on preset behaviors that can be applied.

This was our goal. It streamlines and organizes the work of a group working on a project while
also facilitating the creation of software.

Error control and tree structure, which enable us to develop a system that is robust and trustworthy,
are two of the guiding ideas behind the construction of this library, which has garnered attention
from people all around the world.

The MishkaInstaller library can be created in various systems, and it provides fundamental
capabilities such as the management of plugin states and the application of standard behaviors.
These features can all be accessed by specified hooks in the library.

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
    {:mishka_installer, "~> 0.1.0"}
  ]
end
```

---

# Donate

If the project was useful for you, the only way you can donate to me is the following ways

| **BTC**                                                                                                                            | **ETH**                                                                                                                            | **DOGE**                                                                                                                           | **TRX**                                                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| <img src="https://github.com/mishka-group/mishka_developer_tools/assets/8413604/230ea4bf-7e8f-4f18-99c9-0f940dd3c6eb" width="200"> | <img src="https://github.com/mishka-group/mishka_developer_tools/assets/8413604/0c8e677b-7240-4b0d-8b9e-bd1efca970fb" width="200"> | <img src="https://github.com/mishka-group/mishka_developer_tools/assets/8413604/3de9183e-c4c0-40fe-b2a1-2b9bb4268e3a" width="200"> | <img src="https://github.com/mishka-group/mishka_developer_tools/assets/8413604/aaa1f103-a7c7-43ed-8f39-20e4c8b9975e" width="200"> |

<details>
  <summary>Donate addresses</summary>

**BTC**:‌

```
bc1q24pmrpn8v9dddgpg3vw9nld6hl9n5dkw5zkf2c
```

**ETH**:

```
0xD99feB9db83245dE8B9D23052aa8e62feedE764D
```

**DOGE**:

```
DGGT5PfoQsbz3H77sdJ1msfqzfV63Q3nyH
```

**TRX**:

```
TBamHas3wAxSEvtBcWKuT3zphckZo88puz
```

</details>
