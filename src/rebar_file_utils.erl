%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% Copyright (c) 2009 Dave Smith (dizzyd@dizzyd.com)
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% -------------------------------------------------------------------
-module(rebar_file_utils).

-export([try_consult/1,
         consult_config/2,
         consult_env_config/2,
         consult_config_terms/2,
         format_error/1,
         symlink_or_copy/2,
         rm_rf/1,
         cp_r/2,
         mv/2,
         delete_each/1,
         write_file_if_contents_differ/2,
         write_file_if_contents_differ/3,
         system_tmpdir/0,
         system_tmpdir/1,
         reset_dir/1,
         touch/1,
         path_from_ancestor/2,
         canonical_path/1,
         absolute_path/1,
         normalized_path/1,
         normalize_relative_path/1,
         resolve_link/1,
         split_dirname/1,
         ensure_dir/1]).

-include("rebar.hrl").

-include_lib("providers/include/providers.hrl").
-include_lib("kernel/include/file.hrl").


%% ===================================================================
%% Public API
%% ===================================================================

try_consult(File) ->
    case file:consult(File) of
        {ok, Terms} ->
            Terms;
        {error, enoent} ->
            [];
        {error, Reason} ->
            throw(?PRV_ERROR({bad_term_file, File, Reason}))
    end.

%% @doc Parse a sys.config file and return the configuration terms
%% for all its potentially nested configs.
-spec consult_config(file:filename(), string()) -> [[tuple()]].
consult_config(RootDir, Filename) ->
    Fullpath = join_if_relative_path(RootDir, Filename),
    ?DEBUG("Loading configuration from ~p", [Fullpath]),
    Config = case try_consult(Fullpath) of
        [T] -> T;
        [] -> []
    end,
    consult_config_terms(RootDir, Config).

%% @doc Parse a sys.config.src file and return the configuration terms
%% for all its potentially nested configs.
-spec consult_env_config(file:filename(), file:filename()) -> [[tuple()]].
consult_env_config(RootDir, Filename) ->
    Fullpath = join_if_relative_path(RootDir, Filename),
    RawString = case file:read_file(Fullpath) of
        {error, _} -> "[].";
        {ok, Bin} -> unicode:characters_to_list(Bin)
    end,
    ReplacedStr = replace_env_vars(RawString),
    case rebar_string:consult(unicode:characters_to_list(ReplacedStr)) of
        {error, Reason} ->
            throw(?PRV_ERROR({bad_term_file, Filename, Reason}));
        [Terms] ->
            consult_config_terms(RootDir, Terms)
    end.

-spec join_if_relative_path(file:filename(), file:filename()) -> file:filename().
join_if_relative_path(Dir, Path) ->
    case filename:pathtype(Path) of
        absolute -> Path;
        _ -> filename:join(Dir, Path)
    end.

%% @doc quick and simple variable substitution writeup.
%% Supports `${varname}' but not `$varname' nor nested
%% values such as `${my_${varname}}'.
%% The variable are also defined as only supporting
%% the form `[a-zA-Z_]+[a-zA-Z0-9_]*' as per the POSIX
%% standard.
-spec replace_env_vars(string()) -> unicode:charlist().
replace_env_vars("") -> "";
replace_env_vars("${" ++ Str) ->
    case until_var_end(Str) of
        {ok, VarName, Rest} ->
            replace_varname(VarName) ++ replace_env_vars(Rest);
        error ->
            "${" ++ replace_env_vars(Str)
    end;
replace_env_vars([Char|Str]) ->
    [Char | replace_env_vars(Str)].

until_var_end(Str) ->
    case re:run(Str, "([a-zA-Z_]+[a-zA-Z0-9_]*)}", [{capture, [1], list}]) of
        nomatch ->
            error;
        {match, [Name]} ->
            {ok, Name, drop_varname(Name, Str)}
    end.

replace_varname(Var) ->
    %% os:getenv(Var, "") is only available in OTP-18.0
    case os:getenv(Var) of
        false -> "";
        Val -> Val
    end.

drop_varname("", "}" ++ Str) -> Str;
drop_varname([_|Var], [_|Str]) -> drop_varname(Var, Str).

%% @doc From a parsed sys.config file, expand all the terms to include
%% its potential nested configs. It is also possible that no sub-terms
%% (i.e. the config file does not refer to "some/other/file.config")
%% that the input term is returned as-is.
%%
%% This function is added mostly to help with variable substitution
%% and evaluation of 'sys.config.src' files, giving a way to handle
%% expansion that is separate from regular config handling.
-spec consult_config_terms(rebar_state:t(), [tuple()]) -> [[tuple()]].
consult_config_terms(RootDir, Config) ->
    JoinedConfig = lists:flatmap(
        fun (SubConfig) when is_list(SubConfig) ->
            T = {lists:suffix(".config", SubConfig), lists:suffix(".config.src", SubConfig)},
            case T of
                %% since consult_config returns a list in a list we take the head here
                {false, false} -> hd(consult_config(RootDir, SubConfig ++ ".config"));
                {true, _} -> hd(consult_config(RootDir, SubConfig));
                {_, true} -> hd(consult_env_config(RootDir, SubConfig))
            end;
            (Entry) -> [Entry]
      end, Config),
    %% Backwards compatibility
    [JoinedConfig].

format_error({bad_term_file, AppFile, Reason}) ->
    io_lib:format("Error reading file ~ts: ~ts", [AppFile, file:format_error(Reason)]).

symlink_or_copy(Source, Target) ->
    Link = case os:type() of
               {win32, _} ->
                   Source;
               _ ->
                   rebar_dir:make_relative_path(Source, Target)
           end,
    case file:make_symlink(Link, Target) of
        ok ->
            ok;
        {error, eexist} ->
            exists;
        {error, _} ->
            case os:type() of
                {win32, _} ->
                    S = unicode:characters_to_list(Source),
                    T = unicode:characters_to_list(Target),
                    case filelib:is_dir(S) of
                        true ->
                            win32_symlink_or_copy(S, T);
                        false ->
                            cp_r([S], T)
                    end;
                _ ->
                    case filelib:is_dir(Target) of
                        true ->
                            ok;
                        false ->
                            cp_r([Source], Target)
                    end
            end
    end.

%% @private Compatibility function for windows
win32_symlink_or_copy(Source, Target) ->
    Res = rebar_utils:sh(
            ?FMT("cmd /c mklink /j \"~ts\" \"~ts\"",
                 [rebar_utils:escape_double_quotes(filename:nativename(Target)),
                  rebar_utils:escape_double_quotes(filename:nativename(Source))]),
            [{use_stdout, false}, return_on_error]),
    case win32_mklink_ok(Res, Target) of
        true -> ok;
        false -> cp_r_win32(Source, drop_last_dir_from_path(Target))
    end.

%% @private specifically pattern match against the output
%% of the windows 'mklink' shell call; different values from
%% what win32_ok/1 handles
win32_mklink_ok({ok, _}, _) ->
    true;
win32_mklink_ok({error,{1,"Local NTFS volumes are required to complete the operation.\n"}}, _) ->
    false;
win32_mklink_ok({error,{1,"Cannot create a file when that file already exists.\n"}}, Target) ->
    % File or dir is already in place; find if it is already a symlink (true) or
    % if it is a directory (copy-required; false)
    is_symlink(Target);
win32_mklink_ok(_, Target) ->
    is_symlink(Target).

%% @private
is_symlink(Filename) ->
    case file:read_link_info(Filename) of
        {ok, Info} ->
            Info#file_info.type == symlink;
        _ ->
            false
    end.

%% @private
%% drops the last 'node' of the filename, presumably the last dir such as 'src'
%% this is because cp_r_win32/2 automatically adds the dir name, to appease
%% robocopy and be more uniform with POSIX
drop_last_dir_from_path([]) ->
    [];
drop_last_dir_from_path(Path) ->
    case lists:droplast(filename:split(Path)) of
        [] -> [];
        Dirs -> filename:join(Dirs)
    end.

%% @doc Remove files and directories.
%% Target is a single filename, directoryname or wildcard expression.
-spec rm_rf(string()) -> 'ok'.
rm_rf(Target) ->
    case os:type() of
        {unix, _} ->
            EscTarget = rebar_utils:escape_chars(Target),
            {ok, []} = rebar_utils:sh(?FMT("rm -rf ~ts", [EscTarget]),
                                      [{use_stdout, false}, abort_on_error]),
            ok;
        {win32, _} ->
            Filelist = filelib:wildcard(Target),
            Dirs = [F || F <- Filelist, filelib:is_dir(F)],
            Files = Filelist -- Dirs,
            ok = delete_each(Files),
            ok = delete_each_dir_win32(Dirs),
            ok
    end.

-spec cp_r(list(string()), file:filename()) -> 'ok'.
cp_r([], _Dest) ->
    ok;
cp_r(Sources, Dest) ->
    case os:type() of
        {unix, Os} ->
            EscSources = [rebar_utils:escape_chars(Src) || Src <- Sources],
            SourceStr = rebar_string:join(EscSources, " "),
            % On darwin the following cp command will cp everything inside
            % target vs target and everything inside, so we chop the last char
            % off if it is a '/'
            Source = case {Os == darwin, lists:last(SourceStr) == $/} of
                {true, true} ->
                    rebar_string:trim(SourceStr, trailing, "/");
                {true, false} ->
                    SourceStr;
                {false, _} ->
                    SourceStr
            end,
            % ensure destination exists before copying files into it
            {ok, []} = rebar_utils:sh(?FMT("mkdir -p ~ts",
                           [rebar_utils:escape_chars(Dest)]),
                      [{use_stdout, false}, abort_on_error]),
            {ok, []} = rebar_utils:sh(?FMT("cp -Rp ~ts \"~ts\"",
                                           [Source, rebar_utils:escape_double_quotes(Dest)]),
                                      [{use_stdout, true}, abort_on_error]),
            ok;
        {win32, _} ->
            lists:foreach(fun(Src) -> ok = cp_r_win32(Src,Dest) end, Sources),
            ok
    end.

-spec mv(string(), file:filename()) -> 'ok'.
mv(Source, Dest) ->
    case os:type() of
        {unix, _} ->
            EscSource = rebar_utils:escape_chars(Source),
            EscDest = rebar_utils:escape_chars(Dest),
            case rebar_utils:sh(?FMT("mv ~ts ~ts", [EscSource, EscDest]),
                                      [{use_stdout, false}, abort_on_error]) of
                {ok, []} ->
                    ok;
                {ok, Warning} ->
                    ?WARN("mv: ~p", [Warning]),
                    ok
            end;
        {win32, _} ->
            case filelib:is_dir(Source) of
                true ->
                    SrcDir = filename:nativename(Source),
                    DestDir = case filelib:is_dir(Dest) of
                        true ->
                            %% to simulate unix/posix mv, we have to replicate
                            %% the same directory movement by moving the whole
                            %% top-level directory, not just the insides
                            SrcName = filename:basename(Source),
                            filename:nativename(filename:join(Dest, SrcName));
                        false ->
                            filename:nativename(Dest)
                    end,
                    robocopy_dir(SrcDir, DestDir);
                false ->
                    SrcDir = filename:nativename(filename:dirname(Source)),
                    SrcName = filename:basename(Source),
                    DestDir = filename:nativename(filename:dirname(Dest)),
                    DestName = filename:basename(Dest),
                    IsDestDir = filelib:is_dir(Dest),
                    if IsDestDir ->
                        %% if basename and target name are different because
                        %% we move to a directory, then just move there.
                        %% Similarly, if they are the same but we're going to
                        %% a directory, let's just do that directly.
                        FullDestDir = filename:nativename(Dest),
                        robocopy_file(SrcDir, FullDestDir, SrcName)
                    ;  SrcName =:= DestName ->
                        %% if basename and target name are the same and both are files,
                        %% we do a regular move with robocopy without rename.
                        robocopy_file(SrcDir, DestDir, DestName)
                    ;  SrcName =/= DestName->
                        robocopy_mv_and_rename(Source, Dest, SrcDir, SrcName, DestDir, DestName)
                    end

            end
    end.

robocopy_mv_and_rename(Source, Dest, SrcDir, SrcName, DestDir, DestName) ->
    %% If we're moving a file and the origin and
    %% destination names are different:
    %%  - mktmp
    %%  - robocopy source_dir tmp_dir srcname
    %%  - rename srcname destname (to avoid clobbering)
    %%  - robocopy tmp_dir dest_dir destname
    %%  - remove tmp_dir
    case ec_file:insecure_mkdtemp() of
        {error, _Reason} ->
            {error, lists:flatten(
                     io_lib:format("Failed to move ~ts to ~ts (tmpdir failed)~n",
                                   [Source, Dest]))};
        TmpPath ->
            case robocopy_file(SrcDir, TmpPath, SrcName) of
                {error, Reason} ->
                    {error, Reason};
                ok ->
                    TmpSrc = filename:join(TmpPath, SrcName),
                    TmpDst = filename:join(TmpPath, DestName),
                    case file:rename(TmpSrc, TmpDst) of
                        {error, _} ->
                            {error, lists:flatten(
                                      io_lib:format("Failed to move ~ts to ~ts (via rename)~n",
                                                    [Source, Dest]))};
                        ok ->
                            case robocopy_file(TmpPath, DestDir, DestName) of
                                Err = {error, _} -> Err;
                                OK -> rm_rf(TmpPath), OK
                            end
                    end
            end
    end.

robocopy_file(SrcPath, DestPath, FileName) ->
    Cmd = ?FMT("robocopy /move /e \"~ts\" \"~ts\" \"~ts\" 1> nul",
               [rebar_utils:escape_double_quotes(SrcPath),
                rebar_utils:escape_double_quotes(DestPath),
                rebar_utils:escape_double_quotes(FileName)]),
    Res = rebar_utils:sh(Cmd, [{use_stdout, false}, return_on_error]),
    case win32_ok(Res) of
        false ->
            {error, lists:flatten(
                        io_lib:format("Failed to move ~ts to ~ts~n",
                                      [filename:join(SrcPath, FileName),
                                       filename:join(DestPath, FileName)]))};
        true ->
            ok
    end.

robocopy_dir(Source, Dest) ->
    Cmd = ?FMT("robocopy /move /e \"~ts\" \"~ts\" 1> nul",
               [rebar_utils:escape_double_quotes(Source),
                rebar_utils:escape_double_quotes(Dest)]),
    Res = rebar_utils:sh(Cmd,
                         [{use_stdout, false}, return_on_error]),
    case win32_ok(Res) of
        true -> ok;
        false ->
            {error, lists:flatten(
                      io_lib:format("Failed to move ~ts to ~ts~n",
                                    [Source, Dest]))}
    end.

win32_ok({ok, _}) -> true;
win32_ok({error, {Rc, _}}) when Rc<9; Rc=:=16 -> true;
win32_ok(_) -> false.


delete_each([]) ->
    ok;
delete_each([File | Rest]) ->
    case file:delete(File) of
        ok ->
            delete_each(Rest);
        {error, enoent} ->
            delete_each(Rest);
        {error, Reason} ->
            ?ERROR("Failed to delete file ~ts: ~p\n", [File, Reason]),
            ?ABORT
    end.

%% @doc backwards compat layer to pre-utf8 support
write_file_if_contents_differ(Filename, Bytes) ->
    write_file_if_contents_differ(Filename, Bytes, raw).

%% @doc let the user pick the encoding required; there are no good
%% heuristics for data encoding
write_file_if_contents_differ(Filename, Bytes, raw) ->
    write_file_if_contents_differ_(Filename, iolist_to_binary(Bytes));
write_file_if_contents_differ(Filename, Bytes, utf8) ->
    write_file_if_contents_differ_(Filename, unicode:characters_to_binary(Bytes, utf8)).

%% @private compare raw strings and check contents
write_file_if_contents_differ_(Filename, ToWrite) ->
    case file:read_file(Filename) of
        {ok, ToWrite} ->
            ok;
        {ok,  _} ->
            file:write_file(Filename, ToWrite, [raw]);
        {error,  _} ->
            file:write_file(Filename, ToWrite, [raw])
    end.

%% returns an os appropriate tmpdir given a path
-spec system_tmpdir() -> file:filename().
system_tmpdir() -> system_tmpdir([]).

-spec system_tmpdir(PathComponents) -> file:filename() when
      PathComponents :: [file:name()].
system_tmpdir(PathComponents) ->
    Tmp = case erlang:system_info(system_architecture) of
        "win32" ->
            "./tmp";
        _SysArch ->
            "/tmp"
    end,
    filename:join([Tmp|PathComponents]).

%% recursively removes a directory and then recreates the same
%%  directory but empty
-spec reset_dir(Path) -> ok | {error, Reason} when
      Path   :: file:name(),
      Reason :: file:posix().

reset_dir(Path) ->
    %% delete the directory if it exists
    _ = ec_file:remove(Path, [recursive]),
    %% recreate the directory
    ensure_dir(Path).


%% Linux touch but using erlang functions to work in bot *nix os and
%% windows
-spec touch(Path) -> ok | {error, Reason} when
      Path :: file:name(),
      Reason :: file:posix().
touch(Path) ->
    {ok, A} = file:read_file_info(Path),
    ok = file:write_file_info(Path, A#file_info{mtime = calendar:local_time(),
                                                atime = calendar:local_time()}).

%% for a given path return the path relative to a base directory
-spec path_from_ancestor(string(), string()) -> {ok, string()} | {error, badparent}.

path_from_ancestor(Target, To) ->
    path_from_ancestor_(filename:split(canonical_path(Target)),
                        filename:split(canonical_path(To))).

path_from_ancestor_([Part|Target], [Part|To]) -> path_from_ancestor_(Target, To);
path_from_ancestor_([], [])                   -> {ok, ""};
path_from_ancestor_(Target, [])               -> {ok, filename:join(Target)};
path_from_ancestor_(_, _)                     -> {error, badparent}.


%% reduce a filepath by removing all incidences of `.' and `..'
-spec canonical_path(string()) -> string().

canonical_path(Dir) ->
    Canon = canonical_path([], filename:split(filename:absname(Dir))),
    filename:nativename(Canon).

canonical_path([], [])                -> filename:absname("/");
canonical_path(Acc, [])               -> filename:join(lists:reverse(Acc));
canonical_path(Acc, ["."|Rest])       -> canonical_path(Acc, Rest);
canonical_path([_|Acc], [".."|Rest])  -> canonical_path(Acc, Rest);
canonical_path([], [".."|Rest])       -> canonical_path([], Rest);
canonical_path(Acc, [Component|Rest]) -> canonical_path([Component|Acc], Rest).

%% @doc make a path absolute
-spec absolute_path(file:filename()) -> file:filename().
absolute_path(Path) ->
    case filename:pathtype(Path) of
        absolute ->
            Path;
        relative ->
            {ok, Dir} = file:get_cwd(),
            filename:join([Dir, Path]);
        volumerelative ->
            [Letter, $: | _] = filename:nativename(filename:absname(Path)),
            Volume = [Letter, $:],
            {ok, Dir} = file:get_cwd(Volume),
            Volume ++ filename:join([Dir, Path])
    end.

%% @doc normalizing a path removes all of the `..' and the
%% `.' segments it may contain.
-spec normalized_path(file:filename()) -> file:filename().
normalized_path(Path) ->
    AbsPath = absolute_path(Path),
    Components = filename:split(AbsPath),
    normalized_path(Components, []).

%% @private drops path fragments for normalization
-spec normalized_path([string()], [string()]) -> file:filename().
normalized_path([], NormalizedPath) ->
    filename:join(lists:reverse(NormalizedPath));
normalized_path([H|T], NormalizedPath) ->
    case H of
        "." when NormalizedPath == [], T == [] -> normalized_path(T, ["."]);
        "."  -> normalized_path(T, NormalizedPath);
        ".." when NormalizedPath == [] -> normalized_path(T, [".."]);
        ".." when hd(NormalizedPath) =/= ".." -> normalized_path(T, tl(NormalizedPath));
        _    -> normalized_path(T, [H|NormalizedPath])
    end.

%% @doc normalizes relative paths so that ./a/b/c/ => a/b/c
-spec normalize_relative_path(string()) -> file:filename().
normalize_relative_path(Path) ->
    normalized_path(filename:split(Path), []).

%% @doc returns canonical target of path if path is a link, otherwise returns path
-spec resolve_link(string()) -> string().
resolve_link(Path) ->
    case file:read_link(Path) of
        {ok, Target} ->
            canonical_path(filename:absname(Target, filename:dirname(Path)));
        {error, _} -> Path
    end.

%% @doc splits a path into dirname and basename
-spec split_dirname(string()) -> {string(), string()}.
split_dirname(Path) ->
    {filename:dirname(Path), filename:basename(Path)}.

-spec ensure_dir(file:name_all()) -> ok | {error, file:posix()}.
ensure_dir(Path) ->
    filelib:ensure_dir(filename:join(Path, "fake_file")).

%% ===================================================================
%% Internal functions
%% ===================================================================

delete_each_dir_win32([]) -> ok;
delete_each_dir_win32([Dir | Rest]) ->
    {ok, []} = rebar_utils:sh(?FMT("rd /q /s \"~ts\"",
                                   [rebar_utils:escape_double_quotes(filename:nativename(Dir))]),
                              [{use_stdout, false}, return_on_error]),
    delete_each_dir_win32(Rest).

xcopy_win32(Source,Dest)->
    %% "xcopy \"~ts\" \"~ts\" /q /y /e 2> nul", Changed to robocopy to
    %% handle long names. May have issues with older windows.
    Cmd = case filelib:is_dir(Source) of
              true ->
                  %% For robocopy, copying /a/b/c/ to /d/e/f/ recursively does not
                  %% create /d/e/f/c/*, but rather copies all files to /d/e/f/*.
                  %% The usage we make here expects the former, not the later, so we
                  %% must manually add the last fragment of a directory to the `Dest`
                  %% in order to properly replicate POSIX platforms
                  NewDest = filename:join([Dest, filename:basename(Source)]),
                  ?FMT("robocopy \"~ts\" \"~ts\" /e 1> nul",
                       [rebar_utils:escape_double_quotes(filename:nativename(Source)),
                        rebar_utils:escape_double_quotes(filename:nativename(NewDest))]);
              false ->
                  ?FMT("robocopy \"~ts\" \"~ts\" \"~ts\" /e 1> nul",
                       [rebar_utils:escape_double_quotes(filename:nativename(filename:dirname(Source))),
                        rebar_utils:escape_double_quotes(filename:nativename(Dest)),
                        rebar_utils:escape_double_quotes(filename:basename(Source))])
          end,
    Res = rebar_utils:sh(Cmd,
                [{use_stdout, false}, return_on_error]),
    case win32_ok(Res) of
                true -> ok;
                false ->
                    {error, lists:flatten(
                              io_lib:format("Failed to copy ~ts to ~ts~n",
                                            [Source, Dest]))}
    end.

cp_r_win32({true, SourceDir}, {true, DestDir}) ->
    %% from directory to directory
     ok = case file:make_dir(DestDir) of
             {error, eexist} -> ok;
             Other -> Other
         end,
    ok = xcopy_win32(SourceDir, DestDir);
cp_r_win32({false, Source} = S,{true, DestDir}) ->
    %% from file to directory
    cp_r_win32(S, {false, filename:join(DestDir, filename:basename(Source))});
cp_r_win32({false, Source},{false, Dest}) ->
    %% from file to file
    {ok,_} = file:copy(Source, Dest),
    ok;
cp_r_win32({true, SourceDir}, {false, DestDir}) ->
    case filelib:is_regular(DestDir) of
        true ->
            %% From directory to file? This shouldn't happen
            {error, lists:flatten(
                      io_lib:format("Cannot copy dir (~p) to file (~p)\n",
                                    [SourceDir, DestDir]))};
        false ->
            %% Specifying a target directory that doesn't currently exist.
            %% So let's attempt to create this directory
            case ensure_dir(DestDir) of
                ok ->
                    ok = xcopy_win32(SourceDir, DestDir);
                {error, Reason} ->
                    {error, lists:flatten(
                              io_lib:format("Unable to create dir ~p: ~p\n",
                                            [DestDir, Reason]))}
            end
    end;
cp_r_win32(Source,Dest) ->
    Dst = {filelib:is_dir(Dest), Dest},
    lists:foreach(fun(Src) ->
                          ok = cp_r_win32({filelib:is_dir(Src), Src}, Dst)
                  end, filelib:wildcard(Source)),
    ok.
