{application,mishka_installer,
             [{config_mtime,1718226658},
              {compile_env,[{guarded_struct,[sanitize_derive],{ok,nil}},
                            {guarded_struct,[validate_derive],{ok,nil}}]},
              {optional_applications,[]},
              {applications,[kernel,stdlib,elixir,logger,phoenix_pubsub,
                             mishka_developer_tools,telemetry]},
              {description,"Mishka Installer is a system plugin manager and run time installer for elixir."},
              {modules,['Elixir.MishkaInstaller',
                        'Elixir.MishkaInstaller.Application',
                        'Elixir.MishkaInstaller.Event.Event',
                        'Elixir.MishkaInstaller.Event.EventHandler',
                        'Elixir.MishkaInstaller.Event.Hook',
                        'Elixir.MishkaInstaller.Event.ModuleStateCompiler',
                        'Elixir.MishkaInstaller.Installer.LibraryReader',
                        'Elixir.MishkaInstaller.Installer.PortHandler',
                        'Elixir.MishkaInstaller.Installer.RunTimeSourcing',
                        'Elixir.MishkaInstaller.MnesiaRepo',
                        'Elixir.MishkaInstaller.MnesiaRepo.State',
                        'Elixir.MishkaInstallerTest.Support.MishkaPlugin.RegisterEmailSender',
                        'Elixir.MishkaInstallerTest.Support.MishkaPlugin.RegisterOTPSender']},
              {registered,[]},
              {vsn,"0.1.0"},
              {mod,{'Elixir.MishkaInstaller.Application',[]}}]}.