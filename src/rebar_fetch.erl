%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% -------------------------------------------------------------------
-module(rebar_fetch).

-export([lock_source/3,
         download_source/2,
         needs_update/3]).

-export([format_error/1]).

-include("rebar.hrl").
-include_lib("providers/include/providers.hrl").

-spec lock_source(file:filename_all(), rebar_resource:source(), rebar_state:t())
                 -> rebar_resource:source() | {error, string()}.
lock_source(AppDir, Source, State) ->
    Resources = rebar_state:resources(State),
    Module = get_resource_type(Source, Resources),
    Module:lock(AppDir, Source).

-spec download_source(rebar_app_info:t(), rebar_state:t())
                     -> rebar_app_info:t() | {error, any()}.
download_source(AppInfo, State) ->
    AppDir = rebar_app_info:dir(AppInfo),
    Source = rebar_app_info:source(AppInfo),
    try download_source_(AppDir, Source, State) of
        true ->
            %% freshly downloaded, update the app info opts to reflect the new config
            Config = rebar_config:consult(AppDir),
            AppInfo1 = rebar_app_info:update_opts(AppInfo, rebar_app_info:opts(AppInfo), Config),
            case rebar_app_discover:find_app(AppInfo1, AppDir, all) of
                {true, AppInfo2} ->
                    AppInfo2;
                false ->
                    throw(?PRV_ERROR({dep_app_not_found, AppDir, rebar_app_info:name(AppInfo1)}))
            end;
        Error ->
            throw(?PRV_ERROR(Error))
    catch
        throw:{no_resource, Type, Location} ->
            throw(?PRV_ERROR({no_resource, Location, Type}));
        ?WITH_STACKTRACE(C,T,S)
            ?DEBUG("rebar_fetch exception ~p ~p ~p", [C, T, S]),
            throw(?PRV_ERROR({fetch_fail, Source}))
    end.

download_source_(AppDir, Source, State) ->
    Resources = rebar_state:resources(State),
    Module = get_resource_type(Source, Resources),
    TmpDir = ec_file:insecure_mkdtemp(),
    AppDir1 = rebar_utils:to_list(AppDir),
    case Module:download(TmpDir, Source, State) of
        {ok, _} ->
            ec_file:mkdir_p(AppDir1),
            code:del_path(filename:absname(filename:join(AppDir1, "ebin"))),
            ok = rebar_file_utils:rm_rf(filename:absname(AppDir1)),
            ?DEBUG("Moving checkout ~p to ~p", [TmpDir, filename:absname(AppDir1)]),
            ok = rebar_file_utils:mv(TmpDir, filename:absname(AppDir1)),
            true;
        Error ->
            Error
    end.

-spec needs_update(file:filename_all(), rebar_resource:source(), rebar_state:t())
                  -> boolean() | {error, string()}.
needs_update(AppDir, Source, State) ->
    Resources = rebar_state:resources(State),
    Module = get_resource_type(Source, Resources),
    try
        Module:needs_update(AppDir, Source)
    catch
        _:_ ->
            true
    end.

format_error({bad_download, CachePath}) ->
    io_lib:format("Download of package does not match md5sum from server: ~ts", [CachePath]);
format_error({unexpected_hash, CachePath, Expected, Found}) ->
    io_lib:format("The checksum for package at ~ts (~ts) does not match the "
                  "checksum previously locked (~ts). Either unlock or "
                  "upgrade the package, or make sure you fetched it from "
                  "the same index from which it was initially fetched.",
                  [CachePath, Found, Expected]);
format_error({failed_extract, CachePath}) ->
    io_lib:format("Failed to extract package: ~ts", [CachePath]);
format_error({bad_etag, Source}) ->
    io_lib:format("MD5 Checksum comparison failed for: ~ts", [Source]);
format_error({fetch_fail, Name, Vsn}) ->
    io_lib:format("Failed to fetch and copy dep: ~ts-~ts", [Name, Vsn]);
format_error({fetch_fail, Source}) ->
    io_lib:format("Failed to fetch and copy dep: ~p", [Source]);
format_error({bad_checksum, File}) ->
    io_lib:format("Checksum mismatch against tarball in ~ts", [File]);
format_error({bad_registry_checksum, File}) ->
    io_lib:format("Checksum mismatch against registry in ~ts", [File]);
format_error({no_resource, Location, Type}) ->    
    io_lib:format("Cannot handle dependency ~ts.~n"
                  "     No module for resource type ~p", [Location, Type]).

get_resource_type({Type, Location}, Resources) ->
    get_resource_module(Type, Location, Resources);
get_resource_type({Type, Location, _}, Resources) ->
    get_resource_module(Type, Location, Resources);
get_resource_type({Type, _, _, Location}, Resources) ->
    get_resource_module(Type, Location, Resources);
get_resource_type(_, _) ->
    rebar_pkg_resource.

get_resource_module(Type, Location, Resources) ->   
    case rebar_resource:find_resource_module(Type, Resources) of
        {error, not_found} ->
            throw({no_resource, Location, Type});
        {ok, Module} ->
            Module
    end.

