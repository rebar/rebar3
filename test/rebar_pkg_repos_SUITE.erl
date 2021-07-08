%% Test suite for the handling hexpm repo configurations
-module(rebar_pkg_repos_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("rebar.hrl").

all() ->
    [default_repo, repo_merging, repo_replacing,
     auth_read_write_read, auth_remove_from_config, auth_merging, auth_config_errors, organization_merging,
     {group, resolve_version}].

groups() ->
    [{resolve_version, [use_first_repo_match, use_exact_with_hash, fail_repo_update,
                        update_package,
                        ignore_match_in_excluded_repo, optional_prereleases]}].

init_per_group(resolve_version, Config) ->
    Repo1 = <<"test-repo-1">>,
    Repo2 = <<"test-repo-2">>,
    Repo3 = <<"test-repo-3">>,
    Hexpm = <<"hexpm">>,
    Repos = [Repo1, Repo2, Repo3, Hexpm],

    Deps = [{"A", "0.1.1", <<"inner checksum">>, <<"good outer checksum">>, Repo1, false},
            {"A", "0.1.1", <<"inner checksum">>, <<"good outer checksum">>, Repo2, false},
            {"B", "1.0.0", Repo1, false},
            {"B", "2.0.0", Repo2, false},
            {"B", "1.4.0", Repo3, false},
            {"B", "1.4.3", Hexpm, false},
            {"B", "1.4.6", Hexpm, #{reason => 'RETIRED_INVALID'}},
            {"B", "1.5.0", Hexpm, false},
            {"B", "1.5.6-rc.0", Hexpm, true},
            {"C", "1.3.1", <<"inner checksum">>, <<"bad outer checksum">>, Repo1, false},
            {"C", "1.3.1", <<"inner checksum">>, <<"good outer checksum">>, Repo2, false}],
    [{deps, Deps}, {repos, Repos} | Config];
init_per_group(_, Config) ->
    Config.

end_per_group(_, _) ->
    ok.

init_per_testcase(use_first_repo_match, Config) ->
    Deps = ?config(deps, Config),
    Repos = ?config(repos, Config),
    State = setup_deps_and_repos(Deps, Repos),

    meck:new(rebar_packages, [passthrough, no_link]),

    %% fail when the first repo is updated since it doesn't have a matching package
    %% should continue anyway
    meck:expect(rebar_packages, update_package,
                fun(_, _, _State) -> ok  end),
    meck:expect(rebar_packages, verify_table,
                fun(_State) -> true end),

    [{state, State} | Config];
init_per_testcase(use_exact_with_hash, Config) ->
    Deps = ?config(deps, Config),
    Repos = ?config(repos, Config),
    State = setup_deps_and_repos(Deps, Repos),

    meck:new(rebar_packages, [passthrough, no_link]),

    %% fail when the first repo is updated since it doesn't have a matching package
    %% should continue anyway
    meck:expect(rebar_packages, update_package,
                fun(_, _, _State) -> ok  end),
    meck:expect(rebar_packages, verify_table,
                fun(_State) -> true end),

    [{state, State} | Config];
init_per_testcase(fail_repo_update, Config) ->
    Deps = ?config(deps, Config),
    Repos = ?config(repos, Config),
    State = setup_deps_and_repos(Deps, Repos),

    meck:new(rebar_packages, [passthrough, no_link]),

    %% fail when the first repo is updated since it doesn't have a matching package
    %% should continue anyway
    [Repo1 | _] = Repos,
    meck:expect(rebar_packages, update_package,
                fun(_, #{name := Repo}, _State) when Repo =:= Repo1 -> fail;
                   (_, _, _State) -> ok  end),
    meck:expect(rebar_packages, verify_table,
                fun(_State) -> true end),

    [{state, State} | Config];
init_per_testcase(ignore_match_in_excluded_repo, Config) ->
    Deps = ?config(deps, Config),
    Repos = [Repo1, _, Repo3 | _] = ?config(repos, Config),

    %% drop repo1 and repo2 from the repos to be used by the pkg resource
    State = setup_deps_and_repos(Deps, [R || R <- Repos, R =/= Repo3, R =/= Repo1]),

    meck:new(rebar_packages, [passthrough, no_link]),

    %% fail when the first repo is updated since it doesn't have a matching package
    %% should continue anyway
    [_, _, Repo3 | _] = Repos,
    meck:expect(rebar_packages, update_package,
                fun(_, _, _State) -> ok  end),
    meck:expect(rebar_packages, verify_table,
                fun(_State) -> true end),

    [{state, State} | Config];
init_per_testcase(optional_prereleases, Config) ->
    Deps = ?config(deps, Config),
    Repos = ?config(repos, Config),

    State = setup_deps_and_repos(Deps, Repos),

    meck:new(rebar_packages, [passthrough, no_link]),

    meck:expect(rebar_packages, update_package,
                fun(_, _, _State) -> ok  end),
    meck:expect(rebar_packages, verify_table,
                fun(_State) -> true end),

    [{state, State} | Config];
init_per_testcase(Case, Config) when Case =:= auth_merging ;
                                     Case =:= auth_config_errors ;
                                     Case =:= auth_remove_from_config ;
                                     Case =:= auth_read_write_read ->
    meck:new(file, [passthrough, no_link, unstick]),
    meck:new(rebar_packages, [passthrough, no_link]),
    Config;
init_per_testcase(organization_merging, Config) ->
    meck:new(file, [passthrough, no_link, unstick]),
    meck:new(rebar_packages, [passthrough, no_link]),
    Config;
init_per_testcase(update_package, Config) ->
    Deps = ?config(deps, Config),
    Repos = ?config(repos, Config),
    State = setup_deps_and_repos(Deps, Repos),

    DDeps = [ #{package => <<"DD1">>, optional => true, requirement => <<"~> 0.1">>},
              #{package => <<"DD2">>, optional => false, requirement => <<"~> 0.1">>},
              #{package => <<"DD3">>, requirement => <<"~> 0.1">>}
            ],

    meck:new(r3_hex_repo, [passthrough, no_link]),
    meck:expect(r3_hex_repo, get_package,
               fun(_, <<"D">>) ->
                       {ok, {200, #{}, [#{
                                         inner_checksum => <<"inner checksum">>,
                                         outer_checksum => <<"outer checksum">>,
                                         version => <<"1.0.0">>,
                                         dependencies => DDeps
                                        }]}}
               end),
    [{state, State} | Config];
init_per_testcase(_, Config) ->
    Config.

end_per_testcase(Case, _Config) when Case =:= auth_merging ;
                                     Case =:= auth_config_errors ;
                                     Case =:= organization_merging ;
                                     Case =:= auth_remove_from_config ;
                                     Case =:= auth_read_write_read ->
    meck:unload(file),
    meck:unload(rebar_packages);
end_per_testcase(Case, _Config) when Case =:= use_first_repo_match ;
                                     Case =:= use_exact_with_hash ;
                                     Case =:= fail_repo_update ;
                                     Case =:= ignore_match_in_excluded_repo ;
                                     Case =:= optional_prereleases ->
    meck:unload(rebar_packages);
end_per_testcase(update_package, _Config) ->
    meck:unload(r3_hex_repo);
end_per_testcase(_, _) ->
    ok.


default_repo(_Config) ->
    Repo1 = #{name => <<"hexpm">>,
              api_key => <<"asdf">>},

    MergedRepos = rebar_hex_repos:repos([{repos, [Repo1]}]),

    ?assertMatch([#{name := <<"hexpm">>,
                    api_key := <<"asdf">>,
                    api_url := <<"https://hex.pm/api">>}], MergedRepos).


repo_merging(_Config) ->
    Repo1 = #{name => <<"repo-1">>,
              api_url => <<"repo-1/api">>},
    Repo2 = #{name => <<"repo-2">>,
              repo_url => <<"repo-2/repo">>,
              repo_verify => false},
    Result = rebar_hex_repos:merge_repos([Repo1, Repo2,
                                             #{name => <<"repo-2">>,
                                               api_url => <<"repo-2/api">>,
                                               repo_url => <<"bad url">>,
                                               repo_verify => true},
                                             #{name => <<"repo-1">>,
                                               api_url => <<"bad url">>,
                                               repo_verify => true},
                                             #{name => <<"repo-2">>,
                                               api_url => <<"repo-2/api-2">>,
                                               repo_url => <<"other/repo">>}]),
    ?assertMatch([#{name := <<"repo-1">>,
                    api_url := <<"repo-1/api">>,
                    repo_verify := true},
                  #{name := <<"repo-2">>,
                    api_url := <<"repo-2/api">>,
                    repo_url := <<"repo-2/repo">>,
                    repo_verify := false}], Result).

repo_replacing(_Config) ->
    Repo1 = #{name => <<"repo-1">>,
              repo_name => <<"repo-1">>,
              api_url => <<"repo-1/api">>},
    Repo2 = #{name => <<"repo-2">>,
              repo_name => <<"repo-2">>,
              repo_url => <<"repo-2/repo">>,
              repo_verify => false},

    ?assertMatch([Repo1, Repo2, #{name := <<"hexpm">>}],
                 rebar_hex_repos:repos([{repos, [Repo1]},
                                        {repos, [Repo2]}])),

    %% use of replace is ignored if found in later entries than the first
    ?assertMatch([Repo1, Repo2, #{name := <<"hexpm">>}],
                 rebar_hex_repos:repos([{repos, [Repo1]},
                                        {repos, replace, [Repo2]}])),

    ?assertMatch([Repo1],
                 rebar_hex_repos:repos([{repos, replace, [Repo1]},
                                        {repos, [Repo2]}])).

auth_merging(_Config) ->
    Repo1 = #{name => <<"repo-1">>,
              api_url => <<"repo-1/api">>},
    Repo2 = #{name => <<"repo-2">>,
              repo_url => <<"repo-2/repo">>,
              repo_verify => false},

    State = rebar_state:new([{hex, [{repos, [Repo1, Repo2]}]}]),
    meck:expect(file, consult,
                fun(_) ->
                        {ok, [#{<<"repo-1">> => #{read_key => <<"read key">>,
                                                 write_key => <<"write key">>},
                               <<"repo-2">> => #{read_key => <<"read key 2">>,
                                                 repos_key => <<"repos key 2">>,
                                                 write_key => <<"write key 2">>},
                                <<"hexpm">> => #{write_key => <<"write key hexpm">>}}]}
                end),

    ?assertMatch({ok,
                  #resource{state=#{repos := [#{name := <<"repo-1">>,
                                                read_key := <<"read key">>,
                                                write_key := <<"write key">>},
                                              #{name := <<"repo-2">>,
                                                read_key := <<"read key 2">>,
                                                repos_key := <<"repos key 2">>,
                                                write_key := <<"write key 2">>},
                                              #{name := <<"hexpm">>,
                                                write_key := <<"write key hexpm">>}]}}},
                 rebar_pkg_resource:init(pkg, State)),

    ok.

auth_config_errors(_Config) ->
    Repo1 = #{name => <<"repo-1">>,
              api_url => <<"repo-1/api">>},
    Repo2 = #{name => <<"repo-2">>,
              repo_url => <<"repo-2/repo">>,
              repo_verify => false},

    State = rebar_state:new([{hex, [{repos, [Repo1, Repo2]}]}]),
    meck:expect(file, consult,
                fun(_) ->
                        {error, {3,erl_parse,["syntax error before: ","'=>'"]}}
                end),

    ?assertThrow(rebar_abort, rebar_pkg_resource:init(pkg, State)),
    meck:expect(file, consult,
                fun(_) ->
                        {error, enoent}
                end),


    {ok, #resource{state=#{ repos := [
                                      UpdatedRepo1,
                                      UpdatedRepo2,
                                      DefaultRepo
                                     ]}}} =  rebar_pkg_resource:init(pkg, State),

    ?assertEqual(undefined, maps:get(write_key, UpdatedRepo1, undefined)),
    ?assertEqual(undefined, maps:get(read_key, UpdatedRepo1, undefined)),
    ?assertEqual(undefined, maps:get(repos_key, UpdatedRepo1, undefined)),
    ?assertEqual(undefined, maps:get(write_key, UpdatedRepo2, undefined)),
    ?assertEqual(undefined, maps:get(repos_key, UpdatedRepo2, undefined)),
    ?assertEqual(undefined, maps:get(read_key, UpdatedRepo2, undefined)),
    ?assertEqual(undefined, maps:get(write_key, DefaultRepo, undefined)),
    ok.

auth_read_write_read(_Config) ->
    Repo1 = #{name => <<"hexpm:repo-1">>,
              api_url => <<"repo-1/api">>},
    Repo2 = #{name => <<"hexpm:repo-2">>,
              repo_url => <<"repo-2/repo">>,
              repo_verify => false},
    State = rebar_state:new([{hex, [{repos, [Repo1, Repo2]}]}]),

    meck:expect(file, consult,
                fun(_) ->
                        {ok, [#{<<"hexpm:repo-1">> => #{read_key => <<"read key">>},
                                <<"hexpm:repo-2">> => #{read_key => <<"read key 2">>,
                                                        repos_key => <<"repos key 2">>,
                                                        write_key => <<"write key 2">>}}]}
                end),

    meck:expect(file, write_file,
                fun(_File, CfgBin, _) ->
                        case binary:match(CfgBin, <<"foo">>) of
                            nomatch ->
                                Err = "expected auth config binary with key <<\"foo\">>",
                                meck:exception(error, {expected, Err});
                            _ ->
                                ok
                        end
                end),

    rebar_hex_repos:update_auth_config(#{<<"foo">> => <<200>>}, State).

auth_remove_from_config(_Config) ->
    Repo1 = #{name => <<"hexpm:repo-1">>,
              api_url => <<"repo-1/api">>},
    Repo2 = #{name => <<"hexpm:repo-2">>,
              repo_url => <<"repo-2/repo">>,
              repo_verify => false},
    State = rebar_state:new([{hex, [{repos, [Repo1, Repo2]}]}]),

    meck:expect(file, consult,
                fun(_) ->
                        {ok, [#{<<"hexpm:repo-1">> => #{read_key => <<"read key">>},
                                <<"hexpm:repo-2">> => #{read_key => <<"read key 2">>,
                                                        repos_key => <<"repos key 2">>,
                                                        write_key => <<"write key 2">>}}]}
                end),

    meck:expect(file, write_file,
                fun(_File, CfgBin, _) ->
                        case binary:match(CfgBin, <<"hexpm:repo-1">>) of
                            nomatch ->
                                ok;
                            _ ->
                                Err = "expected auth config binary without key <<\"hexpm:repo-1\">>",
                                meck:exception(error, {expected, Err})
                        end
                end),

    rebar_hex_repos:remove_from_auth_config(<<"hexpm:repo-1">>, State).

organization_merging(_Config) ->
    Repo1 = #{name => <<"hexpm:repo-1">>,
              api_url => <<"repo-1/api">>},
    Repo2 = #{name => <<"hexpm:repo-2">>,
              repo_url => <<"repo-2/repo">>,
              repo_verify => false},

    State = rebar_state:new([{hex, [{repos, [Repo1, Repo2]}]}]),
    meck:expect(file, consult,
                fun(_) ->
                        {ok, [#{<<"hexpm:repo-1">> => #{read_key => <<"read key">>},
                                <<"hexpm:repo-2">> => #{read_key => <<"read key 2">>,
                                                        repos_key => <<"repos key 2">>,
                                                        write_key => <<"write key 2">>},
                                <<"hexpm">> => #{write_key => <<"write key hexpm">>}}]}
                end),

    ?assertMatch({ok,
                  #resource{state=#{repos := [#{name := <<"hexpm:repo-1">>,
                                    parent := <<"hexpm">>,
                                    repo_name := <<"repo-1">>,
                                    api_repository := <<"repo-1">>,
                                    repo_organization := <<"repo-1">>,
                                    read_key := <<"read key">>,
                                    write_key := <<"write key hexpm">>},
                                  #{name := <<"hexpm:repo-2">>,
                                    parent := <<"hexpm">>,
                                    repo_name := <<"repo-2">>,
                                    api_repository := <<"repo-2">>,
                                    repo_organization := <<"repo-2">>,
                                    read_key := <<"read key 2">>,
                                    repos_key := <<"repos key 2">>,
                                    write_key := <<"write key 2">>},
                                  #{name := <<"hexpm">>,
                                    repo_name := <<"hexpm">>,
                                    api_repository := undefined,
                                    repo_organization := undefined,
                                    write_key := <<"write key hexpm">>}]}}},
                 rebar_pkg_resource:init(pkg, State)),

    ok.

use_first_repo_match(Config) ->
    State = ?config(state, Config),

    ?assertMatch({ok,{package,{<<"B">>, {{2,0,0}, {[],[]}}, Repo2},
                      <<"inner checksum">>,<<"outer checksum">>, false, []},
                  #{name := Repo2,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"B">>, <<"> 1.4.0">>, undefined, undefined,
                                                ?PACKAGE_TABLE, State)),

    ?assertMatch({ok,{package,{<<"B">>, {{1,4,0}, {[],[]}}, Repo3},
                    <<"inner checksum">>,<<"outer checksum">>, false, []},
                  #{name := Repo3,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"B">>, <<"~> 1.4.0">>, undefined, undefined,
                                                ?PACKAGE_TABLE, State)).

%% tests that even though an easier repo has C-1.3.1 it doesn't use it since its hash is different
use_exact_with_hash(Config) ->
    State = ?config(state, Config),

    ?assertMatch({ok,{package,{<<"C">>, {{1,3,1}, {[],[]}}, Repo2},
                      <<"inner checksum">>, <<"good outer checksum">>, false, []},
                  #{name := Repo2,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"C">>, <<"1.3.1">>, <<"inner checksum">>, <<"good outer checksum">>,
                                                ?PACKAGE_TABLE, State)).

fail_repo_update(Config) ->
    State = ?config(state, Config),

    ?assertMatch({ok,{package,{<<"B">>, {{1,4,0}, {[],[]}}, Repo3},
                      <<"inner checksum">>,<<"outer checksum">>, false, []},
                  #{name := Repo3,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"B">>, <<"~> 1.4.0">>, undefined, undefined,
                                                ?PACKAGE_TABLE, State)).

ignore_match_in_excluded_repo(Config) ->
    State = ?config(state, Config),
    Repos = ?config(repos, Config),

    ?assertMatch({ok,{package,{<<"B">>, {{1,4,6}, {[],[]}}, Hexpm},
                      <<"inner checksum">>,<<"outer checksum">>, #{reason := 'RETIRED_INVALID'}, []},
                  #{name := Hexpm,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"B">>, <<"~> 1.4.0">>, undefined, undefined,
                                                ?PACKAGE_TABLE, State)),

    [_, Repo2 | _] = Repos,
    ?assertMatch({ok,{package,{<<"A">>, {{0,1,1}, {[],[]}}, Repo2},
                      <<"inner checksum">>,  <<"good outer checksum">>, false, []},
                  #{name := Repo2,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"A">>, <<"0.1.1">>, <<"inner checksum">>, <<"good outer checksum">>,
                                                ?PACKAGE_TABLE, State)).

optional_prereleases(Config) ->
    State = ?config(state, Config),

    ?assertMatch({ok,{package,{<<"B">>, {{1,5,0}, {[],[]}}, Hexpm},
                     <<"inner checksum">>,<<"outer checksum">>, false, []},
                  #{name := Hexpm,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"B">>, <<"~> 1.5.0">>, undefined, undefined,
                                                ?PACKAGE_TABLE, State)),

    ?assertMatch({ok,{package,{<<"B">>, {{1,5,6}, {[<<"rc">>,0],[]}}, Hexpm},
                      <<"inner checksum">>,<<"outer checksum">>, true, []},
                  #{name := Hexpm,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"B">>, <<"1.5.6-rc.0">>, <<"inner checksum">>, <<"outer checksum">>,
                                                ?PACKAGE_TABLE, State)),

    %% allow prerelease through configuration
    State1 = rebar_state:set(State, deps_allow_prerelease, true),
    ?assertMatch({ok,{package,{<<"B">>, {{1,5,6}, {[<<"rc">>,0],[]}}, Hexpm},
                      <<"inner checksum">>,<<"outer checksum">>, true, []},
                  #{name := Hexpm,
                    http_adapter := {rebar_httpc_adapter, #{profile := rebar}}}},
                 rebar_packages:resolve_version(<<"B">>, <<"~> 1.5.0">>, <<"inner checksum">>, <<"outer checksum">>,
                                                ?PACKAGE_TABLE, State1)).

update_package(Config) ->
    State = ?config(state, Config),
    Repo = <<"hexpm">>,
    ok = rebar_packages:update_package(<<"D">>, #{name => Repo}, State),
    Key = {<<"D">>, ec_semver:parse(<<"1.0.0">>), Repo},
    [#package{key = Key, dependencies = Deps}] = ets:lookup(?PACKAGE_TABLE, Key),
    Expect = [<<"DD2">>, <<"DD3">>],
    ?assertMatch(Expect, lists:sort([Dep || {Dep, _} <- Deps])).

%%

setup_deps_and_repos(Deps, Repos) ->
    catch ets:delete(?PACKAGE_TABLE),
    true = rebar_packages:new_package_table(),
    insert_deps(Deps),
    State = rebar_state:new([{hex, [{repos, [#{name => R} || R <- Repos]}]}]),
    rebar_state:create_resources([{pkg, rebar_pkg_resource}], State).


insert_deps(Deps) ->
    lists:foreach(fun({Name, Version, Repo, Retired}) ->
                          ets:insert(?PACKAGE_TABLE, #package{key={rebar_utils:to_binary(Name),
                                                                   ec_semver:parse(Version),
                                                                   rebar_utils:to_binary(Repo)},
                                                              dependencies=[],
                                                              retired=Retired,
                                                              inner_checksum = <<"inner checksum">>,
                                                              outer_checksum = <<"outer checksum">>});
                     ({Name, Version, InnerChecksum, OuterChecksum, Repo, Retired}) ->
                          ets:insert(?PACKAGE_TABLE, #package{key={rebar_utils:to_binary(Name),
                                                                   ec_semver:parse(Version),
                                                                   rebar_utils:to_binary(Repo)},
                                                              dependencies=[],
                                                              retired=Retired,
                                                              inner_checksum = InnerChecksum,
                                                              outer_checksum = OuterChecksum})
                  end, Deps).
