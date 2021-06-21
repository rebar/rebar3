{{=@@ @@=}}
%%%-------------------------------------------------------------------
%% @doc @@name@@ top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(@@name@@_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer(),        % optional
%%                 auto_shutdown()}                % optional
%% child_spec() = #{id => child_id(),             % mandatory
%%                  start => mfargs(),            % mandatory
%%                  restart => restart(),         % optional
%%                  significant => significant(), % optional
%%                  shutdown => shutdown(),       % optional
%%                  type => worker(),             % optional
%%                  modules => modules()}         % optional
init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 0,
                 period => 1,
                 auto_shutdown => never},
    ChildSpecs = [],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
