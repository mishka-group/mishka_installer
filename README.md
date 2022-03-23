# Elixir programming language plugin management system

## Build purpose
---

Imagine you are going to make an application that will have many plugins built for it in the future. But the fact that many manipulations will be made on your source code makes it difficult to maintain the application. For example, you present a content management system for your users, and now they need to activate a section for registration and SMS; the system allows you to present your desired input/output absolutely plugin oriented to your users and makes it possible for the developers to write their required applications beyond the core source code. 
> We have used this library in the [Mishka content management system](https://github.com/mishka-group/mishka-cms).

## Plugin management system implementation theory
---
The library categorizes your whole software design structure into many parts; and has an appropriate dependency that is optional with `Genserver`; it considers a monitoring branch for each of your plugins, which results in fewer errors and `downtime`. The considered part:

1. Behaviors and events
2. Recalling or `Hook` with priority
3. `State` management and links to the database (`PostgreSQL` support)

Except from the 1st item, which can be redefined based on the developer's needs in his/her personal systems, the remaining items are almost constant, and a lot of functions will be handed to the developer to manage each plugin.

## Behaviors and events
---
In this section, you can define a series of events for each `event`, for example: after `successful registration` or `unsuccessful purchase` from “the store”, and for each `event`, put a set of `callbacks` in one module. After completing this step, when the user wants to create his own plugin, the `@behaviour` module will call you in its action module.
This helps you have a regular and error-free system, and the library uses an almost integrated structure in all of its events.

## `Hook` with priority
---
In Mishka Elixir Plugin Management Library, a series of action or `hook` functions are given to the developer of the main plugin or software, which helps build plugins outside the system and convert software sections into separate `events`. Some of the functions of this module include the following:

1. Registering a plugin outside of the system in database and ram `state`
2. Removing plugin from database and `state`
3. Restoring plugin
4. Successful pause of plugin
5. `Hook` plugin
6. Search among the `events`

And other functions that help both the mother software become an event-driven system and the developer can build the desired plugin or extension for different parts of the software and install it on the system as a separate package. This package can also be published in `hex`.

## State management and links to the database supporting `PostgreSQL`
---

The `Hook` module manages a large part of this part, and the developer of the external plugin usually does not need it much. Still, this part creates a `state` on RAM for each plugin that is activated in a specific event and a dynamic supervisor for it. This allows us in case of an error in each plugin; the other plugins in the different events face no errors, and the system will try to restart with various strategies. 
It should be noted for more stability and data storage after registering a plugin in the system; This section also maintains a backup copy of the database and strategies for recall in the event in case of an error. But to speed up the calling of each plugin, the website always uses `state`.

## Installing the library:
---
It should be noted that this library must be installed in two parts of the plugin and the software that wants to display the plugins, and due to its small dependencies, it does not cause any problems. To install, just add this library to your "mix.exs" in the "deps" function as follows:

```elixir
def deps do
  [
    {:mishka_installer, "~> 0.0.1"}
  ]
end
```

## Using the library:
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

The last step to use the plugin you have to put it in your `Application` module so that whenever the server is turned off and on, the plugin is run again and if it is not registered, a copy of its support will be provided once in the database.

```elixir
children = [
  %{id: YOUR_PLUGIN_MODULE, start: {YOUR_PLUGIN_MODULE, :start_link, [[]]}}
]
```

You can see our recommendations and other colleagues in the [Proposal](https://github.com/mishka-group/Proposals) repository, and if you have a request or idea, send us the full description.

> **Please help us by submitting suggestions and reviewing the project so that [Mishka Group](https://github.com/mishka-group) can produce more products and provide them to programmers and webmasters, and online software.**
