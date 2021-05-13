-module(rebar_compile_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/file.hrl").

suite() ->
    [].

all() ->
    [{group, basic_app}, {group, release_apps},
     {group, checkout_apps}, {group, checkout_deps},
     {group, basic_srcdirs}, {group, release_srcdirs}, {group, unbalanced_srcdirs},
     {group, basic_extras}, {group, release_extras}, {group, unbalanced_extras},
     {group, root_extras},
     recompile_when_hrl_changes, recompile_when_included_hrl_changes,
     recompile_when_recursive_hrl_changes,
     recompile_extra_when_hrl_in_src_changes,
     recompile_when_opts_included_hrl_changes,
     recompile_when_foreign_included_hrl_changes,
     recompile_when_foreign_behaviour_changes,
     recompile_when_recursive_behaviour_changes,
     recompile_when_parent_behaviour_changes,
     recompile_when_opts_change, recompile_when_dag_opts_change,
     dont_recompile_when_opts_dont_change, dont_recompile_yrl_or_xrl,
     delete_beam_if_source_deleted,
     deps_in_path, checkout_priority, highest_version_of_pkg_dep,
     parse_transform_test, erl_first_files_test, mib_test,
     umbrella_mib_first_test, deps_mib_test,
     only_default_transitive_deps, clean_all,
     clean_specific, profile_deps, deps_build_in_prod, only_deps,
     override_deps, git_subdir_deps, override_add_deps, override_del_deps,
     override_del_pkg_deps, override_opts, override_add_opts, override_del_opts,
     apply_overrides_exactly_once, override_only_deps,
     profile_override_deps, profile_override_add_deps, profile_override_del_deps,
     profile_override_opts, profile_override_add_opts, profile_override_del_opts,
     include_file_relative_to_working_directory, include_file_in_src,
     include_file_relative_to_working_directory_test, include_file_in_src_test,
     include_file_in_src_test_multiapp,
     recompile_when_parse_transform_as_opt_changes,
     recompile_when_parse_transform_inline_changes,
     regex_filter_skip, regex_filter_regression,
     recursive, no_recursive, extra_recursion,
     always_recompile_when_erl_compiler_options_set,
     dont_recompile_when_erl_compiler_options_env_does_not_change,
     recompile_when_erl_compiler_options_env_changes,
     rebar_config_os_var, split_project_apps_hooks,
     app_file_linting].

groups() ->
    [{basic_app, [], [build_basic_app, paths_basic_app, clean_basic_app]},
     {release_apps, [], [build_release_apps, paths_release_apps, clean_release_apps]},
     {checkout_apps, [], [paths_checkout_apps]},
     {checkout_deps, [], [build_checkout_deps, paths_checkout_deps]},
     {basic_srcdirs, [], [build_basic_srcdirs, paths_basic_srcdirs]},
     {release_srcdirs, [], [build_release_srcdirs,
                            paths_release_srcdirs]},
     {unbalanced_srcdirs, [], [build_unbalanced_srcdirs,
                               paths_unbalanced_srcdirs]},
     {basic_extras, [], [build_basic_extra_dirs,
                         paths_basic_extra_dirs,
                         clean_basic_extra_dirs]},
     {release_extras, [], [build_release_extra_dirs,
                           paths_release_extra_dirs,
                           clean_release_extra_dirs]},
     {unbalanced_extras, [], [build_unbalanced_extra_dirs,
                              paths_unbalanced_extra_dirs]},
     {root_extras, [], [build_extra_dirs_in_project_root,
                        paths_extra_dirs_in_project_root,
                        clean_extra_dirs_in_project_root]}].

init_per_group(basic_app, Config) ->
    NewConfig = rebar_test_utils:init_rebar_state(Config, "basic_app_"),
    AppDir = ?config(apps, NewConfig),

    Name = rebar_test_utils:create_random_name("app1"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    [{app_names, [Name]}, {vsns, [Vsn]}|NewConfig];

init_per_group(release_apps, Config) ->
    NewConfig = rebar_test_utils:init_rebar_state(Config, "release_apps_"),
    AppDir = ?config(apps, NewConfig),

    Name1 = rebar_test_utils:create_random_name("relapp1_"),
    Vsn1 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([AppDir,"apps",Name1]), Name1, Vsn1, [kernel, stdlib]),

    Name2 = rebar_test_utils:create_random_name("relapp2_"),
    Vsn2 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([AppDir,"apps",Name2]), Name2, Vsn2, [kernel, stdlib]),

    [{app_names, [Name1, Name2]}, {vsns, [Vsn1, Vsn2]}|NewConfig];

init_per_group(checkout_apps, Config) ->
    NewConfig = rebar_test_utils:init_rebar_state(Config, "checkout_apps_"),
    AppDir = ?config(apps, NewConfig),
    CheckoutsDir = ?config(checkouts, NewConfig),

    Name1 = rebar_test_utils:create_random_name("checkapp1_"),
    Vsn1 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name1, Vsn1, [kernel, stdlib]),

    Name2 = rebar_test_utils:create_random_name("checkapp2_"),
    Vsn2 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([CheckoutsDir,Name2]), Name2, Vsn2, [kernel, stdlib]),

    [{app_names, [Name1, Name2]}, {vsns, [Vsn1, Vsn2]}|NewConfig];

init_per_group(checkout_deps, Config) ->
    NewConfig = rebar_test_utils:init_rebar_state(Config, "checkout_deps_"),
    AppDir = ?config(apps, NewConfig),
    CheckoutsDir = ?config(checkouts, NewConfig),
    DepsDir = filename:join([AppDir, "_build", "default", "lib"]),

    Name1 = rebar_test_utils:create_random_name("checkapp1_"),
    Vsn1 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name1, Vsn1, [kernel, stdlib]),

    Name2 = rebar_test_utils:create_random_name("checkapp2_"),
    Vsn2 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([CheckoutsDir,Name2]), Name2, Vsn2, [kernel, stdlib]),

    rebar_test_utils:create_app(filename:join([DepsDir,Name2]), Name2, Vsn1, [kernel, stdlib]),

    [{app_names, [Name1, Name2]}, {vsns, [Vsn1, Vsn2]}|NewConfig];

init_per_group(Group, Config) when Group == basic_srcdirs; Group == basic_extras ->
    NewConfig = rebar_test_utils:init_rebar_state(Config, "basic_srcdirs_"),
    AppDir = ?config(apps, NewConfig),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    ExtraSrc = io_lib:format("-module(~ts_extra).\n-export([ok/0]).\nok() -> ok.\n", [Name]),

    ok = filelib:ensure_dir(filename:join([AppDir, "extra", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "extra", io_lib:format("~ts_extra.erl", [Name])]),
                         ExtraSrc),

    [{app_names, [Name]}, {vsns, [Vsn]}|NewConfig];

init_per_group(Group, Config) when Group == release_srcdirs; Group == release_extras ->
    NewConfig = rebar_test_utils:init_rebar_state(Config, "release_srcdirs_"),
    AppDir = ?config(apps, NewConfig),

    Name1 = rebar_test_utils:create_random_name("relapp1_"),
    Vsn1 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([AppDir, "apps", Name1]), Name1, Vsn1, [kernel, stdlib]),

    Name2 = rebar_test_utils:create_random_name("relapp2_"),
    Vsn2 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([AppDir, "apps", Name2]), Name2, Vsn2, [kernel, stdlib]),

    ExtraOne = io_lib:format("-module(~ts_extra).\n-export([ok/0]).\nok() -> ok.\n", [Name1]),

    ok = filelib:ensure_dir(filename:join([AppDir, "apps", Name1, "extra", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "apps", Name1, "extra",
                                        io_lib:format("~ts_extra.erl", [Name1])]),
                         ExtraOne),

    ExtraTwo = io_lib:format("-module(~ts_extra).\n-export([ok/0]).\nok() -> ok.\n", [Name2]),

    ok = filelib:ensure_dir(filename:join([AppDir, "apps", Name2, "extra", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "apps", Name2, "extra",
                                        io_lib:format("~ts_extra.erl", [Name2])]),
                         ExtraTwo),

    [{app_names, [Name1, Name2]}, {vsns, [Vsn1, Vsn2]}|NewConfig];

init_per_group(Group, Config) when Group == unbalanced_srcdirs; Group == unbalanced_extras ->
    NewConfig = rebar_test_utils:init_rebar_state(Config, "unbalanced_srcdirs_"),
    AppDir = ?config(apps, NewConfig),

    Name1 = rebar_test_utils:create_random_name("relapp1_"),
    Vsn1 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([AppDir, "apps", Name1]), Name1, Vsn1, [kernel, stdlib]),

    Name2 = rebar_test_utils:create_random_name("relapp2_"),
    Vsn2 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([AppDir, "apps", Name2]), Name2, Vsn2, [kernel, stdlib]),

    ExtraOne = io_lib:format("-module(~ts_extra).\n-export([ok/0]).\nok() -> ok.\n", [Name1]),

    ok = filelib:ensure_dir(filename:join([AppDir, "apps", Name1, "extra", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "apps", Name1, "extra",
                                        io_lib:format("~ts_extra.erl", [Name1])]),
                         ExtraOne),

    [{app_names, [Name1, Name2]}, {vsns, [Vsn1, Vsn2]}|NewConfig];

init_per_group(root_extras, Config) ->
    NewConfig = rebar_test_utils:init_rebar_state(Config, "root_extras_"),
    AppDir = ?config(apps, NewConfig),

    Name1 = rebar_test_utils:create_random_name("relapp1_"),
    Vsn1 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([AppDir, "apps", Name1]), Name1, Vsn1, [kernel, stdlib]),

    Name2 = rebar_test_utils:create_random_name("relapp2_"),
    Vsn2 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([AppDir, "apps", Name2]), Name2, Vsn2, [kernel, stdlib]),

    Extra = <<"-module(extra).\n-export([ok/0]).\nok() -> ok.\n">>,

    ok = filelib:ensure_dir(filename:join([AppDir, "extra", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "extra", "extra.erl"]), Extra),

    [{app_names, [Name1, Name2]}, {vsns, [Vsn1, Vsn2]}|NewConfig].

end_per_group(_Group, _Config) ->
    ok.

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(Test, Config) when
        Test == dont_recompile_when_erl_compiler_options_env_does_not_change
    orelse
        Test == recompile_when_erl_compiler_options_env_changes ->
    _ = code:ensure_loaded(os),
    UnSetEnv = erlang:function_exported(os, unsetenv, 1),
    _ = code:ensure_loaded(compile),
    EnvOpts = erlang:function_exported(compile, env_compiler_options, 0),
    case {UnSetEnv, EnvOpts} of
        {true, true} -> maybe_init_config(Config);
        _            -> {skip, "compile:env_compiler_options/0 unavailable"}
    end;
init_per_testcase(always_recompile_when_erl_compiler_options_set, Config) ->
    _ = code:ensure_loaded(os),
    UnSetEnv = erlang:function_exported(os, unsetenv, 1),
    _ = code:ensure_loaded(compile),
    EnvOpts = erlang:function_exported(compile, env_compiler_options, 0),
    case {UnSetEnv, EnvOpts} of
        {true, true}  -> {skip, "compile:env_compiler_options/0 available"};
        {true, false} -> maybe_init_config(Config);
        _             -> {skip, "os:unsetenv/1 unavailable"}
    end;
init_per_testcase(_, Config) -> maybe_init_config(Config).

maybe_init_config(Config) ->
    case ?config(apps, Config) of
        undefined -> rebar_test_utils:init_rebar_state(Config);
        _         -> Config
    end.

end_per_testcase(_, _Config) ->
    catch meck:unload().


%% test cases

build_basic_app(Config) ->
    [Name] = ?config(app_names, Config),
    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}).

build_release_apps(Config) ->
    [Name1, Name2] = ?config(app_names, Config),
    rebar_test_utils:run_and_check(
        Config, [], ["compile"],
        {ok, [{app, Name1}, {app, Name2}]}
    ).

build_checkout_deps(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),
    [_, Vsn2] = ?config(vsns, Config),

    Deps = [{list_to_atom(Name2), Vsn2, {git, "", ""}}],
    {ok, RebarConfig} = file:consult(rebar_test_utils:create_config(AppDir, [{deps, Deps}])),

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{app, Name1}, {checkout, Name2}]}
    ).

build_basic_srcdirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{src_dirs, ["src", "extra"]}]}],

    %% check a beam corresponding to the src in the extra src_dir exists
    ExtraBeam = filename:join([AppDir, "_build", "default", "lib", Name, "ebin",
                               io_lib:format("~ts_extra.beam", [Name])]),
    %% check the extra src_dir was copied/linked into the _build dir
    ExtraDir = filename:join([AppDir, "_build", "default", "lib", Name, "extra"]),

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{app, Name}, {file, ExtraBeam}, {dir, ExtraDir}]}
    ).

build_release_srcdirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{src_dirs, ["src", "extra"]}]}],

    %% check a beam corresponding to the src in the extra src_dir exists
    Extra1Beam = filename:join([AppDir, "_build", "default", "lib", Name1, "ebin",
                                io_lib:format("~ts_extra.beam", [Name1])]),
    Extra2Beam = filename:join([AppDir, "_build", "default", "lib", Name2, "ebin",
                                io_lib:format("~ts_extra.beam", [Name2])]),

    %% check the extra src_dir was copied/linked into the _build dir
    Extra1Dir = filename:join([AppDir, "_build", "default", "lib", Name1, "extra"]),
    Extra2Dir = filename:join([AppDir, "_build", "default", "lib", Name2, "extra"]),

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{app, Name1}, {app, Name2},
              {file, Extra1Beam}, {file, Extra2Beam},
              {dir, Extra1Dir}, {dir, Extra2Dir}]}
    ).

build_unbalanced_srcdirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{src_dirs, ["src", "extra"]}]}],

    %% check a beam corresponding to the src in the extra src_dir exists
    Extra1Beam = filename:join([AppDir, "_build", "default", "lib", Name1, "ebin",
                                io_lib:format("~ts_extra.beam", [Name1])]),

    %% check the extra src_dir was copied/linked into the _build dir
    Extra1Dir = filename:join([AppDir, "_build", "default", "lib", Name1, "extra"]),

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{app, Name1}, {app, Name2}, {file, Extra1Beam}, {dir, Extra1Dir}]}
    ),

    %% check no extra src_dir were copied/linked into the _build dir
    Extra2Dir = filename:join([AppDir, "_build", "default", "lib", Name2, "extra"]),
    false = filelib:is_dir(Extra2Dir),
    %% check only expected beams are in the ebin dir
    {ok, Files} = rebar_utils:list_dir(filename:join([AppDir, "_build", "default", "lib", Name2, "ebin"])),
    lists:all(fun(Beam) -> lists:member(Beam, [Name2 ++ ".app", "not_a_real_src_" ++ Name2 ++ ".beam"]) end,
              Files).

build_basic_extra_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{extra_src_dirs, ["extra"]}]}],

    %% check a beam corresponding to the src in the extra src_dir exists
    ExtraBeam = filename:join([AppDir, "_build", "default", "lib", Name, "extra",
                               io_lib:format("~ts_extra.beam", [Name])]),

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{app, Name}, {file, ExtraBeam}]}
    ).

build_release_extra_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{extra_src_dirs, ["extra"]}]}],

    %% check a beam corresponding to the src in the extra src_dir exists
    Extra1Beam = filename:join([AppDir, "_build", "default", "lib", Name1, "extra",
                                io_lib:format("~ts_extra.beam", [Name1])]),
    Extra2Beam = filename:join([AppDir, "_build", "default", "lib", Name2, "extra",
                                io_lib:format("~ts_extra.beam", [Name2])]),

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{app, Name1}, {app, Name2}, {file, Extra1Beam}, {file, Extra2Beam}]}
    ).

build_unbalanced_extra_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{extra_src_dirs, ["extra"]}]}],

    %% check a beam corresponding to the src in the extra src_dir exists
    Extra1Beam = filename:join([AppDir, "_build", "default", "lib", Name1, "extra",
                                io_lib:format("~ts_extra.beam", [Name1])]),

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{app, Name1}, {app, Name2}, {file, Extra1Beam}]}
    ),

    %% check no extra src_dir were copied/linked into the _build dir
    false = filelib:is_dir(filename:join([AppDir, "_build", "default", "lib", Name2, "extra"])),
    %% check only expected beams are in the ebin dir
    {ok, Files} = rebar_utils:list_dir(filename:join([AppDir, "_build", "default", "lib", Name2, "ebin"])),
    lists:all(fun(Beam) -> lists:member(Beam, [Name2 ++ ".app", "not_a_real_src_" ++ Name2 ++ ".beam"]) end,
              Files).

build_extra_dirs_in_project_root(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{extra_src_dirs, ["extra"]}]}],

    %% check a beam corresponding to the src in the extra src_dir exists
    ExtraBeam = filename:join([AppDir, "_build", "default", "extras", "extra", "extra.beam"]),

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{app, Name1}, {app, Name2}, {file, ExtraBeam}]}
    ).

paths_basic_app(Config) ->
    [Name] = ?config(app_names, Config),
    [Vsn] = ?config(vsns, Config),

    {ok, State} = rebar_test_utils:run_and_check(Config, [], ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    ok = application:load(list_to_atom(Name)),
    Loaded = application:loaded_applications(),
    {_, _, Vsn} = lists:keyfind(list_to_atom(Name), 1, Loaded).

paths_release_apps(Config) ->
    [Name1, Name2] = ?config(app_names, Config),
    [Vsn1, Vsn2] = ?config(vsns, Config),

    {ok, State} = rebar_test_utils:run_and_check(Config, [], ["compile"], return),
    code:add_paths(rebar_state:code_paths(State, all_deps)),
    ok = application:load(list_to_atom(Name1)),
    ok = application:load(list_to_atom(Name2)),
    Loaded = application:loaded_applications(),
    {_, _, Vsn1} = lists:keyfind(list_to_atom(Name1), 1, Loaded),
    {_, _, Vsn2} = lists:keyfind(list_to_atom(Name2), 1, Loaded).

paths_checkout_apps(Config) ->
    [Name1, _Name2] = ?config(app_names, Config),
    [Vsn1, _Vsn2] = ?config(vsns, Config),

    {ok, State} = rebar_test_utils:run_and_check(Config, [], ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    ok = application:load(list_to_atom(Name1)),
    Loaded = application:loaded_applications(),
    {_, _, Vsn1} = lists:keyfind(list_to_atom(Name1), 1, Loaded).

paths_checkout_deps(Config) ->
    AppDir = ?config(apps, Config),
    [_Name1, Name2] = ?config(app_names, Config),
    [_Vsn1, Vsn2] = ?config(vsns, Config),

    %% rebar_test_utils:init_rebar_state/1,2 uses rebar_state:new/3 which
    %% maybe incorrectly sets deps to [] (based on `rebar.lock`) instead of
    %% to the checkapps
    %% until that is sorted out the lock file has to be removed before
    %% this test will pass
    file:delete(filename:join([AppDir, "rebar.lock"])),

    {ok, RebarConfig} = file:consult(filename:join([AppDir, "rebar.config"])),

    {ok, State} = rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], return),

    [AppName2] = rebar_state:all_checkout_deps(State),
    Name2Bin = binary:list_to_bin(Name2),
    Name2Bin = rebar_app_info:name(AppName2),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    ok = application:load(list_to_atom(Name2)),
    Loaded = application:loaded_applications(),
    {_, _, Vsn2} = lists:keyfind(list_to_atom(Name2), 1, Loaded).

paths_basic_srcdirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{src_dirs, ["src", "extra"]}]}],

    {ok, State} = rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    Mod = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name]))),
    {module, Mod} = code:ensure_loaded(Mod),

    Expect = filename:join([AppDir, "_build", "default", "lib", Name, "ebin",
                            io_lib:format("~ts_extra.beam", [Name])]),
    Expect = code:which(Mod).

paths_release_srcdirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{src_dirs, ["src", "extra"]}]}],

    {ok, State} = rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    Mod1 = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name1]))),
    {module, Mod1} = code:ensure_loaded(Mod1),
    Mod2 = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name2]))),
    {module, Mod2} = code:ensure_loaded(Mod2),

    ExpectOne = filename:join([AppDir, "_build", "default", "lib", Name1, "ebin",
                               io_lib:format("~ts_extra.beam", [Name1])]),
    ExpectOne = code:which(Mod1),
    ExpectTwo = filename:join([AppDir, "_build", "default", "lib", Name2, "ebin",
                               io_lib:format("~ts_extra.beam", [Name2])]),
    ExpectTwo = code:which(Mod2).

paths_unbalanced_srcdirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{src_dirs, ["src", "extra"]}]}],

    {ok, State} = rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    Mod1 = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name1]))),
    {module, Mod1} = code:ensure_loaded(Mod1),
    Mod2 = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name2]))),
    {error, nofile} = code:ensure_loaded(Mod2),

    ExpectOne = filename:join([AppDir, "_build", "default", "lib", Name1, "ebin",
                               io_lib:format("~ts_extra.beam", [Name1])]),
    ExpectOne = code:which(Mod1).

paths_basic_extra_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{extra_src_dirs, ["extra"]}]}],

    {ok, State} = rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    Mod = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name]))),
    {module, Mod} = code:ensure_loaded(Mod),

    Expect = filename:join([AppDir, "_build", "default", "lib", Name, "extra",
                            io_lib:format("~ts_extra.beam", [Name])]),
    Expect = code:which(Mod).

paths_release_extra_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{extra_src_dirs, ["extra"]}]}],

    {ok, State} = rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    Mod1 = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name1]))),
    {module, Mod1} = code:ensure_loaded(Mod1),
    Mod2 = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name2]))),
    {module, Mod2} = code:ensure_loaded(Mod2),

    ExpectOne = filename:join([AppDir, "_build", "default", "lib", Name1, "extra",
                               io_lib:format("~ts_extra.beam", [Name1])]),
    ExpectOne = code:which(Mod1),
    ExpectTwo = filename:join([AppDir, "_build", "default", "lib", Name2, "extra",
                               io_lib:format("~ts_extra.beam", [Name2])]),
    ExpectTwo = code:which(Mod2).


paths_unbalanced_extra_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    RebarConfig = [{erl_opts, [{extra_src_dirs, ["extra"]}]}],

    {ok, State} = rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    Mod1 = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name1]))),
    {module, Mod1} = code:ensure_loaded(Mod1),
    Mod2 = list_to_atom(lists:flatten(io_lib:format("~ts_extra", [Name2]))),
    {error, nofile} = code:ensure_loaded(Mod2),

    ExpectOne = filename:join([AppDir, "_build", "default", "lib", Name1, "extra",
                               io_lib:format("~ts_extra.beam", [Name1])]),
    ExpectOne = code:which(Mod1).

paths_extra_dirs_in_project_root(Config) ->
    AppDir = ?config(apps, Config),

    RebarConfig = [{erl_opts, [{extra_src_dirs, ["extra"]}]}],

    {ok, State} = rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], return),

    code:add_paths(rebar_state:code_paths(State, all_deps)),
    {module, extra} = code:ensure_loaded(extra),

    Expect = filename:join([AppDir, "_build", "default", "extras", "extra", "extra.beam"]),
    Expect = code:which(extra).

clean_basic_app(Config) ->
    [Name] = ?config(app_names, Config),

    rebar_test_utils:run_and_check(Config, [], ["clean"], {ok, [{app, Name, invalid}]}).

clean_release_apps(Config) ->
    [Name1, Name2] = ?config(app_names, Config),

    rebar_test_utils:run_and_check(Config, [], ["clean"],
                                   {ok, [{app, Name1, invalid}, {app, Name2, invalid}]}).

clean_basic_extra_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name] = ?config(app_names, Config),

    rebar_test_utils:run_and_check(Config, [], ["clean"], {ok, [{app, Name, invalid}]}),

    Beam = lists:flatten(io_lib:format("~ts_extra", [Name])),
    false = ec_file:exists(filename:join([AppDir, "_build", "default", "lib", Name, "extras", Beam])).

clean_release_extra_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    rebar_test_utils:run_and_check(Config, [], ["clean"],
                                   {ok, [{app, Name1, invalid}, {app, Name2, invalid}]}),

    Beam1 = lists:flatten(io_lib:format("~ts_extra", [Name1])),
    false = ec_file:exists(filename:join([AppDir, "_build", "default", "lib", Name1, "extras", Beam1])),
    Beam2 = lists:flatten(io_lib:format("~ts_extra", [Name2])),
    false = ec_file:exists(filename:join([AppDir, "_build", "default", "lib", Name2, "extras", Beam2])).

clean_extra_dirs_in_project_root(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(app_names, Config),

    rebar_test_utils:run_and_check(Config, [], ["clean"],
                                   {ok, [{app, Name1, invalid}, {app, Name2, invalid}]}),

    false = ec_file:exists(filename:join([AppDir, "_build", "default", "extras"])).

recompile_when_hrl_changes(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    ExtraSrc = <<"-module(test_header_include).\n"
                  "-export([main/0]).\n"
                  "-include(\"test_header_include.hrl\").\n"
                  "main() -> ?SOME_DEFINE.\n">>,

    ExtraHeader = <<"-define(SOME_DEFINE, true).\n">>,
    HeaderFile = filename:join([AppDir, "src", "test_header_include.hrl"]),
    ok = file:write_file(filename:join([AppDir, "src", "test_header_include.erl"]), ExtraSrc),
    ok = file:write_file(HeaderFile, ExtraHeader),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    NewExtraHeader = <<"-define(SOME_DEFINE, false).\n">>,
    ok = file:write_file(HeaderFile, NewExtraHeader),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime).

recompile_when_included_hrl_changes(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    ExtraSrc = <<"-module(test_header_include).\n"
                  "-export([main/0]).\n"
                  "-include(\"test_header_include.hrl\").\n"
                  "main() -> ?SOME_DEFINE.\n">>,

    ExtraHeader = <<"-define(SOME_DEFINE, true).\n">>,
    ok = filelib:ensure_dir(filename:join([AppDir, "include", "dummy"])),
    HeaderFile = filename:join([AppDir, "include", "test_header_include.hrl"]),
    ok = file:write_file(filename:join([AppDir, "src", "test_header_include.erl"]), ExtraSrc),
    ok = file:write_file(HeaderFile, ExtraHeader),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    NewExtraHeader = <<"-define(SOME_DEFINE, false).\n">>,
    ok = file:write_file(HeaderFile, NewExtraHeader),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime).

recompile_when_recursive_hrl_changes(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    %% The included path is specifically no specified with a ../<file> to
    %% check dynamic path search generation for includes
    RecurSrc = <<"-module(test_recursive_header_include).\n"
                  "-export([main/0]).\n"
                  "-include(\"test_header_include.hrl\").\n"
                  "main() -> ?SOME_DEFINE.\n">>,

    ExtraHeader = <<"-define(SOME_DEFINE, true).\n">>,
    ok = filelib:ensure_dir(filename:join([AppDir, "src", "recur", "dummy"])),
    HeaderFile = filename:join([AppDir, "src", "test_header_include.hrl"]),
    ok = file:write_file(filename:join([AppDir, "src", "recur", "test_recursive_header_include.erl"]), RecurSrc),
    ok = file:write_file(HeaderFile, ExtraHeader),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    NewExtraHeader = <<"-define(SOME_DEFINE, false).\n">>,
    ok = file:write_file(HeaderFile, NewExtraHeader),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime),
    ok.


recompile_extra_when_hrl_in_src_changes(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    ExtraSrc = <<"-module(test_header_include).\n"
                  "-export([main/0]).\n"
                  "-include(\"test_header_include.hrl\").\n"
                  "main() -> ?SOME_DEFINE.\n">>,

    ExtraHeader = <<"-define(SOME_DEFINE, true).\n">>,
    HeaderFile = filename:join([AppDir, "src", "test_header_include.hrl"]),
    SrcFile = filename:join([AppDir, "extra", "test_header_include.erl"]),
    filelib:ensure_dir(SrcFile),
    ok = file:write_file(SrcFile, ExtraSrc),
    ok = file:write_file(HeaderFile, ExtraHeader),

    RebarCfg = [{extra_src_dirs, ["extra"]}],
    rebar_test_utils:run_and_check(Config, RebarCfg, ["compile"],
                                   {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "extra"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    NewExtraHeader = <<"-define(SOME_DEFINE, false).\n">>,
    ok = file:write_file(HeaderFile, NewExtraHeader, [sync]),

    rebar_test_utils:run_and_check(Config, RebarCfg, ["compile"],
                                   {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),

    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime).

recompile_when_opts_included_hrl_changes(Config) ->
    AppsDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir = filename:join([AppsDir, "apps", Name]),

    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    ExtraSrc = <<"-module(test_header_include).\n"
                  "-export([main/0]).\n"
                  "-include(\"test_header_include.hrl\").\n"
                  "main() -> ?SOME_DEFINE.\n">>,

    ExtraHeader = <<"-define(SOME_DEFINE, true).\n">>,
    ok = filelib:ensure_dir(filename:join([AppsDir, "include", "dummy"])),
    HeaderFile = filename:join([AppsDir, "include", "test_header_include.hrl"]),
    ok = file:write_file(filename:join([AppDir, "src", "test_header_include.erl"]), ExtraSrc),
    ok = file:write_file(HeaderFile, ExtraHeader),

    %% Using relative path from the project root
    RebarConfig = [{erl_opts, [{i, "include/"}]}],
    {ok,Cwd} = file:get_cwd(),
    ok = file:set_cwd(AppsDir),

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppsDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    NewExtraHeader = <<"-define(SOME_DEFINE, false).\n">>,
    ok = file:write_file(HeaderFile, NewExtraHeader),

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ok = file:set_cwd(Cwd),

    ?assert(ModTime =/= NewModTime).

recompile_when_foreign_included_hrl_changes(Config) ->
    AppDir = ?config(apps, Config),
    AppsDir = filename:join([AppDir, "apps"]),

    Name1 = rebar_test_utils:create_random_name("app1_"),
    Name2 = rebar_test_utils:create_random_name("app2_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join(AppsDir, Name1),
                                Name1, Vsn, [kernel, stdlib]),
    rebar_test_utils:create_app(filename:join(AppsDir, Name2),
                                Name2, Vsn, [kernel, stdlib]),

    ExtraSrc = [<<"-module(test_header_include).\n"
                  "-export([main/0]).\n"
                  "-include_lib(\"">>, Name2, <<"/include/test_header_include.hrl\").\n"
                  "main() -> ?SOME_DEFINE.\n">>],

    ExtraHeader = <<"-define(SOME_DEFINE, true).\n">>,
    ok = filelib:ensure_dir(filename:join([AppsDir, Name1, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppsDir, Name2, "include", "dummy"])),
    HeaderFile = filename:join([AppsDir, Name2, "include", "test_header_include.hrl"]),
    ok = file:write_file(filename:join([AppsDir, Name1, "src", "test_header_include.erl"]), ExtraSrc),
    ok = file:write_file(HeaderFile, ExtraHeader),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name1}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name1, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    NewExtraHeader = <<"-define(SOME_DEFINE, false).\n">>,
    ok = file:write_file(HeaderFile, NewExtraHeader),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name1}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime).

recompile_when_foreign_behaviour_changes(Config) ->
    AppDir = ?config(apps, Config),
    AppsDir = filename:join([AppDir, "apps"]),

    Name1 = rebar_test_utils:create_random_name("app1_"),
    Name2 = rebar_test_utils:create_random_name("app2_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join(AppsDir, Name1),
                                Name1, Vsn, [kernel, stdlib]),
    rebar_test_utils:create_app(filename:join(AppsDir, Name2),
                                Name2, Vsn, [kernel, stdlib]),

    ExtraSrc = <<"-module(test_behaviour_include).\n"
                 "-export([main/0]).\n"
                 "-behaviour(app2_behaviour).\n"
                 "main() -> 1.\n">>,

    Behaviour = <<"-module(app2_behaviour).\n"
                  "-callback main() -> term().\n">>,
    ok = filelib:ensure_dir(filename:join([AppsDir, Name1, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppsDir, Name2, "src", "dummy"])),
    BehaviourFile = filename:join([AppsDir, Name2, "src", "app2_behaviour.erl"]),
    ok = file:write_file(filename:join([AppsDir, Name1, "src", "test_behaviour_include.erl"]), ExtraSrc),
    ok = file:write_file(BehaviourFile, Behaviour),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name1}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name1, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    NewBehaviour = <<"-module(app2_behaviour).\n"
                     "-callback main(_) -> term().\n">>,
    ok = file:write_file(BehaviourFile, NewBehaviour),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name1}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime).

recompile_when_recursive_behaviour_changes(Config) ->
    AppDir = ?config(apps, Config),
    AppsDir = filename:join([AppDir, "apps"]),

    Name1 = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join(AppsDir, Name1),
                                Name1, Vsn, [kernel, stdlib]),

    ExtraSrc = <<"-module(test_behaviour_include).\n"
                 "-export([main/0]).\n"
                 "-behaviour(app1_behaviour).\n"
                 "main() -> 1.\n">>,

    Behaviour = <<"-module(app1_behaviour).\n"
                  "-callback main() -> term().\n">>,
    ok = filelib:ensure_dir(filename:join([AppsDir, Name1, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppsDir, Name1, "src", "sub", "dummy"])),
    BehaviourFile = filename:join([AppsDir, Name1, "src", "sub", "app1_behaviour.erl"]),
    ok = file:write_file(filename:join([AppsDir, Name1, "src", "test_behaviour_include.erl"]), ExtraSrc),
    ok = file:write_file(BehaviourFile, Behaviour),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name1}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name1, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files,
                  filename:extension(F) == ".beam",
                  filename:basename(F) =/= "app1_behaviour.beam"],

    timer:sleep(1000),

    NewBehaviour = <<"-module(app1_behaviour).\n"
                     "-callback main(_) -> term().\n">>,
    ok = file:write_file(BehaviourFile, NewBehaviour),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name1}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles,
                     filename:extension(F) == ".beam",
                     filename:basename(F) =/= "app1_behaviour.beam"],

    ?assert(ModTime =/= NewModTime).

recompile_when_parent_behaviour_changes(Config) ->
    AppDir = ?config(apps, Config),
    AppsDir = filename:join([AppDir, "apps"]),

    Name1 = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join(AppsDir, Name1),
                                Name1, Vsn, [kernel, stdlib]),

    ExtraSrc = <<"-module(test_behaviour_include).\n"
                 "-export([main/0]).\n"
                 "-behaviour(app1_behaviour).\n"
                 "main() -> 1.\n">>,

    Behaviour = <<"-module(app1_behaviour).\n"
                  "-callback main() -> term().\n">>,
    %% fun thing requires 2+ levels of nesting to trigger a regression due to bad path
    %% merging/appending in lists levels.
    ok = filelib:ensure_dir(filename:join([AppsDir, Name1, "src", "sub", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppsDir, Name1, "src", "sub", "sub", "dummy"])),
    BehaviourFile = filename:join([AppsDir, Name1, "src", "sub", "app1_behaviour.erl"]),
    ok = file:write_file(filename:join([AppsDir, Name1, "src", "sub", "sub", "test_behaviour_include.erl"]), ExtraSrc),
    ok = file:write_file(BehaviourFile, Behaviour),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name1}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name1, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files,
                  filename:extension(F) == ".beam",
                  filename:basename(F) =/= "app1_behaviour.beam"],

    timer:sleep(1000),

    NewBehaviour = <<"-module(app1_behaviour).\n"
                     "-callback main(_) -> term().\n">>,
    ok = file:write_file(BehaviourFile, NewBehaviour),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name1}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles,
                     filename:extension(F) == ".beam",
                     filename:basename(F) =/= "app1_behaviour.beam"],

    ?assert(ModTime =/= NewModTime).

recompile_when_opts_change(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    rebar_test_utils:create_config(AppDir, [{erl_opts, [{d, some_define}]}]),

    rebar_test_utils:run_and_check(Config, [{erl_opts, [{d, some_define}]}], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime).

recompile_when_dag_opts_change(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    Beams = [filename:join([EbinDir, F])
             || F <- Files, filename:extension(F) == ".beam"],
    ModTime = [filelib:last_modified(Beam) || Beam <- Beams],

    timer:sleep(1000),

    DepsDir = filename:join([AppDir, "_build", "default", "lib"]),
    G = rebar_compiler_dag:init(DepsDir, rebar_compiler_erl, "project_apps", []),
    %% change the config in the DAG...
    [digraph:add_vertex(G, Beam, {artifact, [{d, some_define}]}) || Beam <- Beams],
    digraph:add_vertex(G, '$r3_dirty_bit', true), % trigger a save
    %% the rebar_compiler_erl module is annotated with a compiler version
    %% to help rebuild deps
    {ok, CompileVsn} = application:get_key(compiler, vsn),
    CritMeta = [{compiler, CompileVsn}],

    rebar_compiler_dag:maybe_store(G, DepsDir, rebar_compiler_erl, "project_apps", CritMeta),
    rebar_compiler_dag:terminate(G),
    %% ... but don't change the actual rebar3 config...
    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    %% ... and checks that it rebuilds anyway due to DAG changes
    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewBeams = [filename:join([EbinDir, F])
                || F <- NewFiles, filename:extension(F) == ".beam"],
    NewModTime = [filelib:last_modified(Beam) || Beam <- NewBeams],

    ?assert(ModTime =/= NewModTime).

dont_recompile_when_opts_dont_change(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assertEqual(ModTime, NewModTime).

dont_recompile_yrl_or_xrl(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Xrl = filename:join([AppDir, "src", "not_a_real_xrl_" ++ Name ++ ".xrl"]),
    ok = filelib:ensure_dir(Xrl),
    XrlBody =
        "Definitions."
        "\n\n"
        "D = [0-9]"
        "\n\n"
        "Rules."
        "\n\n"
        "{D}+ :"
        "  {token,{integer,TokenLine,list_to_integer(TokenChars)}}."
        "\n\n"
        "{D}+\\.{D}+((E|e)(\\+|\\-)?{D}+)? :"
        "  {token,{float,TokenLine,list_to_float(TokenChars)}}."
        "\n\n"
        "Erlang code.",
    ok = ec_file:write(Xrl, XrlBody),

    Yrl = filename:join([AppDir, "src", "not_a_real_yrl_" ++ Name ++ ".yrl"]),
    ok = filelib:ensure_dir(Yrl),
    YrlBody = ["Nonterminals E T F.\n"
               "Terminals '+' '*' '(' ')' number.\n"
               "Rootsymbol E.\n"
               "E -> E '+' T: {'$2', '$1', '$3'}.\n"
               "E -> T : '$1'.\n"
               "T -> T '*' F: {'$2', '$1', '$3'}.\n"
               "T -> F : '$1'.\n"
               "F -> '(' E ')' : '$2'.\n"
               "F -> number : '$1'.\n"],
    ok = ec_file:write(Yrl, YrlBody),

    XrlErl = filename:join([AppDir, "src", filename:basename(Xrl, ".xrl") ++ ".erl"]),
    YrlErl = filename:join([AppDir, "src", filename:basename(Yrl, ".yrl") ++ ".erl"]),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    XrlBeam = filename:join([EbinDir, filename:basename(Xrl, ".xrl") ++ ".beam"]),
    YrlBeam = filename:join([EbinDir, filename:basename(Yrl, ".yrl") ++ ".beam"]),

    Hrl = filename:join([AppDir, "include", "some_header.hrl"]),
    ok = filelib:ensure_dir(Hrl),
    HrlBody = yeccpre_hrl(),
    ok = ec_file:write(Hrl, HrlBody),
    RebarConfig = [{yrl_opts, [{includefile, "include/some_header.hrl"}]}],

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    XrlModTime = filelib:last_modified(XrlErl),
    YrlModTime = filelib:last_modified(YrlErl),

    XrlBeamModTime = filelib:last_modified(XrlBeam),
    YrlBeamModTime = filelib:last_modified(YrlBeam),

    timer:sleep(1000),

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    NewXrlModTime = filelib:last_modified(XrlErl),
    NewYrlModTime = filelib:last_modified(YrlErl),

    NewXrlBeamModTime = filelib:last_modified(XrlBeam),
    NewYrlBeamModTime = filelib:last_modified(YrlBeam),

    ?assert(XrlBeamModTime == NewXrlBeamModTime),
    ?assert(YrlBeamModTime == NewYrlBeamModTime),

    ?assert(XrlModTime == NewXrlModTime),
    ?assert(YrlModTime == NewYrlModTime).

delete_beam_if_source_deleted(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    _SrcDir = filename:join([AppDir, "_build", "default", "lib", Name, "src"]),
    ?assert(filelib:is_regular(filename:join(EbinDir, "not_a_real_src_" ++ Name ++ ".beam"))),
    file:delete(filename:join([AppDir, "src", "not_a_real_src_" ++ Name ++ ".erl"])),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    ?assertNot(filelib:is_regular(filename:join(EbinDir, "not_a_real_src_" ++ Name ++ ".beam"))).

deps_in_path(Config) ->
    AppDir = ?config(apps, Config),
    StartPaths = code:get_path(),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    DepName = rebar_test_utils:create_random_name("dep1_"),
    PkgName = rebar_test_utils:create_random_name("pkg1_"),
    mock_git_resource:mock([]),
    mock_pkg_resource:mock([
        {pkgdeps, [{{iolist_to_binary(PkgName), iolist_to_binary(Vsn)}, []}]}
    ]),

    RConfFile = rebar_test_utils:create_config(AppDir, [{deps, [
        {list_to_atom(DepName), {git, "http://site.com/user/"++DepName++".git", {tag, Vsn}}},
        {list_to_atom(PkgName), Vsn}
    ]}]),
    {ok, RConf} = file:consult(RConfFile),
    %% Make sure apps we look for are not visible
    %% Hope not to find src name
    ?assertEqual([], [Path || Path <- code:get_path(),
                              {match, _} <- [re:run(Path, DepName)]]),
    %% Hope not to find pkg name in there

    ?assertEqual([], [Path || Path <- code:get_path(),
                                 {match, _} <- [re:run(Path, PkgName)]]),
    %% Build things
    {ok, State} = rebar_test_utils:run_and_check(
        Config, RConf, ["compile"],
        {ok, [{app, Name}, {dep, DepName}, {dep, PkgName}]}
    ),
    code:add_paths(rebar_state:code_paths(State, all_deps)),
    %% Find src name in there
    ?assertNotEqual([], [Path || Path <- code:get_path(),
                                 {match, _} <- [re:run(Path, DepName)]]),
    %% find pkg name in there
    ?assertNotEqual([], [Path || Path <- code:get_path(),
                                 {match, _} <- [re:run(Path, PkgName)]]),

    true = code:set_path(lists:filter(fun(P) -> ec_file:exists(P) end, StartPaths)),
    %% Make sure apps we look for are not visible again
    %% Hope not to find src name
    ?assertEqual([], [Path || Path <- code:get_path(),
                              {match, _} <- [re:run(Path, DepName)]]),
    %% Hope not to find pkg name in there
    ?assertEqual([], [Path || Path <- code:get_path(),
                                 {match, _} <- [re:run(Path, PkgName)]]),
    %% Rebuild
    {ok, State1} = rebar_test_utils:run_and_check(
        Config, RConf, ["compile"],
        {ok, [{app, Name}, {dep, DepName}, {dep, PkgName}]}
    ),
    %% Find src name in there
    code:add_paths(rebar_state:code_paths(State1, all_deps)),
    ?assertNotEqual([], [Path || Path <- code:get_path(),
                                 {match, _} <- [re:run(Path, DepName)]]),
    %% find pkg name in there
    ?assertNotEqual([], [Path || Path <- code:get_path(),
                                 {match, _} <- [re:run(Path, PkgName)]]).

checkout_priority(Config) ->
    AppDir = ?config(apps, Config),
    CheckoutsDir = ?config(checkouts, Config),
    StartPaths = code:get_path(),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    DepName = rebar_test_utils:create_random_name("dep1_"),
    PkgName = rebar_test_utils:create_random_name("pkg1_"),
    mock_git_resource:mock([]),
    mock_pkg_resource:mock([
        {pkgdeps, [{{iolist_to_binary(PkgName), iolist_to_binary(Vsn)}, []}]}
    ]),

    RConfFile = rebar_test_utils:create_config(AppDir, [{deps, [
        {list_to_atom(DepName), {git, "http://site.com/user/"++DepName++".git", {tag, Vsn}}},
        {list_to_atom(PkgName), Vsn}
    ]}]),
    {ok, RConf} = file:consult(RConfFile),

    %% Build with deps.
    rebar_test_utils:run_and_check(
        Config, RConf, ["compile"],
        {ok, [{app, Name}, {dep, DepName}, {dep, PkgName}]}
    ),

    %% Build two checkout apps similar to dependencies to be fetched,
    %% but on a different version
    Vsn2 = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(filename:join([CheckoutsDir,DepName]), DepName, Vsn2, [kernel, stdlib]),
    rebar_test_utils:create_app(filename:join([CheckoutsDir,PkgName]), PkgName, Vsn2, [kernel, stdlib]),

    %% Rebuild and make sure the checkout apps are in path
    code:set_path(StartPaths),
    {ok, State} = rebar_test_utils:run_and_check(
        Config, RConf, ["compile"],
        {ok, [{app, Name}, {checkout, DepName}, {checkout, PkgName}]}
    ),
    code:add_paths(rebar_state:code_paths(State, all_deps)),
    [DepPath] = [Path || Path <- code:get_path(),
                         {match, _} <- [re:run(Path, DepName)]],
    [PkgPath] = [Path || Path <- code:get_path(),
                         {match, _} <- [re:run(Path, PkgName)]],

    {ok, [DepApp]} = file:consult(filename:join([DepPath, DepName ++ ".app"])),
    {ok, [PkgApp]} = file:consult(filename:join([PkgPath, PkgName ++ ".app"])),

    {application, _, DepProps} = DepApp,
    {application, _, PkgProps} = PkgApp,

    ?assertEqual(Vsn2, proplists:get_value(vsn, DepProps)),
    ?assertEqual(Vsn2, proplists:get_value(vsn, PkgProps)).


highest_version_of_pkg_dep(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    PkgName = rebar_test_utils:create_random_name("pkg1_"),
    mock_git_resource:mock([]),
    mock_pkg_resource:mock([
        {pkgdeps, [{{iolist_to_binary(PkgName), <<"0.1.0">>}, []},
                   {{iolist_to_binary(PkgName), <<"0.0.1">>}, []},
                   {{iolist_to_binary(PkgName), <<"0.1.3">>}, []},
                   {{iolist_to_binary(PkgName), <<"0.1.1">>}, []}]}
    ]),

    RConfFile = rebar_test_utils:create_config(AppDir, [{deps, [list_to_atom(PkgName)]}]),
    {ok, RConf} = file:consult(RConfFile),

    %% Build with deps.
    rebar_test_utils:run_and_check(
        Config, RConf, ["compile"],
        {ok, [{app, Name}, {dep, PkgName, <<"0.1.3">>}]}
    ).

parse_transform_test(Config) ->
    AppDir = ?config(apps, Config),

    RebarConfig = [{erl_opts, [{parse_transform, pascal}]}],

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    ExtraSrc = <<"-module(pascal). "
                 "-export([parse_transform/2]). "
                 "parse_transform(Forms, _Options) -> "
                 "Forms.">>,

    ok = file:write_file(filename:join([AppDir, "src", "pascal.erl"]), ExtraSrc),

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    true = filelib:is_file(filename:join([EbinDir, "pascal.beam"])).

erl_first_files_test(Config) ->
    AppDir = ?config(apps, Config),
    RebarConfig = [{erl_opts, [{parse_transform, mark_time}]},
                   {erl_first_files, ["src/mark_time.erl",
                                      "src/b.erl",
                                      "src/d.erl",
                                      "src/a.erl"]}],

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    rebar_test_utils:write_src_file(AppDir, "a.erl"),
    rebar_test_utils:write_src_file(AppDir, "b.erl"),
    rebar_test_utils:write_src_file(AppDir, "d.erl"),
    rebar_test_utils:write_src_file(AppDir, "e.erl"),

    ExtraSrc = <<"-module(mark_time). "
                 "-export([parse_transform/2]). "
                 "parse_transform([Form={attribute,_,module,Mod}|Forms], Options) -> "
                 "    [Form, {attribute,1,number, os:timestamp()} | Forms];"
                 "parse_transform([Form|Forms], Options) -> "
                 "    [Form | parse_transform(Forms, Options)].">>,

    ok = file:write_file(filename:join([AppDir, "src", "mark_time.erl"]), ExtraSrc),

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    true = filelib:is_file(filename:join([EbinDir, "mark_time.beam"])),

    code:load_abs(filename:join([EbinDir, "a"])),
    code:load_abs(filename:join([EbinDir, "b"])),
    code:load_abs(filename:join([EbinDir, "d"])),
    code:load_abs(filename:join([EbinDir, "e"])),
    A = proplists:get_value(number, a:module_info(attributes)),
    B = proplists:get_value(number, b:module_info(attributes)),
    D = proplists:get_value(number, d:module_info(attributes)),
    E = proplists:get_value(number, e:module_info(attributes)),
    ?assertEqual([B,D,A,E], lists:sort([A,B,D,E])).

mib_test(Config) ->
    AppDir = ?config(apps, Config),

    RebarConfig = [{mib_first_files, ["mibs/SIMPLE-MIB.mib"]}],

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    MibsSrc = <<"-- SIMPLE-MIB.\n"
"-- This is just a simple MIB used for testing!\n"
"--\n"
"SIMPLE-MIB DEFINITIONS ::= BEGIN\n"
"IMPORTS\n"
"    MODULE-IDENTITY, enterprises\n"
"        FROM SNMPv2-SMI;\n"
"\n"
"ericsson MODULE-IDENTITY\n"
"    LAST-UPDATED\n"
"        \"201403060000Z\"\n"
"    ORGANIZATION\n"
"        \"rebar\"\n"
"    CONTACT-INFO\n"
"        \"rebar <rebar@example.com>\n"
"    or\n"
"    whoever is currently responsible for the SIMPLE\n"
"    enterprise MIB tree branch (enterprises.999).\"\n"
"    DESCRIPTION\n"
"        \"This very small module is made available\n"
"	for mib-compilation testing.\"\n"
"    ::= { enterprises 999 }\n"
"END\n">>,

    ok = filelib:ensure_dir(filename:join([AppDir, "mibs", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "mibs", "SIMPLE-MIB.mib"]), MibsSrc),

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    %% check a bin corresponding to the mib in the mibs dir exists in priv/mibs
    PrivMibsDir = filename:join([AppDir, "_build", "default", "lib", Name, "priv", "mibs"]),
    true = filelib:is_file(filename:join([PrivMibsDir, "SIMPLE-MIB.bin"])),

    %% check a hrl corresponding to the mib in the mibs dir exists in include
    true = filelib:is_file(filename:join([AppDir, "include", "SIMPLE-MIB.hrl"])),

    %% check the mibs dir was linked into the _build dir
    true = filelib:is_dir(filename:join([AppDir, "_build", "default", "lib", Name, "mibs"])).

umbrella_mib_first_test(Config) ->
    AppsDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir = filename:join([AppsDir, "apps", Name]),

    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    BExporterSrc = <<"-- BEXPORTER-MIB.\n"
"-- This is just a simple MIB used for testing!\n"
"--\n"
"BEXPORTER-MIB DEFINITIONS ::= BEGIN\n"
"IMPORTS\n"
"    TEXTUAL-CONVENTION\n"
"        FROM SNMPv2-TC\n"
"    MODULE-IDENTITY, enterprises\n"
"        FROM SNMPv2-SMI;\n"
"\n"
"ericsson MODULE-IDENTITY\n"
"    LAST-UPDATED\n"
"        \"201812050000Z\"\n"
"    ORGANIZATION\n"
"        \"rebar\"\n"
"    CONTACT-INFO\n"
"        \"rebar <rebar@example.com>\n"
"    or\n"
"    whoever is currently responsible for the SIMPLE\n"
"    enterprise MIB tree branch (enterprises.999).\"\n"
"    DESCRIPTION\n"
"        \"This very small module is made available\n"
"	for mib-compilation testing.\"\n"
"    ::= { enterprises 999 }\n"
"\n"
"Something ::= TEXTUAL-CONVENTION\n"
"    STATUS current\n"
"    DESCRIPTION \"\"\n"
"    SYNTAX      OCTET STRING (SIZE (4))\n"
"END\n">>,

    AImporterSrc = <<"-- AIMPORTER-MIB.\n"
"-- This is just a simple MIB used for testing!\n"
"--\n"
"AIMPORTER-MIB DEFINITIONS ::= BEGIN\n"
"IMPORTS\n"
"    Something\n"
"        FROM BEXPORTER-MIB\n"
"    MODULE-IDENTITY, enterprises\n"
"        FROM SNMPv2-SMI;\n"
"\n"
"ericsson MODULE-IDENTITY\n"
"    LAST-UPDATED\n"
"        \"201812050000Z\"\n"
"    ORGANIZATION\n"
"        \"rebar\"\n"
"    CONTACT-INFO\n"
"        \"rebar <rebar@example.com>\n"
"    or\n"
"    whoever is currently responsible for the SIMPLE\n"
"    enterprise MIB tree branch (enterprises.999).\"\n"
"    DESCRIPTION\n"
"        \"This very small module is made available\n"
"	for mib-compilation testing.\"\n"
"    ::= { enterprises 1000 }\n"
"END\n">>,



    ok = filelib:ensure_dir(filename:join([AppDir, "mibs", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "mibs", "AIMPORTER-MIB.mib"]), AImporterSrc),
    ok = file:write_file(filename:join([AppDir, "mibs", "BEXPORTER-MIB.mib"]), BExporterSrc),

        FailureRebarConfig = [{mib_first_files, ["mibs/AIMPORTER-MIB.mib"]}],
    SuccessRebarConfig = [{mib_first_files, ["mibs/BEXPORTER-MIB.mib"]}],

    PrivMibsDir = filename:join([AppsDir, "_build", "default", "lib", Name, "priv", "mibs"]),

    FailureRebarConfig = [{mib_first_files, ["mibs/AIMPORTER-MIB.mib"]}],
    catch (
    rebar_test_utils:run_and_check(Config, FailureRebarConfig, ["compile"], {ok, [{app, Name}]}) ),

    %% check that the bin file was NOT cretated
    false = filelib:is_file(filename:join([PrivMibsDir, "AIMPORTER-MIB.bin"])),


    SuccessRebarConfig = [{mib_first_files, ["mibs/BEXPORTER-MIB.mib"]}],
    rebar_test_utils:run_and_check(Config, SuccessRebarConfig, ["compile"], {ok, [{app, Name}]}),

    %% check a bin corresponding to the mib in the mibs dir exists in priv/mibs
    true = filelib:is_file(filename:join([PrivMibsDir, "AIMPORTER-MIB.bin"])),

    %% check a hrl corresponding to the mib in the mibs dir exists in include
    true = filelib:is_file(filename:join([AppDir, "include", "AIMPORTER-MIB.hrl"])),

    %% check the mibs dir was linked into the _build dir
    true = filelib:is_dir(filename:join([AppsDir, "_build", "default", "lib", Name, "mibs"])).

deps_mib_test() ->
    [{doc, "reproduces the dependency handling required for the issue "
           "reported in https://github.com/erlang/rebar3/issues/2372"}].
deps_mib_test(Config) ->
    Priv = ?config(priv_dir, Config),
    CliLvl2Mib =
        "---\n"
        "---\n"
        "---\n"
        "LVL2-MIB DEFINITIONS ::= BEGIN\n"
        "IMPORTS\n"
        "    MODULE-IDENTITY, OBJECT-TYPE\n"
        "        FROM SNMPv2-SMI\n"
        "    lvlModules, lvlApplications\n"
        "        FROM LVL0-REG\n"
        "    LvlFoo\n"
        "        FROM LVL0-TC\n"
        "    ;\n"
        "\n"
        "lvl2Module MODULE-IDENTITY\n"
        "    LAST-UPDATED \"202009261630Z\"\n"
        "    ORGANIZATION \"'some org'\"\n"
        "    CONTACT-INFO \"'Contact: some contact'\"\n"
        "    DESCRIPTION\n"
        "         \" \"\n"
        "    ::= { lvlModules 3 }\n"
        "\n\n\n"
        "END",
    CpiLvl0Mib1 =
        "        \n"
        "---\n"
        "---\n\n"
        "LVL0-TC DEFINITIONS ::= BEGIN\n"
        "IMPORTS\n"
        "    lvlModules\n"
        "        FROM LVL0-REG\n"
        "    MODULE-IDENTITY\n"
        "        FROM SNMPv2-SMI\n"
        "    TEXTUAL-CONVENTION\n"
        "        FROM SNMPv2-TC\n"
        "    ;\n\n"
        "lvlTcModule MODULE-IDENTITY\n"
        "    LAST-UPDATED \"202009261630Z\"\n"
        "    ORGANIZATION \"'some org'\"\n"
        "    CONTACT-INFO \"'Contact: some contact'\"\n"
        "    DESCRIPTION\n"
        "         \" This MIB is part of the LVL MIB. It defines common\n"
        "         Textual Conventions used in other LVL mib modules.\"\n"
        "    ::= { lvlModules 2 }\n\n\n"
        "LvlFoo ::= TEXTUAL-CONVENTION\n"
        "    DISPLAY-HINT \"512a\"\n"
        "    STATUS current\n"
        "    DESCRIPTION \"\"\n"
        "    SYNTAX OCTET STRING (SIZE (1..512))\n\n"
        "LvlEnum ::= TEXTUAL-CONVENTION\n"
        "    STATUS	current\n"
        "    DESCRIPTION	\"\"\n"
        "    SYNTAX	INTEGER { foo(1), bar(2), baz(3) }\n\n"
        "END\n",
    CpiLvl0Mib2 =
        "---\n---\n---\n\n"
        "LVL0-REG DEFINITIONS ::= BEGIN\n"
        "\n"
        "IMPORTS\n"
        "    MODULE-IDENTITY, enterprises\n"
        "        FROM SNMPv2-SMI\n"
        "    ;\n\n"
        "lvlRegModule MODULE-IDENTITY\n"
        "    LAST-UPDATED \"202009261630Z\"\n"
        "    ORGANIZATION \"'some org'\"\n"
        "    CONTACT-INFO \"'Contact: some contact'\"\n"
        "    DESCRIPTION\n"
        "        \"The root MIB module for LVL\"\n"
        "    ::= { lvlModules 1 }\n\n"
        "-- Example Enterprise Number for Documentation use\n"
        "example OBJECT IDENTIFIER ::= { enterprises 32473 }\n"
        "\n"
        "lvl OBJECT IDENTIFIER ::= { example 1 }\n\n"
        "-- sub-tree for registrations (Modules information)\n"
        "lvlReg OBJECT IDENTIFIER ::= { lvl 1 }\n"
        "lvlModules OBJECT IDENTIFIER ::= { lvlReg 1 }\n"
        "\n"
        "-- the application subtree\n"
        "lvlApplications OBJECT IDENTIFIER ::= { lvl 2 }\n"
        "END\n",
    CliLvl2Path = filename:join([Priv, "deps_mib", "cli_lvl2", "mibs", "LVL2-MIB.mib"]),
    CpiLvl0Path1 = filename:join([Priv, "deps_mib", "cpi_lvl0", "mibs", "LVL0-TC.mib"]),
    CpiLvl0Path2 = filename:join([Priv, "deps_mib", "cpi_lvl0", "mibs", "LVL0-REG.mib"]),
    NprLvl1Path = filename:join([Priv, "deps_mib", "npr_lvl1", "mibs"]), % no mibs dir
    FakeLvl1Path = filename:join([Priv, "deps_mib", "fake_lvl1", "mibs", "no_file"]), % no mibs file
    ok = filelib:ensure_dir(CliLvl2Path),
    ok = filelib:ensure_dir(CpiLvl0Path1), % CpiLvl0Path2 is the same dir
    ok = filelib:ensure_dir(NprLvl1Path),
    ok = filelib:ensure_dir(FakeLvl1Path),
    ok = file:write_file(CliLvl2Path, CliLvl2Mib),
    ok = file:write_file(CpiLvl0Path1, CpiLvl0Mib1),
    ok = file:write_file(CpiLvl0Path2, CpiLvl0Mib2),
    Res = rebar_compiler_mib:dependencies(
            CliLvl2Path,
            filename:dirname(CliLvl2Path),
            [filename:dirname(CliLvl2Path),
             filename:dirname(CpiLvl0Path1),
             NprLvl1Path,
             filename:dirname(FakeLvl1Path)]
    ),
    ?assertEqual(lists:sort([CpiLvl0Path1, CpiLvl0Path2]),
                 lists:sort(Res)),
    ok.

only_default_transitive_deps(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    GitDeps = rebar_test_utils:expand_deps(git, [{"a", "1.0.0", []}]),
    PkgName = rebar_test_utils:create_random_name("pkg1_"),
    {SrcDeps, _} = rebar_test_utils:flat_deps(GitDeps),
    mock_git_resource:mock([{deps, SrcDeps},
                            {config, [{profiles, [{test, [{deps, [list_to_atom(PkgName)]}]}]}]}]),

    mock_pkg_resource:mock([{pkgdeps, [{{iolist_to_binary(PkgName), <<"0.1.0">>}, []}]}]),

    Deps = rebar_test_utils:top_level_deps(GitDeps),
    RConfFile = rebar_test_utils:create_config(AppDir, [{deps, Deps}]),
    {ok, RConf} = file:consult(RConfFile),

    %% Build with deps.
    rebar_test_utils:run_and_check(
        Config, RConf, ["as", "test", "compile"],
        {ok, [{app, Name}, {dep, "a", <<"1.0.0">>}, {dep_not_exist, PkgName}]}
    ).

clean_all(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    DepName = rebar_test_utils:create_random_name("dep1_"),
    PkgName = rebar_test_utils:create_random_name("pkg1_"),
    mock_git_resource:mock([]),
    mock_pkg_resource:mock([
        {pkgdeps, [{{iolist_to_binary(PkgName), iolist_to_binary(Vsn)}, []}]}
    ]),

    RConfFile = rebar_test_utils:create_config(AppDir, [{deps, [
        {list_to_atom(DepName), {git, "http://site.com/user/"++DepName++".git", {tag, Vsn}}},
        {list_to_atom(PkgName), Vsn}
    ]}]),
    {ok, RConf} = file:consult(RConfFile),

    %% Build things
    rebar_test_utils:run_and_check(
        Config, RConf, ["compile"],
        {ok, [{app, Name}, {app, DepName}, {app, PkgName}]}
    ),

    %% Clean all
    rebar_test_utils:run_and_check(Config, [], ["clean", "--all"],
                                   {ok, [{app, Name, invalid},
                                         {app, DepName, invalid},
                                         {app, PkgName, invalid}]}).

clean_specific(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    DepName = rebar_test_utils:create_random_name("dep1_"),
    PkgName = rebar_test_utils:create_random_name("pkg1_"),
    mock_git_resource:mock([]),
    mock_pkg_resource:mock([
        {pkgdeps, [{{iolist_to_binary(PkgName), iolist_to_binary(Vsn)}, []}]}
    ]),

    RConfFile = rebar_test_utils:create_config(AppDir, [{deps, [
        {list_to_atom(DepName), {git, "http://site.com/user/"++DepName++".git", {tag, Vsn}}},
        {list_to_atom(PkgName), Vsn}
    ]}]),
    {ok, RConf} = file:consult(RConfFile),

    %% Build things
    rebar_test_utils:run_and_check(
        Config, RConf, ["compile"],
        {ok, [{app, Name}, {app, DepName}, {app, PkgName}]}
    ),

    %% Clean all
    rebar_test_utils:run_and_check(Config, [], ["clean", "--apps="++DepName++","++Name],
                                   {ok, [{app, Name, invalid},
                                         {app, DepName, invalid},
                                         {app, PkgName, valid}]}).

override_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, SrcDeps}]),

    RebarConfig = [
        {deps, TopDeps},
        {overrides, [
            {override, some_dep, [
                {deps, []}
            ]}
        ]}
    ],
    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{dep, "some_dep"},
              {dep_not_exist, "other_dep"}]}
    ).

git_subdir_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(git_subdir, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_subdir_resource:mock([{deps, SrcDeps}]),

    RebarConfig = [
        {deps, TopDeps}
    ],
    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{subdir_dep, "some_dep"},
              {subdir_dep, "other_dep"}]}
    ).

override_add_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    DepA = {dep_a, "0.0.1", {git, "http://site.com/dep_a.git", {tag, "0.0.1"}}},
    DepB = {dep_b, "0.0.1", {git, "http://site.com/dep_b.git", {tag, "0.0.1"}}},
    DepC = {dep_c, "0.0.1", {git, "http://site.com/dep_c.git", {tag, "0.0.1"}}},

    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, [DepA, DepB, DepC | SrcDeps]}]),

    RebarConfig = [
        {deps, TopDeps},
        {overrides, [
            {add, some_dep, [
                {deps, [DepA, DepB]}
            ]},
            {add, [
                {deps, [DepC]}
            ]}
        ]}
    ],
    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{dep, "some_dep"},
              {dep, "other_dep"},
              {dep, "dep_a"},
              {dep, "dep_b"},
              {dep, "dep_c"}]}
    ).

override_del_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"dep_a", "0.0.1", []},
                                                                     {"dep_b", "0.0.1", []},
                                                                     {"dep_c", "0.0.1", []}]},
                                              {"other_dep", "0.0.1", [{"dep_c", "0.0.1", []},
                                                                      {"dep_d", "0.0.1", []},
                                                                      {"dep_e", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    DepA = {dep_a, "0.0.1", {git, "https://example.org/user/dep_a.git", {tag, "0.0.1"}}},
    DepB = {dep_b, "0.0.1", {git, "https://example.org/user/dep_b.git", {tag, "0.0.1"}}},
    DepC = {dep_c, "0.0.1", {git, "https://example.org/user/dep_c.git", {tag, "0.0.1"}}},

    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, SrcDeps}]),

    RebarConfig = [
        {deps, TopDeps},
        {overrides, [
            {del, some_dep, [
                {deps, [DepA, DepB]}
            ]},
            {del, [
                {deps, [DepC, dep_e]}
            ]}
        ]}
    ],

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{dep, "some_dep"},
              {dep, "other_dep"},
              {dep_not_exist, "dep_a"},
              {dep_not_exist, "dep_b"},
              {dep_not_exist, "dep_c"},
              {dep_not_exist, "dep_e"},
              {dep, "dep_d"}]}
    ).

override_del_pkg_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(pkg, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    {_, PkgDeps} = rebar_test_utils:flat_deps(Deps),
    mock_pkg_resource:mock([{pkgdeps, PkgDeps}]),

    RebarConfig = [
        {deps, TopDeps},
        {overrides, [
            {del, some_dep, [
                {deps, [other_dep]},
                %% regression: a non-existing option deletion
                %% could trigger an infinite loop
                {provider_hooks, [{post, [{compile, xref}]}]}
            ]}
        ]}
    ],

    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{dep, "some_dep"},
              {dep_not_exist, "other_dep"}]}
    ).

override_opts(Config) ->
    AppsDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir = filename:join([AppsDir, "apps", Name]),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [
        {erl_opts, [
            compressed,
            warn_missing_spec
        ]},
        {overrides, [
            {override, [
                {erl_opts, [compressed]}
            ]}
        ]}
    ],

    rebar_test_utils:create_config(AppsDir, RebarConfig),

    rebar_test_utils:run_and_check(
         Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    Path = filename:join([AppsDir, "_build", "default", "lib", Name, "ebin"]),
    code:add_patha(Path),

    Mod = list_to_atom("not_a_real_src_" ++ Name),

    true = lists:member(compressed, proplists:get_value(options, Mod:module_info(compile), [])),
    false = lists:member(warn_missing_spec, proplists:get_value(options, Mod:module_info(compile), [])).

%% test for fix of https://github.com/erlang/rebar3/issues/1801
%% only apply overrides once
%% verify by having an override add the macro TEST to the dep some_dep
%% building under `ct` will fail if the `add` is applied more than once
apply_overrides_exactly_once(Config) ->
    AppDir = ?config(apps, Config),

    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, SrcDeps}]),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{deps, TopDeps},
                   {overrides, [
                                {add, some_dep, [
                                             {erl_opts, [{d, 'TEST'}]}
                                            ]}
                               ]}],

    rebar_test_utils:create_config(AppDir, RebarConfig),

    rebar_test_utils:run_and_check(
      Config, RebarConfig, ["ct", "--compile_only"], {ok, [{app, Name}, {dep, "some_dep"}], "test"}).

override_only_deps(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [
        {deps, []}, %% with deps enabled, this test fails
        {overrides, [
            {add, [
                {erl_opts, [{d, bad, a}, {d, bad, b}]}
            ]}
        ]}
    ],

    rebar_test_utils:create_config(AppDir, RebarConfig),

    rebar_test_utils:run_and_check(
         Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    ok.

override_add_opts(Config) ->
    AppsDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir = filename:join([AppsDir, "apps", Name]),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [
        {erl_opts, [
            warn_missing_spec
        ]},
        {overrides, [
            {add, [
                {erl_opts, [compressed]}
            ]}
        ]}
    ],

    rebar_test_utils:create_config(AppsDir, RebarConfig),

    rebar_test_utils:run_and_check(
         Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    Path = filename:join([AppsDir, "_build", "default", "lib", Name, "ebin"]),
    code:add_patha(Path),

    Mod = list_to_atom("not_a_real_src_" ++ Name),

    true = lists:member(compressed, proplists:get_value(options, Mod:module_info(compile), [])),
    true = lists:member(warn_missing_spec, proplists:get_value(options, Mod:module_info(compile), [])).

override_del_opts(Config) ->
    AppsDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir = filename:join([AppsDir, "apps", Name]),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [
        {erl_opts, [
            compressed,
            warn_missing_spec
        ]},
        {overrides, [
            {del, [
                {erl_opts, [warn_missing_spec]}
            ]}
        ]}
    ],

    rebar_test_utils:create_config(AppsDir, RebarConfig),

    rebar_test_utils:run_and_check(
         Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    Path = filename:join([AppsDir, "_build", "default", "lib", Name, "ebin"]),
    code:add_patha(Path),

    Mod = list_to_atom("not_a_real_src_" ++ Name),

    true = lists:member(compressed, proplists:get_value(options, Mod:module_info(compile), [])),
    false = lists:member(warn_missing_spec, proplists:get_value(options, Mod:module_info(compile), [])),
    ok.

profile_override_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, SrcDeps}]),

    RebarConfig = [
        {deps, TopDeps},
        {profiles, [
            {a, [
                {overrides, [
                    {override, some_dep, [
                        {deps, []}
                    ]}
                ]}
            ]}
        ]}],
    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["as", "a", "compile"],
        {ok, [{dep, "some_dep"},
              {dep_not_exist, "other_dep"}]}
    ).

profile_override_add_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    DepA = {dep_a, "0.0.1", {git, "http://site.com/dep_a.git", {tag, "0.0.1"}}},
    DepB = {dep_b, "0.0.1", {git, "http://site.com/dep_b.git", {tag, "0.0.1"}}},
    DepC = {dep_c, "0.0.1", {git, "http://site.com/dep_c.git", {tag, "0.0.1"}}},

    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, [DepA, DepB, DepC | SrcDeps]}]),

    RebarConfig = [
        {deps, TopDeps},
        {profiles, [
            {a, [
                {overrides, [
                    {add, some_dep, [
                        {deps, [DepA, DepB]}
                    ]},
                    {add, [
                        {deps, [DepC]}
                    ]}
                ]}
            ]}
        ]}
    ],
    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["as", "a", "compile"],
        {ok, [{dep, "some_dep"},
              {dep, "other_dep"},
              {dep, "dep_a"},
              {dep, "dep_b"},
              {dep, "dep_c"}]}
    ).

profile_override_del_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"dep_a", "0.0.1", []},
                                                                     {"dep_b", "0.0.1", []},
                                                                     {"dep_c", "0.0.1", []}]},
                                              {"other_dep", "0.0.1", [{"dep_c", "0.0.1", []},
                                                                      {"dep_d", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    DepA = {dep_a, "0.0.1", {git, "https://example.org/user/dep_a.git", {tag, "0.0.1"}}},
    DepB = {dep_b, "0.0.1", {git, "https://example.org/user/dep_b.git", {tag, "0.0.1"}}},
    DepC = {dep_c, "0.0.1", {git, "https://example.org/user/dep_c.git", {tag, "0.0.1"}}},

    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, SrcDeps}]),

    RebarConfig = [
        {deps, TopDeps},
        {profiles, [
            {a, [
                {overrides, [
                    {del, some_dep, [
                        {deps, [DepA, DepB]}
                    ]},
                    {del, [
                        {deps, [DepC]}
                    ]}
                ]}
            ]}
        ]}
    ],
    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["as", "a", "compile"],
        {ok, [{dep, "some_dep"},
              {dep, "other_dep"},
              {dep_not_exist, "dep_a"},
              {dep_not_exist, "dep_b"},
              {dep_not_exist, "dep_c"},
              {dep, "dep_d"}]}
    ).

profile_override_opts(Config) ->
    AppsDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir = filename:join([AppsDir, "apps", Name]),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [
        {erl_opts, [
            compressed,
            warn_missing_spec
        ]},
        {profiles, [
            {a, [
                {overrides, [
                    {override, [
                        {erl_opts, [compressed]}
                    ]}
                ]}
            ]}
        ]}
    ],

    rebar_test_utils:create_config(AppsDir, RebarConfig),

    rebar_test_utils:run_and_check(
         Config, RebarConfig, ["as", "a", "compile"], {ok, [{app, Name}]}),

    Path = filename:join([AppsDir, "_build", "a", "lib", Name, "ebin"]),
    code:add_patha(Path),

    Mod = list_to_atom("not_a_real_src_" ++ Name),

    true = lists:member(compressed, proplists:get_value(options, Mod:module_info(compile), [])),
    false = lists:member(warn_missing_spec, proplists:get_value(options, Mod:module_info(compile), [])).

profile_override_add_opts(Config) ->
    AppsDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir = filename:join([AppsDir, "apps", Name]),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [
        {erl_opts, [
            warn_missing_spec
        ]},
        {profiles, [
            {a, [
                {overrides, [
                    {add, [
                        {erl_opts, [compressed]}
                    ]}
                ]}
            ]}
        ]}
    ],

    rebar_test_utils:create_config(AppsDir, RebarConfig),

    rebar_test_utils:run_and_check(
         Config, RebarConfig, ["as", "a", "compile"], {ok, [{app, Name}]}),

    Path = filename:join([AppsDir, "_build", "a", "lib", Name, "ebin"]),
    code:add_patha(Path),

    Mod = list_to_atom("not_a_real_src_" ++ Name),

    true = lists:member(compressed, proplists:get_value(options, Mod:module_info(compile), [])),
    true = lists:member(warn_missing_spec, proplists:get_value(options, Mod:module_info(compile), [])).

profile_override_del_opts(Config) ->
    AppsDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir = filename:join([AppsDir, "apps", Name]),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [
        {erl_opts, [
            compressed,
            warn_missing_spec
        ]},
        {profiles, [
            {a, [
                {overrides, [
                    {del, [
                        {erl_opts, [warn_missing_spec]}
                    ]}
                ]}
            ]}
        ]}
    ],

    rebar_test_utils:create_config(AppsDir, RebarConfig),

    rebar_test_utils:run_and_check(
         Config, RebarConfig, ["as", "a", "compile"], {ok, [{app, Name}]}),

    Path = filename:join([AppsDir, "_build", "a", "lib", Name, "ebin"]),
    code:add_patha(Path),

    Mod = list_to_atom("not_a_real_src_" ++ Name),

    true = lists:member(compressed, proplists:get_value(options, Mod:module_info(compile), [])),
    false = lists:member(warn_missing_spec, proplists:get_value(options, Mod:module_info(compile), [])),
    ok.

profile_deps(Config) ->
    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),
    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, SrcDeps}]),

    RebarConfig = [
        {deps, TopDeps},
        {profiles, [{a, []}]}],
    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["as", "a", "compile"],
        {ok, [{dep, "some_dep"},{dep, "other_dep"}]}
    ).

only_deps(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", [{"other_dep", "0.0.1", []}]}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),
    {SrcDeps, _} = rebar_test_utils:flat_deps(Deps),
    mock_git_resource:mock([{deps, SrcDeps}]),

    RConfFile = rebar_test_utils:create_config(AppDir, [{deps, TopDeps}]),
    {ok, RConf} = file:consult(RConfFile),
    rebar_test_utils:run_and_check(
        Config, RConf, ["compile", "--deps_only"],
        {ok, [{app_not_exist, Name}, {dep, "some_dep"},{dep, "other_dep"}]}
    ).

%% verify a deps prod profile is used
%% tested by checking prod hooks run and outputs to default profile dir for dep
%% and prod deps are installed for dep
deps_build_in_prod(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    GitDeps = rebar_test_utils:expand_deps(git, [{"asdf", "1.0.0", []}]),
    PkgName = rebar_test_utils:create_random_name("pkg1_"),
    {SrcDeps, _} = rebar_test_utils:flat_deps(GitDeps),
    mock_git_resource:mock([{deps, SrcDeps},
                            {config, [{profiles, [{prod, [{pre_hooks, [{compile, "echo whatsup > randomfile"}]},
                                                          {deps, [list_to_atom(PkgName)]}]}]}]}]),

    mock_pkg_resource:mock([{pkgdeps, [{{iolist_to_binary(PkgName), <<"0.1.0">>}, []}]}]),

    Deps = rebar_test_utils:top_level_deps(GitDeps),
    RConfFile = rebar_test_utils:create_config(AppDir, [{deps, Deps}]),
    {ok, RConf} = file:consult(RConfFile),

    %% Build with deps.
    rebar_test_utils:run_and_check(
        Config, RConf, ["compile"],
        {ok, [{app, Name}, {dep, "asdf", <<"1.0.0">>}, {dep, PkgName},
              {file, filename:join([AppDir, "_build", "default", "lib", "asdf", "randomfile"])}]}
    ).

%% verify that the proper include path is defined
%% according the erlang doc which states:
%%      If the filename File is absolute (possibly after variable substitution),
%%      the include file with that name is included. Otherwise, the specified file
%%      is searched for in the following directories, and in this order:
%%          * The current working directory
%%          * The directory where the module is being compiled
%%          * The directories given by the include option
include_file_relative_to_working_directory(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Src = <<"-module(test).\n"
"\n"
"-include(\"include/test.hrl\").\n"
"\n"
"test() -> ?TEST_MACRO.\n"
"\n">>,
    Include = <<"-define(TEST_MACRO, test).\n">>,

    ok = filelib:ensure_dir(filename:join([AppDir, "src", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "src", "test.erl"]), Src),

    ok = filelib:ensure_dir(filename:join([AppDir, "include", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "include", "test.hrl"]), Include),

    RebarConfig = [],
    rebar_test_utils:run_and_check(Config, RebarConfig,
                                   ["compile"],
                                   {ok, [{app, Name}]}).

include_file_in_src(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Src = <<"-module(test).\n"
"\n"
"-include(\"test.hrl\").\n"
"\n"
"test() -> ?TEST_MACRO.\n"
"\n">>,
    Include = <<"-define(TEST_MACRO, test).\n">>,

    ok = filelib:ensure_dir(filename:join([AppDir, "src", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "src", "test.erl"]), Src),

    ok = file:write_file(filename:join([AppDir, "src", "test.hrl"]), Include),

    RebarConfig = [],
    rebar_test_utils:run_and_check(Config, RebarConfig,
                                   ["compile"],
                                   {ok, [{app, Name}]}).

%% verify that the proper include path is defined
%% according the erlang doc which states:
%%      If the filename File is absolute (possibly after variable substitution),
%%      the include file with that name is included. Otherwise, the specified file
%%      is searched for in the following directories, and in this order:
%%          * The current working directory
%%          * The directory where the module is being compiled
%%          * The directories given by the include option
%%
%% This test ensures that things keep working when additional directories
%% are used for apps, such as the test/ directory within the test profile.
include_file_relative_to_working_directory_test(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Src = <<"-module(test).\n"
"\n"
"-include(\"include/test.hrl\").\n"
"\n"
"test() -> ?TEST_MACRO.\n"
"\n">>,
    Include = <<"-define(TEST_MACRO, test).\n">>,

    ok = filelib:ensure_dir(filename:join([AppDir, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppDir, "test", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "test", "test.erl"]), Src),

    ok = filelib:ensure_dir(filename:join([AppDir, "include", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "include", "test.hrl"]), Include),

    RebarConfig = [],
    rebar_test_utils:run_and_check(Config, RebarConfig,
                                   ["as", "test", "compile"],
                                   {ok, [{app, Name}]}).

%% Same as `include_file_in_src/1' but using the `test/' directory
%% within the test profile.
include_file_in_src_test(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Src = <<"-module(test).\n"
"\n"
"-include(\"test.hrl\").\n"
"\n"
"test() -> ?TEST_MACRO.\n"
"\n">>,
    Include = <<"-define(TEST_MACRO, test).\n">>,

    ok = filelib:ensure_dir(filename:join([AppDir, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppDir, "test", "dummy"])),
    ok = file:write_file(filename:join([AppDir, "test", "test.erl"]), Src),

    ok = file:write_file(filename:join([AppDir, "src", "test.hrl"]), Include),

    RebarConfig = [],
    rebar_test_utils:run_and_check(Config, RebarConfig,
                                   ["as", "test", "compile"],
                                   {ok, [{app, Name}]}).

%% Same as `include_file_in_src_test/1' but using multiple top-level
%% apps as dependencies.
include_file_in_src_test_multiapp(Config) ->

    Name1 = rebar_test_utils:create_random_name("app2_"),
    Name2 = rebar_test_utils:create_random_name("app1_"),
    AppDir1 = filename:join([?config(apps, Config), "lib", Name1]),
    AppDir2 = filename:join([?config(apps, Config), "lib", Name2]),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir1, Name1, Vsn, [kernel, stdlib, list_to_atom(Name2)]),
    rebar_test_utils:create_app(AppDir2, Name2, Vsn, [kernel, stdlib]),

    Src = "-module(test).\n"
"\n"
"-include_lib(\"" ++ Name2 ++ "/include/test.hrl\").\n"
"\n"
"test() -> ?TEST_MACRO.\n"
"\n",
    Include = <<"-define(TEST_MACRO, test).\n">>,

    ok = filelib:ensure_dir(filename:join([AppDir1, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppDir1, "test", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppDir2, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppDir2, "include", "dummy"])),
    ok = file:write_file(filename:join([AppDir1, "test", "test.erl"]), Src),

    ok = file:write_file(filename:join([AppDir2, "include", "test.hrl"]), Include),

    RebarConfig = [],
    rebar_test_utils:run_and_check(Config, RebarConfig,
                                   ["as", "test", "compile"],
                                   {ok, [{app, Name1}]}),
    ok.

%% this test sets the env var, compiles, records the file last modified timestamp,
%% recompiles and compares the file last modified timestamp to ensure it hasn't
%% changed. this test should run on 19.x+
dont_recompile_when_erl_compiler_options_env_does_not_change(Config) ->
    %% save existing env to restore after test
    ExistingEnv = os:getenv("ERL_COMPILER_OPTIONS"),

    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("erl_compiler_options_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    true = os:unsetenv("ERL_COMPILER_OPTIONS"),

    true = os:putenv("ERL_COMPILER_OPTIONS", "[{d, some_macro}]"),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),

    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime == NewModTime),

    %% restore existing env
    case ExistingEnv of
        false -> ok;
        _     -> os:putenv("ERL_COMPILER_OPTIONS", ExistingEnv)
    end.

%% this test compiles, records the file last modified timestamp, sets the env
%% var, recompiles and compares the file last modified timestamp to ensure it
%% has changed. this test should run on 19.x+
recompile_when_erl_compiler_options_env_changes(Config) ->
    %% save existing env to restore after test
    ExistingEnv = os:getenv("ERL_COMPILER_OPTIONS"),

    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("erl_compiler_options_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    true = os:unsetenv("ERL_COMPILER_OPTIONS"),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),

    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    true = os:putenv("ERL_COMPILER_OPTIONS", "[{d, some_macro}]"),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime),

    %% restore existing env
    case ExistingEnv of
        false -> ok;
        _     -> os:putenv("ERL_COMPILER_OPTIONS", ExistingEnv)
    end.

rebar_config_os_var(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("rebar_config_os_var_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    rebar_test_utils:create_config(AppDir, [{erl_opts, []}]),

    AltConfig = filename:join(AppDir, "test.rebar.config"),
    file:write_file(AltConfig, "{erl_opts, [compressed]}."),
    true = os:putenv("REBAR_CONFIG", AltConfig),

    rebar_test_utils:run_and_check(Config, ["compile"], {ok, [{app, Name}]}),

    Path = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    code:add_patha(Path),

    Mod = list_to_atom("not_a_real_src_" ++ Name),

    true = lists:member(compressed, proplists:get_value(options, Mod:module_info(compile), [])),
    ok.

%% this test sets the env var, compiles, records the file last modified
%% timestamp, recompiles and compares the file last modified timestamp to
%% ensure it has changed. this test should run on 18.x
always_recompile_when_erl_compiler_options_set(Config) ->
    %% save existing env to restore after test
    ExistingEnv = os:getenv("ERL_COMPILER_OPTIONS"),

    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("erl_compiler_options_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    true = os:unsetenv("ERL_COMPILER_OPTIONS"),

    true = os:putenv("ERL_COMPILER_OPTIONS", "[{d, some_macro}]"),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),

    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:extension(F) == ".beam"],

    timer:sleep(1000),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:extension(F) == ".beam"],

    ?assert(ModTime =/= NewModTime),

    %% restore existing env
    case ExistingEnv of
        false -> ok;
        _     -> os:putenv("ERL_COMPILER_OPTIONS", ExistingEnv)
    end.

recompile_when_parse_transform_inline_changes(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("parse_transform_inline_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    ok = filelib:ensure_dir(filename:join([AppDir, "src", "dummy"])),

    ModSrc = <<"-module(example).\n"
               "-export([foo/2]).\n"
               "-compile([{parse_transform, example_parse_transform}]).\n"
               "foo(_, _) -> ok.">>,

    ok = file:write_file(filename:join([AppDir, "src", "example.erl"]),
                         ModSrc),

    ParseTransform = <<"-module(example_parse_transform).\n"
                       "-export([parse_transform/2]).\n"
                       "parse_transform(AST, _) -> AST.\n">>,

    ok = file:write_file(filename:join([AppDir, "src", "example_parse_transform.erl"]),
                         ParseTransform),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:basename(F, ".beam") == "example"],

    timer:sleep(1000),

    NewParseTransform = <<"-module(example_parse_transform).\n"
                          "-export([parse_transform/2]).\n"
                          "parse_transform(AST, _) -> identity(AST).\n"
                          "identity(AST) -> AST.\n">>,

    ok = file:write_file(filename:join([AppDir, "src", "example_parse_transform.erl"]),
                         NewParseTransform),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:basename(F, ".beam") == "example"],

    ?assert(ModTime =/= NewModTime).

recompile_when_parse_transform_as_opt_changes(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("parse_transform_opt_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    ok = filelib:ensure_dir(filename:join([AppDir, "src", "dummy"])),

    ModSrc = <<"-module(example).\n"
               "-export([foo/2]).\n"
               "foo(_, _) -> ok.">>,

    ok = file:write_file(filename:join([AppDir, "src", "example.erl"]),
                         ModSrc),

    ParseTransform = <<"-module(example_parse_transform).\n"
                       "-export([parse_transform/2]).\n"
                       "parse_transform(AST, _) -> AST.">>,

    ok = file:write_file(filename:join([AppDir, "src", "example_parse_transform.erl"]),
                         ParseTransform),

    RebarConfig = [{erl_opts, [{parse_transform, example_parse_transform}]}],

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ModTime = [filelib:last_modified(filename:join([EbinDir, F]))
               || F <- Files, filename:basename(F, ".beam") == "example"],

    timer:sleep(1000),

    NewParseTransform = <<"-module(example_parse_transform).\n"
                          "-export([parse_transform/2]).\n"
                          "parse_transform(AST, _) -> identity(AST).\n"
                          "identity(AST) -> AST.">>,

    ok = file:write_file(filename:join([AppDir, "src", "example_parse_transform.erl"]),
                         NewParseTransform),

    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name}]}),

    {ok, NewFiles} = rebar_utils:list_dir(EbinDir),
    NewModTime = [filelib:last_modified(filename:join([EbinDir, F]))
                  || F <- NewFiles, filename:basename(F, ".beam") == "example"],

    ?assert(ModTime =/= NewModTime).

recursive(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    rebar_test_utils:write_src_file(filename:join(AppDir,src),"rec.erl"),

    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name}]}),

    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files} = rebar_utils:list_dir(EbinDir),
    ?assert(lists:member("rec.beam",Files)),

    %% check that rec is in modules list of .app file
    AppFile = filename:join(EbinDir, Name++".app"),
    {ok, [{application, _, List}]} = file:consult(AppFile),
    {modules, Modules} = lists:keyfind(modules, 1, List),
    ?assert(lists:member(rec, Modules)).

no_recursive(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    rebar_test_utils:write_src_file(filename:join(AppDir,src),"rec.erl"),

    RebarConfig1 = [{erlc_compiler,[{recursive,false}]}],
    rebar_test_utils:run_and_check(Config, RebarConfig1, ["compile"],
                                   {ok, [{app, Name}]}),
    EbinDir = filename:join([AppDir, "_build", "default", "lib", Name, "ebin"]),
    {ok, Files1} = rebar_utils:list_dir(EbinDir),
    ?assert(false==lists:member("rec.beam",Files1)),

    RebarConfig2 = [{src_dirs,[{"src",[{recursive,false}]}]}],
    rebar_test_utils:run_and_check(Config, RebarConfig2, ["compile"],
                                   {ok, [{app, Name}]}),
    {ok, Files2} = rebar_utils:list_dir(EbinDir),
    ?assert(false==lists:member("rec.beam",Files2)),
    ok.

extra_recursion(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    rebar_test_utils:write_src_file(filename:join([AppDir, "src", "src2"]), "rec.erl"),
    rebar_test_utils:write_src_file(filename:join([AppDir, "test", "test2"]), "rectest.erl"),

    %% Default for src directories: recursive
    %% default for extra_src directories: non-recursive
    RebarConfig1 = [],
    rebar_test_utils:run_and_check(Config, RebarConfig1, ["as", "test", "compile"],
                                   {ok, [{app, Name}]}),
    EbinDir = filename:join([AppDir, "_build", "test", "lib", Name, "ebin"]),
    {ok, Files1} = rebar_utils:list_dir(EbinDir),
    ?assert(lists:member("rec.beam", Files1)),
    file:delete(filename:join(EbinDir, "rec.beam")),

    TestEbinDir = filename:join([AppDir, "_build", "test", "lib", Name, "test"]),
    {ok, TestFiles1} = rebar_utils:list_dir(TestEbinDir),
    ?assertNot(lists:member("rectest.beam", TestFiles1)),

    RebarConfig2 = [{src_dirs,[{"src",[{recursive,false}]}]},
                    {extra_src_dirs, [{"test", [{recursive, true}]}]}],
    rebar_test_utils:run_and_check(Config, RebarConfig2, ["as", "test", "compile"],
                                   {ok, [{app, Name}]}),
    {ok, Files2} = rebar_utils:list_dir(EbinDir),
    ?assertNot(lists:member("rec.beam",Files2)),

    {ok, TestFiles2} = rebar_utils:list_dir(TestEbinDir),
    ?assert(lists:member("rectest.beam", TestFiles2)),
    ok.

regex_filter_skip(Config) ->
    AppDir = ?config(apps, Config),
    Name = rebar_test_utils:create_random_name("regex_skip"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    rebar_test_utils:write_src_file(filename:join(AppDir,src),"._rec.erl"),
    Expected = filename:join([AppDir, "_build", "default", "lib", Name, "ebin","._rec.beam"]),

    RebarConfig = [],
    try
        rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"],
                                             {ok, [{file, Expected}]}),
        throw(should_not_be_found)
    catch
        %% the file was not found, as desired!
        error:{assertion_failed,_} -> %% OTP =< 17
            ok;
        error:{assert,_} -> %% OTP >= 18
            ok
    end.

regex_filter_regression(Config) ->
    AppDir = ?config(apps, Config),
    Name = rebar_test_utils:create_random_name("regex_regression"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    rebar_test_utils:write_src_file(filename:join(AppDir,src),"r_f.erl"),
    Expected = filename:join([AppDir, "_build", "default", "lib", Name, "ebin","r_f.beam"]),
    RebarConfig = [],
    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"],
                                   {ok, [{file, Expected}]}),
    ok.

%% This test could also have existed in rebar_hooks_SUITE but it's more
%% about compiler implementation details than the hook logic itself,
%% so it was located here.
split_project_apps_hooks() ->
    [{doc, "Ensure that a project with multiple project apps runs the "
           "pre-hooks before all the apps are compiled, and the post "
           "hooks after they are all compiled."}].
split_project_apps_hooks(Config) ->
    BaseDir = ?config(apps, Config),
    Name1 = rebar_test_utils:create_random_name("app2_"),
    Name2 = rebar_test_utils:create_random_name("app1_"),
    AppDir1 = filename:join([BaseDir, "lib", Name1]),
    AppDir2 = filename:join([BaseDir, "lib", Name2]),
    HookDir = filename:join([BaseDir, "hooks"]),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir1, Name1, Vsn, [kernel, stdlib, list_to_atom(Name2)]),
    rebar_test_utils:create_app(AppDir2, Name2, Vsn, [kernel, stdlib]),

    ok = filelib:ensure_dir(filename:join([AppDir1, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppDir1, "test", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppDir2, "src", "dummy"])),
    ok = filelib:ensure_dir(filename:join([AppDir2, "include", "dummy"])),
    ok = filelib:ensure_dir(filename:join([HookDir, "dummy"])),
    Cmd = case os:type() of
        {win32, _} -> "dir /B";
        _ -> "ls"
    end,
    Cfg = fun(Name) ->
        [{pre_hooks, [{compile,      Cmd++" \""++HookDir++"\" > \""++filename:join(HookDir, "pre-compile-"++Name)++"\""},
                      {erlc_compile, Cmd++" \""++HookDir++"\" > \""++filename:join(HookDir, "pre-erlc-"++Name)++"\""},
                      {app_compile,  Cmd++" \""++HookDir++"\" > \""++filename:join(HookDir, "pre-app-"++Name)++"\""}]},
         {post_hooks, [{compile,      Cmd++" \""++HookDir++"\" > \""++filename:join(HookDir, "post-compile-"++Name)++"\""},
                       {erlc_compile, Cmd++" \""++HookDir++"\" > \""++filename:join(HookDir, "post-erlc-"++Name)++"\""},
                       {app_compile,  Cmd++" \""++HookDir++"\" > \""++filename:join(HookDir, "post-app-"++Name)++"\""}]}
        ]
    end,
    ok = file:write_file(filename:join(AppDir1, "rebar.config"),
                         io_lib:format("~p.~n~p.", Cfg("app1"))),
    ok = file:write_file(filename:join(AppDir2, "rebar.config"),
                         io_lib:format("~p.~n~p.", Cfg("app2"))),
    RebarConfig = Cfg("all"),
    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"],
                                   {ok, [{app, Name1}, {app, Name2}]}),
    %% Now for the big party:
    %% - we expect whole pre-hooks to run before either app is compiled
    %% - we don't expect app and erlc hooks on the total run
    %% - we expect app2 to be compiled before app1 (rev alphabetical order)
    %% - we expect all pre-hooks to show up before post-hooks
    %% - the pre-order is: compile->erlc, taking place before any app
    %%   is actually compiled, so that analysis can be done on all apps.
    %% - the post-order is more as expected:
    %%   - erlc post hook runs right with the app
    %%   - app pre hook runs right with the app
    %%   - app post hook runs right with the app
    %%   - compile post hook runs for each app individually
    %% - we expect app compile post-hooks to show up in order
    %% - we expect whole post-hooks to run last
    CallOrder = [
        "pre-compile-all",
        "pre-compile-app2",
        "pre-compile-app1",
        "pre-erlc-app2",
        "pre-erlc-app1",
        "post-erlc-app2",
        "post-erlc-app1",
        "pre-app-app2",
        "pre-app-app1",
        "post-app-app2",
        "post-app-app1",
        "post-compile-app2",
        "post-compile-app1",
        "post-compile-all"
    ],
    validate_call_order(CallOrder, HookDir),
    ok.

validate_call_order(Calls, Dir) -> validate_call_order(Calls, Dir, []).

validate_call_order([], _, _) ->
    ok;
validate_call_order([Name|T], Dir, Seen) ->
    {ok, Bin} = file:read_file(filename:join(Dir, Name)),
    %% weird list of tokens, but works on lexemes/tokens for backwards compat
    Found = rebar_string:lexemes(binary_to_list(Bin), [$\n, $\r, "\r\n"]),
    NewSeen = [Name|Seen],
    ?assertEqual({Name, Found}, {Name, lists:sort(NewSeen)}),
    validate_call_order(T, Dir, NewSeen).

app_file_linting(Config) ->
    meck:new(rebar_log, [no_link, passthrough]),
    AppDir = ?config(apps, Config),
    Name = rebar_test_utils:create_random_name("app_file_linting"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [foo]),

    _ = rebar_test_utils:run_and_check(Config, [], ["compile"], return),
    History = meck:history(rebar_log),
    Warnings = [{Str, Args} || {_, {rebar_log, log, [warn, Str, Args]}, _} <- History],

    ?assert(none /= proplists:lookup("~p is missing description entry", Warnings)),
    ?assert(none /= proplists:lookup("~p is missing kernel from applications list", Warnings)),
    ?assert(none /= proplists:lookup("~p is missing stdlib from applications list", Warnings)).

%%

%% a copy of lib/parsetools/include/yeccpre.hrl so we can test yrl includefile
yeccpre_hrl() ->
    <<"-type yecc_ret() :: {'error', _} | {'ok', _}.

-spec parse(Tokens :: list()) -> yecc_ret().
parse(Tokens) ->
    yeccpars0(Tokens, {no_func, no_line}, 0, [], []).

-spec parse_and_scan({function() | {atom(), atom()}, [_]}
                     | {atom(), atom(), [_]}) -> yecc_ret().
parse_and_scan({F, A}) ->
    yeccpars0([], {{F, A}, no_line}, 0, [], []);
parse_and_scan({M, F, A}) ->
    Arity = length(A),
    yeccpars0([], {{fun M:F/Arity, A}, no_line}, 0, [], []).

-spec format_error(any()) -> [char() | list()].
format_error(Message) ->
    case io_lib:deep_char_list(Message) of
        true ->
            Message;
        _ ->
            io_lib:write(Message)
    end.

%% To be used in grammar files to throw an error message to the parser
%% toplevel. Doesn't have to be exported!
-compile({nowarn_unused_function, return_error/2}).
-spec return_error(integer(), any()) -> no_return().
return_error(Line, Message) ->
    throw({error, {Line, ?MODULE, Message}}).

-define(CODE_VERSION, \"1.4\").

yeccpars0(Tokens, Tzr, State, States, Vstack) ->
    try yeccpars1(Tokens, Tzr, State, States, Vstack)
    catch
        error:Error ->
            try yecc_error_type(Error, []) of
                Desc ->
                    erlang:raise(error, {yecc_bug, ?CODE_VERSION, Desc},
                                 [])
            catch _:_ -> erlang:raise(error, Error, [])
            end;
        %% Probably thrown from return_error/2:
        throw: {error, {_Line, ?MODULE, _M}} = Error ->
            Error
    end.

yecc_error_type(function_clause, _) ->
    not_implemented.

yeccpars1([Token | Tokens], Tzr, State, States, Vstack) ->
    yeccpars2(State, element(1, Token), States, Vstack, Token, Tokens, Tzr);
yeccpars1([], {{F, A},_Line}, State, States, Vstack) ->
    case apply(F, A) of
        {ok, Tokens, Endline} ->
            yeccpars1(Tokens, {{F, A}, Endline}, State, States, Vstack);
        {eof, Endline} ->
            yeccpars1([], {no_func, Endline}, State, States, Vstack);
        {error, Descriptor, _Endline} ->
            {error, Descriptor}
    end;
yeccpars1([], {no_func, no_line}, State, States, Vstack) ->
    Line = 999999,
    yeccpars2(State, '$end', States, Vstack, yecc_end(Line), [],
              {no_func, Line});
yeccpars1([], {no_func, Endline}, State, States, Vstack) ->
    yeccpars2(State, '$end', States, Vstack, yecc_end(Endline), [],
              {no_func, Endline}).

%% yeccpars1/7 is called from generated code.
%%
%% When using the {includefile, Includefile} option, make sure that
%% yeccpars1/7 can be found by parsing the file without following
%% include directives. yecc will otherwise assume that an old
%% yeccpre.hrl is included (one which defines yeccpars1/5).
yeccpars1(State1, State, States, Vstack, Token0, [Token | Tokens], Tzr) ->
    yeccpars2(State, element(1, Token), [State1 | States],
              [Token0 | Vstack], Token, Tokens, Tzr);
yeccpars1(State1, State, States, Vstack, Token0, [], {{_F,_A}, _Line}=Tzr) ->
    yeccpars1([], Tzr, State, [State1 | States], [Token0 | Vstack]);
yeccpars1(State1, State, States, Vstack, Token0, [], {no_func, no_line}) ->
    Line = yecctoken_end_location(Token0),
    yeccpars2(State, '$end', [State1 | States], [Token0 | Vstack],
              yecc_end(Line), [], {no_func, Line});
yeccpars1(State1, State, States, Vstack, Token0, [], {no_func, Line}) ->
    yeccpars2(State, '$end', [State1 | States], [Token0 | Vstack],
              yecc_end(Line), [], {no_func, Line}).

%% For internal use only.
yecc_end({Line,_Column}) ->
    {'$end', Line};
yecc_end(Line) ->
    {'$end', Line}.

yecctoken_end_location(Token) ->
    try erl_anno:end_location(element(2, Token)) of
        undefined -> yecctoken_location(Token);
        Loc -> Loc
    catch _:_ -> yecctoken_location(Token)
    end.

-compile({nowarn_unused_function, yeccerror/1}).
yeccerror(Token) ->
    Text = yecctoken_to_string(Token),
    Location = yecctoken_location(Token),
    {error, {Location, ?MODULE, [\"syntax error before: \", Text]}}.

-compile({nowarn_unused_function, yecctoken_to_string/1}).
yecctoken_to_string(Token) ->
    try erl_scan:text(Token) of
        undefined -> yecctoken2string(Token);
        Txt -> Txt
    catch _:_ -> yecctoken2string(Token)
    end.

yecctoken_location(Token) ->
    try erl_scan:location(Token)
    catch _:_ -> element(2, Token)
    end.

-compile({nowarn_unused_function, yecctoken2string/1}).
yecctoken2string({atom, _, A}) -> io_lib:write_atom(A);
yecctoken2string({integer,_,N}) -> io_lib:write(N);
yecctoken2string({float,_,F}) -> io_lib:write(F);
yecctoken2string({char,_,C}) -> io_lib:write_char(C);
yecctoken2string({var,_,V}) -> io_lib:format(\"~s\", [V]);
yecctoken2string({string,_,S}) -> io_lib:write_string(S);
yecctoken2string({reserved_symbol, _, A}) -> io_lib:write(A);
yecctoken2string({_Cat, _, Val}) -> io_lib:format(\"~p\", [Val]);
yecctoken2string({dot, _}) -> \"'.'\";
yecctoken2string({'$end', _}) -> [];
yecctoken2string({Other, _}) when is_atom(Other) ->
    io_lib:write_atom(Other);
yecctoken2string(Other) ->
    io_lib:format(\"~p\", [Other]).
">>.
