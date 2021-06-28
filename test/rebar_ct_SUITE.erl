-module(rebar_ct_SUITE).

-export([all/0,
         groups/0,
         init_per_group/2,
         end_per_group/2]).
-export([basic_app_default_dirs/1,
         basic_app_default_beams/1,
         basic_app_ct_macro/1,
         multi_app_default_dirs/1,
         multi_app_default_beams/1,
         multi_app_ct_macro/1,
         no_ct_suite/1,
         single_app_dir/1,
         single_extra_dir/1,
         single_unmanaged_dir/1,
         single_suite/1,
         single_extra_suite/1,
         single_unmanaged_suite/1,
         multi_suite/1,
         all_suite/1,
         single_dir_and_single_suite/1,
         suite_at_root/1,
         suite_at_app_root/1,
         data_dir_correct/1,
         cmd_label/1,
         cmd_config/1,
         cmd_spec/1,
         cmd_join_specs/1,
         cmd_allow_user_terms/1,
         cmd_logdir/1,
         cmd_logopts/1,
         cmd_verbosity/1,
         cmd_repeat/1,
         cmd_duration/1,
         cmd_until/1,
         cmd_force_stop/1,
         cmd_basic_html/1,
         cmd_stylesheet/1,
         cmd_decrypt_key/1,
         cmd_decrypt_file/1,
         cmd_abort_if_missing_suites/1,
         cmd_multiply_timetraps/1,
         cmd_scale_timetraps/1,
         cmd_create_priv_dir/1,
         cmd_include_dir/1,
         cmd_sys_config/1,
         cfg_opts/1,
         cfg_arbitrary_opts/1,
         cfg_cover_spec/1,
         cfg_atom_suites/1,
         cover_compiled/1,
         cover_export_name/1,
         misspecified_ct_opts/1,
         misspecified_ct_compile_opts/1,
         misspecified_ct_first_files/1,
         testspec/1,
         testspec_at_root/1,
         testspec_parse_error/1,
         cmd_vs_cfg_opts/1,
         single_testspec_in_ct_opts/1,
         compile_only/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

all() -> [{group, basic_app},
          {group, multi_app},
          {group, dirs_and_suites},
          {group, data_dirs},
          {group, ct_opts},
          {group, cover},
          cfg_opts, cfg_arbitrary_opts,
          cfg_cover_spec,
          cfg_atom_suites,
          misspecified_ct_opts,
          misspecified_ct_compile_opts,
          misspecified_ct_first_files,
          testspec,
          testspec_at_root,
          testspec_parse_error,
          cmd_vs_cfg_opts,
          single_testspec_in_ct_opts,
          compile_only,
          no_ct_suite].

groups() -> [{basic_app, [], [basic_app_default_dirs,
                              basic_app_default_beams,
                              basic_app_ct_macro]},
             {multi_app, [], [multi_app_default_dirs,
                              multi_app_default_beams,
                              multi_app_ct_macro]},
             {dirs_and_suites, [], [single_app_dir,
                                    single_extra_dir,
                                    single_unmanaged_dir,
                                    single_suite,
                                    single_extra_suite,
                                    single_unmanaged_suite,
                                    multi_suite,
                                    all_suite,
                                    single_dir_and_single_suite,
                                    suite_at_root,
                                    suite_at_app_root]},
             {data_dirs, [], [data_dir_correct]},
             {ct_opts, [], [cmd_label,
                            cmd_config,
                            cmd_spec,
                            cmd_join_specs,
                            cmd_allow_user_terms,
                            cmd_logdir,
                            cmd_logopts,
                            cmd_verbosity,
                            cmd_repeat,
                            cmd_duration,
                            cmd_until,
                            cmd_force_stop,
                            cmd_basic_html,
                            cmd_stylesheet,
                            cmd_decrypt_key,
                            cmd_decrypt_file,
                            cmd_abort_if_missing_suites,
                            cmd_multiply_timetraps,
                            cmd_scale_timetraps,
                            cmd_create_priv_dir,
                            cmd_include_dir,
                            cmd_sys_config]},
             {cover, [], [cover_compiled,
                          cover_export_name]}].

init_per_group(basic_app, Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name(atom_to_list(basic_app) ++ "_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Suite = filename:join([AppDir, "test", Name ++ "_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite),
    ok = file:write_file(Suite, test_suite(Name)),

    {ok, State} = rebar_test_utils:run_and_check(C, [], ["as", "test", "lock"], return),

    Tests = rebar_prv_common_test:prepare_tests(State),
    {ok, NewState} = rebar_prv_common_test:compile(State, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    [{result, Opts}, {appnames, [Name]}, {compile_state, NewState}|C];
init_per_group(multi_app, Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_"),

    AppDir = ?config(apps, C),

    Name1 = rebar_test_utils:create_random_name(atom_to_list(multi_app) ++ "_"),
    Vsn1 = rebar_test_utils:create_random_vsn(),
    AppDir1 = filename:join([AppDir, "apps", Name1]),
    rebar_test_utils:create_app(AppDir1, Name1, Vsn1, [kernel, stdlib]),

    Suite1 = filename:join([AppDir1, "test", Name1 ++ "_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite1),
    ok = file:write_file(Suite1, test_suite(Name1)),

    Name2 = rebar_test_utils:create_random_name(atom_to_list(multi_app) ++ "_"),
    Vsn2 = rebar_test_utils:create_random_vsn(),
    AppDir2 = filename:join([AppDir, "apps", Name2]),
    rebar_test_utils:create_app(AppDir2, Name2, Vsn2, [kernel, stdlib]),

    Suite2 = filename:join([AppDir2, "test", Name2 ++ "_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite2),
    ok = file:write_file(Suite2, test_suite(Name2)),

    Suite3 = filename:join([AppDir, "test", "extras_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite3),
    ok = file:write_file(Suite3, test_suite("extras")),

    {ok, State} = rebar_test_utils:run_and_check(C, [], ["as", "test", "lock"], return),

    Tests = rebar_prv_common_test:prepare_tests(State),
    {ok, NewState} = rebar_prv_common_test:compile(State, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    [{result, Opts}, {appnames, [Name1, Name2]}, {compile_state, NewState}|C];
init_per_group(dirs_and_suites, Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_"),

    AppDir = ?config(apps, C),

    Name1 = rebar_test_utils:create_random_name(atom_to_list(dirs_and_suites) ++ "_"),
    Vsn1 = rebar_test_utils:create_random_vsn(),
    AppDir1 = filename:join([AppDir, "apps", Name1]),
    rebar_test_utils:create_app(AppDir1, Name1, Vsn1, [kernel, stdlib]),

    Suite1 = filename:join([AppDir1, "test", Name1 ++ "_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite1),
    ok = file:write_file(Suite1, test_suite(Name1)),

    Name2 = rebar_test_utils:create_random_name(atom_to_list(dir_and_suites) ++ "_"),
    Vsn2 = rebar_test_utils:create_random_vsn(),
    AppDir2 = filename:join([AppDir, "apps", Name2]),
    rebar_test_utils:create_app(AppDir2, Name2, Vsn2, [kernel, stdlib]),

    Suite2 = filename:join([AppDir2, "test", Name2 ++ "_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite2),
    ok = file:write_file(Suite2, test_suite(Name2)),

    Suite3 = filename:join([AppDir, "test", "extras_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite3),
    ok = file:write_file(Suite3, test_suite("extras")),

    Suite4 = filename:join([AppDir, "root_SUITE.erl"]),
    ok = file:write_file(Suite4, test_suite("root")),

    ok = file:write_file(filename:join([AppDir, "root_SUITE.hrl"]), <<>>),

    ok = filelib:ensure_dir(filename:join([AppDir, "root_SUITE_data", "dummy.txt"])),
    ok = file:write_file(filename:join([AppDir, "root_SUITE_data", "some_data.txt"]), <<>>),

    Suite5 = filename:join([AppDir, "apps", Name2, "app_root_SUITE.erl"]),
    ok = file:write_file(Suite5, test_suite("app_root")),

    ok = file:write_file(filename:join([AppDir, "apps", Name2, "app_root_SUITE.hrl"]), <<>>),

    ok = filelib:ensure_dir(filename:join([AppDir, "apps", Name2, "app_root_SUITE_data", "dummy.txt"])),
    ok = file:write_file(filename:join([AppDir, "apps", Name2, "app_root_SUITE_data", "some_data.txt"]), <<>>),

    {ok, State} = rebar_test_utils:run_and_check(C, [], ["as", "test", "lock"], return),

    [{s, State}, {appnames, [Name1, Name2]}|C];
init_per_group(ct_opts, Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_opts"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_opts_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    {ok, State} = rebar_test_utils:run_and_check(C, [], ["as", "test", "lock"], return),

    [{result, State}, {name, Name}|C];
init_per_group(cover, Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_opts"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_opts_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    {ok, State} = rebar_test_utils:run_and_check(C, [], ["as", "test", "lock"], return),

    [{result, State}, {name, Name}|C];
init_per_group(_, Config) -> Config.

end_per_group(_Group, _Config) -> ok.

basic_app_default_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name] = ?config(appnames, Config),
    Result = ?config(result, Config),

    Expect = filename:join([AppDir, "_build", "test", "lib", Name, "test"]),
    Dir = proplists:get_value(dir, Result),

    [Expect] = Dir.

basic_app_default_beams(Config) ->
    AppDir = ?config(apps, Config),
    [Name] = ?config(appnames, Config),

    File = filename:join([AppDir,
                          "_build",
                          "test",
                          "lib",
                          Name,
                          "test",
                          Name ++ "_SUITE.beam"]),

    true = filelib:is_file(File).

basic_app_ct_macro(Config) ->
    State = ?config(compile_state, Config),

    [App] = rebar_state:project_apps(State),
    Opts = rebar_app_info:opts(App),
    ErlOpts = dict:fetch(erl_opts, Opts),
    true = lists:member({d, 'COMMON_TEST'}, ErlOpts).


multi_app_default_dirs(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(appnames, Config),
    Result = ?config(result, Config),

    Expect1 = filename:absname(filename:join([AppDir, "_build", "test", "lib", Name1, "test"])),
    Expect2 = filename:absname(filename:join([AppDir, "_build", "test", "lib", Name2, "test"])),
    Expect3 = filename:absname(filename:join([AppDir, "_build", "test", "extras", "test"])),
    Dirs = proplists:get_value(dir, Result),

    true = (lists:sort([Expect1, Expect2, Expect3]) == lists:sort(Dirs)).

multi_app_default_beams(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(appnames, Config),

    File1 = filename:join([AppDir,
                           "_build",
                           "test",
                           "lib",
                           Name1,
                           "test",
                           Name1 ++ "_SUITE.beam"]),
    File2 = filename:join([AppDir,
                           "_build",
                           "test",
                           "lib",
                           Name2,
                           "test",
                           Name2 ++ "_SUITE.beam"]),
    File3 = filename:join([AppDir,
                           "_build",
                           "test",
                           "extras",
                           "test",
                           "extras_SUITE.beam"]),

    true = filelib:is_file(File1),
    true = filelib:is_file(File2),
    true = filelib:is_file(File3).

multi_app_ct_macro(Config) ->
    State = ?config(compile_state, Config),

    Apps = rebar_state:project_apps(State),
    lists:foreach(fun(App) ->
        Opts = rebar_app_info:opts(App),
        ErlOpts = dict:fetch(erl_opts, Opts),
        true = lists:member({d, 'COMMON_TEST'}, ErlOpts)
    end, Apps).

no_ct_suite(Config0) ->
    Config = rebar_test_utils:init_rebar_state(Config0),
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("no_ct_suite_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    {ok, State} = rebar_test_utils:run_and_check(Config, [], ["as", "test", "lock"], return),

    {ok, Opts} = rebar_prv_common_test:prepare_tests(State),

    undefined = proplists:get_value(dir, Opts),
    undefined = proplists:get_value(suite, Opts),
    undefined = proplists:get_value(spec, Opts),
    ok.

single_app_dir(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, _Name2] = ?config(appnames, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec,
                                      ["--dir=" ++ filename:join([AppDir,
                                                                  "apps",
                                                                  Name1,
                                                                  "test"])]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect = filename:join([AppDir, "_build", "test", "lib", Name1, "test"]),
    Dir = proplists:get_value(dir, Opts),

    [Expect] = Dir.

single_extra_dir(Config) ->
    AppDir = ?config(apps, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--dir=" ++ filename:join([AppDir,
                                                                              "test"])]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect = filename:join([AppDir, "_build", "test", "extras", "test"]),
    Dir = proplists:get_value(dir, Opts),

    [Expect] = Dir.

single_unmanaged_dir(Config) ->
    PrivDir = ?config(priv_dir, Config),
    State = ?config(s, Config),

    Suite = filename:join([PrivDir, "unmanaged_dir", "unmanaged_dir_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite),
    ok = file:write_file(Suite, test_suite("unmanaged_dir")),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--dir=" ++ filename:absname(filename:join([PrivDir,
                                                                                               "unmanaged_dir"]))]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect = filename:join([PrivDir, "unmanaged_dir"]),
    Dir = proplists:get_value(dir, Opts),

    [Expect] = Dir.

single_suite(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, _Name2] = ?config(appnames, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec,
                                      ["--suite=" ++ filename:join([AppDir,
                                                                    "apps",
                                                                    Name1,
                                                                    "test",
                                                                    Name1 ++ "_SUITE"])]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect = filename:join([AppDir,
                            "_build",
                            "test",
                            "lib",
                            Name1,
                            "test",
                            Name1 ++ "_SUITE"]),
    Suite = proplists:get_value(suite, Opts),

    [Expect] = Suite.

single_extra_suite(Config) ->
    AppDir = ?config(apps, Config),
    [_Name1, _Name2] = ?config(appnames, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec,
                                      ["--suite=" ++ filename:join([AppDir,
                                                                    "test",
                                                                    "extra_SUITE"])]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect = filename:join([AppDir,
                            "_build",
                            "test",
                            "extras",
                            "test",
                            "extra_SUITE"]),
    Suite = proplists:get_value(suite, Opts),

    [Expect] = Suite.

single_unmanaged_suite(Config) ->
    PrivDir = ?config(priv_dir, Config),
    [_Name1, _Name2] = ?config(appnames, Config),
    State = ?config(s, Config),

    Suite = filename:join([PrivDir, "unmanaged", "unmanaged_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite),
    ok = file:write_file(Suite, test_suite("unmanaged")),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec,
                                      ["--suite=" ++ filename:absname(filename:join([PrivDir,
                                                                                     "unmanaged",
                                                                                     "unmanaged_SUITE"]))]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect = filename:join([PrivDir,
                            "unmanaged",
                            "unmanaged_SUITE"]),
    SuitePath = proplists:get_value(suite, Opts),

    [Expect] = SuitePath.

multi_suite(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(appnames, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec,
                                      ["--suite=" ++ filename:join([AppDir,
                                                                    "apps",
                                                                    Name1,
                                                                    "test",
                                                                    Name1 ++ "_SUITE," ++ AppDir,
                                                                    "apps",
                                                                    Name2,
                                                                    "test",
                                                                    Name2 ++ "_SUITE"])]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect1 = filename:join([AppDir,
                             "_build",
                             "test",
                             "lib",
                             Name1,
                             "test",
                             Name1 ++ "_SUITE"]),
    Expect2 = filename:join([AppDir,
                             "_build",
                             "test",
                             "lib",
                             Name2,
                             "test",
                             Name2 ++ "_SUITE"]),
    Suites = proplists:get_value(suite, Opts),

    true = (lists:sort([Expect1, Expect2]) == lists:sort(Suites)).

all_suite(Config) ->
    AppDir = ?config(apps, Config),
    [Name1, Name2] = ?config(appnames, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec,
                                      ["--suite=" ++ filename:join([AppDir,
                                                                    "apps",
                                                                    Name1,
                                                                    "test",
                                                                    Name1 ++ "_SUITE," ++ AppDir,
                                                                    "apps",
                                                                    Name2,
                                                                    "test",
                                                                    Name2 ++ "_SUITE," ++ AppDir,
                                                                    "test",
                                                                    "extra_SUITE"])]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect1 = filename:join([AppDir,
                             "_build",
                             "test",
                             "lib",
                             Name1,
                             "test",
                             Name1 ++ "_SUITE"]),
    Expect2 = filename:join([AppDir,
                             "_build",
                             "test",
                             "lib",
                             Name2,
                             "test",
                             Name2 ++ "_SUITE"]),
    Expect3 = filename:join([AppDir,
                             "_build",
                             "test",
                             "extras",
                             "test",
                             "extra_SUITE"]),
    Suites = proplists:get_value(suite, Opts),

    true = (lists:sort([Expect1, Expect2, Expect3]) == lists:sort(Suites)).

single_dir_and_single_suite(Config) ->
    AppDir = ?config(apps, Config),
    [_Name1, _Name2] = ?config(appnames, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec,
                                      ["--dir=" ++ filename:join([AppDir, "test"]),
                                       "--suite=extra_SUITE"]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Expect = filename:join([AppDir,
                            "_build",
                            "test",
                            "extras",
                            "test"]),
    Dir = proplists:get_value(dir, Opts),
    [Expect] = Dir,

    Suite = proplists:get_value(suite, Opts),
    ["extra_SUITE"] = Suite.

suite_at_root(Config) ->
    AppDir = ?config(apps, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--suite=" ++ filename:join([AppDir, "root_SUITE"])]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Suite = proplists:get_value(suite, Opts),
    Expected = filename:join([AppDir, "_build", "test", "extras", "root_SUITE"]),
    [Expected] = Suite,

    TestHrl = filename:join([AppDir, "_build", "test", "extras", "root_SUITE.hrl"]),
    true = filelib:is_file(TestHrl),

    TestBeam = filename:join([AppDir, "_build", "test", "extras", "root_SUITE.beam"]),
    true = filelib:is_file(TestBeam),

    DataDir = filename:join([AppDir, "_build", "test", "extras", "root_SUITE_data"]),
    true = filelib:is_dir(DataDir),

    DataFile = filename:join([AppDir, "_build", "test", "extras", "root_SUITE_data", "some_data.txt"]),
    true = filelib:is_file(DataFile),

    %% Same test again, but using relative path to the suite from the
    %% project root
    {ok,Cwd} = file:get_cwd(),
    ok = file:set_cwd(AppDir),
    rebar_file_utils:rm_rf("_build"),

    {ok, GetOptResult2} = getopt:parse(GetOptSpec, ["--suite=" ++ "root_SUITE"]),

    State3 = rebar_state:command_parsed_args(State1, GetOptResult2),

    Tests2 = rebar_prv_common_test:prepare_tests(State3),
    {ok, NewState2} = rebar_prv_common_test:compile(State3, Tests2),
    {ok, T2} = Tests2,
    Opts2 = rebar_prv_common_test:translate_paths(NewState2, T2),

    ok = file:set_cwd(Cwd),

    Suite2 = proplists:get_value(suite, Opts2),
    [Expected] = Suite2,
    true = filelib:is_file(TestHrl),
    true = filelib:is_file(TestBeam),
    true = filelib:is_dir(DataDir),
    true = filelib:is_file(DataFile),

    ok.

suite_at_app_root(Config) ->
    AppDir = ?config(apps, Config),
    [_Name1, Name2] = ?config(appnames, Config),
    State = ?config(s, Config),

    LibDirs = rebar_dir:lib_dirs(State),
    State1 = rebar_app_discover:do(State, LibDirs),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--suite=" ++ filename:join([AppDir, "apps", Name2, "app_root_SUITE"])]),

    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState} = rebar_prv_common_test:compile(State2, Tests),
    {ok, T} = Tests,
    Opts = rebar_prv_common_test:translate_paths(NewState, T),

    Suite = proplists:get_value(suite, Opts),
    Expected = filename:join([AppDir, "_build", "test", "lib", Name2, "app_root_SUITE"]),
    [Expected] = Suite,

    TestHrl = filename:join([AppDir, "_build", "test", "lib", Name2, "app_root_SUITE.hrl"]),
    true = filelib:is_file(TestHrl),

    TestBeam = filename:join([AppDir, "_build", "test", "lib", Name2, "app_root_SUITE.beam"]),
    true = filelib:is_file(TestBeam),

    DataDir = filename:join([AppDir, "_build", "test", "lib", Name2, "app_root_SUITE_data"]),
    true = filelib:is_dir(DataDir),

    DataFile = filename:join([AppDir, "_build", "test", "lib", Name2, "app_root_SUITE_data", "some_data.txt"]),
    true = filelib:is_file(DataFile),

    %% Same test again using relative path to the suite from the project root
    {ok,Cwd} = file:get_cwd(),
    ok = file:set_cwd(AppDir),
    rebar_file_utils:rm_rf("_build"),

    {ok, GetOptResult2} = getopt:parse(GetOptSpec, ["--suite=" ++ filename:join(["apps", Name2, "app_root_SUITE"])]),

    State3 = rebar_state:command_parsed_args(State1, GetOptResult2),

    Tests2 = rebar_prv_common_test:prepare_tests(State3),
    {ok, NewState2} = rebar_prv_common_test:compile(State3, Tests2),
    {ok, T2} = Tests2,
    Opts2 = rebar_prv_common_test:translate_paths(NewState2, T2),

    ok = file:set_cwd(Cwd),

    Suite2 = proplists:get_value(suite, Opts2),
    [Expected] = Suite2,
    true = filelib:is_file(TestHrl),
    true = filelib:is_file(TestBeam),
    true = filelib:is_dir(DataDir),
    true = filelib:is_file(DataFile),

    ok.

%% this test probably only fails when this suite is run via rebar3 with the --cover flag
data_dir_correct(Config) ->
    DataDir = ?config(data_dir, Config),
    Parts = filename:split(DataDir),
    ["rebar_ct_SUITE_data","test","rebar","lib",_,"_build"|_] = lists:reverse(Parts).

cmd_label(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--label=this_is_a_label"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({label, "this_is_a_label"}, TestOpts).

cmd_config(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--config=config/foo,config/bar,config/baz"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({config, ["config/foo", "config/bar", "config/baz"]}, TestOpts).

cmd_spec(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--spec=foo.spec,bar.spec,baz.spec"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({spec, ["foo.spec", "bar.spec", "baz.spec"]}, TestOpts).

cmd_join_specs(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--join_specs=true"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({join_specs, true}, TestOpts).

cmd_allow_user_terms(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--allow_user_terms=true"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({allow_user_terms, true}, TestOpts).

cmd_logdir(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--logdir=/tmp/ct_logs"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({logdir, "/tmp/ct_logs"}, TestOpts).

cmd_logopts(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--logopts=no_src,no_nl"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({logopts, [no_src, no_nl]}, TestOpts).

cmd_verbosity(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--verbosity=43"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({verbosity, 43}, TestOpts).

cmd_repeat(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--repeat=3"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({repeat, 3}, TestOpts).

cmd_duration(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--duration=001500"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({duration, "001500"}, TestOpts).

cmd_until(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--until=001500"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({until, "001500"}, TestOpts).

cmd_force_stop(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--force_stop=skip_rest"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({force_stop, skip_rest}, TestOpts).

cmd_basic_html(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--basic_html"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({basic_html, true}, TestOpts).

cmd_stylesheet(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--stylesheet=resources/tests.css"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({stylesheet, "resources/tests.css"}, TestOpts).

cmd_decrypt_key(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--decrypt_key==ac467e30"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({decrypt_key, "=ac467e30"}, TestOpts).

cmd_decrypt_file(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--decrypt_file=../keyfile.pem"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({decrypt_file, "../keyfile.pem"}, TestOpts).

cmd_abort_if_missing_suites(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--abort_if_missing_suites"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({abort_if_missing_suites, true}, TestOpts).

cmd_multiply_timetraps(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--multiply_timetraps=3"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({multiply_timetraps, 3}, TestOpts).

cmd_scale_timetraps(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--scale_timetraps"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({scale_timetraps, true}, TestOpts).

cmd_create_priv_dir(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--create_priv_dir=manual_per_tc"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(NewState),

    true = lists:member({create_priv_dir, manual_per_tc}, TestOpts).

cmd_include_dir(Config) ->
    State = ?config(result, Config),
    AppDir = ?config(apps, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--include=foo/bar/baz,qux"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(NewState),
    {ok, _} = rebar_prv_common_test:compile(NewState, Tests),

    Name = ?config(name, Config),
    Beam = filename:join([AppDir, "_build", "test", "lib", Name, "ebin", Name ++ ".beam"]),

    {ok, {_, [{compile_info, Info}]}} = beam_lib:chunks(Beam, [compile_info]),
    CompileOpts = proplists:get_value(options, Info),
    true = lists:member({i, "foo/bar/baz"}, CompileOpts),
    true = lists:member({i, "qux"}, CompileOpts).

cmd_sys_config(Config) ->
    State = ?config(result, Config),
    AppDir = ?config(apps, Config),
    Name = ?config(name, Config),
    AppName = list_to_atom(Name),

    {ok, _} = rebar_prv_common_test:prepare_tests(State),
    ?assertEqual(undefined, application:get_env(AppName, key)),

    CfgFile = filename:join([AppDir, "config", "cfg_sys.config"]),
    ok = filelib:ensure_dir(CfgFile),
    ok = file:write_file(CfgFile, cfg_sys_config_file(AppName)),

    OtherCfgFile = filename:join([AppDir, "config", "other.config"]),
    ok = filelib:ensure_dir(OtherCfgFile),
    ok = file:write_file(OtherCfgFile, other_sys_config_file(AppName)),

    SrcCfgFile = filename:join([AppDir, "config", "source.config.src"]),
    ok = filelib:ensure_dir(SrcCfgFile),
    ok = file:write_file(SrcCfgFile, cfg_sys_src_config_file(AppName, "MyExpectedString")),

    RebarConfig = [{ct_opts, [{sys_config, CfgFile}]}],
    {ok, State1} = rebar_test_utils:run_and_check(Config, RebarConfig, ["as", "test", "lock"], return),

    {ok, _} = rebar_prv_common_test:prepare_tests(State1),
    ?assertEqual({ok, cfg_value}, application:get_env(AppName, key)),

    ?assertEqual({ok, other_cfg_value}, application:get_env(AppName, other_key)),

    ?assertEqual({ok, "MyExpectedString"}, application:get_env(AppName, src_key)),

    Providers = rebar_state:providers(State1),
    Namespace = rebar_state:namespace(State1),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),

    CmdFile = filename:join([AppDir, "config", "cmd_sys.config"]),
    ok = filelib:ensure_dir(CmdFile),
    ok = file:write_file(CmdFile, cmd_sys_config_file(AppName)),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--sys_config="++CmdFile]),
    State2 = rebar_state:command_parsed_args(State1, GetOptResult),

    {ok, _} = rebar_prv_common_test:prepare_tests(State2),

    ?assertEqual({ok ,cmd_value}, application:get_env(AppName, key)).


cfg_opts(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_cfg_opts_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_cfg_opts_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{ct_opts, [{label, "this_is_a_label"}, {decrypt_file, "../keyfile.pem"}]}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(State),

    true = lists:member({label, "this_is_a_label"}, TestOpts),
    true = lists:member({decrypt_file, "../keyfile.pem"}, TestOpts).

%% allow even nonsensical opts to be passed to ct_run for futureproofing
cfg_arbitrary_opts(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_cfg_arbitrary_opts_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_cfg_arbitrary_opts_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{ct_opts, [{foo, 1}, {bar, 2}, {baz, 3}]}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(State),

    true = lists:member({foo, 1}, TestOpts),
    true = lists:member({bar, 2}, TestOpts),
    true = lists:member({baz, 3}, TestOpts).

cfg_cover_spec(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_cfg_cover_spec_opts_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_cfg_cover_spec_opts_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{ct_opts, [Opt = {cover, "spec/foo.spec"}]}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(State),

    false = lists:member(Opt, TestOpts).

cfg_atom_suites(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_cfg_atom_suites_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_cfg_atom_suites_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{ct_opts, [{suite, [foo, bar, baz]}]}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(State),

    true = lists:member({suite, ["foo", "bar", "baz"]}, TestOpts).

cover_compiled(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--cover"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(NewState),
    {ok, _} = rebar_prv_common_test:compile(NewState, Tests),

    Name = ?config(name, Config),
    Mod = list_to_atom(Name),
    {file, _} = cover:is_compiled(Mod).

cover_export_name(Config) ->
    State = ?config(result, Config),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),
    {ok, GetOptResult} = getopt:parse(GetOptSpec, ["--cover", "--cover_export_name=export_name"]),

    NewState = rebar_state:command_parsed_args(State, GetOptResult),

    Tests = rebar_prv_common_test:prepare_tests(NewState),
    {ok, _} = rebar_prv_common_test:compile(NewState, Tests),
    rebar_prv_common_test:maybe_write_coverdata(NewState),

    Name = ?config(name, Config),
    Mod = list_to_atom(Name),
    {file, _} = cover:is_compiled(Mod),

    Dir = rebar_dir:profile_dir(rebar_state:opts(NewState), [default, test]),
    ct:pal("DIR ~s", [Dir]),
    true = filelib:is_file(filename:join([Dir, "cover", "export_name.coverdata"])).

misspecified_ct_opts(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_cfg_atom_suites_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_cfg_atom_suites_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{ct_opts, {basic_html, false}}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    {error, {rebar_prv_common_test, Error}} = rebar_prv_common_test:prepare_tests(State),

    {badconfig, {"Value `~p' of option `~p' must be a list", {{basic_html, false}, ct_opts}}} = Error.

misspecified_ct_compile_opts(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_cfg_atom_suites_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_cfg_atom_suites_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{ct_compile_opts, {d, whatever}}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    Tests = rebar_prv_common_test:prepare_tests(State),
    {error, {rebar_prv_common_test, Error}} = rebar_prv_common_test:compile(State, Tests),

    {badconfig, {"Value `~p' of option `~p' must be a list", {{d, whatever}, ct_compile_opts}}} = Error.

misspecified_ct_first_files(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_cfg_atom_suites_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_cfg_atom_suites_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{ct_first_files, some_file}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    Tests = rebar_prv_common_test:prepare_tests(State),
    {error, {rebar_prv_common_test, Error}} = rebar_prv_common_test:compile(State, Tests),

    {badconfig, {"Value `~p' of option `~p' must be a list", {some_file, ct_first_files}}} = Error.

testspec(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_testspec_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_testspec_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    Spec1 = filename:join([AppDir, "test", "some.spec"]),
    ok = filelib:ensure_dir(Spec1),
    ok = file:write_file(Spec1, "{suites,\".\",all}.\n"),
    Spec2 = filename:join([AppDir, "specs", "another.spec"]),
    ok = filelib:ensure_dir(Spec2),
    Suites2 = filename:join([AppDir,"suites","*"]),
    ok = filelib:ensure_dir(Suites2),
    ok = file:write_file(Spec2, "{suites,\"../suites/\",all}.\n"),

    {ok,Wd} = file:get_cwd(),
    ok = file:set_cwd(AppDir),

    {ok, State} = rebar_test_utils:run_and_check(C,
                                                 [],
                                                 ["as", "test", "lock"],
                                                 return),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),

    %% Testspec in "test" directory
    {ok, GetOptResult1} = getopt:parse(GetOptSpec, ["--spec","test/some.spec"]),
    State1 = rebar_state:command_parsed_args(State, GetOptResult1),
    Tests1 = rebar_prv_common_test:prepare_tests(State1),
    {ok, NewState1} = rebar_prv_common_test:compile(State1, Tests1),
    {ok, T1} = Tests1,
    Opts1= rebar_prv_common_test:translate_paths(NewState1, T1),

    %% check that extra src dir is added
    [App1] = rebar_state:project_apps(NewState1),
    ["test"] = rebar_dir:extra_src_dirs(rebar_app_info:opts(App1)),

    %% check that path is translated
    ExpectedSpec1 = filename:join([AppDir, "_build", "test", "lib", Name,
                                  "test", "some.spec"]),
    [ExpectedSpec1] = proplists:get_value(spec, Opts1),


    %% Testspec in directory other than "test"
    {ok, GetOptResult2} = getopt:parse(GetOptSpec,
                                       ["--spec","specs/another.spec"]),
    State2 = rebar_state:command_parsed_args(State, GetOptResult2),
    Tests2 = {ok, T2} =rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState2} = rebar_prv_common_test:compile(State2, Tests2),
    Opts2= rebar_prv_common_test:translate_paths(NewState2, T2),

    %% check that extra src dirs are added
    [App2] = rebar_state:project_apps(NewState2),
    ["specs","suites","test"] =
        lists:sort(rebar_dir:extra_src_dirs(rebar_app_info:opts(App2))),

    %% check that paths are translated
    ExpectedSpec2 = filename:join([AppDir, "_build", "test", "lib", Name,
                                  "specs", "another.spec"]),
    [ExpectedSpec2] = proplists:get_value(spec, Opts2),

    ok = file:set_cwd(Wd),

    ok.

testspec_at_root(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_testspec_at_root_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_testspec_at_root_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    AppDir1 = filename:join([AppDir, "apps", Name]),
    rebar_test_utils:create_app(AppDir1, Name, Vsn, [kernel, stdlib]),

    Spec1 = filename:join([AppDir, "root.spec"]),
    ok = filelib:ensure_dir(Spec1),
    ok = file:write_file(Spec1, "{suites,\"test\",all}."),
    Spec2 = filename:join([AppDir, "root1.spec"]),
    ok = file:write_file(Spec2, "{suites,\".\",all}."),
    Spec3 = filename:join([AppDir, "root2.spec"]),
    ok = file:write_file(Spec3, "{suites,\"suites\",all}."),
    Suite1 = filename:join(AppDir,"root_SUITE.erl"),
    ok = file:write_file(Suite1, test_suite("root")),
    Suite2 = filename:join([AppDir,"suites","test_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite2),
    ok = file:write_file(Suite2, test_suite("test")),

    {ok, State} = rebar_test_utils:run_and_check(C,
                                                 [],
                                                 ["as", "test", "lock"],
                                                 return),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),

    SpecArg1 = rebar_string:join([Spec1,Spec2,Spec3],","),
    {ok, GetOptResult1} = getopt:parse(GetOptSpec, ["--spec",SpecArg1]),
    State1 = rebar_state:command_parsed_args(State, GetOptResult1),
    Tests1 = rebar_prv_common_test:prepare_tests(State1),
    {ok, NewState1} = rebar_prv_common_test:compile(State1, Tests1),
    {ok, T1} = Tests1,
    Opts1= rebar_prv_common_test:translate_paths(NewState1, T1),

    %% check that extra src dir is added
    ExtraDir = filename:join([AppDir, "_build", "test", "extras"]),
    [ExtraDir,"suites","test"] =
        rebar_dir:extra_src_dirs(rebar_state:opts(NewState1)),

    %% check that path is translated
    ExpectedSpec1 = filename:join([AppDir, "_build", "test",
                                   "extras", "root.spec"]),
    ExpectedSpec2 = filename:join([AppDir, "_build", "test",
                                   "extras", "root1.spec"]),
    ExpectedSpec3 = filename:join([AppDir, "_build", "test",
                                   "extras", "root2.spec"]),
    [ExpectedSpec1,ExpectedSpec2,ExpectedSpec3] =
        lists:sort(proplists:get_value(spec, Opts1)),

    %% check that test specs are copied
    [ExpectedSpec1,ExpectedSpec2,ExpectedSpec3] =
        lists:sort(filelib:wildcard(filename:join([AppDir, "_build", "test",
                                                   "extras", "*.spec"]))),

    %% Same test again, using relative path
    {ok,Cwd} = file:get_cwd(),
    ok = file:set_cwd(AppDir),
    ok = rebar_file_utils:rm_rf("_build"),

    SpecArg2 = "root.spec,root1.spec,root2.spec",
    {ok, GetOptResult2} = getopt:parse(GetOptSpec, ["--spec",SpecArg2]),
    State2 = rebar_state:command_parsed_args(State, GetOptResult2),
    Tests2 = rebar_prv_common_test:prepare_tests(State2),
    {ok, NewState2} = rebar_prv_common_test:compile(State2, Tests2),
    {ok, T2} = Tests2,
    Opts2= rebar_prv_common_test:translate_paths(NewState2, T2),

    %% check that extra src dir is added
    [ExtraDir,"suites","test"] =
        rebar_dir:extra_src_dirs(rebar_state:opts(NewState2)),

    %% check that path is translated
    [ExpectedSpec1,ExpectedSpec2,ExpectedSpec3] =
        lists:sort(proplists:get_value(spec, Opts2)),

    %% check that test specs are copied
    [ExpectedSpec1,ExpectedSpec2,ExpectedSpec3] =
        lists:sort(filelib:wildcard(filename:join([AppDir, "_build", "test",
                                                   "extras", "root*.spec"]))),

    ok = file:set_cwd(Cwd),

    ok.

testspec_parse_error(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_testspec_error"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_testspec_error"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    Spec1 = filename:join([AppDir, "test", "nonexisting.spec"]),
    Spec2 = filename:join([AppDir, "test", "some.spec"]),
    ok = filelib:ensure_dir(Spec2),
    ok = file:write_file(Spec2, ".\n"),

    {ok, State} = rebar_test_utils:run_and_check(C,
                                                 [],
                                                 ["as", "test", "lock"],
                                                 return),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),

    %% Non existing testspec
    {ok, GetOptResult1} = getopt:parse(GetOptSpec, ["--spec",Spec1]),
    State1 = rebar_state:command_parsed_args(State, GetOptResult1),
    Tests1 = rebar_prv_common_test:prepare_tests(State1),
    {error,
     {rebar_prv_common_test,
      {error_reading_testspec,
       {Spec1,"no such file or directory"}}}} =
        rebar_prv_common_test:compile(State1, Tests1),

    %% Syntax error
    {ok, GetOptResult2} = getopt:parse(GetOptSpec, ["--spec",Spec2]),
    State2 = rebar_state:command_parsed_args(State, GetOptResult2),
    Tests2 = rebar_prv_common_test:prepare_tests(State2),
    {error,
     {rebar_prv_common_test,
      {error_reading_testspec,
       {Spec2,"1: syntax error before: '.'"}}}} =
        rebar_prv_common_test:compile(State2, Tests2),

    ok.

cmd_vs_cfg_opts(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_cmd_vs_cfg_opts_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_cmd_vs_cfg_opts_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    RebarConfig = [{ct_opts, [{spec,"mytest.spec"},
                              {dir,"test"},
                              {suite,"some_SUITE"},
                              {group,"some_group"},
                              {testcase,"some_test"}]}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    {ok, TestOpts} = rebar_prv_common_test:prepare_tests(State),
    true = lists:member({spec, "mytest.spec"}, TestOpts),
    true = lists:member({dir, "test"}, TestOpts),
    true = lists:member({suite, "some_SUITE"}, TestOpts),
    true = lists:member({group, "some_group"}, TestOpts),
    true = lists:member({testcase, "some_test"}, TestOpts),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),

    {ok, GetOptResult1} = getopt:parse(GetOptSpec, ["--spec","test/some.spec"]),
    State1 = rebar_state:command_parsed_args(State, GetOptResult1),
    {ok, TestOpts1} = rebar_prv_common_test:prepare_tests(State1),
    true = lists:member({spec, ["test/some.spec"]}, TestOpts1),
    false = lists:keymember(dir, 1, TestOpts1),
    false = lists:keymember(suite, 1, TestOpts1),
    false = lists:keymember(group, 1, TestOpts1),
    false = lists:keymember(testcase, 1, TestOpts1),

    {ok, GetOptResult2} = getopt:parse(GetOptSpec, ["--suite","test/some_SUITE"]),
    State2 = rebar_state:command_parsed_args(State, GetOptResult2),
    {ok, TestOpts2} = rebar_prv_common_test:prepare_tests(State2),
    true = lists:member({suite, ["test/some_SUITE"]}, TestOpts2),
    false = lists:keymember(spec, 1, TestOpts2),
    false = lists:keymember(dir, 1, TestOpts2),
    false = lists:keymember(group, 1, TestOpts2),
    false = lists:keymember(testcase, 1, TestOpts2),

    {ok, GetOptResult3} = getopt:parse(GetOptSpec, ["--group","[g1,g2],g3"]),
    State3 = rebar_state:command_parsed_args(State, GetOptResult3),
    {ok, TestOpts3} = rebar_prv_common_test:prepare_tests(State3),
    true = lists:member({group, [[g1,g2],g3]}, TestOpts3),
    false = lists:keymember(suite, 1, TestOpts3),
    false = lists:keymember(spec, 1, TestOpts3),
    false = lists:keymember(dir, 1, TestOpts3),
    false = lists:keymember(testcase, 1, TestOpts3),

    ok.

single_testspec_in_ct_opts(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "ct_testspec_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name("ct_testspec_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    Spec = filename:join([AppDir, "test", "some.spec"]),
    ok = filelib:ensure_dir(Spec),
    ok = file:write_file(Spec, "{suites,\".\",all}.\n"),

    {ok,Wd} = file:get_cwd(),
    ok = file:set_cwd(AppDir),

    RebarConfig = [{ct_opts, [{spec,"test/some.spec"}]}],

    {ok, State} = rebar_test_utils:run_and_check(C, RebarConfig, ["as", "test", "lock"], return),

    Providers = rebar_state:providers(State),
    Namespace = rebar_state:namespace(State),
    CommandProvider = providers:get_provider(ct, Providers, Namespace),
    GetOptSpec = providers:opts(CommandProvider),

    %% Testspec in "test" directory
    {ok, GetOptResult1} = getopt:parse(GetOptSpec, []),
    State1 = rebar_state:command_parsed_args(State, GetOptResult1),
    Tests1 = rebar_prv_common_test:prepare_tests(State1),
    {ok, T1} = Tests1,
    "test/some.spec" = proplists:get_value(spec,T1),
    {ok, _NewState} = rebar_prv_common_test:compile(State1, Tests1),

    ok = file:set_cwd(Wd),
    ok.

compile_only(Config) ->
    C = rebar_test_utils:init_rebar_state(Config, "compile_only_"),

    AppDir = ?config(apps, C),

    Name = rebar_test_utils:create_random_name(atom_to_list(basic_app) ++ "_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Suite = filename:join([AppDir, "test", Name ++ "_SUITE.erl"]),
    ok = filelib:ensure_dir(Suite),
    ok = file:write_file(Suite, test_suite(Name)),

    {ok, _State} = rebar_test_utils:run_and_check(C, [], ["ct", "--compile_only"], {ok, [{app,Name}], "test"}).


%% helper for generating test data
test_suite(Name) ->
    io_lib:format("-module(~ts_SUITE).\n"
                  "-compile(export_all).\n"
                  "all() -> [some_test].\n"
                  "some_test(_) -> ok.\n", [Name]).

cmd_sys_config_file(AppName) ->
    io_lib:format("[{~ts, [{key, cmd_value}]}].", [AppName]).

cfg_sys_config_file(AppName) ->
    io_lib:format("[{~ts, [{key, cfg_value}]}, \"config/other\", \"config/source.config.src\"].", [AppName]).

other_sys_config_file(AppName) ->
    io_lib:format("[{~ts, [{other_key, other_cfg_value}]}].", [AppName]).

cfg_sys_src_config_file(AppName, ExpectedValue) ->
    os:putenv("SRC_VALUE", ExpectedValue),
    io_lib:format("[{~ts, [{src_key, \"${SRC_VALUE}\"}]}].", [AppName]).
