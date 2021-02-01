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
-module(rebar_templater).

-export([new/4,
         list_templates/1,
         render/2]).
-ifdef(TEST).
-export([consult_template/3]).
-endif.


-include("rebar.hrl").

-define(TEMPLATE_RE, "^(?!\\._).*\\.template\$").

%% ===================================================================
%% Public API
%% ===================================================================

%% Apply a template
new(Template, Vars, Force, State) ->
    {AvailTemplates, Files} = find_templates(State),
    ?DEBUG("Looking for ~p", [Template]),
    case lists:keyfind(Template, 1, AvailTemplates) of
        false -> {not_found, Template};
        TemplateTup -> create(TemplateTup, Files, Vars, Force, State)
    end.

%% Give a list of templates with their expanded content
list_templates(State) ->
    {AvailTemplates, Files} = find_templates(State),
    [list_template(Files, Template, State) || Template <- AvailTemplates].

%% ===================================================================
%% Internal Functions
%% ===================================================================

%% Expand a single template's value
list_template(Files, {Name, Type, File}, State) ->
    case consult_template(Files, Type, File) of
        {error, Reason} ->
            {error, {consult, File, Reason}};
        TemplateTerms ->
            {Name, Type, File,
             get_template_description(TemplateTerms),
             get_template_vars(TemplateTerms, State)}
    end.

%% Load up the template description out from a list of attributes read in
%% a .template file.
get_template_description(TemplateTerms) ->
    case lists:keyfind(description, 1, TemplateTerms) of
        {_, Desc} -> Desc;
        false -> undefined
    end.

%% Load up the variables out from a list of attributes read in a .template file
%% and return them merged with the globally-defined and default variables.
get_template_vars(TemplateTerms, State) ->
    Vars = case lists:keyfind(variables, 1, TemplateTerms) of
        {_, Value} -> Value;
        false -> []
    end,
    override_vars(Vars, override_vars(global_variables(State), default_variables(State))).

%% Provide a way to merge a set of variables with another one. The left-hand
%% set of variables takes precedence over the right-hand set.
%% In the case where left-hand variable description contains overriden defaults, but
%% the right-hand one contains additional data such as documentation, the resulting
%% variable description will contain the widest set of information possible.
override_vars(Vars, General) ->
    {NewGeneral, VarsAcc} =
      lists:foldl(fun({Var, Default}, {General1, Acc}) ->
                    case lists:keytake(Var, 1, General1) of
                        {value, {Var, _Default, Doc}, NewGeneral1} ->
                            {NewGeneral1, [{Var, expand_path(Default, General1), Doc} | Acc]};
                        {value, {Var, _Default}, NewGeneral1} ->
                            {NewGeneral1, [{Var, expand_path(Default, General1)}]};
                        false ->
                            {General1, [{Var, expand_path(Default, General1)} | Acc]}
                    end;
                   ({Var, Default, Doc}, {General1, Acc}) ->
                        {lists:keydelete(Var, 1, General1), [{Var, rebar_utils:to_list(render(Default, General1)), Doc} | Acc]}
                end, {General, []}, Vars),
    NewGeneral ++ VarsAcc.

%% Default variables, generated dynamically.
default_variables(State) ->
    RootName = filename:basename(filename:rootname(rebar_dir:root_dir(State))),
    {DefaultAuthor, DefaultEmail} = default_author_and_email(),
    {{Y,M,D},{H,Min,S}} = calendar:universal_time(),
    [{date, lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0w",[Y,M,D]))},
     {datetime, lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0w+00:00",[Y,M,D,H,Min,S]))},
     {author_name, DefaultAuthor},
     {author_email, DefaultEmail},
     {copyright_year, integer_to_list(Y)},
     {root_name, RootName},
     {apps_dir, "apps", "Directory where applications will be created if needed"}].

default_author_and_email() ->
    %% See if we can get a git user and email to use as defaults
    case rebar_utils:sh("git config --global user.name", [return_on_error]) of
        {ok, Name} ->
            case rebar_utils:sh("git config --global user.email", [return_on_error]) of
                {ok, Email} ->
                    {rebar_string:trim(Name, both, "\n"),
                     rebar_string:trim(Email, both, "\n")};
                {error, _} ->
                    %% Use neither if one doesn't exist
                    {"Anonymous", "anonymous@example.org"}
            end;
        {error, _} ->
            %% Ok, try mecurial
            case rebar_utils:sh("hg showconfig ui.username", [return_on_error]) of
                {ok, NameEmail} ->
                    case re:run(NameEmail, "^(.*) <(.*)>$", [{capture, [1,2], list}, unicode]) of
                        {match, [Name, Email]} ->
                            {Name, Email};
                        _ ->
                            {"Anonymous", "anonymous@example.org"}
                    end;
                {error, _} ->
                    {"Anonymous", "anonymous@example.org"}
            end
    end.

%% Load variable definitions from the 'Globals' file in the home template
%% directory
global_variables(State) ->
    GlobalFile = rebar_dir:template_globals(State),
    case file:consult(GlobalFile) of
        {error, enoent} -> [];
        {ok, Data} -> proplists:get_value(variables, Data, [])
    end.

%% drop the documentation for variables when present
drop_var_docs([]) -> [];
drop_var_docs([{K,V,_}|Rest]) -> [{K,V} | drop_var_docs(Rest)];
drop_var_docs([{K,V}|Rest]) -> [{K,V} | drop_var_docs(Rest)].

%% Load the template index, resolve all variables, and then execute
%% the template.
create({Template, Type, File}, Files, UserVars, Force, State) ->
    TemplateTerms = consult_template(Files, Type, File),
    Vars0 = drop_var_docs(override_vars(UserVars, get_template_vars(TemplateTerms, State))),
    Vars = maybe_handle_author_name(Vars0),
    maybe_warn_about_name(Vars),
    TemplateCwd = filename:dirname(File),
    Result = execute_template(TemplateTerms, Files, {Template, Type, TemplateCwd}, Vars, Force),
    maybe_print_final_message(proplists:get_value(message, TemplateTerms, undefined), Vars),
    Result.

maybe_handle_author_name(Vars) ->
    case lists:keyfind(author_name, 1, Vars) of
        false -> Vars;
        {author_name, Name0} ->
            Name1 = unicode:characters_to_binary(Name0),
            lists:keyreplace(author_name, 1, Vars, {author_name, Name1})
    end.

maybe_print_final_message(undefined, _) ->
    ok;
maybe_print_final_message(Message, Values) ->
    io:format("~s~n", [render(Message, Values)]).

maybe_warn_about_name(Vars) ->
    Name = proplists:get_value(name, Vars, "valid"),
    case validate_atom(Name) of
        invalid ->
           ?WARN("The 'name' variable is often associated with Erlang "
                 "module names and/or file names. The value submitted "
                 "(~ts) isn't an unquoted Erlang atom. Templates "
                 "generated may contain errors.",
                 [Name]);
        valid ->
            ok
    end.

maybe_warn_about_name_clash(File) ->
    case filename:extension(File) of
        ".erl" ->
            Module0 = re:replace(filename:basename(File), "\\.erl$", "", [{return, list}]),
            Module = list_to_atom(Module0),
            try Module:module_info() of
                _ -> ?WARN("The module definition of '~ts' in file ~ts "
                           "will clash with an existing Erlang module.",
                           [Module, File])
            catch
                _:_ -> ok
            end;
        _ -> ok
    end.

validate_atom(Str) ->
    case io_lib:fread("~a", unicode:characters_to_list(Str)) of
        {ok, [Atom], ""} ->
            case io_lib:write_atom(Atom) of
                "'" ++ _ -> invalid; % quoted
                _ -> valid % unquoted
            end;
        _ ->
            invalid
    end.

%% Run template instructions one at a time.
execute_template([], _, {Template,_,_}, _, _) ->
    ?DEBUG("Template ~ts applied", [Template]),
    ok;
%% We can't execute the description
execute_template([{description, _} | Terms], Files, Template, Vars, Force) ->
    execute_template(Terms, Files, Template, Vars, Force);
%% We can't execute variables
execute_template([{variables, _} | Terms], Files, Template, Vars, Force) ->
    execute_template(Terms, Files, Template, Vars, Force);
%% We can't execute message
execute_template([{message, _} | Terms], Files, Template, Vars, Force) ->
    execute_template(Terms, Files, Template, Vars, Force);
%% Create a directory
execute_template([{dir, Path} | Terms], Files, Template, Vars, Force) ->
    ?DEBUG("Creating directory ~p", [Path]),
    case ec_file:mkdir_p(expand_path(Path, Vars)) of
        ok ->
            ok;
        {error, Reason} ->
            ?ABORT("Failed while processing template instruction "
                   "{dir, ~p}: ~p", [Path, Reason])
    end,
    execute_template(Terms, Files, Template, Vars, Force);
%% Change permissions on a file
execute_template([{chmod, File, Perm} | Terms], Files, Template, Vars, Force) ->
    Path = expand_path(File, Vars),
    case file:change_mode(Path, Perm) of
        ok ->
            execute_template(Terms, Files, Template, Vars, Force);
        {error, Reason} ->
            ?ABORT("Failed while processing template instruction "
                   "{chmod, ~.8#, ~p}: ~p", [Perm, File, Reason])
    end;
%% Create a raw untemplated file
execute_template([{file, From, To} | Terms], Files, {Template, Type, Cwd}, Vars, Force) ->
    ?DEBUG("Creating file ~p", [To]),
    In = expand_path(From, Vars),
    Data = load_file(Files, Type, filename:join(Cwd, In)),
    Out = expand_path(To,Vars),
    case write_file(Out, Data, Force) of
        ok -> ok;
        {error, exists} -> ?INFO("File ~p already exists.", [Out])
    end,
    execute_template(Terms, Files, {Template, Type, Cwd}, Vars, Force);
%% Operate on a django template
execute_template([{template, From, To} | Terms], Files, {Template, Type, Cwd}, Vars, Force) ->
    ?DEBUG("Executing template file ~p", [From]),
    In = expand_path(From, Vars),
    Out = expand_path(To, Vars),
    Tpl = load_file(Files, Type, filename:join(Cwd, In)),
    maybe_warn_about_name_clash(Out),
    case write_file(Out, render(Tpl, Vars), Force) of
        ok ->
            ok;
        {error, exists} ->
            ?INFO("File ~p already exists", [Out])
    end,
    execute_template(Terms, Files, {Template, Type, Cwd}, Vars, Force);
%% Unknown
execute_template([Instruction|Terms], Files, Tpl={Template,_,_}, Vars, Force) ->
    ?WARN("Unknown template instruction ~p in template ~ts",
          [Instruction, Template]),
    execute_template(Terms, Files, Tpl, Vars, Force).

%% Workaround to allow variable substitution in path names without going
%% through the ErlyDTL compilation step. Parse the string and replace
%% as we go.
expand_path([], _) -> [];
expand_path("{{"++Rest, Vars) -> replace_var(Rest, [], Vars);
expand_path([H|T], Vars) -> [H | expand_path(T, Vars)].

%% Actual variable replacement.
replace_var("}}"++Rest, Acc, Vars) ->
    Var = lists:reverse(Acc),
    Val = proplists:get_value(list_to_atom(Var), Vars, ""),
    Val ++ expand_path(Rest, Vars);
replace_var([H|T], Acc, Vars) ->
    replace_var(T, [H|Acc], Vars).

%% Load a list of all the files in the escript and on disk
find_templates(State) ->
    DiskTemplates = find_disk_templates(State),
    PluginTemplates = find_plugin_templates(State),
    {MainTemplates, Files} =
        case rebar_state:escript_path(State) of
            undefined -> % running in local install
                {find_localinstall_templates(State), []};
            _ ->
                %% Cache the files since we'll potentially need to walk it several times
                %% over the course of a run.
                F = cache_escript_files(State),
                {find_escript_templates(F), F}
        end,
    AvailTemplates = find_available_templates([MainTemplates,
                                               PluginTemplates,
                                               DiskTemplates]),
    ?DEBUG("Available templates: ~p\n", [AvailTemplates]),
    {AvailTemplates, Files}.

find_available_templates(TemplateListList) ->
    AvailTemplates = prioritize_templates(TemplateListList),
    ?DEBUG("Available templates: ~p\n", [AvailTemplates]),
    AvailTemplates.

prioritize_templates([TemplateList]) ->
    tag_names(TemplateList);
prioritize_templates([TemplateList | TemplateListList]) ->
    prioritize_templates(tag_names(TemplateList),
                         prioritize_templates(TemplateListList)).

%% Scan the current escript for available files
cache_escript_files(State) ->
    {ok, Files} = rebar_utils:escript_foldl(
                    fun(Name, _, GetBin, Acc) ->
                            [{Name, GetBin()} | Acc]
                    end,
                    [], rebar_state:escript_path(State)),
    Files.

%% Find all the template indexes hiding in the rebar3 escript.
find_escript_templates(Files) ->
    [{escript, Name}
     || {Name, _Bin} <- Files,
        re:run(Name, ?TEMPLATE_RE, [{capture, none}, unicode]) == match].

find_localinstall_templates(_State) ->
    Templates = rebar_utils:find_files(code:priv_dir(rebar), ?TEMPLATE_RE),
    %% Pretend we're still running escripts; should work transparently.
    [{builtin, F} || F <- Templates].

%% Fetch template indexes that sit on disk in the user's HOME
find_disk_templates(State) ->
    OtherTemplates = find_other_templates(State),
    HomeFiles = rebar_utils:find_files(rebar_dir:template_dir(State),
                                       ?TEMPLATE_RE, true), % recursive
    [{file, F} || F <- OtherTemplates ++ HomeFiles].

%% Fetch template indexes that sit on disk in custom areas
find_other_templates(State) ->
    case rebar_state:get(State, template_dir, undefined) of
        undefined ->
            [];
        TemplateDir ->
            rebar_utils:find_files(TemplateDir, ?TEMPLATE_RE, true) % recursive
    end.

%% Fetch template indexes that sit on disk in plugins
find_plugin_templates(State) ->
    [{plugin, File}
     || App <- rebar_state:all_plugin_deps(State),
        Priv <- [rebar_app_info:priv_dir(App)],
        Priv =/= undefined,
        File <- rebar_utils:find_files(Priv, ?TEMPLATE_RE)]
    ++ %% and add global plugins too
    [{plugin, File}
     || PSource <- rebar_state:get(State, {plugins, global}, []),
        Plugin <- [plugin_provider(PSource)],
        is_atom(Plugin),
        Priv <- [code:priv_dir(Plugin)],
        Priv =/= undefined,
        File <- rebar_utils:find_files(Priv, ?TEMPLATE_RE)].

plugin_provider(P) when is_atom(P) -> P;
plugin_provider(T) when is_tuple(T) -> element(1, T).

%% Take an existing list of templates and tag them by name the way
%% the user would enter it from the CLI
tag_names(List) ->
    [{filename:basename(File, ".template"), Type, File}
     || {Type, File} <- List].

%% If multiple templates share the same name, those in the escript (built-in)
%% take precedence. Otherwise, the on-disk order is the one to win.
prioritize_templates([], Acc) -> Acc;
prioritize_templates([{Name, Type, File} | Rest], Valid) ->
    case lists:keyfind(Name, 1, Valid) of
        false ->
            prioritize_templates(Rest, [{Name, Type, File} | Valid]);
        {_, escript, _} ->
            ?DEBUG("Skipping template ~p, due to presence of a built-in "
                   "template with the same name", [Name]),
            prioritize_templates(Rest, Valid);
        {_, builtin, _} ->
            ?DEBUG("Skipping template ~p, due to presence of a built-in "
                   "template with the same name", [Name]),
            prioritize_templates(Rest, Valid);
        {_, plugin, _} ->
            ?DEBUG("Skipping template ~p, due to presence of a plugin "
                   "template with the same name", [Name]),
            prioritize_templates(Rest, Valid);
        {_, file, _} ->
            ?DEBUG("Skipping template ~p, due to presence of a custom "
                   "template at ~ts", [Name, File]),
            prioritize_templates(Rest, Valid)
    end.


%% Read the contents of a file from the appropriate source
load_file(Files, escript, Name) ->
    {Name, Bin} = lists:keyfind(Name, 1, Files),
    Bin;
load_file(_Files, builtin, Name) ->
    {ok, Bin} = file:read_file(Name),
    Bin;
load_file(_Files, plugin, Name) ->
    {ok, Bin} = file:read_file(Name),
    Bin;
load_file(_Files, file, Name) ->
    case file:read_file(Name) of
        {ok, Bin} -> Bin;
        {error, Reason} -> 
            ?ABORT("Failed to load file ~p: ~p\n", [Name, Reason])
    end.

write_file(Output, Data, Force) ->
    %% determine if the target file already exists
    FileExists = filelib:is_regular(Output),

    %% perform the function if we're allowed,
    %% otherwise just process the next template
    case Force orelse FileExists =:= false of
        true ->
            ok = filelib:ensure_dir(Output),
            case {Force, FileExists} of
                {true, true} ->
                    ?INFO("Writing ~ts (forcibly overwriting)",
                             [Output]);
                _ ->
                    ?INFO("Writing ~ts", [Output])
            end,
            case file:write_file(Output, Data) of
                ok ->
                    ok;
                {error, Reason} ->
                    ?ABORT("Failed to write output file ~p: ~p\n",
                           [Output, Reason])
            end;
        false ->
            {error, exists}
    end.

%% Render a binary to a string, using mustache and the specified context
render(Bin, Context) ->
    bbmustache:render(
      rebar_utils:to_binary(Bin),
      Context,
      [{key_type, atom},
       {escape_fun, fun(X) -> X end}] % disable HTML-style escaping
    ).

consult_template(Files, Type, File) ->
    TemplateBin = load_file(Files, Type, File),
    Encoding =
        case epp:read_encoding_from_binary(TemplateBin) of
            none -> epp:default_encoding();
            X -> X
        end,
    rebar_string:consult(unicode:characters_to_list(TemplateBin, Encoding)).
