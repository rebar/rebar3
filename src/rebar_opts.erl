-module(rebar_opts).

-export([get/2,
         get/3,
         set/3,

         erl_opts/1,

         apply_overrides/3,
         add_to_profile/3,
         merge_opts/2,
         merge_opts/3]).

-include("rebar.hrl").

get(Opts, Key) ->
    {ok, Value} = dict:find(Key, Opts),
    Value.

get(Opts, Key, Default) ->
    case dict:find(Key, Opts) of
        {ok, Value} ->
            Value;
        error ->
            Default
    end.

set(Opts, Key, Value) ->
    dict:store(Key, Value, Opts).

%% @doc Return list of erl_opts
-spec erl_opts(rebar_dict()) -> list().
erl_opts(Opts) ->
    RawErlOpts = filter_defines(?MODULE:get(Opts, erl_opts, []), []),
    Defines = [{d, list_to_atom(D)} ||
                  D <- ?MODULE:get(Opts, defines, [])],
    AllOpts = Defines ++ RawErlOpts,
    lists:reverse(filter_debug_info(lists:reverse(AllOpts))).

filter_debug_info([]) ->
    %% Default == ON
    [debug_info];
filter_debug_info([debug_info|_] = L) ->
    %% drop no_debug_info and {debug_info_key, _} since those would
    %% conflict with a plain debug_info
    [debug_info |
     lists:filter(fun(K) ->
         K =/= no_debug_info andalso K =/= debug_info andalso
         not (is_tuple(K) andalso element(1,K) =:= debug_info_key)
     end, L)];
filter_debug_info([{debug_info, _} = H | T]) ->
    %% custom debug_info field; keep and filter the rest except
    %% without no_debug_info. Still have to filter for regular or crypto
    %% debug_info.
    [H | filter_debug_info(lists:filter(fun(K) -> K =/= no_debug_info end, T))];
filter_debug_info([{debug_info_key, _}=H | T]) ->
    %% Drop no_debug_info and regular debug_info
    [H | lists:filter(fun(K) ->
            K =/= no_debug_info andalso K =/= debug_info andalso
            not (is_tuple(K) andalso element(1,K) =:= debug_info_key)
         end, T)];
filter_debug_info([no_debug_info|T]) ->
    %% Drop all debug info
    lists:filter(fun(debug_info) -> false
                 ;  ({debug_info, _}) -> false
                 ;  ({debug_info_key, _}) -> false
                 ;  (no_debug_info) -> false
                 ;  (_Other) -> true
                 end, T);
filter_debug_info([H|T]) ->
    [H|filter_debug_info(T)].

apply_overrides(Opts, Name, Overrides) ->
    %% Inefficient. We want the order we get here though.
    Opts1 = lists:foldl(fun({override, O}, OptsAcc) ->
                                override_opt(O, OptsAcc);
                            (_, OptsAcc) ->
                                 OptsAcc
                        end, Opts, Overrides),

    Opts2 = lists:foldl(fun({add, O}, OptsAcc) ->
                                add_opt(O, OptsAcc);
                           (_, OptsAcc) ->
                                OptsAcc
                        end, Opts1, Overrides),

    Opts3 = lists:foldl(fun({del, O}, OptsAcc) ->
                                del_opt(O, OptsAcc);
                            (_, OptsAcc) ->
                                 OptsAcc
                        end, Opts2, Overrides),

    Opts4 = lists:foldl(fun({override, N, O}, OptsAcc) when N =:= Name ->
                                override_opt(O, OptsAcc);
                            (_, OptsAcc) ->
                                 OptsAcc
                        end, Opts3, Overrides),

    Opts5 = lists:foldl(fun({add, N, O}, OptsAcc) when N =:= Name ->
                                add_opt(O, OptsAcc);
                           (_, OptsAcc) ->
                                OptsAcc
                        end, Opts4, Overrides),

    Opts6 = lists:foldl(fun({del, N, O}, OptsAcc) when N =:= Name ->
                                del_opt(O, OptsAcc);
                            (_, OptsAcc) ->
                                 OptsAcc
                        end, Opts5, Overrides),

    Opts6.

add_to_profile(Opts, Profile, KVs) when is_atom(Profile), is_list(KVs) ->
    Profiles = ?MODULE:get(Opts, profiles, []),
    ProfileOpts = dict:from_list(proplists:get_value(Profile, Profiles, [])),
    NewOpts = merge_opts(Profile, dict:from_list(KVs), ProfileOpts),
    NewProfiles = [{Profile, dict:to_list(NewOpts)}|lists:keydelete(Profile, 1, Profiles)],
    set(Opts, profiles, NewProfiles).

merge_opts(Profile, NewOpts, OldOpts) ->
    Opts = merge_opts(NewOpts, OldOpts),

    Opts2 = case dict:find(plugins, NewOpts) of
        {ok, Value} ->
            dict:store({plugins, Profile}, Value, Opts);
        error ->
            Opts
    end,

    case dict:find(deps, NewOpts) of
        {ok, Value2} ->
            dict:store({deps, Profile}, Value2, Opts2);
        error ->
            Opts2
    end.

merge_opts(NewOpts, OldOpts) ->
    dict:merge(fun merge_opt/3, NewOpts, OldOpts).

%% Internal functions

add_opt(Opts1, Opts2) ->
    lists:foldl(fun({deps, Value}, OptsAcc) ->
                        OldValue = ?MODULE:get(OptsAcc, {deps,default}, []),
                        set(OptsAcc, {deps,default}, Value++OldValue);
                    ({Key, Value}, OptsAcc) ->
                        OldValue = ?MODULE:get(OptsAcc, Key, []),
                        set(OptsAcc, Key, Value++OldValue)
                end, Opts2, Opts1).

del_opt(Opts1, Opts2) ->
    lists:foldl(fun({deps, Value}, OptsAcc) ->
                        OldValue = ?MODULE:get(OptsAcc, {deps,default}, []),
                        set(OptsAcc, {deps,default}, del_dep(OldValue, Value));
                   ({Key, Value}, OptsAcc) ->
                        OldValue = ?MODULE:get(OptsAcc, Key, []),
                        set(OptsAcc, Key, del_dep(OldValue, Value))
                end, Opts2, Opts1).

override_opt(Opts1, Opts2) ->
    lists:foldl(fun({deps, Value}, OptsAcc) ->
                        set(OptsAcc, {deps,default}, Value);
                   ({Key, Value}, OptsAcc) ->
                        set(OptsAcc, Key, Value)
                end, Opts2, Opts1).

%% @private
del_dep(OldValue, [Value]) when is_atom(Value) ->
    NewValue = lists:keydelete(atom_to_binary(Value, utf8), 1, OldValue),
    del_dep(NewValue, OldValue, [Value]);
del_dep(OldValue, [{Value, _Version, _Source}]) ->
    NewValue = lists:keydelete(atom_to_binary(Value, utf8), 1, OldValue),
    del_dep(NewValue, OldValue, [{Value, _Version, _Source}]);
del_dep(OldValue, [Value]) ->
    del_dep(OldValue, OldValue, [Value]);
del_dep(OldValue, [Value|Values]) ->
    NewValue = del_dep(del_dep(OldValue, [Value]), OldValue, [Value]),
    del_dep(NewValue, Values).

%% @private
%% If the initial deletion did not work remove it as always
%% to ensure rebar3 at least maintains its old behaviour.
del_dep(OldValue, OldValue, Value) ->
    OldValue--Value;
del_dep(NewValue, _OldValue, _Value) ->
    NewValue.

%%
%% Function for dict:merge/3 (in merge_opts/2) to merge options by priority.
%%
merge_opt(deps, _NewValue, OldValue) ->
    OldValue;
merge_opt({deps, _}, NewValue, _OldValue) ->
    NewValue;
merge_opt(plugins, NewValue, _OldValue) ->
    NewValue;
merge_opt({plugins, _}, NewValue, _OldValue) ->
    NewValue;
merge_opt(profiles, NewValue, OldValue) ->
    %% Merge up sparse pairs of {Profile, Opts} into a joined up
    %% {Profile, OptsNew, OptsOld} list.
    ToMerge = normalise_profile_pairs(lists:sort(NewValue),
                                      lists:sort(OldValue)),
    [{K,dict:to_list(merge_opts(dict:from_list(New), dict:from_list(Old)))}
     || {K,New,Old} <- ToMerge];
merge_opt(erl_first_files, Value, Value) ->
    Value;
merge_opt(erl_first_files, NewValue, OldValue) ->
    OldValue ++ NewValue;
merge_opt(mib_first_files, Value, Value) ->
    Value;
merge_opt(mib_first_files, NewValue, OldValue) ->
    OldValue ++ NewValue;
merge_opt(relx, NewValue, OldValue) ->
    Partition = fun(C) -> is_tuple(C) andalso element(1, C) =:= overlay end,
    {NewOverlays, NewOther} = lists:partition(Partition, NewValue),
    {OldOverlays, OldOther} = lists:partition(Partition, OldValue),
    rebar_utils:tup_umerge(NewOverlays, OldOverlays)
    ++ OldOther ++ NewOther;
merge_opt(Key, NewValue, OldValue)
    when Key == erl_opts; Key == eunit_compile_opts; Key == ct_compile_opts ->
    merge_erl_opts(lists:reverse(OldValue), NewValue);
merge_opt(_Key, NewValue, OldValue) when is_list(NewValue) ->
    case io_lib:printable_list(NewValue) of
        true when NewValue =:= [] ->
            case io_lib:printable_list(OldValue) of
                true ->
                    NewValue;
                false ->
                    OldValue
            end;
        true ->
            NewValue;
        false ->
            rebar_utils:tup_umerge(NewValue, OldValue)
    end;
merge_opt(_Key, NewValue, _OldValue) ->
    NewValue.

%%
%% Merge Erlang compiler options such that the result
%%  a)  Doesn't contain duplicates.
%%  b)  Resulting options are ordered by increasing precedence as expected by
%%      the compiler.
%% The first parameter is the lower precedence options, in reverse order, to
%% be merged with the higher-precedence options in the second parameter.
%%
merge_erl_opts([Opt | Opts], []) ->
    merge_erl_opts(Opts, [Opt]);
merge_erl_opts([Opt | Opts], Merged) ->
    case lists:member(Opt, Merged) of
        true ->
            merge_erl_opts(Opts, Merged);
        _ ->
            merge_erl_opts(Opts, [Opt | Merged])
    end;
merge_erl_opts([], Merged) ->
    Merged.

%%
%% Filter a list of erl_opts platform_define options such that only
%% those which match the provided architecture regex are returned.
%%
filter_defines([], Acc) ->
    lists:reverse(Acc);
filter_defines([{platform_define, ArchRegex, Key} | Rest], Acc) ->
    case rebar_utils:is_arch(ArchRegex) of
        true ->
            filter_defines(Rest, [{d, Key} | Acc]);
        false ->
            filter_defines(Rest, Acc)
    end;
filter_defines([{platform_define, ArchRegex, Key, Value} | Rest], Acc) ->
    case rebar_utils:is_arch(ArchRegex) of
        true ->
            filter_defines(Rest, [{d, Key, Value} | Acc]);
        false ->
            filter_defines(Rest, Acc)
    end;
filter_defines([Opt | Rest], Acc) ->
    filter_defines(Rest, [Opt | Acc]).

%% @private takes two lists of profile tuples and merges them
%% into one list of 3-tuples containing the values of either
%% profiles.
%% Any missing profile in one of the keys is replaced by an
%% empty one.
-spec normalise_profile_pairs([Profile], [Profile]) -> [Pair] when
      Profile :: {Name, Opts},
      Pair :: {Name, Opts, Opts},
      Name :: atom(),
      Opts :: [term()].
normalise_profile_pairs([], []) ->
    [];
normalise_profile_pairs([{P,V}|Ps], []) ->
    [{P,V,[]} | normalise_profile_pairs(Ps, [])];
normalise_profile_pairs([], [{P,V}|Ps]) ->
    [{P,[],V} | normalise_profile_pairs([], Ps)];
normalise_profile_pairs([{P,VA}|PAs], [{P,VB}|PBs]) ->
    [{P,VA,VB} | normalise_profile_pairs(PAs, PBs)];
normalise_profile_pairs([{PA,VA}|PAs], [{PB,VB}|PBs]) when PA < PB ->
    [{PA,VA,[]} | normalise_profile_pairs(PAs, [{PB, VB}|PBs])];
normalise_profile_pairs([{PA,VA}|PAs], [{PB,VB}|PBs]) when PA > PB ->
    [{PB,[],VB} | normalise_profile_pairs([{PA,VA}|PAs], PBs)].
