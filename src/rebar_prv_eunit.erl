%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et

-module(rebar_prv_eunit).

-behaviour(provider).

-export([init/1,
         do/1,
         format_error/1]).
%% exported solely for tests
-export([prepare_tests/1, eunit_opts/1, validate_tests/2]).

-include("rebar.hrl").
-include_lib("providers/include/providers.hrl").

-define(PROVIDER, eunit).
%% we need to modify app_info state before compile
-define(DEPS, [lock]).

-define(DEFAULT_TEST_REGEX, "^(?!\\._).*\\.erl\$").

%% ===================================================================
%% Public API
%% ===================================================================

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([{name, ?PROVIDER},
                                 {module, ?MODULE},
                                 {deps, ?DEPS},
                                 {bare, true},
                                 {example, "rebar3 eunit"},
                                 {short_desc, "Run EUnit Tests."},
                                 {desc, "Run EUnit Tests."},
                                 {opts, eunit_opts(State)},
                                 {profiles, [test]}]),
    State1 = rebar_state:add_provider(State, Provider),
    {ok, State1}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    Tests = prepare_tests(State),
    %% inject `eunit_first_files`, `eunit_compile_opts` and any
    %% directories required by tests into the applications
    NewState = inject_eunit_state(State, Tests),
    case compile(NewState) of
        %% successfully compiled apps
        {ok, S} -> do(S, Tests);
        Error   -> Error
    end.

do(State, Tests) ->
    ?INFO("Performing EUnit tests...", []),

    setup_name(State),
    rebar_paths:set_paths([deps, plugins], State),

    %% Run eunit provider prehooks
    Providers = rebar_state:providers(State),
    Cwd = rebar_dir:get_cwd(),
    rebar_hooks:run_project_and_app_hooks(Cwd, pre, ?PROVIDER, Providers, State),

    case validate_tests(State, Tests) of
        {ok, T} ->
            case run_tests(State, T) of
                {ok, State1} ->
                    %% Run eunit provider posthooks
                    rebar_hooks:run_project_and_app_hooks(Cwd, post, ?PROVIDER, Providers, State1),
                    rebar_paths:set_paths([plugins, deps], State),
                    {ok, State1};
                Error ->
                    rebar_paths:set_paths([plugins, deps], State),
                    Error
            end;
        Error ->
            rebar_paths:set_paths([plugins, deps], State),
            Error
    end.

run_tests(State, Tests) ->
    T = translate_paths(State, Tests),
    EUnitOpts = resolve_eunit_opts(State),
    ?DEBUG("finding tests in:~n\t{eunit_tests, ~p}.", [T]),
    ?DEBUG("with options:~n\t{eunit_opts, ~p}.", [EUnitOpts]),
    apply_sys_config(State),
    try eunit:test(T, EUnitOpts) of
      Result ->
        ok = maybe_write_coverdata(State),
        case handle_results(Result) of
            {error, Reason} ->
                ?PRV_ERROR(Reason);
            ok ->
                {ok, State}
        end
    catch error:badarg -> ?PRV_ERROR({error, badarg})
    end.

-spec format_error(any()) -> iolist().
format_error(unknown_error) ->
    io_lib:format("Error running tests", []);
format_error({error_running_tests, Reason}) ->
    io_lib:format("Error running tests: ~p", [Reason]);
format_error({eunit_test_errors, Errors}) ->
    io_lib:format(lists:concat(["Error Running EUnit Tests:"] ++
                               lists:map(fun(Error) -> "~n  " ++ Error end, Errors)), []);
format_error({badconfig, {Msg, {Value, Key}}}) ->
    io_lib:format(Msg, [Value, Key]);
format_error({generator, Value}) ->
    io_lib:format("Generator ~p has an invalid format", [Value]);
format_error({error, Error}) ->
    format_error({error_running_tests, Error}).

%% ===================================================================
%% Internal functions
%% ===================================================================

setup_name(State) ->
    {Long, Short, Opts} = rebar_dist_utils:find_options(State),
    rebar_dist_utils:either(Long, Short, Opts).

prepare_tests(State) ->
    %% parse and translate command line tests
    CmdTests = resolve_tests(State),
    CfgTests = cfg_tests(State),
    ProjectApps = rebar_state:project_apps(State),
    %% prioritize tests to run first trying any command line specified
    %% tests falling back to tests specified in the config file finally
    %% running a default set if no other tests are present
    select_tests(State, ProjectApps, CmdTests, CfgTests).

resolve_tests(State) ->
    {RawOpts, _} = rebar_state:command_parsed_args(State),
    Apps         = resolve(app, application, RawOpts),
    Applications = resolve(application, RawOpts),
    Dirs         = resolve(dir, RawOpts),
    Files        = resolve(file, RawOpts),
    Modules      = resolve(module, RawOpts),
    Suites       = resolve(suite, module, RawOpts),
    Generator    = resolve(generator, RawOpts),
    Apps ++ Applications ++ Dirs ++ Files ++ Modules ++ Suites ++ Generator.

resolve(Flag, RawOpts) -> resolve(Flag, Flag, RawOpts).

resolve(Flag, EUnitKey, RawOpts) ->
    case proplists:get_value(Flag, RawOpts) of
        undefined -> [];
        Args      -> normalize(EUnitKey,
                               rebar_string:lexemes(Args, [$,]))
    end.

normalize(generator, Args) ->
    lists:flatmap(fun(Value) -> normalize_(generator, Value) end, Args);
normalize(EUnitKey, Args) ->
    lists:map(fun(Arg) -> normalize_(EUnitKey, Arg) end, Args).

normalize_(generator, Value) ->
    case string:tokens(Value, [$:]) of
        [Module0, Functions] ->
            Module = list_to_atom(Module0),
            lists:map(fun(F) -> {generator, Module, list_to_atom(F)} end,
                      string:tokens(Functions, [$;]));
        _ ->
            ?PRV_ERROR({generator, Value})
    end;
normalize_(Key, Value) when Key == dir; Key == file -> {Key, Value};
normalize_(Key, Value) -> {Key, list_to_atom(Value)}.

cfg_tests(State) ->
    case rebar_state:get(State, eunit_tests, []) of
        Tests when is_list(Tests) ->
            lists:map(fun({app, App}) -> {application, App}; (T) -> T end, Tests);
        Wrong ->
            %% probably a single non list term
            ?PRV_ERROR({badconfig, {"Value `~p' of option `~p' must be a list", {Wrong, eunit_tests}}})
    end.

select_tests(_State, _ProjectApps, _, {error, _} = Error) -> Error;
select_tests(State, ProjectApps, [], []) -> {ok, default_tests(State, ProjectApps)};
select_tests(_State, _ProjectApps, [], Tests)  -> {ok, Tests};
select_tests(_State, _ProjectApps, Tests, _) -> {ok, Tests}.

default_tests(State, Apps) ->
    %% use `{application, App}` for each app in project
    AppTests = set_apps(Apps),
    %% additional test modules in `test` dir of each app
    ModTests = set_modules(Apps, State),
    AppTests ++ ModTests.

set_apps(Apps) -> set_apps(Apps, []).

set_apps([], Acc) -> Acc;
set_apps([App|Rest], Acc) ->
    AppName = list_to_atom(binary_to_list(rebar_app_info:name(App))),
    set_apps(Rest, [{application, AppName}|Acc]).

set_modules(Apps, State) -> set_modules(Apps, State, {[], []}).

set_modules([], State, {AppAcc, TestAcc}) ->
    Regex = rebar_state:get(State, eunit_test_regex, ?DEFAULT_TEST_REGEX),
    BareTestDir = [filename:join([rebar_state:dir(State), "test"])],
    TestSrc = gather_src(BareTestDir, Regex),
    dedupe_tests({AppAcc, TestAcc ++ TestSrc});
set_modules([App|Rest], State, {AppAcc, TestAcc}) ->
    F = fun(Dir) -> filename:join([rebar_app_info:dir(App), Dir]) end,
    AppDirs = lists:map(F, rebar_dir:src_dirs(rebar_app_info:opts(App), ["src"])),
    Regex = rebar_state:get(State, eunit_test_regex, ?DEFAULT_TEST_REGEX),
    AppSrc = gather_src(AppDirs, Regex),
    TestDirs = [filename:join([rebar_app_info:dir(App), "test"])],
    TestSrc = gather_src(TestDirs, Regex),
    set_modules(Rest, State, {AppSrc ++ AppAcc, TestSrc ++ TestAcc}).

gather_src(Dirs, Regex) -> gather_src(Dirs, Regex, []).

gather_src([], _Regex, Srcs) -> Srcs;
gather_src([Dir|Rest], Regex, Srcs) ->
    gather_src(Rest, Regex, Srcs ++ rebar_utils:find_files(Dir, Regex, true)).

dedupe_tests({AppMods, TestMods}) ->
    UniqueTestMods = lists:usort(TestMods) -- AppMods,
    %% for each modules in TestMods create a test if there is not a module
    %% in AppMods that will trigger it
    F = fun(TestMod) ->
        M = filename:rootname(filename:basename(TestMod)),
        MatchesTest = fun(AppMod) -> filename:rootname(filename:basename(AppMod)) ++ "_tests" == M end,
        case lists:any(MatchesTest, AppMods) of
            false -> {true, {module, list_to_atom(M)}};
            true  -> false
        end
    end,
    rebar_utils:filtermap(F, UniqueTestMods).

inject_eunit_state(State, {ok, Tests}) ->
    Apps = rebar_state:project_apps(State),
    case inject_eunit_state(State, Apps, []) of
        {ok, {NewState, ModdedApps}} ->
            test_dirs(NewState, ModdedApps, Tests);
        {error, _} = Error           -> Error
    end;
inject_eunit_state(_State, Error) -> Error.

inject_eunit_state(State, [App|Rest], Acc) ->
    case inject(rebar_app_info:opts(App)) of
        {error, _} = Error -> Error;
        NewOpts            ->
            NewApp = rebar_app_info:opts(App, NewOpts),
            inject_eunit_state(State, Rest, [NewApp|Acc])
    end;
inject_eunit_state(State, [], Acc) ->
    case inject(rebar_state:opts(State)) of
        {error, _} = Error -> Error;
        NewOpts            -> {ok, {rebar_state:opts(State, NewOpts), lists:reverse(Acc)}}
    end.

opts(Opts, Key, Default) ->
    case rebar_opts:get(Opts, Key, Default) of
        Vs when is_list(Vs) -> Vs;
        Wrong ->
            ?PRV_ERROR({badconfig, {"Value `~p' of option `~p' must be a list", {Wrong, Key}}})
    end.

inject(Opts) -> erl_opts(Opts).

erl_opts(Opts) ->
    %% append `eunit_compile_opts` to app defined `erl_opts`
    ErlOpts = opts(Opts, erl_opts, []),
    EUnitOpts = opts(Opts, eunit_compile_opts, []),
    case append(EUnitOpts, ErlOpts) of
        {error, _} = Error -> Error;
        NewErlOpts         -> first_files(rebar_opts:set(Opts, erl_opts, NewErlOpts))
    end.

first_files(Opts) ->
    %% append `eunit_first_files` to app defined `erl_first_files`
    FirstFiles = opts(Opts, erl_first_files, []),
    EUnitFirstFiles = opts(Opts, eunit_first_files, []),
    case append(EUnitFirstFiles, FirstFiles) of
        {error, _} = Error -> Error;
        NewFirstFiles  -> eunit_macro(rebar_opts:set(Opts, erl_first_files, NewFirstFiles))
    end.

eunit_macro(Opts) ->
    ErlOpts = opts(Opts, erl_opts, []),
    NewOpts = safe_define_eunit_macro(ErlOpts),
    rebar_opts:set(Opts, erl_opts, NewOpts).

safe_define_eunit_macro(Opts) ->
    %% defining a compile macro twice results in an exception so
    %% make sure 'EUNIT' is only defined once
    case test_defined(Opts) of
       true  -> Opts;
       false -> [{d, 'EUNIT'}|Opts]
    end.

test_defined([{d, 'EUNIT'}|_]) -> true;
test_defined([{d, 'EUNIT', true}|_]) -> true;
test_defined([_|Rest]) -> test_defined(Rest);
test_defined([]) -> false.

append({error, _} = Error, _) -> Error;
append(_, {error, _} = Error) -> Error;
append(A, B) -> A ++ B.

test_dirs(State, Apps, []) -> rebar_state:project_apps(State, Apps);
test_dirs(State, Apps, [{dir, Dir}|Rest]) ->
    %% insert `Dir` into an app if relative, or the base state if not
    %% app relative but relative to the root or not at all if outside
    %% project scope
    {NewState, NewApps} = maybe_inject_test_dir(State, [], Apps, Dir),
    test_dirs(NewState, NewApps, Rest);
test_dirs(State, Apps, [{file, File}|Rest]) ->
    Dir = filename:dirname(File),
    {NewState, NewApps} = maybe_inject_test_dir(State, [], Apps, Dir),
    test_dirs(NewState, NewApps, Rest);
test_dirs(State, Apps, [_|Rest]) -> test_dirs(State, Apps, Rest).

maybe_inject_test_dir(State, AppAcc, [App|Rest], Dir) ->
    case rebar_file_utils:path_from_ancestor(Dir, rebar_app_info:dir(App)) of
        {ok, Path} ->
            Opts = inject_test_dir(rebar_app_info:opts(App), Path),
            {State, AppAcc ++ [rebar_app_info:opts(App, Opts)] ++ Rest};
        {error, badparent} ->
            maybe_inject_test_dir(State, AppAcc ++ [App], Rest, Dir)
    end;
maybe_inject_test_dir(State, AppAcc, [], Dir) ->
    case rebar_file_utils:path_from_ancestor(Dir, rebar_state:dir(State)) of
        {ok, Path} ->
            Opts = inject_test_dir(rebar_state:opts(State), Path),
            {rebar_state:opts(State, Opts), AppAcc};
        {error, badparent} ->
            {State, AppAcc}
    end.

inject_test_dir(Opts, Dir) ->
    %% append specified test targets to app defined `extra_src_dirs`
    ExtraSrcDirs = rebar_opts:get(Opts, extra_src_dirs, []),
    rebar_opts:set(Opts, extra_src_dirs, ExtraSrcDirs ++ [Dir]).

compile({error, _} = Error) -> Error;
compile(State) ->
    {ok, S} = rebar_prv_compile:do(State),
    ok = maybe_cover_compile(S),
    {ok, S}.

validate_tests(State, {ok, Tests}) ->
    gather_tests(fun(Elem) -> validate(State, Elem) end, Tests, []);
validate_tests(_State, Error) -> Error.

gather_tests(_F, [], Acc) -> {ok, lists:reverse(Acc)};
gather_tests(F, [Test|Rest], Acc) ->
    case F(Test) of
        ok             -> gather_tests(F, Rest, [Test|Acc]);
        %% failure mode, switch to gathering errors
        {error, Error} -> gather_errors(F, Rest, [Error])
    end.

gather_errors(_F, [], Acc) -> ?PRV_ERROR({eunit_test_errors, lists:reverse(Acc)});
gather_errors(F, [Test|Rest], Acc) ->
    case F(Test) of
        ok             -> gather_errors(F, Rest, Acc);
        {error, Error} -> gather_errors(F, Rest, [Error|Acc])
    end.

validate(State, {application, App}) ->
    validate_app(State, App);
validate(State, {dir, Dir}) ->
    validate_dir(State, Dir);
validate(State, {file, File}) ->
    validate_file(State, File);
validate(State, {module, Module}) ->
    validate_module(State, Module);
validate(State, {suite, Module}) ->
    validate_module(State, Module);
validate(State, {generator, Module, Function}) ->
    validate_generator(State, Module, Function);
validate(State, Module) when is_atom(Module) ->
    validate_module(State, Module);
validate(State, Path) when is_list(Path) ->
    case ec_file:is_dir(Path) of
        true  -> validate(State, {dir, Path});
        false -> validate(State, {file, Path})
    end;
%% unrecognized tests should be included. if they're invalid eunit will error
%% and rebar.config may contain arbitrarily complex tests that are effectively
%% unvalidatable
validate(_State, _Test) -> ok.

validate_app(State, AppName) ->
    ProjectApps = rebar_state:project_apps(State),
    validate_app(State, ProjectApps, AppName).

validate_app(_State, [], AppName) ->
    {error, lists:concat(["Application `", AppName, "' not found in project."])};
validate_app(State, [App|Rest], AppName) ->
    case AppName == binary_to_atom(rebar_app_info:name(App), unicode) of
        true  -> ok;
        false -> validate_app(State, Rest, AppName)
    end.

validate_dir(State, Dir) ->
    case ec_file:is_dir(filename:join([rebar_state:dir(State), Dir])) of
        true  -> ok;
        false -> {error, lists:concat(["Directory `", Dir, "' not found."])}
    end.

validate_file(State, File) ->
    case ec_file:exists(filename:join([rebar_state:dir(State), File])) of
        true  -> ok;
        false -> {error, lists:concat(["File `", File, "' not found."])}
    end.

validate_module(_State, Module) ->
    case code:which(Module) of
        non_existing -> {error, lists:concat(["Module `", Module, "' not found in project."])};
        _            -> ok
    end.

validate_generator(State, Module, _Function) ->
    validate_module(State, Module).

resolve_eunit_opts(State) ->
    {Opts, _} = rebar_state:command_parsed_args(State),
    EUnitOpts = rebar_state:get(State, eunit_opts, []),
    EUnitOpts1 = case proplists:get_value(verbose, Opts, false) of
                    true  -> set_verbose(EUnitOpts);
                    false -> EUnitOpts
                 end,
    EUnitOpts2 = case proplists:get_value(profile, Opts, false) of
                    true  -> set_profile(EUnitOpts1);
                    false -> EUnitOpts1
                 end,
    IsVerbose = lists:member(verbose, EUnitOpts2),
    case proplists:get_value(eunit_formatters, Opts, not IsVerbose) of
        true  -> custom_eunit_formatters(EUnitOpts2);
        false -> EUnitOpts2
    end.

custom_eunit_formatters(Opts) ->
    ReportOpts = custom_eunit_report_options(Opts),
    %% If `report` is already set then treat that like `eunit_formatters` is false
    case lists:keymember(report, 1, Opts) of
        true -> Opts;
        false -> [no_tty, {report, {eunit_progress, ReportOpts}} | Opts]
    end.

custom_eunit_report_options(Opts) ->
    case lists:member(profile, Opts) of
        true -> [colored, profile];
        false -> [colored]
    end.

set_profile(Opts) ->
    %% if `profile` is already set don't set it again
    case lists:member(profile, Opts) of
        true  -> Opts;
        false -> [profile] ++ Opts
    end.

set_verbose(Opts) ->
    %% if `verbose` is already set don't set it again
    case lists:member(verbose, Opts) of
        true  -> Opts;
        false -> [verbose] ++ Opts
    end.

translate_paths(State, Tests) -> translate_paths(State, Tests, []).

translate_paths(_State, [], Acc) -> lists:reverse(Acc);
translate_paths(State, [{K, _} = Path|Rest], Acc) when K == file; K == dir ->
    Apps = rebar_state:project_apps(State),
    translate_paths(State, Rest, [translate(State, Apps, Path)|Acc]);
translate_paths(State, [Test|Rest], Acc) ->
    translate_paths(State, Rest, [Test|Acc]).

translate(State, [App|Rest], {dir, Dir}) ->
    case rebar_file_utils:path_from_ancestor(Dir, rebar_app_info:dir(App)) of
        {ok, Path}         -> {dir, filename:join([rebar_app_info:out_dir(App), Path])};
        {error, badparent} -> translate(State, Rest, {dir, Dir})
    end;
translate(State, [App|Rest], {file, FilePath}) ->
    Dir = filename:dirname(FilePath),
    File = filename:basename(FilePath),
    case rebar_file_utils:path_from_ancestor(Dir, rebar_app_info:dir(App)) of
        {ok, Path}         -> {file, filename:join([rebar_app_info:out_dir(App), Path, File])};
        {error, badparent} -> translate(State, Rest, {file, FilePath})
    end;
translate(State, [], {dir, Dir}) ->
    case rebar_file_utils:path_from_ancestor(Dir, rebar_state:dir(State)) of
        {ok, Path}         -> {dir, filename:join([rebar_dir:base_dir(State), "extras", Path])};
        %% not relative, leave as is
        {error, badparent} -> {dir, Dir}
    end;
translate(State, [], {file, FilePath}) ->
    Dir = filename:dirname(FilePath),
    File = filename:basename(FilePath),
    case rebar_file_utils:path_from_ancestor(Dir, rebar_state:dir(State)) of
        {ok, Path}         -> {file, filename:join([rebar_dir:base_dir(State), "extras", Path, File])};
        %% not relative, leave as is
        {error, badparent} -> {file, FilePath}
    end.

apply_sys_config(State) ->
    CfgSysCfg = case rebar_state:get(State, eunit_opts, []) of
        Opts when is_list(Opts) ->
            case proplists:get_value(sys_config, Opts, []) of
                [] -> [];
                L when is_list(hd(L)) -> L;
                S when is_list(S) -> [S]
            end;
        _ ->
            []
    end,
    {RawOpts, _} = rebar_state:command_parsed_args(State),
    SysCfgs = rebar_string:lexemes(
        proplists:get_value(sys_config, RawOpts, ""),
        [$,]
    ) ++ CfgSysCfg,
    RootDir = rebar_dir:root_dir(State),
    Configs = lists:flatmap(
        fun(Filename) -> rebar_file_utils:consult_config(RootDir, Filename) end,
        SysCfgs
    ),
    %% NB: load the applications (from user directories too) to support OTP < 17
    %% to our best ability.
    rebar_paths:set_paths([deps, plugins], State),
    [application:load(Application) || Config <- Configs, {Application, _} <- Config],
    rebar_utils:reread_config(Configs, [update_logger]),
    ok.

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

handle_results(ok) -> ok;
handle_results(error) ->
    {error, unknown_error};
handle_results({error, Reason}) ->
    {error, {error_running_tests, Reason}}.

eunit_opts(_State) ->
    [{app, undefined, "app", string, help(app)},
     {application, undefined, "application", string, help(app)},
     {cover, $c, "cover", boolean, help(cover)},
     {cover_export_name, undefined, "cover_export_name", string, help(cover_export_name)},
     {profile, $p, "profile", boolean, help(profile)},
     {dir, $d, "dir", string, help(dir)},
     {file, $f, "file", string, help(file)},
     {module, $m, "module", string, help(module)},
     {suite, $s, "suite", string, help(module)},
     {generator, $g, "generator", string, help(generator)},
     {verbose, $v, "verbose", boolean, help(verbose)},
     {name, undefined, "name", atom, help(name)},
     {sname, undefined, "sname", atom, help(sname)},
     {sys_config, undefined, "sys_config", string, help(sys_config)}, %% comma-separated list
     {setcookie, undefined, "setcookie", atom, help(setcookie)}].

help(app)       -> "Comma separated list of application test suites to run. Equivalent to `[{application, App}]`.";
help(cover)     -> "Generate cover data. Defaults to false.";
help(cover_export_name) -> "Base name of the coverdata file to write";
help(profile)   -> "Show the slowest tests. Defaults to false.";
help(dir)       -> "Comma separated list of dirs to load tests from. Equivalent to `[{dir, Dir}]`.";
help(file)      -> "Comma separated list of files to load tests from. Equivalent to `[{file, File}]`.";
help(module)    -> "Comma separated list of modules to load tests from. Equivalent to `[{module, Module}]`.";
help(generator) -> "Comma separated list of generators (the format is `module:function`) to load tests from. Equivalent to `[{generator, Module, Function}]`.";
help(verbose)   -> "Verbose output. Defaults to false.";
help(name)      -> "Gives a long name to the node";
help(sname)     -> "Gives a short name to the node";
help(setcookie) -> "Sets the cookie if the node is distributed";
help(sys_config) -> "List of application config files".
