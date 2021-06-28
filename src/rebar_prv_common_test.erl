%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et

-module(rebar_prv_common_test).

-behaviour(provider).

-export([init/1,
         do/1,
         format_error/1]).

-ifdef(TEST).
%% exported for test purposes
-export([compile/2, prepare_tests/1, translate_paths/2, maybe_write_coverdata/1]).
-endif.

-include("rebar.hrl").
-include_lib("providers/include/providers.hrl").

-define(PROVIDER, ct).
%% we need to modify app_info state before compile
-define(DEPS, [lock]).

%% ===================================================================
%% Public API
%% ===================================================================

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([{name, ?PROVIDER},
                                 {module, ?MODULE},
                                 {deps, ?DEPS},
                                 {bare, true},
                                 {example, "rebar3 ct"},
                                 {short_desc, "Run Common Tests."},
                                 {desc, "Run Common Tests."},
                                 {opts, ct_opts(State)},
                                 {profiles, [test]}]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    setup_name(State),
    Tests = prepare_tests(State),
    case compile(State, Tests) of
        %% successfully compiled apps
        {ok, S} ->
            {RawOpts, _} = rebar_state:command_parsed_args(S),
            case proplists:get_value(compile_only, RawOpts, false) of
                true ->
                    {ok, S};
                false ->
                    do(S, Tests)
            end;
        %% this should look like a compiler error, not a ct error
        Error   -> Error
    end.

do(State, Tests) ->
    ?INFO("Running Common Test suites...", []),
    rebar_paths:set_paths([deps, plugins], State),

    %% Run ct provider prehooks
    Providers = rebar_state:providers(State),
    Cwd = rebar_dir:get_cwd(),

    %% Run ct provider pre hooks for all project apps and top level project hooks
    rebar_hooks:run_project_and_app_hooks(Cwd, pre, ?PROVIDER, Providers, State),

    case Tests of
        {ok, T} ->
            case run_tests(State, T) of
                ok    ->
                    %% Run ct provider post hooks for all project apps and top level project hooks
                    rebar_hooks:run_project_and_app_hooks(Cwd, post, ?PROVIDER, Providers, State),
                    rebar_paths:set_paths([plugins, deps], State),
                    symlink_to_last_ct_logs(State, T),
                    {ok, State};
                Error ->
                    rebar_paths:set_paths([plugins, deps], State),
                    symlink_to_last_ct_logs(State, T),
                    Error
            end;
        Error ->
            rebar_paths:set_paths([plugins, deps], State),
            Error
    end.

run_tests(State, Opts) ->
    T = translate_paths(State, Opts),
    Opts1 = setup_logdir(State, T),
    Opts2 = turn_off_auto_compile(Opts1),
    ?DEBUG("Running tests with {ct_opts, ~p}.", [Opts2]),
    {RawOpts, _} = rebar_state:command_parsed_args(State),
    Result = case proplists:get_value(verbose, RawOpts, false) of
        true  -> run_test_verbose(Opts2);
        false -> run_test_quiet(Opts2)
    end,
    ok = maybe_write_coverdata(State),
    Result.

-spec format_error(any()) -> iolist().
format_error({error, Reason}) ->
    io_lib:format("Error running tests:~n  ~p", [Reason]);
format_error({error_running_tests, Reason}) ->
    format_error({error, Reason});
format_error({failures_running_tests, {Failed, AutoSkipped}}) ->
    io_lib:format("Failures occurred running tests: ~b", [Failed+AutoSkipped]);
format_error({badconfig, {Msg, {Value, Key}}}) ->
    io_lib:format(Msg, [Value, Key]);
format_error({badconfig, Msg}) ->
    io_lib:format(Msg, []);
format_error({multiple_errors, Errors}) ->
    io_lib:format(lists:concat(["Error running tests:"] ++
                               lists:map(fun(Error) -> "~n  " ++ Error end, Errors)), []);
format_error({error_reading_testspec, Reason}) ->
    io_lib:format("Error reading testspec: ~p", [Reason]).

%% ===================================================================
%% Internal functions
%% ===================================================================

%% @doc Tries to make the symlink `_build/<profile>/logs/last' to the `ct_run' directory
%% of the last common test run.
-spec symlink_to_last_ct_logs(rebar_state:t(), list()) -> ok.
symlink_to_last_ct_logs(State, Opts) ->
    LogDir = case proplists:get_value(logdir, Opts) of
        undefined -> filename:join([rebar_dir:base_dir(State), "logs"]);
        Dir -> Dir
    end,
    {ok, Filenames} = file:list_dir(LogDir),
    CtRunDirs = lists:filter(fun(S) -> re:run(S, "ct_run", [unicode]) /= nomatch end, Filenames),
    case CtRunDirs of
        [] ->
            % If for some reason there are no such directories, we should not try to set up a link either.
            ok;
        _ ->
            NewestDir = lists:last(lists:sort(CtRunDirs)),
            Target = filename:join([LogDir, "last"]),
            Existing = filename:join([LogDir, NewestDir]),
            case rebar_file_utils:symlink_or_copy(Existing, Target) of
                ok -> ok;
                exists ->
                    %% in case the symlink already exists we remove it
                    %% and make a new updated one
                    rebar_file_utils:rm_rf(Target),
                    rebar_file_utils:symlink_or_copy(Existing, Target);
                Reason -> ?DIAGNOSTIC("Warning, couldn't make a symlink to ~ts, reason: ~p.", [Target, Reason])
            end
    end.

setup_name(State) ->
    {Long, Short, Opts} = rebar_dist_utils:find_options(State),
    rebar_dist_utils:either(Long, Short, Opts).

prepare_tests(State) ->
    %% command line test options
    CmdOpts = cmdopts(State),
    %% rebar.config test options
    CfgOpts = cfgopts(State),
    ProjectApps = rebar_state:project_apps(State),

    %% prioritize tests to run first trying any command line specified
    %% tests falling back to tests specified in the config file finally
    %% running a default set if no other tests are present
    select_tests(State, ProjectApps, CmdOpts, CfgOpts).

cmdopts(State) ->
    {RawOpts, _} = rebar_state:command_parsed_args(State),
    %% filter out opts common_test doesn't know about and convert
    %% to ct acceptable forms
    transform_retry(transform_opts(RawOpts, []), State).

transform_opts([], Acc) -> lists:reverse(Acc);
transform_opts([{dir, Dirs}|Rest], Acc) ->
    transform_opts(Rest, [{dir, split_string(Dirs)}|Acc]);
transform_opts([{suite, Suites}|Rest], Acc) ->
    transform_opts(Rest, [{suite, split_string(Suites)}|Acc]);
transform_opts([{group, Groups}|Rest], Acc) ->
    transform_opts(Rest, [{group, transform_group(Groups)}|Acc]);
transform_opts([{testcase, Cases}|Rest], Acc) ->
    transform_opts(Rest, [{testcase, split_string(Cases)}|Acc]);
transform_opts([{config, Configs}|Rest], Acc) ->
    transform_opts(Rest, [{config, split_string(Configs)}|Acc]);
transform_opts([{spec, Specs}|Rest], Acc) ->
    transform_opts(Rest, [{spec, split_string(Specs)}|Acc]);
transform_opts([{include, Includes}|Rest], Acc) ->
    transform_opts(Rest, [{include, split_string(Includes)}|Acc]);
transform_opts([{logopts, LogOpts}|Rest], Acc) ->
    transform_opts(Rest, [{logopts, lists:map(fun(P) -> list_to_atom(P) end, split_string(LogOpts))}|Acc]);
transform_opts([{force_stop, "true"}|Rest], Acc) ->
    transform_opts(Rest, [{force_stop, true}|Acc]);
transform_opts([{force_stop, "false"}|Rest], Acc) ->
    transform_opts(Rest, [{force_stop, false}|Acc]);
transform_opts([{force_stop, "skip_rest"}|Rest], Acc) ->
    transform_opts(Rest, [{force_stop, skip_rest}|Acc]);
transform_opts([{create_priv_dir, CreatePrivDir}|Rest], Acc) ->
    transform_opts(Rest, [{create_priv_dir, list_to_atom(CreatePrivDir)}|Acc]);
%% drop cover from opts, ct doesn't care about it
transform_opts([{cover, _}|Rest], Acc) ->
    transform_opts(Rest, Acc);
%% drop verbose from opts, ct doesn't care about it
transform_opts([{verbose, _}|Rest], Acc) ->
    transform_opts(Rest, Acc);
%% drop fail_fast from opts, ct doesn't care about it
transform_opts([{fail_fast, _}|Rest], Acc) ->
    transform_opts(Rest, Acc);
%% getopt should handle anything else
transform_opts([Opt|Rest], Acc) ->
    transform_opts(Rest, [Opt|Acc]).

%% @private only retry if specified and if no other spec
%% is given.
transform_retry(Opts, State) ->
    case proplists:get_value(retry, Opts, false) andalso
         not is_any_defined([spec,dir,suite], Opts) of
        false ->
            Opts;
        true ->
            Path = filename:join([rebar_dir:base_dir(State), "logs", "retry.spec"]),
            filelib:is_file(Path) andalso [{spec, Path}|Opts]
    end.

split_string(String) ->
    rebar_string:lexemes(String, [$,]).

transform_group(String) ->
    case rebar_string:consult([$[, String, $], $.]) of
        [Terms] when is_list(Terms) ->
            Terms;
        Terms when is_list(Terms) ->
            Terms;
        {error, _} ->
            %% try a normal string split
            split_string(String)
    end.

cfgopts(State) ->
    case rebar_state:get(State, ct_opts, []) of
        Opts when is_list(Opts) ->
            ensure_opts(add_hooks(Opts, State), []);
        Wrong ->
            %% probably a single non list term
            ?PRV_ERROR({badconfig, {"Value `~p' of option `~p' must be a list", {Wrong, ct_opts}}})
    end.

ensure_opts([], Acc) -> lists:reverse(Acc);
ensure_opts([{cover, _}|Rest], Acc) ->
    ?WARN("Cover specs not supported. See https://www.rebar3.org/docs/testing/ct/", []),
    ensure_opts(Rest, Acc);
ensure_opts([{auto_compile, _}|Rest], Acc) ->
    ?WARN("Auto compile not supported", []),
    ensure_opts(Rest, Acc);
ensure_opts([{suite, Suite}|Rest], Acc) when is_integer(hd(Suite)) ->
    ensure_opts(Rest, [{suite, Suite}|Acc]);
ensure_opts([{suite, Suite}|Rest], Acc) when is_atom(Suite) ->
    ensure_opts(Rest, [{suite, atom_to_list(Suite)}|Acc]);
ensure_opts([{suite, Suites}|Rest], Acc) ->
    NewSuites = {suite, lists:map(fun(S) when is_atom(S) -> atom_to_list(S);
                                     (S) when is_list(S) -> S
                                  end,
                                  Suites)},
    ensure_opts(Rest, [NewSuites|Acc]);
ensure_opts([{K, V}|Rest], Acc) ->
    ensure_opts(Rest, [{K, V}|Acc]);
%% pass through other options, in case of things like config terms
%% in `ct_opts`
ensure_opts([V|Rest], Acc) ->
    ensure_opts(Rest, [V|Acc]).

add_hooks(Opts, State) ->
    FailFast = case fails_fast(State) of
        true -> [cth_fail_fast];
        false -> []
    end,
    case {readable(State), lists:keyfind(ct_hooks, 1, Opts)} of
        {false, _} ->
            Opts;
        {Other, false} ->
            [{ct_hooks, [cth_readable_failonly, readable_shell_type(Other),
                         cth_retry] ++ FailFast} | Opts];
        {Other, {ct_hooks, Hooks}} ->
            %% Make sure hooks are there once only and add wanted hooks that are not defined yet
            ReadableHooks = [cth_readable_failonly, readable_shell_type(Other),
                             cth_retry] ++ FailFast,
            NewHooks = Hooks ++ [ReadableHook ||
                ReadableHook <- ReadableHooks,
                not is_defined(ReadableHook, Hooks)
            ],
            lists:keyreplace(ct_hooks, 1, Opts, {ct_hooks, NewHooks})
    end.

is_defined(_Key, []) -> false;
is_defined(Key, [Key | _Hs]) -> true;
is_defined(Key, [{Key, _Opts} | _Hs]) -> true;
is_defined(Key, [{Key, _Opts, _Prio} | _Hs]) -> true;
is_defined(Key, [_ | Hs]) -> is_defined(Key, Hs).


readable_shell_type(true) -> cth_readable_shell;
readable_shell_type(compact) -> cth_readable_compact_shell.

select_tests(_, _, _, {error, _} = Error) -> Error;
select_tests(State, ProjectApps, CmdOpts, CfgOpts) ->
    %% set application env if sys_config argument is provided
    SysConfigs = sys_config_list(CmdOpts, CfgOpts),
    _ = rebar_prv_shell:maybe_set_env_vars(State, ct_opts),
    RootDir = rebar_dir:root_dir(State),
    Configs = lists:flatmap(fun(Filename) ->
                                consult_config(RootDir, Filename)
                            end, SysConfigs),
    %% NB: load the applications (from user directories too) to support OTP < 17
    %% to our best ability.
    rebar_paths:set_paths([deps, plugins], State),
    [application:load(Application) || Config <- Configs, {Application, _} <- Config],
    rebar_utils:reread_config(Configs, [update_logger]),

    Opts = merge_opts(CmdOpts,CfgOpts),
    discover_tests(State, ProjectApps, Opts).

consult_config(RootDir, Filename) ->
    case is_src_config(Filename) of
        false ->
            rebar_file_utils:consult_config(RootDir, Filename);
        true ->
            rebar_file_utils:consult_env_config(RootDir, Filename)
    end.

-spec is_src_config(file:filename()) -> boolean().
is_src_config(Filename) ->
    filename:extension(Filename) =:= ".src".

%% Merge the option lists from command line and rebar.config:
%%
%% - Options set on the command line will replace the same options if
%%   set in rebar.config.
%%
%% - Special care is taken with options that select which tests to
%%   run - ANY such option on the command line will replace ALL such
%%   options in the config.
%%
%%   Note that if 'spec' is given, common_test will ignore all 'dir',
%%   'suite', 'group' and 'case', so there is no need to explicitly
%%   remove any options from the command line.
%%
%%   All faulty combinations of options are also handled by
%%   common_test and are not taken into account here.
merge_opts(CmdOpts0, CfgOpts0) ->
    TestSelectOpts = [spec,dir,suite,group,testcase],
    CmdOpts = lists:ukeysort(1, CmdOpts0),
    CfgOpts1 = lists:ukeysort(1, CfgOpts0),
    CfgOpts = case is_any_defined(TestSelectOpts,CmdOpts) of
                  false ->
                      CfgOpts1;
                  true ->
                       [Opt || Opt={K,_} <- CfgOpts1,
                               not lists:member(K,TestSelectOpts)]
              end,
    lists:ukeymerge(1, CmdOpts, CfgOpts).

is_any_defined([Key|Keys],Opts) ->
    proplists:is_defined(Key,Opts) orelse is_any_defined(Keys,Opts);
is_any_defined([],_Opts) ->
    false.

sys_config_list(CmdOpts, CfgOpts) ->
    CmdSysConfigs = split_string(proplists:get_value(sys_config, CmdOpts, "")),
    case proplists:get_value(sys_config, CfgOpts, []) of
        [H | _]=Configs when is_list(H) ->
            Configs ++ CmdSysConfigs;
        [] ->
            CmdSysConfigs;
        Configs ->
            [Configs | CmdSysConfigs]
    end.

discover_tests(State, ProjectApps, Opts) ->
    case is_any_defined([spec,dir,suite],Opts) of
        %% no tests defined, try using `$APP/test` and `$ROOT/test` as dirs
        false -> {ok, default_tests(State, ProjectApps) ++ Opts};
        true  -> {ok, Opts}
    end.

default_tests(State, ProjectApps) ->
    BareTest = filename:join([rebar_state:dir(State), "test"]),
    F = fun(App) -> rebar_app_info:dir(App) == rebar_state:dir(State) end,
    AppTests = application_dirs(ProjectApps, []),
    case filelib:is_dir(BareTest) andalso not lists:any(F, ProjectApps) of
        %% `test` dir at root of project is already scheduled to be
        %%  included or `test` does not exist
        false ->
            %% The rest of the call-chain expects the list of tests to not be
            %% empty, thus we drop the parameter in that case entirely.
            case AppTests of
                [] ->
                    [];
                _ ->
                    [{dir, AppTests}]
            end;
        %% need to add `test` dir at root to dirs to be included
        true  ->
            [{dir, AppTests ++ [BareTest]}]
    end.

application_dirs([], []) -> [];
application_dirs([], Acc) -> lists:reverse(Acc);
application_dirs([App|Rest], Acc) ->
    TestDir = filename:join([rebar_app_info:dir(App), "test"]),
    case filelib:is_dir(TestDir) of
        true  -> application_dirs(Rest, [TestDir|Acc]);
        false -> application_dirs(Rest, Acc)
    end.

compile(State, {ok, _} = Tests) ->
    %% inject `ct_first_files`, `ct_compile_opts` and `include` (from `ct_opts`
    %% and command line options) into the applications to be compiled
    case inject_ct_state(State, Tests) of
        {ok, NewState} -> do_compile(NewState);
        Error          -> Error
    end;
%% maybe compile even in the face of errors?
compile(_State, Error) -> Error.

do_compile(State) ->
    ?DEBUG("Re-compiling the project under the test profile with CT options injected...", []),
    {ok, S} = rebar_prv_compile:do(State),
    ok = maybe_cover_compile(S),
    {ok, S}.

inject_ct_state(State, {ok, Tests}) ->
    Apps = rebar_state:project_apps(State),
    case inject_ct_state(State, Tests, Apps, []) of
        {ok, {NewState, ModdedApps}} ->
            test_dirs(NewState, ModdedApps, Tests);
        {error, _} = Error           -> Error
    end.

inject_ct_state(State, Tests, [App|Rest], Acc) ->
    case inject(rebar_app_info:opts(App), State, Tests) of
        {error, _} = Error -> Error;
        NewOpts            ->
            NewApp = rebar_app_info:opts(App, NewOpts),
            inject_ct_state(State, Tests, Rest, [NewApp|Acc])
    end;
inject_ct_state(State, Tests, [], Acc) ->
    case inject(rebar_state:opts(State), State, Tests) of
        {error, _} = Error -> Error;
        NewOpts            ->
          {ok, {rebar_state:opts(State, NewOpts), lists:reverse(Acc)}}
    end.

opts(Opts, Key, Default) ->
    case rebar_opts:get(Opts, Key, Default) of
        Vs when is_list(Vs) -> Vs;
        Wrong ->
            ?PRV_ERROR({badconfig, {"Value `~p' of option `~p' must be a list", {Wrong, Key}}})
    end.

inject(Opts, State, Tests) -> erl_opts(Opts, State, Tests).

erl_opts(Opts, State, Tests) ->
    %% append `ct_compile_opts` to app defined `erl_opts`
    ErlOpts = opts(Opts, erl_opts, []),
    CTOpts = opts(Opts, ct_compile_opts, []),
    case add_transforms(append(CTOpts, ErlOpts), State) of
        {error, _} = Error -> Error;
        NewErlOpts         -> first_files(rebar_opts:set(Opts, erl_opts, NewErlOpts), Tests)
    end.

first_files(Opts, Tests) ->
    %% append `ct_first_files` to app defined `erl_first_files`
    FirstFiles = opts(Opts, erl_first_files, []),
    CTFirstFiles = opts(Opts, ct_first_files, []),
    case append(CTFirstFiles, FirstFiles) of
        {error, _} = Error -> Error;
        NewFirstFiles      -> include_files(rebar_opts:set(Opts, erl_first_files, NewFirstFiles), Tests)
    end.

include_files(Opts, Tests) ->
    %% append include dirs from command line and `ct_opts` to app defined
    %% `erl_opts`
    ErlOpts = opts(Opts, erl_opts, []),
    Includes = proplists:get_value(include, Tests, []),
    Is = lists:map(fun(I) -> {i, I} end, Includes),
    case append(Is, ErlOpts) of
        {error, _} = Error -> Error;
        NewIncludes        -> ct_macro(rebar_opts:set(Opts, erl_opts, NewIncludes))
    end.

ct_macro(Opts) ->
    ErlOpts = opts(Opts, erl_opts, []),
    NewOpts = safe_define_ct_macro(ErlOpts),
    rebar_opts:set(Opts, erl_opts, NewOpts).

safe_define_ct_macro(Opts) ->
    %% defining a compile macro twice results in an exception so
    %% make sure 'COMMON_TEST' is only defined once
    case test_defined(Opts) of
       true  -> Opts;
       false -> [{d, 'COMMON_TEST'}|Opts]
    end.

test_defined([{d, 'COMMON_TEST'}|_]) -> true;
test_defined([{d, 'COMMON_TEST', true}|_]) -> true;
test_defined([_|Rest]) -> test_defined(Rest);
test_defined([]) -> false.

append({error, _} = Error, _) -> Error;
append(_, {error, _} = Error) -> Error;
append(A, B) -> A ++ B.

add_transforms(CTOpts, State) when is_list(CTOpts) ->
    case readable(State) of
        false ->
            CTOpts;
        Other when Other == true; Other == compact ->
            ReadableTransform = [{parse_transform, cth_readable_transform}],
            (CTOpts -- ReadableTransform) ++ ReadableTransform
    end;
add_transforms({error, _} = Error, _State) -> Error.

readable(State) ->
    {RawOpts, _} = rebar_state:command_parsed_args(State),
    case proplists:get_value(readable, RawOpts) of
        "true"  -> true;
        "false" -> false;
        "compact" -> compact;
        undefined -> rebar_state:get(State, ct_readable, compact)
    end.

fails_fast(State) ->
    {RawOpts, _} = rebar_state:command_parsed_args(State),
    proplists:get_value(fail_fast, RawOpts) == true.

test_dirs(State, Apps, Opts) ->
    case proplists:get_value(spec, Opts) of
        undefined ->
            case {proplists:get_value(suite, Opts), proplists:get_value(dir, Opts)} of
                {undefined, undefined}  ->
                    {ok, rebar_state:project_apps(State, Apps)};
                {Suites, undefined} -> set_compile_dirs(State, Apps, {suite, Suites});
                {undefined, Dirs}   -> set_compile_dirs(State, Apps, {dir, Dirs});
                {Suites, Dir} when is_integer(hd(Dir)) ->
                    set_compile_dirs(State, Apps, join(Suites, Dir));
                {Suites, [Dir]} when is_integer(hd(Dir)) ->
                    set_compile_dirs(State, Apps, join(Suites, Dir));
                {_Suites, _Dirs}    -> {error, "Only a single directory may be specified when specifying suites"}
            end;
        Spec when is_integer(hd(Spec)) ->
            spec_test_dirs(State, Apps, [Spec]);
        Specs ->
            spec_test_dirs(State, Apps, Specs)
    end.

spec_test_dirs(State, Apps, Specs0) ->
    case get_dirs_from_specs(Specs0) of
        {ok,{Specs,SuiteDirs}} ->
            {State1,Apps1} = set_compile_dirs1(State, Apps, {dir, SuiteDirs}),
            {State2,Apps2} = set_compile_dirs1(State1, Apps1, {spec, Specs}),
            [maybe_copy_spec(State2,Apps2,S) || S <- Specs],
            {ok, rebar_state:project_apps(State2, Apps2)};
        Error ->
            Error
    end.

join(Suite, Dir) when is_integer(hd(Suite)) ->
    {suite, [filename:join([Dir, Suite])]};
join(Suites, Dir) ->
    {suite, lists:map(fun(S) -> filename:join([Dir, S]) end, Suites)}.

set_compile_dirs(State, Apps, What) ->
    {NewState,NewApps} = set_compile_dirs1(State, Apps, What),
    {ok, rebar_state:project_apps(NewState, NewApps)}.

set_compile_dirs1(State, Apps, {dir, Dir}) when is_integer(hd(Dir)) ->
    %% single directory
    %% insert `Dir` into an app if relative, or the base state if not
    %% app relative but relative to the root or not at all if outside
    %% project scope
    maybe_inject_test_dir(State, [], Apps, Dir);
set_compile_dirs1(State, Apps, {dir, Dirs}) ->
    %% multiple directories
    F = fun(Dir, {S, A}) -> maybe_inject_test_dir(S, [], A, Dir) end,
    lists:foldl(F, {State, Apps}, Dirs);
set_compile_dirs1(State, Apps, {Type, Files}) when Type==spec; Type==suite ->
    %% specs or suites with dir component
    Dirs = find_file_dirs(Files),
    F = fun(Dir, {S, A}) -> maybe_inject_test_dir(S, [], A, Dir) end,
    lists:foldl(F, {State, Apps}, Dirs).

find_file_dirs(Files) ->
    AllDirs = lists:map(fun(F) -> filename:dirname(filename:absname(F)) end, Files),
    %% eliminate duplicates
    lists:usort(AllDirs).

maybe_inject_test_dir(State, AppAcc, [App|Rest], Dir) ->
    case rebar_file_utils:path_from_ancestor(Dir, rebar_app_info:dir(App)) of
        {ok, []}   ->
            %% normal operation involves copying the entire directory a
            %% suite exists in but if the suite is in the app root directory
            %% the current compiler tries to compile all subdirs including priv
            %% instead copy only files ending in `.erl' and directories
            %% ending in `_SUITE_data' into the `_build/PROFILE/lib/APP' dir
            ok = copy_bare_suites(Dir, rebar_app_info:out_dir(App)),
            Opts = inject_test_dir(rebar_state:opts(State), rebar_app_info:out_dir(App)),
            {rebar_state:opts(State, Opts), AppAcc ++ [App]};
        {ok, Path} ->
            Opts = inject_test_dir(rebar_app_info:opts(App), Path),
            {State, AppAcc ++ [rebar_app_info:opts(App, Opts)] ++ Rest};
        {error, badparent} ->
            maybe_inject_test_dir(State, AppAcc ++ [App], Rest, Dir)
    end;
maybe_inject_test_dir(State, AppAcc, [], Dir) ->
    case rebar_file_utils:path_from_ancestor(Dir, rebar_state:dir(State)) of
        {ok, []}   ->
            %% normal operation involves copying the entire directory a
            %% suite exists in but if the suite is in the root directory
            %% that results in a loop as we copy `_build' into itself
            %% instead copy only files ending in `.erl' and directories
            %% ending in `_SUITE_data' in the `_build/PROFILE/extras' dir
            ExtrasDir = filename:join([rebar_dir:base_dir(State), "extras"]),
            ok = copy_bare_suites(Dir, ExtrasDir),
            Opts = inject_test_dir(rebar_state:opts(State), ExtrasDir),
            {rebar_state:opts(State, Opts), AppAcc};
        {ok, Path} ->
            Opts = inject_test_dir(rebar_state:opts(State), Path),
            {rebar_state:opts(State, Opts), AppAcc};
        {error, badparent} ->
            {State, AppAcc}
    end.

copy_bare_suites(From, To) ->
    filelib:ensure_dir(filename:join([To, "dummy.txt"])),
    SrcFiles = rebar_utils:find_files(From, ".*\\.[e|h]rl\$", false),
    DataDirs = lists:filter(fun filelib:is_dir/1,
                            filelib:wildcard(filename:join([From, "*_SUITE_data"]))),
    ok = rebar_file_utils:cp_r(SrcFiles, To),
    rebar_file_utils:cp_r(DataDirs, To).

maybe_copy_spec(State, [App|Apps], Spec) ->
    case rebar_file_utils:path_from_ancestor(filename:dirname(Spec), rebar_app_info:dir(App)) of
        {ok, []}   ->
            ok = rebar_file_utils:cp_r([Spec],rebar_app_info:out_dir(App));
        {ok,_} ->
            ok;
        {error,badparent} ->
            maybe_copy_spec(State, Apps, Spec)
    end;
maybe_copy_spec(State, [], Spec) ->
    case rebar_file_utils:path_from_ancestor(filename:dirname(Spec), rebar_state:dir(State)) of
        {ok, []}   ->
            ExtrasDir = filename:join([rebar_dir:base_dir(State), "extras"]),
            ok = rebar_file_utils:cp_r([Spec],ExtrasDir);
        _R ->
            ok
    end.

inject_test_dir(Opts, Dir) ->
    %% append specified test targets to app defined `extra_src_dirs`
    ExtraSrcDirs = rebar_opts:get(Opts, extra_src_dirs, []),
    rebar_opts:set(Opts, extra_src_dirs, ExtraSrcDirs ++ [Dir]).

get_dirs_from_specs(Specs) ->
    case get_tests_from_specs(Specs) of
        {ok,Tests} ->
            {SpecLists,NodeRunSkipLists} = lists:unzip(Tests),
            SpecList = lists:append(SpecLists),
            NodeRunSkipList = lists:append(NodeRunSkipLists),
            RunList = lists:append([R || {_,R,_} <- NodeRunSkipList]),
            DirList = [element(1,R) || R <- RunList],
            {ok,{SpecList,DirList}};
        {error,Reason} ->
            {error,{?MODULE,{error_reading_testspec,Reason}}}
    end.

get_tests_from_specs(Specs) ->
    _ = ct_testspec:module_info(), % make sure ct_testspec is loaded
    case erlang:function_exported(ct_testspec,get_tests,1) of
        true ->
            ct_testspec:get_tests(Specs);
        false ->
            case ct_testspec:collect_tests_from_file(Specs,true) of
                Tests when is_list(Tests) ->
                    {ok,[{S,ct_testspec:prepare_tests(R)} || {S,R} <- Tests]};
                Error ->
                    Error
            end
    end.

translate_paths(State, Opts) ->
    case proplists:get_value(spec, Opts) of
        undefined ->
            case {proplists:get_value(suite, Opts), proplists:get_value(dir, Opts)} of
                {_Suites, undefined} -> translate_paths(State, suite, Opts, []);
                {undefined, _Dirs}   -> translate_paths(State, dir, Opts, []);
                %% both dirs and suites are defined, only translate dir paths
                _                    -> translate_paths(State, dir, Opts, [])
            end;
        _Specs ->
            translate_paths(State, spec, Opts, [])
    end.

translate_paths(_State, _Type, [], Acc) -> lists:reverse(Acc);
translate_paths(State, Type, [{Type, Val}|Rest], Acc) when is_integer(hd(Val)) ->
    %% single file or dir
    translate_paths(State, Type, [{Type, [Val]}|Rest], Acc);
translate_paths(State, Type, [{Type, Files}|Rest], Acc) ->
    Apps = rebar_state:project_apps(State),
    New = {Type, lists:map(fun(File) -> translate(State, Apps, File) end, Files)},
    translate_paths(State, Type, Rest, [New|Acc]);
translate_paths(State, Type, [Test|Rest], Acc) ->
    translate_paths(State, Type, Rest, [Test|Acc]).

translate(State, [App|Rest], Path) ->
    case rebar_file_utils:path_from_ancestor(Path, rebar_app_info:dir(App)) of
        {ok, P}            -> filename:join([rebar_app_info:out_dir(App), P]);
        {error, badparent} -> translate(State, Rest, Path)
    end;
translate(State, [], Path) ->
    case rebar_file_utils:path_from_ancestor(Path, rebar_state:dir(State)) of
        {ok, P}            -> filename:join([rebar_dir:base_dir(State), "extras", P]);
        %% not relative, leave as is
        {error, badparent} -> Path
    end.

-spec handle_keep_logs(file:filename(), pos_integer()) -> ok.
handle_keep_logs(LogDir, N) ->
    case file:list_dir(LogDir) of
        {ok, Filenames} ->
            Dirs = lists:filter(fun(File) ->
                        filelib:is_dir(filename:join([LogDir, File]))
                    end, Filenames) -- ["last"], %% we ignore the symlink as we later handle it
            case Dirs of
                %% first time running the tests, there are no logs to delete
                [] -> ok;
                %% during the next run we would crash because of keep_logs
                _ when length(Dirs) >= N ->
                    SortedDirs = lists:reverse(lists:sort(Dirs)),
                    %% sort the log dirs and keep the N - 1 newest
                    {_Keep, Discard} = lists:split(N - 1, SortedDirs),
                    ?DEBUG("Removing the following directories because keep_logs is in ct_opts: ~p", [Discard]),
                    [rebar_file_utils:rm_rf(filename:join([LogDir, Dir])) || Dir <- Discard],
                    ok;
                %% we still dont have enough log run directories as to crash
                _ -> ok
            end;
        _ -> ok
    end.

setup_logdir(State, Opts) ->
    Logdir = case proplists:get_value(logdir, Opts) of
        undefined -> filename:join([rebar_dir:base_dir(State), "logs"]);
        Dir       -> Dir
    end,
    filelib:ensure_dir(filename:join([Logdir, "dummy.beam"])),
    case proplists:get_value(keep_logs, Opts) of
        all -> ok;
        undefined -> ok;
        N -> handle_keep_logs(Logdir, N)
    end,
    [{logdir, Logdir}|lists:keydelete(logdir, 1, Opts)].

turn_off_auto_compile(Opts) ->
    [{auto_compile, false}|lists:keydelete(auto_compile, 1, Opts)].

run_test_verbose(Opts) -> handle_results(ct:run_test(Opts)).

run_test_quiet(Opts) ->
    Pid = self(),
    Ref = erlang:make_ref(),
    LogDir = proplists:get_value(logdir, Opts),
    {_, Monitor} = erlang:spawn_monitor(fun() ->
        {ok, F} = file:open(filename:join([LogDir, "ct.latest.log"]),
                            [write]),
        true = group_leader(F, self()),
        Pid ! {Ref, ct:run_test(Opts)}
    end),
    receive
        {Ref, Result} -> handle_quiet_results(Opts, Result);
        {'DOWN', Monitor, _, _, Reason} -> handle_results(?PRV_ERROR(Reason))
    end.

handle_results(Results) when is_list(Results) ->
    Result = lists:foldl(fun sum_results/2, {0, 0, {0,0}}, Results),
    handle_results(Result);
handle_results({_, Failed, {_, AutoSkipped}})
  when Failed > 0 orelse AutoSkipped > 0 ->
    ?PRV_ERROR({failures_running_tests, {Failed, AutoSkipped}});
handle_results({error, Reason}) ->
    ?PRV_ERROR({error_running_tests, Reason});
handle_results(_) ->
    ok.

sum_results({Passed, Failed, {UserSkipped, AutoSkipped}},
            {Passed2, Failed2, {UserSkipped2, AutoSkipped2}}) ->
    {Passed+Passed2, Failed+Failed2,
     {UserSkipped+UserSkipped2, AutoSkipped+AutoSkipped2}};
sum_results(_, {error, Reason}) ->
    {error, Reason};
sum_results(Unknown, _) ->
    {error, Unknown}.

handle_quiet_results(_, {error, _} = Result) ->
    handle_results(Result);
handle_quiet_results(CTOpts, Results) when is_list(Results) ->
    _ = [format_result(Result) || Result <- Results],
    case handle_results(Results) of
        ?PRV_ERROR({failures_running_tests, _}) = Error ->
            LogDir = proplists:get_value(logdir, CTOpts),
            Index = filename:join([LogDir, "index.html"]),
            ?CONSOLE("Results written to ~p.", [Index]),
            Error;
        Other ->
            Other
    end;
handle_quiet_results(CTOpts, Result) ->
    handle_quiet_results(CTOpts, [Result]).

format_result({Passed, 0, {0, 0}}) ->
    ?CONSOLE("All ~p tests passed.", [Passed]);
format_result({Passed, Failed, Skipped}) ->
    Format = [format_failed(Failed), format_skipped(Skipped),
              format_passed(Passed)],
    ?CONSOLE("~ts", [Format]);
format_result(_Unknown) ->
    %% Happens when CT itself encounters a bug
    ok.

format_failed(0) ->
    [];
format_failed(Failed) ->
    io_lib:format("Failed ~p tests. ", [Failed]).

format_passed(Passed) ->
    io_lib:format("Passed ~p tests. ", [Passed]).

format_skipped({0, 0}) ->
    [];
format_skipped({User, Auto}) ->
    io_lib:format("Skipped ~p (~p, ~p) tests. ", [User+Auto, User, Auto]).

maybe_cover_compile(State) ->
    {RawOpts, _} = rebar_state:command_parsed_args(State),
    State1 = case proplists:get_value(cover, RawOpts, false) of
        true  -> rebar_state:set(State, cover_enabled, true);
        false -> State
    end,
    rebar_prv_cover:maybe_cover_compile(State1).

maybe_write_coverdata(State) ->
    {RawOpts, _} = rebar_state:command_parsed_args(State),
    State1 = case proplists:get_value(cover, RawOpts, false) of
        true  -> rebar_state:set(State, cover_enabled, true);
        false -> State
    end,
    Name = proplists:get_value(cover_export_name, RawOpts, ?PROVIDER),
    rebar_prv_cover:maybe_write_coverdata(State1, Name).

ct_opts(_State) ->
    [{dir, undefined, "dir", string, help(dir)}, %% comma-separated list
     {suite, undefined, "suite", string, help(suite)}, %% comma-separated list
     {group, undefined, "group", string, help(group)}, %% comma-separated list
     {testcase, undefined, "case", string, help(testcase)}, %% comma-separated list
     {label, undefined, "label", string, help(label)}, %% String
     {config, undefined, "config", string, help(config)}, %% comma-separated list
     {spec, undefined, "spec", string, help(spec)}, %% comma-separated list
     {join_specs, undefined, "join_specs", boolean, help(join_specs)},
     {allow_user_terms, undefined, "allow_user_terms", boolean, help(allow_user_terms)}, %% Bool
     {logdir, undefined, "logdir", string, help(logdir)}, %% dir
     {logopts, undefined, "logopts", string, help(logopts)}, %% comma-separated list
     {verbosity, undefined, "verbosity", integer, help(verbosity)}, %% Integer
     {cover, $c, "cover", {boolean, false}, help(cover)},
     {cover_export_name, undefined, "cover_export_name", string, help(cover_export_name)},
     {repeat, undefined, "repeat", integer, help(repeat)}, %% integer
     {duration, undefined, "duration", string, help(duration)}, % format: HHMMSS
     {until, undefined, "until", string, help(until)}, %% format: YYMoMoDD[HHMMSS]
     {force_stop, undefined, "force_stop", string, help(force_stop)}, %% String
     {basic_html, undefined, "basic_html", boolean, help(basic_html)}, %% Boolean
     {stylesheet, undefined, "stylesheet", string, help(stylesheet)}, %% String
     {decrypt_key, undefined, "decrypt_key", string, help(decrypt_key)}, %% String
     {decrypt_file, undefined, "decrypt_file", string, help(decrypt_file)}, %% String
     {abort_if_missing_suites, undefined, "abort_if_missing_suites", {boolean, true}, help(abort_if_missing_suites)}, %% Boolean
     {multiply_timetraps, undefined, "multiply_timetraps", integer, help(multiple_timetraps)}, %% Integer
     {scale_timetraps, undefined, "scale_timetraps", boolean, help(scale_timetraps)},
     {create_priv_dir, undefined, "create_priv_dir", string, help(create_priv_dir)},
     {include, undefined, "include", string, help(include)},
     {readable, undefined, "readable", string, help(readable)},
     {verbose, $v, "verbose", boolean, help(verbose)},
     {name, undefined, "name", atom, help(name)},
     {sname, undefined, "sname", atom, help(sname)},
     {setcookie, undefined, "setcookie", atom, help(setcookie)},
     {sys_config, undefined, "sys_config", string, help(sys_config)}, %% comma-separated list
     {compile_only, undefined, "compile_only", boolean, help(compile_only)},
     {retry, undefined, "retry", boolean, help(retry)},
     {fail_fast, undefined, "fail_fast", {boolean, false}, help(fail_fast)}
    ].

help(compile_only) ->
    "Compile modules in the project with the test configuration but do not run the tests";
help(dir) ->
    "List of additional directories containing test suites";
help(suite) ->
    "List of test suites to run";
help(group) ->
    "List of test groups to run";
help(testcase) ->
    "List of test cases to run";
help(label) ->
    "Test label";
help(config) ->
    "List of config files";
help(spec) ->
    "List of test specifications";
help(join_specs) ->
    "Merge all test specifications and perform a single test run";
help(sys_config) ->
    "List of application config files";
help(allow_user_terms) ->
    "Allow user defined config values in config files";
help(logdir) ->
    "Log folder";
help(logopts) ->
    "Options for common test logging";
help(verbosity) ->
    "Verbosity";
help(cover) ->
    "Generate cover data";
help(cover_export_name) ->
    "Base name of the coverdata file to write";
help(repeat) ->
    "How often to repeat tests";
help(duration) ->
    "Max runtime (format: HHMMSS)";
help(until) ->
    "Run until (format: HHMMSS)";
help(force_stop) ->
    "Force stop on test timeout (true | false | skip_rest)";
help(basic_html) ->
    "Show basic HTML";
help(stylesheet) ->
    "CSS stylesheet to apply to html output";
help(decrypt_key) ->
    "Path to key for decrypting config";
help(decrypt_file) ->
    "Path to file containing key for decrypting config";
help(abort_if_missing_suites) ->
    "Abort if suites are missing";
help(multiply_timetraps) ->
    "Multiply timetraps";
help(scale_timetraps) ->
    "Scale timetraps";
help(create_priv_dir) ->
    "Create priv dir (auto_per_run | auto_per_tc | manual_per_tc)";
help(include) ->
    "Directories containing additional include files";
help(readable) ->
    "Shows test case names and only displays logs to shell on failures (true | compact | false)";
help(verbose) ->
    "Verbose output";
help(name) ->
    "Gives a long name to the node";
help(sname) ->
    "Gives a short name to the node";
help(setcookie) ->
    "Sets the cookie if the node is distributed";
help(retry) ->
    "Experimental feature. If any specification for previously failing test is found, runs them.";
help(fail_fast) ->
    "Experimental feature. If any test fails, the run is aborted. Since common test does not "
    "support this natively, we abort the rebar3 run on a failure. This May break CT's disk logging and "
    "other rebar3 features.";
help(_) ->
    "".
