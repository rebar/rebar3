%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et

-module(rebar_prv_xref).

-behaviour(provider).

-export([init/1,
         do/1,
         format_error/1,
         filter_xref_results/3]).

-include("rebar.hrl").
-include_lib("providers/include/providers.hrl").

-define(PROVIDER, xref).
-define(DEPS, [compile]).
-define(SUPPORTED_XREFS, [undefined_function_calls, undefined_functions,
                          locals_not_used, exports_not_used,
                          deprecated_function_calls, deprecated_functions]).

%% ===================================================================
%% Public API
%% ===================================================================

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([{name, ?PROVIDER},
                                 {module, ?MODULE},
                                 {deps, ?DEPS},
                                 {bare, true},
                                 {example, "rebar3 xref"},
                                 {short_desc, short_desc()},
                                 {desc, desc()}]),
    State1 = rebar_state:add_provider(State, Provider),
    {ok, State1}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    rebar_paths:set_paths([runtime], State),
    XrefChecks = prepare(State),
    XrefIgnores = rebar_state:get(State, xref_ignores, []),
    %% Run xref checks
    ?INFO("Running cross reference analysis...", []),
    XrefResults = xref_checks(XrefChecks, XrefIgnores),

    %% Run custom queries
    QueryChecks = rebar_state:get(State, xref_queries, []),
    QueryResults = lists:foldl(fun check_query/2, [], QueryChecks),
    stopped = xref:stop(xref),
    case XrefResults =:= [] andalso QueryResults =:= [] of
        true ->
            {ok, State};
        false ->
            ?PRV_ERROR({xref_issues, XrefResults, QueryResults})
    end.

-spec format_error(any()) -> iolist().
format_error({xref_issues, XrefResults, QueryResults}) ->
    lists:flatten(display_results(XrefResults, QueryResults));
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%% ===================================================================
%% Internal functions
%% ===================================================================

short_desc() ->
    "Run cross reference analysis.".

desc() ->
    io_lib:format(
      "~ts~n"
      "~n"
      "Valid rebar.config options:~n"
      "  ~p~n"
      "  ~p~n"
      "  ~p~n"
      "  ~p~n",
      [short_desc(),
       {xref_warnings, false},
       {xref_extra_paths,[]},
       {xref_checks, [undefined_function_calls, undefined_functions,
                      locals_not_used, exports_not_used,
                      deprecated_function_calls, deprecated_functions]},
       {xref_queries,
        [{"(xc - uc) || (xu - x - b"
          " - (\"mod\":\".*foo\"/\"4\"))",[]}]}
      ]).

-spec prepare(rebar_state:t()) -> [atom()].
prepare(State) ->
    {ok, _} = xref:start(xref),
    ok = xref:set_library_path(xref, code_path(State)),

    xref:set_default(xref, [{warnings,
                             rebar_state:get(State, xref_warnings, false)},
                            {verbose, rebar_log:is_verbose(State)}]),

    [{ok, _} = xref:add_directory(xref, Dir)
     || App <- rebar_state:project_apps(State),
        %% the directory may not exist in rare cases of a compile
        %% hook of a dep running xref prior to the full job being done
        Dir <- [rebar_app_info:ebin_dir(App)], filelib:is_dir(Dir)],

    %% Get list of xref checks we want to run
    ConfXrefChecks = rebar_state:get(State, xref_checks,
                                     [exports_not_used,
                                      undefined_function_calls]),

    XrefChecks = sets:to_list(sets:intersection(
                                sets:from_list(?SUPPORTED_XREFS),
                                sets:from_list(ConfXrefChecks))),
    XrefChecks.

xref_checks(XrefChecks, XrefIgnores) ->
    run_xref_checks(XrefChecks, XrefIgnores, []).

run_xref_checks([], _XrefIgnores, Acc) ->
    Acc;
run_xref_checks([XrefCheck | T], XrefIgnores, Acc) ->
    {ok, Results} = xref:analyze(xref, XrefCheck),
    case filter_xref_results(XrefCheck, XrefIgnores, Results) of
        [] ->
            run_xref_checks(T, XrefIgnores, Acc);
        FilterResult ->
            run_xref_checks(T, XrefIgnores, [{XrefCheck, FilterResult} | Acc])
    end.

check_query({Query, Value}, Acc) ->
    {ok, Answer} = xref:q(xref, Query),
    case Answer =:= Value of
        false ->
            [{Query, Value, Answer} | Acc];
        _     ->
            Acc
    end.

code_path(State) ->
    [P || P <- code:get_path() ++
              rebar_state:get(State, xref_extra_paths, []),
          filelib:is_dir(P)].

%% Ignore behaviour functions, and explicitly marked functions
%%
%% Functions can be ignored by using
%% -ignore_xref([{F, A}, {M, F, A}...]).
get_xref_ignorelist(Mod, XrefCheck) ->
    %% Get ignore_xref attribute and combine them in one list
    Attributes =
        try
            Mod:module_info(attributes)
        catch
            _Class:_Error -> []
        end,

    IgnoreXref = keyall(ignore_xref, Attributes),

    BehaviourCallbacks = get_behaviour_callbacks(XrefCheck, Attributes),

    %% And create a flat {M,F,A} list
    lists:foldl(
      fun({F, A}, Acc) -> [{Mod,F,A} | Acc];
         ({M, F, A}, Acc) -> [{M,F,A} | Acc];
         (M, Acc) when is_atom(M) -> [M | Acc]
      end, [], lists:flatten([IgnoreXref, BehaviourCallbacks])).

keyall(Key, List) ->
    lists:flatmap(fun({K, L}) when Key =:= K -> L; (_) -> [] end, List).

get_behaviour_callbacks(exports_not_used, Attributes) ->
    lists:map(fun(Mod) ->
        try
            Mod:behaviour_info(callbacks)
        catch
            error:undef ->
                ?WARN("Behaviour ~p is used but cannot be found.", [Mod]),
                []
        end
    end, keyall(behaviour, Attributes) ++ keyall(behavior, Attributes));
get_behaviour_callbacks(_XrefCheck, _Attributes) ->
    [].

filter_xref_results(XrefCheck, XrefIgnores, XrefResults) ->
    SearchModules = lists:usort(
                      lists:map(
                        fun({Mt,_Ft,_At}) -> Mt;
                           ({{Ms,_Fs,_As},{_Mt,_Ft,_At}}) -> Ms;
                           (_) -> undefined
                        end, XrefResults)),

    Ignores = XrefIgnores ++ lists:flatmap(fun(Module) ->
                                    get_xref_ignorelist(Module, XrefCheck)
                            end, SearchModules),
    lists:filter( fun(Result) -> pred_xref_result(Result, Ignores) end, XrefResults).

pred_xref_result({Src, Dest}, Ignores) -> pred_xref_result1(Src, Ignores)
    andalso pred_xref_result1(Dest, Ignores);
pred_xref_result(Vertex, Ignores) -> pred_xref_result1(Vertex, Ignores).

pred_xref_result1(Vertex, Ignores) ->
    Mod = case Vertex of {Module, _Func, _Arity} -> Module;
             _ -> Vertex end,
    not lists:member(Vertex, Ignores) andalso not lists:member(Mod, Ignores).

display_results(XrefResults, QueryResults) ->
    [lists:map(fun display_xref_results_for_type/1, XrefResults),
     lists:map(fun display_query_result/1, QueryResults)].

display_query_result({Query, Answer, Value}) ->
    io_lib:format("Query ~ts~n answer ~p~n did not match ~p~n",
                  [Query, Answer, Value]).

display_xref_results_for_type({Type, XrefResults}) ->
    lists:map(display_xref_result_fun(Type), XrefResults).

display_xref_result_fun(Type) ->
    fun(XrefResult) ->
            {Source, SMFA, TMFA} =
                case XrefResult of
                    {MFASource, MFATarget} ->
                        {format_mfa_source(MFASource),
                         format_mfa(MFASource),
                         format_mfa(MFATarget)};
                    MFATarget ->
                        {format_mfa_source(MFATarget),
                         format_mfa(MFATarget),
                         undefined}
                end,
            case Type of
                undefined_function_calls ->
                    io_lib:format("~tsWarning: ~ts calls undefined function ~ts (Xref)\n",
                                  [Source, SMFA, TMFA]);
                undefined_functions ->
                    io_lib:format("~tsWarning: ~ts is undefined function (Xref)\n",
                                  [Source, SMFA]);
                locals_not_used ->
                    io_lib:format("~tsWarning: ~ts is unused local function (Xref)\n",
                                  [Source, SMFA]);
                exports_not_used ->
                    io_lib:format("~tsWarning: ~ts is unused export (Xref)\n",
                                  [Source, SMFA]);
                deprecated_function_calls ->
                    io_lib:format("~tsWarning: ~ts calls deprecated function ~ts (Xref)\n",
                                  [Source, SMFA, TMFA]);
                deprecated_functions ->
                    io_lib:format("~tsWarning: ~ts is deprecated function (Xref)\n",
                                  [Source, SMFA]);
                Other ->
                    io_lib:format("~tsWarning: ~ts - ~ts xref check: ~ts (Xref)\n",
                                  [Source, SMFA, TMFA, Other])
            end
    end.

format_mfa({M, F, A}) ->
    ?FMT("~ts:~ts/~w", [M, F, A]).

format_mfa_source(MFA) ->
    case find_mfa_source(MFA) of
        {module_not_found, function_not_found} -> "";
        {Source, function_not_found} -> ?FMT("~ts: ", [Source]);
        {Source, Line} -> ?FMT("~ts:~w: ", [Source, Line])
    end.

%%
%% Extract an element from a tuple, or undefined if N > tuple size
%%
safe_element(N, Tuple) ->
    try
        element(N, Tuple)
    catch
        error:badarg ->
            undefined
    end.

%%
%% Given a MFA, find the file and LOC where it's defined. Note that
%% xref doesn't work if there is no abstract_code, so we can avoid
%% being too paranoid here.
%%
find_mfa_source({M, F, A}) ->
    case code:get_object_code(M) of
        error -> {module_not_found, function_not_found};
        {M, Bin, _} -> find_function_source(M,F,A,Bin)
    end.

find_function_source(M, F, A, Bin) ->
    ChunksLookup = beam_lib:chunks(Bin, [abstract_code]),
    {ok, {M, [{abstract_code, AbstractCodeLookup}]}} = ChunksLookup,
    case AbstractCodeLookup of
        no_abstract_code ->
            % There isn't much else we can do at this point
            {module_not_found, function_not_found};
        {raw_abstract_v1, AbstractCode} ->
            find_function_source_in_abstract_code(F, A, AbstractCode)
    end.

find_function_source_in_abstract_code(F, A, AbstractCode) ->
    %% Extract the original source filename from the abstract code
    [{attribute, _, file, {Source0, _}} | _] = AbstractCode,
    Source = rebar_dir:make_relative_path(Source0, rebar_dir:get_cwd()),
    %% Extract the line number for a given function def
    Fn = [E || E <- AbstractCode,
               safe_element(1, E) == function,
               safe_element(3, E) == F,
               safe_element(4, E) == A],
    case Fn of
        [{function, Anno, F, _, _}] -> {Source, erl_anno:line(Anno)};
        %% do not crash if functions are exported, even though they
        %% are not in the source.
        %% parameterized modules add new/1 and instance/1 for example.
        [] -> {Source, function_not_found}
    end.
