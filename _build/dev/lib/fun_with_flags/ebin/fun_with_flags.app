{application,fun_with_flags,
    [{compile_env,
         [{fun_with_flags,[cache],error},
          {fun_with_flags,
              [persistence],
              {ok,[{adapter,'Elixir.FunWithFlags.Store.Persistent.Ecto'},
                   {repo,'Elixir.Plausible.Repo'}]}}]},
     {applications,[kernel,stdlib,elixir,logger]},
     {description,
         "FunWithFlags, a flexible and fast feature toggle library for Elixir.\n"},
     {modules,
         ['Elixir.FunWithFlags','Elixir.FunWithFlags.Actor',
          'Elixir.FunWithFlags.Actor.Percentage',
          'Elixir.FunWithFlags.Application','Elixir.FunWithFlags.Config',
          'Elixir.FunWithFlags.Flag','Elixir.FunWithFlags.Gate',
          'Elixir.FunWithFlags.Gate.InvalidGroupNameError',
          'Elixir.FunWithFlags.Gate.InvalidTargetError',
          'Elixir.FunWithFlags.Group','Elixir.FunWithFlags.Group.Any',
          'Elixir.FunWithFlags.Notifications.PhoenixPubSub',
          'Elixir.FunWithFlags.NullEctoRepo',
          'Elixir.FunWithFlags.SimpleStore','Elixir.FunWithFlags.Store',
          'Elixir.FunWithFlags.Store.Cache',
          'Elixir.FunWithFlags.Store.Persistent',
          'Elixir.FunWithFlags.Store.Persistent.Ecto',
          'Elixir.FunWithFlags.Store.Persistent.Ecto.Record',
          'Elixir.FunWithFlags.Store.Serializer.Ecto',
          'Elixir.FunWithFlags.Store.Serializer.Redis',
          'Elixir.FunWithFlags.Supervisor','Elixir.FunWithFlags.Timestamps']},
     {registered,[]},
     {vsn,"1.9.0"},
     {mod,{'Elixir.FunWithFlags.Application',[]}}]}.
