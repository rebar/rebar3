%%%-------------------------------------------------------------------
%% @copyright (c) {{copyright_year}} {{author_name}}
%%%-------------------------------------------------------------------

-module({{name}}_SUITE).
-author("{{author_email}}").

-include_lib("common_test/include/ct.hrl").

%% Enables ?assert() for readable output
-include_lib("stdlib/include/assert.hrl").

-compile(nowarn_export_all).
-compile(export_all).

%%%-------------------------------------------------------------------
%% Test server callbacks

suite() ->
    [].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

groups() ->
    [].

all() ->
    [basic].

%%%-------------------------------------------------------------------
%% Test cases
basic() ->
    [{doc, "Tests basic functionality"}].

basic(_Config) ->
    ?assert(true).

