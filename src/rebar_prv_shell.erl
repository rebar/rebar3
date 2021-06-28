%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% Copyright (c) 2011 Trifork
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% -------------------------------------------------------------------

-module(rebar_prv_shell).
-author("Kresten Krab Thorup <krab@trifork.com>").
-author("Fred Hebert <mononcqc@ferd.ca>").

-behaviour(provider).

-export([init/1,
         do/1,
         format_error/1]).

-export([maybe_set_env_vars/2]).

-include("rebar.hrl").
-include_lib("providers/include/providers.hrl").

-define(PROVIDER, shell).
-define(DEPS, [compile]).

-dialyzer({nowarn_function, rewrite_leaders/2}).

%% ===================================================================
%% Public API
%% ===================================================================

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    State1 = rebar_state:add_provider(
            State,
            providers:create([
                {name, ?PROVIDER},
                {module, ?MODULE},
                {bare, true},
                {deps, ?DEPS},
                {example, "rebar3 shell"},
                {short_desc, "Run shell with project apps and deps in path."},
                {desc, info()},
                {opts, [{config, undefined, "config", string,
                         "Path to the config file to use. Defaults to "
                         "{shell, [{config, File}]} and then the relx "
                         "sys.config file if not specified."},
                        {name, undefined, "name", atom,
                         "Gives a long name to the node."},
                        {sname, undefined, "sname", atom,
                         "Gives a short name to the node."},
                        {setcookie, undefined, "setcookie", atom,
                         "Sets the cookie if the node is distributed."},
                        {script_file, undefined, "script", string,
                         "Path to an escript file to run before "
                         "starting the project apps. Defaults to "
                         "rebar.config {shell, [{script_file, File}]} "
                         "if not specified."},
                        {apps, undefined, "apps", string,
                         "A list of apps to boot before starting the "
                         "shell. (E.g. --apps app1,app2,app3) Defaults "
                         "to rebar.config {shell, [{apps, Apps}]} or "
                         "relx apps if not specified."},
                        {relname, $r, "relname", atom,
                         "Name of the release to use as a template for the "
                         "shell session"},
                        {relvsn, $v, "relvsn", string,
                         "Version of the release to use for the shell "
                         "session"},
                        {start_clean, undefined, "start-clean", boolean,
                         "Cancel any applications in the 'apps' list "
                         "or release."},
                        {env_file, undefined, "env-file", string,
                         "Path to file of os environment variables to setup "
                         "before expanding vars in config files."},
                        {user_drv_args, undefined, "user_drv_args", string,
                         "Arguments passed to user_drv start function for "
                         "creating custom shells."}]}
            ])
    ),
    {ok, State1}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(Config) ->
    shell(Config),
    {ok, Config}.

-spec format_error(any()) -> iolist().
format_error({unknown_app, Unknown}) ->
    io_lib:format("Applications list for shell contains an unrecognizable application definition: ~p", [Unknown]);
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%% NOTE:
%% this is an attempt to replicate `erl -pa ./ebin -pa deps/*/ebin`. it is
%% mostly successful but does stop and then restart the user io system to get
%% around issues with rebar being an escript and starting in `noshell` mode.
%% it also lacks the ctrl-c interrupt handler that `erl` features. ctrl-c will
%% immediately kill the script. ctrl-g, however, works fine

shell(State) ->
    setup_name(State),
    setup_paths(State),
    ShellArgs = debug_get_value(shell_args, rebar_state:get(State, shell, []), undefined,
                                "Found user_drv args from command line option."),
    setup_shell(ShellArgs),
    maybe_run_script(State),
    %% apps must be started after the change in shell because otherwise
    %% their application masters never gets the new group leader (held in
    %% their internal state)
    maybe_boot_apps(State),
    simulate_proc_lib(),
    true = register(rebar_agent, self()),
    {ok, GenState} = rebar_agent:init(State),
    %% Hack to fool the init process into thinking we have stopped and the normal
    %% node start process can go on. Without it, init:get_status() always return
    %% '{starting, started}' instead of '{started, started}'
    init ! {'EXIT', self(), normal},
    gen_server:enter_loop(rebar_agent, [], GenState, {local, rebar_agent}, hibernate).

info() ->
    "Start a shell with project and deps preloaded similar to~n'erl -pa ebin -pa deps/*/ebin'.~n".

setup_shell(ShellArgs) ->
    LoggerState = maybe_remove_logger(),
    OldUser = kill_old_user(),
    %% Test for support here
    NewUser = try erlang:open_port({spawn,"tty_sl -c -e"}, []) of
        Port when is_port(Port) ->
            true = port_close(Port),
            setup_new_shell(ShellArgs)
    catch
        error:_ ->
            setup_old_shell()
    end,
    rewrite_leaders(OldUser, NewUser),
    maybe_reset_logger(LoggerState).

%% @private starting with OTP-21.2.3, there's an oddity where the logger
%% likely tries to handle system logs while we take down the TTY, which
%% ends up hanging the default logger. This function (along with
%% `maybe_reset_logger/1') removes and re-adds the default logger before and
%% after the TTY subsystem is taken offline, which prevents such hanging.
maybe_remove_logger() ->
    case erlang:function_exported(logger, module_info, 0) of
        false ->
            ignore;
        true ->
            {ok, Cfg} = logger:get_handler_config(default),
            logger:remove_handler(default),
            {restart, Cfg}
    end.

maybe_reset_logger(ignore) ->
    ok;
maybe_reset_logger({restart, Config = #{module := Mod}}) ->
    logger:add_handler(default, Mod, Config).

kill_old_user() ->
    OldUser = whereis(user),
    %% terminate the current user's port, in a way that makes it shut down,
    %% but without taking down the supervision tree so that the escript doesn't
    %% fully die
    [P] = [P || P <- element(2,process_info(whereis(user), links)), is_port(P)],
    user ! {'EXIT', P, normal}, % pretend the port died, then the port can die!
    exit(P, kill),
    wait_for_port_death(1000, P),
    OldUser.

wait_for_port_death(N, _) when N < 0 ->
    %% This risks displaying a warning!
    whatever;
wait_for_port_death(N, P) ->
    case erlang:port_info(P) of
        undefined ->
            ok;
        _ ->
            timer:sleep(10),
            wait_for_port_death(N-10, P)
    end.

setup_new_shell(ShellArgs) ->
    %% terminate the current user supervision structure, if any
    _ = supervisor:terminate_child(kernel_sup, user),
    %% start a new shell (this also starts a new user under the correct group)
    case ShellArgs of
        undefined ->
            _ = user_drv:start();
        _ ->
            _ = user_drv:start(ShellArgs)
    end,
    %% wait until user_drv and user have been registered (max 3 seconds)
    ok = wait_until_user_started(3000),
    whereis(user).

setup_old_shell() ->
    %% scan all processes for any with references to the old user and save them to
    %% update later
    NewUser = rebar_user:start(), % hikack IO stuff with fake user
    NewUser = whereis(user),
    NewUser.

rewrite_leaders(OldUser, NewUser) ->
    %% set any process that had a reference to the old user's group leader to the
    %% new user process. Catch the race condition when the Pid exited after the
    %% liveness check.
    _ = [catch erlang:group_leader(NewUser, Pid)
         || Pid <- erlang:processes(),
            [_|_] = Info <- [erlang:process_info(Pid)],
            proplists:get_value(group_leader, Info) == OldUser,
            is_process_alive(Pid)],
    %% Application masters have the same problem, but they hold the old group
    %% leader in their state and hold on to it. Re-point the processes whose
    %% leaders are application masters. This can mess up a few things around
    %% shutdown time, but is nicer than the current lock-up.
    OldMasters = [Pid
         || Pid <- erlang:processes(),
            Pid < NewUser, % only change old masters
            {_,Dict} <- [erlang:process_info(Pid, dictionary)],
            {application_master,init,4} == proplists:get_value('$initial_call', Dict)],
    _ = [catch erlang:group_leader(NewUser, Pid)
         || Pid <- erlang:processes(),
            lists:member(proplists:get_value(group_leader, erlang:process_info(Pid)),
                         OldMasters)],
    try
        case erlang:function_exported(logger, module_info, 0) of
            false ->
                %% Old style logger had a lock-up issue and other problems related
                %% to group leader handling.
                %% enable error_logger's tty output
                error_logger:swap_handler(tty),
                %% disable the simple error_logger (which may have been added
                %% multiple times). removes at most the error_logger added by
                %% init and the error_logger added by the tty handler
                remove_error_handler(3),
                %% reset the tty handler once more for remote shells
                error_logger:swap_handler(tty);
            true ->
                %% This is no longer a problem with the logger interface
                ok
        end
    catch
        ?WITH_STACKTRACE(E,R,S) % may fail with custom loggers
            ?DEBUG("Logger changes failed for ~p:~p (~p)", [E,R,S]),
            hope_for_best
    end.

setup_paths(State) ->
    %% Add deps to path
    code:add_pathsa(rebar_state:code_paths(State, all_deps)),
    %% add project app test paths
    ok = add_test_paths(State).

maybe_run_script(State) ->
    case first_value([fun find_script_option/1,
                      fun find_script_rebar/1], State) of
        no_value ->
            ?DEBUG("No script_file specified.", []),
            ok;
        "none" ->
            ?DEBUG("Shell script execution skipped (--script none).", []),
            ok;
        RelFile ->
            File = filename:absname(RelFile),
            try run_script_file(File)
            catch
                ?WITH_STACKTRACE(C,E,S)
                    ?ABORT("Couldn't run shell escript ~p - ~p:~p~nStack: ~p",
                           [File, C, E, S])
            end
    end.

-spec find_script_option(rebar_state:t()) -> no_value | list().
find_script_option(State) ->
    {Opts, _} = rebar_state:command_parsed_args(State),
    debug_get_value(script_file, Opts, no_value,
                    "Found script file from command line option.").

-spec find_script_rebar(rebar_state:t()) -> no_value | list().
find_script_rebar(State) ->
    Config = rebar_state:get(State, shell, []),
    %% Either a string, or undefined
    debug_get_value(script_file, Config, no_value,
                    "Found script file from rebar config file.").

run_script_file(File) ->
    ?DEBUG("Extracting escript from ~p", [File]),
    {ok, Script} = escript:extract(File, [compile_source]),
    Beam = proplists:get_value(source, Script),
    Mod = proplists:get_value(module, beam_lib:info(Beam)),
    ?DEBUG("Compiled escript as ~p", [Mod]),
    FakeFile = "/fake_path/" ++ atom_to_list(Mod),
    {module, Mod} = code:load_binary(Mod, FakeFile, Beam),
    ?DEBUG("Evaling ~p:main([]).", [Mod]),
    Result = Mod:main([]),
    ?DEBUG("Result: ~p", [Result]),
    Result.

maybe_boot_apps(State) ->
    _ = maybe_set_env_vars(State),
    case find_apps_to_boot(State) of
        undefined ->
            %% try to read in sys.config file
            ok = reread_config([], State);
        Apps ->
            %% load apps, then check config, then boot them.
            load_apps(Apps),
            ok = reread_config(Apps, State),
            ShellOpts = rebar_state:get(State, shell, []),
            BootLogLevel = debug_get_value(log, ShellOpts, info,
                "Found boot log verbosity mode from config."),
            boot_apps(Apps, BootLogLevel)
    end.

simulate_proc_lib() ->
    FakeParent = spawn_link(fun() -> timer:sleep(infinity) end),
    put('$ancestors', [FakeParent]),
    put('$initial_call', {rebar_agent, init, 1}).

setup_name(State) ->
    {Long, Short, Opts} = rebar_dist_utils:find_options(State),
    rebar_dist_utils:either(Long, Short, Opts).

find_apps_to_boot(State) ->
    %% Try the shell_apps option
    case first_value([fun find_apps_option/1,
                      fun find_apps_rebar/1,
                      fun find_apps_relx/1], State) of
        no_value ->
            undefined;
        Apps ->
            Apps
    end.

-spec find_apps_option(rebar_state:t()) -> no_value | [atom()].
find_apps_option(State) ->
    {Opts, _} = rebar_state:command_parsed_args(State),
    case debug_get_value(apps, Opts, no_value,
                         "Found shell apps from command line option.") of
        no_value ->
            case debug_get_value(start_clean, Opts, false,
                                "Found start-clean argument to disable apps") of
                false -> no_value;
                true -> []
            end;
        AppsStr ->
            [ list_to_atom(AppStr)
              || AppStr <- rebar_string:lexemes(AppsStr, " ,:") ]
    end.

-spec find_apps_rebar(rebar_state:t()) -> no_value | list().
find_apps_rebar(State) ->
    ShellOpts = rebar_state:get(State, shell, []),
    debug_get_value(apps, ShellOpts, no_value,
                    "Found shell opts from command line option.").

-spec find_apps_relx(rebar_state:t()) -> no_value | list().
find_apps_relx(State) ->
    {Opts, _} = rebar_state:command_parsed_args(State),
    RelxOpts = rebar_state:get(State, relx, []),
    {Defname, Defvsn} = debug_get_value(default_release, RelxOpts,
                                        {undefined, undefined},
                                        "Found default release from config"),
    Relname = debug_get_value(relname, Opts, Defname,
                              "Found relname from command line option"),
    Relvsn = debug_get_value(relvsn, Opts, Defvsn,
                             "Found relvsn from command line option"),
    Releases = [Rel || Rel <- rebar_state:get(State, relx, []),
                       is_tuple(Rel), element(1, Rel) =:= release,
                       tuple_size(Rel) =:= 3 orelse tuple_size(Rel) =:= 4,
                       {Name, Vsn} <- [element(2, Rel)],
                       Relname == undefined orelse Name == Relname,
                       Relvsn == undefined orelse Vsn == Relvsn],
    case Releases of
        [] ->
            no_value;
        [{_, _, Apps}|_] ->
            ?DEBUG("Found shell apps from relx.", []),
            Apps;
        [{_, _, Apps, _}|_] ->
            ?DEBUG("Found shell apps from relx.", []),
            Apps
    end.

load_apps(Apps) ->
    [case application:load(App) of
        ok ->
             {ok, Ks} = application:get_all_key(App),
             load_apps(proplists:get_value(applications, Ks));
        _ ->
            error % will be caught when starting the app
     end || App <- normalize_load_apps(Apps),
            not lists:keymember(App, 1, application:loaded_applications())],
    ok.

reread_config(AppsToStart, State) ->
    case find_config(State) of
        no_config ->
            ok;
        ConfigList ->
            %% This allows people who use applications that are also
            %% depended on by rebar3 or its plugins to change their
            %% configuration at runtime based on the configuration files.
            %%
            %% To do this, we stop apps that are already started before
            %% reloading their configuration.
            %%
            %% We make an exception for apps that:
            %%  - are not already running
            %%  - would not be restarted (and hence would break some
            %%    compatibility with rebar3)
            %%  - are not in the config files and would see no config
            %%    changes
            %%  - are not in a blacklist, where changing their config
            %%    would be risky to the shell or the rebar3 agent
            %%    functionality (i.e. changing inets may break proxy
            %%    settings, stopping `kernel' would break everything)
            Running = [App || {App, _, _} <- application:which_applications()],
            BlackList = [inets, stdlib, kernel, rebar],
            _ = [application:stop(App)
                 || Config <- ConfigList,
                    {App, _} <- Config,
                    lists:member(App, Running),
                    lists:member(App, AppsToStart),
                    not lists:member(App, BlackList)],
            _ = rebar_utils:reread_config(ConfigList, [update_logger]),
            ok
    end.

boot_apps(Apps, BootLogLevel) ->
    Normalized = normalize_boot_apps(Apps),
    Res = [application:ensure_all_started(App) || App <- Normalized],
    print_booted([App || {ok, Booted} <- Res, App <- Booted], BootLogLevel),
    %% errors are not suppressed
    _ = [?ERROR("Failed to boot ~p for reason ~p", [App, Reason])
            || {error, {App, Reason}} <- Res],
    ok.

print_booted(Booted, debug) ->
    _ = [?DEBUG("Booted ~p", [App]) || App <- Booted];
print_booted(Booted, info) ->
    _ = [?INFO("Booted ~p", [App]) || App <- Booted].

normalize_load_apps([]) -> [];
normalize_load_apps([{_App, none} | T]) -> normalize_load_apps(T);
normalize_load_apps([{App, _} | T]) -> [App | normalize_load_apps(T)];
normalize_load_apps([{App, _Vsn, load} | T]) -> [App | normalize_load_apps(T)];
normalize_load_apps([{_App, _Vsn, none} | T]) -> normalize_load_apps(T);
normalize_load_apps([{App, _Vsn, Operator} | T]) when is_atom(Operator) ->
    [App | normalize_load_apps(T)];
normalize_load_apps([App | T]) when is_atom(App) -> [App | normalize_load_apps(T)];
normalize_load_apps([Unknown | _]) ->
    erlang:error(?PRV_ERROR({unknown_app, Unknown})).

normalize_boot_apps([]) -> [];
normalize_boot_apps([{_App, load} | T]) -> normalize_boot_apps(T);
normalize_boot_apps([{_App, _Vsn, load} | T]) -> normalize_boot_apps(T);
normalize_boot_apps([{_App, none} | T]) -> normalize_boot_apps(T);
normalize_boot_apps([{_App, _Vsn, none} | T]) -> normalize_boot_apps(T);
normalize_boot_apps([{App, _Vsn, Operator} | T]) when is_atom(Operator) ->
    [App | normalize_boot_apps(T)];
normalize_boot_apps([{App, _Vsn} | T]) -> [App | normalize_boot_apps(T)];
normalize_boot_apps([App | T]) when is_atom(App) -> [App | normalize_boot_apps(T)];
normalize_boot_apps([Unknown | _]) ->
    erlang:error(?PRV_ERROR({unknown_app, Unknown})).

remove_error_handler(0) ->
    ?WARN("Unable to remove simple error_logger handler", []);
remove_error_handler(N) ->
    case gen_event:delete_handler(error_logger, error_logger, []) of
        {error, module_not_found} -> ok;
        {error_logger, _} -> remove_error_handler(N-1)
    end.

%% Timeout is a period to wait before giving up
wait_until_user_started(0) ->
    ?ABORT("Timeout exceeded waiting for `user` to register itself", []),
    erlang:error(timeout);
wait_until_user_started(Timeout) ->
    case whereis(user) of
        %% if user is not yet registered wait a tenth of a second and try again
        undefined -> timer:sleep(100), wait_until_user_started(Timeout - 100);
        _ -> ok
    end.

add_test_paths(State) ->
    _ = [begin
            AppDir = rebar_app_info:out_dir(App),
            %% ignore errors resulting from non-existent directories
            _ = code:add_path(filename:join([AppDir, "test"]))
         end || App <- rebar_state:project_apps(State)],
    _ = code:add_path(filename:join([rebar_dir:base_dir(State), "test"])),
    ok.

% First try the --config flag, then try the relx sys_config
-spec find_config(rebar_state:t()) -> [[tuple()]] | no_config.
find_config(State) ->
    RootDir = rebar_dir:root_dir(State),
    case first_value([fun find_config_option/1,
                      fun find_config_rebar/1,
                      fun find_config_relx/1], State) of
        no_value ->
            no_config;
        Filename when is_list(Filename) ->
            case is_src_config(Filename) of
                false ->
                    rebar_file_utils:consult_config(RootDir, Filename);
                true ->
                    rebar_file_utils:consult_env_config(RootDir, Filename)
            end
    end.

-spec first_value([Fun], State) -> no_value | Value when
      Value :: any(),
      State :: rebar_state:t(),
      Fun :: fun ((State) -> no_value | Value).
first_value([], _) -> no_value;
first_value([Fun | Rest], State) ->
    case Fun(State) of
        no_value ->
            first_value(Rest, State);
        Value ->
            Value
    end.

debug_get_value(Key, List, Default, Description) ->
    case proplists:get_value(Key, List, Default) of
        Default -> Default;
        Value ->
            ?DEBUG(Description, []),
            Value
    end.

-spec find_config_option(rebar_state:t()) -> Filename::list() | no_value.
find_config_option(State) ->
    {Opts, _} = rebar_state:command_parsed_args(State),
    debug_get_value(config, Opts, no_value,
                    "Found config from command line option.").

-spec find_config_rebar(rebar_state:t()) -> [tuple()] | no_value.
find_config_rebar(State) ->
    debug_get_value(config, rebar_state:get(State, shell, []), no_value,
                    "Found config from rebar config file.").

-spec find_config_relx(rebar_state:t()) -> [tuple()] | no_value.
find_config_relx(State) ->
    %% The order in relx is to load the src version first;
    %% we do the same.
    RelxCfg = rebar_state:get(State, relx, []),
    Src = debug_get_value(sys_config_src, RelxCfg, no_value,
                          "Found config.src from relx."),
    case Src of
        no_value ->
            debug_get_value(sys_config, RelxCfg, no_value,
                            "Found config from relx.");
        _ ->
            Src
    end.

-spec is_src_config(file:filename()) -> boolean().
is_src_config(Filename) ->
    filename:extension(Filename) =:= ".src".

maybe_set_env_vars(State) ->
    maybe_set_env_vars(State, shell).

maybe_set_env_vars(State, Group) ->
    EnvFile = debug_get_value(env_file, rebar_state:get(State, Group, []), undefined,
                             "Found env_file from config."),
    {Opts, _} = rebar_state:command_parsed_args(State),
    EnvFile1 = debug_get_value(env_file, Opts, EnvFile,
                               "Found env_file from command line option."),

    case maybe_read_file(EnvFile1) of
        ignore ->
            ok;
        {error, _} ->
            ?WARN("Failed to read file with environment variables: ~p", [EnvFile1]);
        {ok, Bin} ->
            Lines = string:split(unicode:characters_to_list(Bin), "\n", all),
            [handle_env_var_line(Line) || Line <- Lines]
    end.

handle_env_var_line(Line) ->
    Trimmed = rebar_string:trim(Line, both, [$\s]),
    %% ignore lines starting with # and
    %% fail if there are spaces around =
    case re:run(Trimmed, "^(?<key>[^#][^\s=]*)=(?<value>[^\s]\.*)",
                [{capture, [key, value], list}, unicode]) of
        {match, [Key, Value]} ->
            os:putenv(Key, Value);
        _ ->
            case Trimmed of
                [$# | _] -> ignore;
                [] -> ignore;
                Other ->
                    ?WARN("Unable to parse environment variable from this line: ~ts", [Other])
            end
    end.

maybe_read_file(undefined) ->
    ignore;
maybe_read_file(EnvFile) ->
    file:read_file(EnvFile).
