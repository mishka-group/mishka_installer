# Elixir programming language plugin management system
[![MishkaInstaller CI](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml/badge.svg)](https://github.com/mishka-group/mishka_installer/actions/workflows/ci.yml) [![Hex.pm](https://img.shields.io/badge/hex-0.0.2-blue.svg)](https://hex.pm/packages/mishka_installer) [![GitHub license](https://img.shields.io/badge/apache-2.0-green.svg)](https://raw.githubusercontent.com/mishka-group/mishka_installer/master/LICENSE) ![GitHub issues](https://img.shields.io/github/issues/mishka-group/mishka_installer)


## Build purpose
---

Imagine you are going to make an application that will have many plugins built for it in the future. But the fact that many manipulations will be made on your source code makes it difficult to maintain the application. For example, you present a content management system for your users, and now they need to activate a section for registration and `SMS`; the system allows you to present your desired input/output absolutely plugin oriented to your users and makes it possible for the developers to write their required applications beyond the core source code. 
> We have used this library in the [Mishka content management system](https://github.com/mishka-group/mishka-cms).

**NOTICE: Do not use the master branch; this library is under heavy development.** Expect version 0.0.3, and for using the new features, please wait until a new release is out.

### Plugin management system theory and installation of Elixir libraries at `runtime`
---
The functionality of this library can be conceptualized as an architectural potential that is composed of two primary components, which are as follows:
1. Event management
2. Managing removal and installation of Elixir plugins without `downtime`.

When a programmer uses this library for his own software development, we sought to ensure that in addition to the established capabilities, he also has access to a set of appropriate standards for software development that are based on preset behaviors that can be applied. This was our goal. It streamlines and organizes the work of a group working on a project while also facilitating the creation of software.

Error control and tree structure, which enable us to develop a system that is robust and trustworthy, are two of the guiding ideas behind the construction of this library, which has garnered attention from people all around the world.
The MishkaInstaller library can be created in various systems, and it provides fundamental capabilities such as the management of plugin states and the application of standard behaviors. These features can all be accessed by specified hooks in the library.


## Behaviors and events
---
In this section, you can define a series of events for each `event`, for example: after `successful registration` or `unsuccessful purchase` from “the store”, and for each `event`, put a set of `callbacks` in one module. After completing this step, when the user wants to create his own plugin, the `@behaviour` module will call you in its action module.
This helps you have a regular and error-free system, and the library uses an almost integrated structure in all of its events.

## `Hook` with priority
---
In Mishka Elixir Plugin Management Library, a series of action or `hook` functions are given to the developer of the main plugin or software, which helps build plugins outside the system and convert software sections into separate `events`. Some of the functions of this module include the following:

1. Registering a plugin outside of the system in database and ram `state`
3. Removing plugin from database and `state`
4. Restoring plugin
5. Successful pause of plugin
6. `Hook` plugin
7. Search among the `events`

And other functions that help both the mother software become an event-driven system and the developer can build the desired plugin or extension for different parts of the software and install it on the system as a separate package. This package can also be published in `hex`.

## State management and links to the database supporting `PostgreSQL`
---

The `Hook` module manages a large part of this part, and the developer of the external plugin usually does not need it much. Still, this part creates a `state` on RAM for each plugin that is activated in a specific event and a dynamic supervisor for it. This allows us in case of an error in each plugin; the other plugins in the different events face no errors, and the system will try to restart with various strategies. 
It should be noted for more stability and data storage after registering a plugin in the system; This section also maintains a backup copy of the database and strategies for recall in the event in case of an error. But to speed up the calling of each plugin, the website always uses `state`.

---

## Managing removal and installation of Elixir plugins without `downtime`

Through the use of event management, you are able to convert any portion of your program into a standalone event based on the specific requirements of the strategy, and you are also able to activate an endless number of modules or plugins for each event. However, if you do not perform installation at runtime, you will need to ensure that you call all of the necessary plugins in addition to the primary source when you start the software. One example of this would be installing an Elixir library in the `mix.exs` file.

By utilizing this capability, you will be able to add your program to the system and manage it after adding it, even if your software is already operating. The following are examples of management facilities that may be included:

1. Register a plugin for a specified event
2. Activate the plugin for the installation
3. Put an end to the installation of plugins
4. Resetting the configuration plugin used during installation
5. Uninstall the currently active plugin.
6. Manage the plugin's requirements after they have been installed.
7. Keeping an eye on the graphic panel and demonstrating it to the site managers

And there are other scenarios that are known as APIs or Hooks to the software developer and management, and making use of them is a pretty straightforward process.
It is important to note that this capability does not involve Erlang's hot coding and that it can only be used to install an Elixir library. Additionally, it is still in the process of being developed and is now in an experimental stage. If you use the software, you need to make sure you have a backup of it. At the moment, it is merely in the testing phase of its development, which consists of trial and error.

> **To use this section, please read the documentation of this library**

---

## Installing the library:
---
It should be noted that this library must be installed in two parts of the plugin and the software that wants to display the plugins, and due to its small dependencies, it does not cause any problems. To install, just add this library to your "mix.exs" in the "deps" function as follows:

```elixir
def deps do
  [
    {:mishka_installer, "~> 0.0.4"}
  ]
end
```

## Using the library for extension creation and event activation:
---

After installing this library, you must first install the required database of this package on your website, for which a `mix task` has been created, which is enough to load it once in your terminal, in the project path before the start.

```elixir
mix mishka_installer.db.gen.migration
```

After implementing the above sections, you must first implement events in your main software and place the `call` function from the `Hook` module there to call all the plugins activated in the event you want based on priority. And give the `state` you want, to these plugins in order, and the output you expect will eventually be generated.

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

Now the event is ready in the part where you need to allow the developer to make his own plugins for it. And it's time to write a plugin for this section. This is very simple. Consider the following example:

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

> As you can see in the above, we used `MishkaInstaller.Reference.OnUserAfterLogin` in order to activate `behavior` which has a few `callback` in it, and you can see [here](https://github.com/mishka-group/mishka_installer/blob/master/lib/plugin_manager/event/reference/on_user_after_login.ex). 

---

> There should be two main functions in each plugin, namely `initial` and also `call`. In the first function, we introduce our plugin, and in the second function, whenever the action function calls this special event for which the plugin is written, based on priority. This plugin is also called. But what is important is the final output of the `call` function. This output may be the input of other plugins with higher priorities. The order of the plugins is from small to large, and if several plugins are registered for a number, it is sorted by name in the second parameter. And it should be noted that in any case, if you did not want this `state` to go to other plugins and the last output is returned in the same plugin, and you can replace `{:reply, :halt, new_state}` with `{:reply, new_state}`.

Subsequent plugins with higher priorities are not counted, and the loop ends here.
Notice that a `Genserver` will be made based on each plugin name without a supervisor, which can be used for temporary memory in the case when the ` __using__` function is used as above, which results in the following option:

```elixir
use MishkaInstaller.Hook,
    module: __MODULE__,
    behaviour: OnUserAfterLogin,
    event: :on_user_after_login,
    initial: []
```

The last two step to use the plugin you have to put it in your `Application` module so that whenever the server is turned off and on, the plugin is run again and if it is not registered, a copy of its support will be provided once in the database.

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
  html_router: YOUR_WEBSITE_ROUTER_MODULE,
  project_path: YOUR_PROJECT_PATH,
  mix: YOUR_MIX_MODULE,
  mix_path: YOUR_MIX_EXS_PATH,
  gettext: YOUR_GETTEXT
```

> **Because there are a lot of moving elements in this plugin, you need to read the documentation before using it.**

You can see our recommendations and other colleagues in the [Proposal](https://github.com/mishka-group/Proposals) repository, and if you have a request or idea, send us the full description.

> **Please help us by submitting suggestions and reviewing the project so that [Mishka Group](https://github.com/mishka-group) can produce more products and provide them to programmers and webmasters, and online software.**