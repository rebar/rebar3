%% Test a unusual rebar3 corner case where an Elixir package, built with mix plugin, is released.
%% If done directly, without previous build, the release will fail.
%% Repeat the release, or compile/test before the first release, and the release is successful.
%%
%% First build rebar3 escript used by this test suite.
%% rebar3 escriptize

-module( mixplugin_SUITE ).

-export( [initial_release/1, re_release/1] ).

%% Common test callbacks
-export( [all/0, end_per_suite/1, init_per_suite/1] ).


all() -> [initial_release, re_release].

end_per_suite( _Config ) -> ok.

init_per_suite( Config ) ->
	Repo = proplists:get_value( data_dir, Config ),
	Rm_command = "cd " ++ Repo ++ " && rm -rf _build",
	Result = os:cmd( Rm_command ),
	ct:pal( "rm -rf _build ~p", [Result] ),
	Config.

%% Test cases

initial_release( Config ) -> release( Config ).

re_release( Config ) -> release( Config ).

%%====================================================================
%% Internal functions
%%====================================================================

%% Find where rebar3 directory is. Where the escript was built.
rebar_escript( {ok, Directory} ) ->
	Rebar_directory = filename:join( lists:takewhile(fun rebar_escript_build/1, filename:split(Directory)) ),
	filename:join( Rebar_directory, "rebar3" ).

rebar_escript_build( "_build" ) -> false;
rebar_escript_build( _) -> true.


release( Config ) ->
	Repo = proplists:get_value( data_dir, Config ),
	Rebar = rebar_escript( file:get_cwd() ),
	Release_command = "cd " ++ Repo ++ " && " ++ Rebar ++ " release",

	Result = os:cmd( Release_command ),

	ct:pal( "~p release\n~p", [Rebar, Result] ),
	[_Release_bin] = filelib:wildcard( filename:join([Repo, "_build", "default", "rel", "*", "bin"]) ).
