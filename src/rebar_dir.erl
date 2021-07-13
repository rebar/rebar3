%%% @doc utility functions for directory and path handling of all kind.
-module(rebar_dir).

-export([base_dir/1,
         profile_dir/2,
         profile_dir_name/1,
         deps_dir/1,
         deps_dir/2,
         root_dir/1,
         checkouts_dir/1,
         checkouts_dir/2,
         checkouts_out_dir/1,
         checkouts_out_dir/2,
         plugins_dir/1,
         lib_dirs/1,
         home_dir/0,
         global_config_dir/1,
         global_config/1,
         global_config/0,
         global_cache_dir/1,
         local_cache_dir/1,
         get_cwd/0,
         template_globals/1,
         template_dir/1,
         processing_base_dir/1,
         processing_base_dir/2,
         make_relative_path/2,
         src_dirs/1, src_dirs/2,
         src_dir_opts/2, recursive/2,
         extra_src_dirs/1, extra_src_dirs/2,
         all_src_dirs/1, all_src_dirs/3,
         retarget_path/2,
         format_source_file_name/1,
         format_source_file_name/2]).

-include("rebar.hrl").

%% @doc returns the directory root for build artifacts
%% for the current profile, such as `_build/default/'.
-spec base_dir(rebar_state:t()) -> file:filename_all().
base_dir(State) ->
    profile_dir(rebar_state:opts(State), rebar_state:current_profiles(State)).

%% @doc returns the directory root for build artifacts for a given set
%% of profiles.
-spec profile_dir(rebar_dict(), [atom(), ...]) -> file:filename_all().
profile_dir(Opts, Profiles) ->
    BasePath =
        case Profiles of
            [global | _] -> ?MODULE:global_cache_dir(Opts);
            [_|_] -> rebar_opts:get(Opts, base_dir, ?DEFAULT_BASE_DIR)
        end,
    DirName = profile_dir_name_(Profiles),
    filename:join(BasePath, DirName).

%% @doc returns the directory name for build artifacts for a given set
%% of profiles.
-spec profile_dir_name(rebar_state:t()) -> file:filename_all().
profile_dir_name(State) ->
    profile_dir_name_(rebar_state:current_profiles(State)).

-spec profile_dir_name_([atom(), ...]) -> file:filename_all().
profile_dir_name_(Profiles)
  when is_list(Profiles) ->
    case [rebar_utils:to_list(P) || P <- Profiles] of
        ["global" | _] -> "";
        ["bootstrap", "default"] -> "default";
        ["default"] -> "default";
        %% drop `default' from the profile dir if it's implicit and reverse order
        %%  of profiles to match order passed to `as`
        ["default"|NonDefaultNames] -> rebar_string:join(NonDefaultNames, "+")
    end.

%% @doc returns the directory where dependencies should be placed
%% given the current profile.
-spec deps_dir(rebar_state:t()) -> file:filename_all().
deps_dir(State) ->
    filename:join(base_dir(State), rebar_state:get(State, deps_dir, ?DEFAULT_DEPS_DIR)).

%% @doc returns the directory where a dependency should be placed
%% given the current profile, based on its app name. Expects to be passed
%% the result of `deps_dir/1' as a first argument.
-spec deps_dir(file:filename_all(), file:filename_all()) -> file:filename_all().
deps_dir(DepsDir, App) ->
    filename:join(DepsDir, App).

%% @doc returns the absolute path for the project root (by default,
%% the current working directory for the currently running escript).
root_dir(State) ->
    filename:absname(rebar_state:get(State, root_dir, ?DEFAULT_ROOT_DIR)).

%% @doc returns the expected location of the `_checkouts' directory.
-spec checkouts_dir(rebar_state:t()) -> file:filename_all().
checkouts_dir(State) ->
    rebar_file_utils:canonical_path(filename:join(root_dir(State), rebar_state:get(State, checkouts_dir, ?DEFAULT_CHECKOUTS_DIR))).

%% @doc returns the expected location of a given app in the checkouts
%% directory for the project.
-spec checkouts_dir(rebar_state:t(), file:filename_all()) -> file:filename_all().
checkouts_dir(State, App) ->
    filename:join(checkouts_dir(State), App).

%% @doc returns the location of the directory checkouts are built to
-spec checkouts_out_dir(rebar_state:t()) -> file:filename_all().
checkouts_out_dir(State) ->
    filename:join(base_dir(State), rebar_state:get(State, checkouts_out_dir, ?DEFAULT_CHECKOUTS_OUT_DIR)).

%% @doc returns the expected location of a given app in the checkouts
%% directory for the project.
-spec checkouts_out_dir(rebar_state:t(), file:filename_all()) -> file:filename_all().
checkouts_out_dir(State, App) ->
    filename:join(checkouts_out_dir(State), App).

%% @doc Returns the directory where plugins are located.
-spec plugins_dir(rebar_state:t()) -> file:filename_all().
plugins_dir(State) ->
    case lists:member(global, rebar_state:current_profiles(State)) of
        true ->
            filename:join([base_dir(State), global_config_dir(State), rebar_state:get(State, plugins_dir, ?DEFAULT_PLUGINS_DIR)]);
        false ->
            filename:join(base_dir(State), rebar_state:get(State, plugins_dir, ?DEFAULT_PLUGINS_DIR))
    end.

%% @doc returns the list of relative path where the project applications can
%% be located.
-spec lib_dirs(rebar_state:t()) -> file:filename_all().
lib_dirs(State) ->
    rebar_state:get(State, project_app_dirs, ?DEFAULT_PROJECT_APP_DIRS).

%% @doc returns the user's home directory.
-spec home_dir() -> file:filename_all().
home_dir() ->
    {ok, [[Home]]} = init:get_argument(home),
    Home.

basedir(Type) ->
    filename:basedir(Type, "rebar3", #{os => linux}).

%% @doc returns the directory where the global configuration files for rebar3
%% may be stored.
-spec global_config_dir(rebar_state:t()) -> file:filename_all().
global_config_dir(State) ->
    case rebar_config_dir(State) of
        undefined -> basedir(user_config);
        Path -> filename:join([Path, ".config", "rebar3"])
    end.

rebar_config_dir(State) ->
    case os:getenv("REBAR_GLOBAL_CONFIG_DIR") of
        false ->
            rebar_state:get(State, global_rebar_dir, undefined);
        ConfDir ->
            ConfDir
    end.

%% @doc returns the path of the global rebar.config file
-spec global_config(rebar_state:t()) -> file:filename_all().
global_config(State) ->
    filename:join(global_config_dir(State), "rebar.config").

%% @doc returns the default path of the global rebar.config file
-spec global_config() -> file:filename_all().
global_config() ->
    filename:join([basedir(user_config), "rebar.config"]).

%% @doc returns the location for the global cache directory
-spec global_cache_dir(rebar_dict()) -> file:filename_all().
global_cache_dir(Opts) ->
    rebar_opts:get(Opts, global_rebar_dir, basedir(user_cache)).

%% @doc appends the cache directory to the path passed to this function.
-spec local_cache_dir(file:filename_all()) -> file:filename_all().
local_cache_dir(Dir) ->
    filename:join(Dir, ".rebar3").

%% @doc returns the current working directory, with some specific
%% conversions and handling done to be cross-platform compatible.
-spec get_cwd() -> file:filename_all().
get_cwd() ->
    {ok, Dir} = file:get_cwd(),
    %% On windows cwd may return capital letter for drive,
    %% for example C:/foobar. But as said in http://www.erlang.org/doc/man/filename.html#join-1
    %% filename:join/1,2 anyway will convert drive-letter to lowercase, so we have to "internalize"
    %% cwd as soon as it possible.
    filename:join([Dir]).

%% @doc returns the file location for the global template
%% configuration variables file.
-spec template_globals(rebar_state:t()) -> file:filename_all().
template_globals(State) ->
    filename:join([global_config_dir(State), "templates", "globals"]).

%% @doc returns the location for the global template directory
-spec template_dir(rebar_state:t()) -> file:filename_all().
template_dir(State) ->
    filename:join([global_config_dir(State), "templates"]).

%% @doc checks if the current working directory is the base directory
%% for the project.
-spec processing_base_dir(rebar_state:t()) -> boolean().
processing_base_dir(State) ->
    Cwd = get_cwd(),
    processing_base_dir(State, Cwd).

%% @doc checks if the passed in directory is the base directory for
%% the project.
-spec processing_base_dir(rebar_state:t(), file:filename()) -> boolean().
processing_base_dir(State, Dir) ->
    AbsDir = filename:absname(Dir),
    AbsDir =:= rebar_state:get(State, base_dir).

%% @doc take a source and a target path, and relativize the target path
%% onto the source.
%%
%% Example:
%% ```
%% 1> rebar_dir:make_relative_path("a/b/c/d/file", "a/b/file").
%% "c/d/file"
%% 2> rebar_dir:make_relative_path("a/b/file", "a/b/c/d/file").
%% "../../file"
%% '''
-spec make_relative_path(file:filename(), file:filename()) -> file:filename().
make_relative_path(Source, Target) ->
    AbsSource = rebar_file_utils:normalized_path(Source),
    AbsTarget = rebar_file_utils:normalized_path(Target),
    do_make_relative_path(filename:split(AbsSource), filename:split(AbsTarget)).

%% @private based on fragments of paths, replace the number of common
%% segments by `../' bits, and add the rest of the source alone after it
-spec do_make_relative_path([string()], [string()]) -> file:filename().
do_make_relative_path([H|T1], [H|T2]) ->
    do_make_relative_path(T1, T2);
do_make_relative_path(Source, Target) ->
    Base = lists:duplicate(max(length(Target) - 1, 0), ".."),
    filename:join(Base ++ Source).

%%% @doc
%%% `src_dirs' and `extra_src_dirs' can be configured with options
%%% like this:
%%% ```
%%% {src_dirs,[{"foo",[{recursive,false}]}]}
%%% {extra_src_dirs,[{"bar",[recursive]}]} (equivalent to {recursive,true})
%%% '''
%%% `src_dirs/1,2' and `extra_src_dirs/1,2' return only the list of
%%% directories for the `src_dirs' and `extra_src_dirs' options
%%% respectively, while `src_dirs_opts/2' returns the options list for
%%% the given directory, no matter if it is configured as `src_dirs' or
%%% `extra_src_dirs'.
-spec src_dirs(rebar_dict()) -> list(file:filename_all()).
src_dirs(Opts) -> src_dirs(Opts, []).

%% @doc same as `src_dirs/1', but allows to pass in a list of default options.
-spec src_dirs(rebar_dict(), list(file:filename_all())) -> list(file:filename_all()).
src_dirs(Opts, Default) ->
    src_dirs(src_dirs, Opts, Default).

%% @doc same as `src_dirs/1', but for the `extra_src_dirs' options
-spec extra_src_dirs(rebar_dict()) -> list(file:filename_all()).
extra_src_dirs(Opts) -> extra_src_dirs(Opts, []).

%% @doc same as `src_dirs/2', but for the `extra_src_dirs' options
-spec extra_src_dirs(rebar_dict(), list(file:filename_all())) -> list(file:filename_all()).
extra_src_dirs(Opts, Default) ->
    src_dirs(extra_src_dirs, Opts, Default).

%% @private agnostic version of src_dirs and extra_src_dirs.
src_dirs(Type, Opts, Default) ->
    lists:usort([
        case D0 of
            {D,_} -> rebar_file_utils:normalize_relative_path(D);
            _ -> rebar_file_utils:normalize_relative_path(D0)
        end || D0 <- raw_src_dirs(Type,Opts,Default)]).

%% @private extracts the un-formatted src_dirs or extra_src_dirs
%% options as configured.
raw_src_dirs(Type, Opts, Default) ->
    ErlOpts = rebar_opts:erl_opts(Opts),
    Vs = proplists:get_all_values(Type, ErlOpts),
    case lists:append([rebar_opts:get(Opts, Type, []) | Vs]) of
        []   -> Default;
        Dirs -> Dirs
    end.

%% @doc returns all the source directories (`src_dirs' and
%% `extra_src_dirs').
-spec all_src_dirs(rebar_dict()) -> list(file:filename_all()).
all_src_dirs(Opts) -> all_src_dirs(Opts, [], []).

%% @doc returns all the source directories (`src_dirs' and
%% `extra_src_dirs') while being able to configure defaults for both.
-spec all_src_dirs(rebar_dict(), list(file:filename_all()), list(file:filename_all())) ->
    list(file:filename_all()).
all_src_dirs(Opts, SrcDefault, ExtraDefault) ->
    lists:usort(src_dirs(Opts, SrcDefault) ++ extra_src_dirs(Opts, ExtraDefault)).

%%% @doc
%%% Return the list of options for the given src directory
%%% If the same option is given multiple times for a directory in the
%%% config, the priority order is: first occurence of `src_dirs'
%%% followed by first occurence of `extra_src_dirs'.
-spec src_dir_opts(rebar_dict(), file:filename_all()) -> [{atom(),term()}].
src_dir_opts(Opts, Dir) ->
    RawSrcDirs = raw_src_dirs(src_dirs, Opts, []),
    RawExtraSrcDirs = raw_src_dirs(extra_src_dirs, Opts, []),
    AllOpts = [Opt || {D, Opt} <- RawSrcDirs++RawExtraSrcDirs, D==Dir],
    lists:ukeysort(1, proplists:unfold(lists:append(AllOpts))).

%%% @doc
%%% Return the value of the 'recursive' option for the given directory.
%%% If not given, the value of 'recursive' in the 'erlc_compiler'
%%% options is used, and finally the default is 'true'.
-spec recursive(rebar_dict(), file:filename_all()) -> boolean().
recursive(Opts, Dir) ->
    DirOpts = src_dir_opts(Opts, Dir),
    Default = proplists:get_value(recursive,
                                  rebar_opts:get(Opts, erlc_compiler, []),
                                  true),
    R = proplists:get_value(recursive, DirOpts, Default),
    R.

%% @doc given a path if that path is an ancestor of an app dir, return the path relative to that
%% apps outdir. If the path is not an ancestor to any app dirs but is an ancestor of the
%% project root, return the path relative to the project base_dir. If it is not an ancestor
%% of either return it unmodified
-spec retarget_path(rebar_state:t(), string()) -> string().
retarget_path(State, Path) ->
    ProjectApps = rebar_state:project_apps(State),
    retarget_path(State, Path, ProjectApps).

%% @private worker for retarget_path/2
%% @end
%% not relative to any apps in project, check to see it's relative to
%% project root
retarget_path(State, Path, []) ->
    case rebar_file_utils:path_from_ancestor(rebar_file_utils:canonical_path(Path), rebar_state:dir(State)) of
        {ok, NewPath}      -> filename:join([base_dir(State), NewPath]);
        %% not relative to project root, don't modify
        {error, badparent} -> Path
    end;
%% relative to current app, retarget to the same dir relative to
%% the app's out_dir
retarget_path(State, Path, [App|Rest]) ->
    case rebar_file_utils:path_from_ancestor(rebar_file_utils:canonical_path(Path), rebar_app_info:dir(App)) of
        {ok, NewPath}      -> filename:join([rebar_app_info:out_dir(App), NewPath]);
        {error, badparent} -> retarget_path(State, Path, Rest)
    end.

format_source_file_name(Path) ->
    format_source_file_name(Path, dict:new()).

format_source_file_name(Path, Opts) ->
    Type = case rebar_opts:get(Opts, compiler_source_format,
                               ?DEFAULT_COMPILER_SOURCE_FORMAT) of
        V when V == absolute; V == relative; V == build ->
            V;
        Other ->
            warn_source_format_once(Other)
    end,
    case Type of
        absolute -> resolve_linked_source(Path);
        build -> Path;
        relative ->
            Cwd = rebar_dir:get_cwd(),
            rebar_dir:make_relative_path(resolve_linked_source(Path), Cwd)
    end.

%% @private displays a warning for the compiler source format option
%% only once
-spec warn_source_format_once(term()) -> ok.
warn_source_format_once(Format) ->
    Warn = application:get_env(rebar, warn_source_format) =/= {ok, false},
    application:set_env(rebar, warn_source_format, false),
    case Warn of
        false ->
            ok;
        true ->
            ?WARN("Invalid argument ~p for compiler_source_format - "
                  "assuming ~ts~n", [Format, ?DEFAULT_COMPILER_SOURCE_FORMAT])
    end.

%% @private takes a filename and canonicalizes its path if it is a link.
-spec resolve_linked_source(file:filename()) -> file:filename().
resolve_linked_source(Src) ->
    {Dir, Base} = rebar_file_utils:split_dirname(Src),
    filename:join(rebar_file_utils:resolve_link(Dir), Base).
