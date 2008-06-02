%% =====================================================================
%% Some utility functions used by the refactorer.
%%
%% Copyright (C) 2006-2008  Huiqing Li, Simon Thompson


%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved via the world wide web at http://www.erlang.org/.


%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.


%% Author contact: hl@kent.ac.uk, sjt@kent.ac.uk
%%
%% =====================================================================

%% @copyright 2006-2008 Huiqing Li, Simon Thompson
%%
%% @author Huiqing Li <hl@kent.ac.uk>
%%   [http://www.cs.kent.ac.uk/projects/forse]

%% @version  0.3
%% @end
%%
%% @doc Some  utility functions used by Wranlger.
%% @end
%% ============================================
-module(refac_util).

-export([ghead/2, glast/2, to_lower/1, to_upper/1, try_evaluation/1,
         is_var_name/1, is_fun_name/1, is_expr/1, is_pattern/1,
	 is_exported/2, inscope_funs/1,
         once_tdTU/3, stop_tdTP/3, full_buTP/3,
         pos_to_fun_name/2, pos_to_fun_def/2,pos_to_var_name/2,
         pos_to_expr/3, expr_to_fun/2,
         get_range/1, get_var_exports/1, get_bound_vars/1, get_free_vars/1,
         get_client_files/2, expand_files/2, get_modules_by_file/1,
         reset_attrs/1, update_ann/2,
         parse_annotate_file/3,tokenize/1, write_refactored_files/1,
         build_lib_side_effect_tab/1, build_local_side_effect_tab/2,
	 build_call_graph/1, has_side_effect/3,
         callback_funs/1,auto_imported_bifs/0]).

-export([analyze_free_vars/1, build_call_graph/3, build_call_graph/2]).

-include("../hrl/wrangler.hrl").

%% =====================================================================
%% @spec ghead(Info::term(),List::[term()]) -> term()
%% @doc Same as erlang:hd/1, except the first argument which is the
%%  error message when the list is empty.
%% @see glast/2


ghead(Info, []) -> erlang:error(Info);
ghead(_Info, List) -> hd(List).

%% =====================================================================
%% @spec glast(Info::term(), List::[term()]) -> term()
%% @doc Same as lists:last(L), except the first argument which is the 
%%  error message when the list is empty.
%% @see ghead/2


glast(Info, []) -> erlang:error(Info);
glast(_Info, List) -> lists:last(List).

%% =====================================================================
%% @spec to_upper(Str::string()) -> string()
%% @doc Convert a string into upper case.
%% @see to_lower/1
to_upper(Str) ->
    to_upper(Str, []).

to_upper([C | Cs], Acc) when C >= $a, C =< $z ->
    to_upper(Cs, [C - ($a - $A) | Acc]);
to_upper([C | Cs], Acc) -> to_upper(Cs, [C | Acc]);
to_upper([], Acc) -> lists:reverse(Acc).


%% =====================================================================
%% @spec to_lower(Str::string()) -> string()
%% @doc Convert a string into lower case.
%% @see to_upper/1

to_lower(Str) ->
    to_lower(Str, []).

to_lower([C | Cs], Acc) when C >= $A, C =< $Z ->
    to_lower(Cs, [C + ($a - $A) | Acc]);
to_lower([C | Cs], Acc) -> to_lower(Cs, [C | Acc]);
to_lower([], Acc) -> lists:reverse(Acc).


%%====================================================================================
%% @spec try_evaluation(Expr::syntaxTree())->{value, term()}|{error, string()}
%% @doc Try to evaluate an expression. 

try_evaluation(Expr) ->
    case catch erl_eval:exprs(Expr, []) of
      {value, V, _} -> {value, V};
      _ -> {error, "Error with evaluation"}
    end.

%% =====================================================================
%% @spec once_tdTU(Function, Tree::syntaxTree(), Others::[term()])-> term()
%%       Function = (syntaxTre(), {term()}) -> term()
%%
%% @doc Once-topdown type-unifying traversal of the abstract syntax tree with some
%% information collected. This function does a pre-order traversal of the
%% abstract syntax tree, and collects the first node, X say, such that
%% Function(X, Others) returns {term(), true}. Function must has a arity of 2, with 
%% the first parameter by the AST node, and all the other necessary information put 
%% into a tupe as the second parameter.
%%
%% @see full_buTP/2
%% @see stop_tdTP/3 		
%% @see refac_syntax_lib:fold/3.

once_tdTU(Function, Node, Others) ->
    case Function(Node, Others) of
      {R, true} -> {R, true};
      {_R, false} ->
	  case erl_syntax:subtrees(Node) of
	    [] -> {[], false};
	    Gs ->
		Flattened_Gs = [T || G <- Gs, T <- G],
		case Flattened_Gs of
		  [] -> {[], false};
		  [H | T1] -> until(Function, [H | T1], Others)
		end
	  end
    end.

until(_F, [], _Others) -> {[], false};
until(F, [H | T], Others) ->
    case once_tdTU(F, H, Others) of
      {_R, true} -> {_R, true};
      {_Rq, false} -> until(F, T, Others)
    end.

%% =====================================================================
%% @spec stop_tdTP(Function, Tree::syntaxTree(), Others::[term()])->  syntaxTree()
%%       Function = (syntaxTree(),{term()}) -> {syntaxTree(), bool()}
%%
%% @doc Stop-topdown type-preserving traversal of the abstract syntax tree.
%% This function does a pre-order traversal of the abstract syntax tree, and
%% modifies certain nodes according to Function. Once a node has been modified, 
%% its subtrees are not going to be traversed.
%% 'Function' must have a arity of two, with the first being the AST node, and 
%% the second being a tuple containing all the other needed info; 'Function' 
%% should returns a tuple containing the possibly modified node and a boolean value, 
%% with the boolean value indicating whether the node has been modified.
%%
%% @see full_buTP/2
%% @see once_tdTU/3

stop_tdTP(Function, Node, Others) ->
    case Function(Node, Others) of
      {Node1, true} -> {Node1, true};
      {Node1, false} ->
	  case refac_syntax:subtrees(Node1) of
	    [] -> {Node1, false};
	    Gs ->
		Gs1 = [[stop_tdTP(Function, T, Others) || T <- G] || G <- Gs],
		Gs2 = [[N || {N, _B} <- G] || G <- Gs1],
		G = [[B || {_N, B} <- G] || G <- Gs1],
		Node2 = refac_syntax:make_tree(refac_syntax:type(Node1), Gs2),
		{refac_syntax:copy_attrs(Node1, Node2), lists:member(true, lists:flatten(G))}
	  end
    end.


%% =====================================================================
%% @spec full_buTP(Function, Tree::syntaxTree(), {term()})-> syntaxTree()
%%       Function = (syntaxTree(), {term()}) -> syntaxTree()
%%
%% @doc Full bottom_up type-preserving traversal of the abstract syntax tree.
%% This function does a bottom_up traversal of the abstract syntax tree, and 
%% modifies certain nodes according to Function. Different from stop_tdTP, all 
%% the nodes in the abstract syntax tree are traversed by this function. 
%%
%%
%% @see stop_tdTP/2
%% @see once_tdTU/3

full_buTP(Fun, Tree, Others) ->
    case refac_syntax:subtrees(Tree) of
      [] -> Fun(Tree, Others);
      Gs ->
	  Gs1 = [[full_buTP(Fun, T, Others) || T <- G] || G <- Gs],
	  Tree1 = refac_syntax:make_tree(refac_syntax:type(Tree), Gs1),
	  Fun(refac_syntax:copy_attrs(Tree, Tree1), Others)
    end.


%% ==========================================================================
%% @spec pos_to_fun_name(Node::syntaxTree(), Pos::{integer(), integer()}) ->
%%                        {ok, {Mod, Fun, Arity, OccurPos, DefPos}} | {error, none}
%%    Mod = atom()
%%    Fun = atom()
%%    Arity = integer()
%%    OccurPos = {integer(), integer()}
%%    DefPos = {integer(), integer()}
%% @doc Get information about the function name which occurs at the specified
%% position in the code. If successful, the returned information contains: 
%% the module in which the function is defined, the function name, the 
%% function's arity, the occurrence position (same as Pos), and the defining 
%% position of this function.
%%
%% @see pos_to_var_name/2
%% @see pos_to_expr/3
%% @see pos_to_fun_def/2.

pos_to_fun_name(Node, Pos) ->
    case once_tdTU(fun pos_to_fun_name_1/2, Node, Pos) of
      {_, false} -> {error, none};
      {R, true} -> {ok, R}
    end. 

pos_to_fun_name_1(Node, Pos = {Ln, Col}) ->
    As = refac_syntax:get_ann(Node),
    case lists:keysearch(fun_def, 1, As) of
      {value, {fun_def, {Mod, Fun, Arity, {Ln, Col1}, DefPos}}} ->
	  case (Col1 =< Col) and (Col =< Col1 + length(atom_to_list(Fun)) - 1) of
	    true -> {{Mod, Fun, Arity, Pos, DefPos}, true};
	    false -> {[], false}
	  end;
      _ -> {[], false}
    end.


%%============================================================================
%% @spec pos_to_fun_def(Node::syntaxTree(), Pos::{integer(), integer()}) 
%%                     -> {ok, syntaxTree()} | {error, none}
%% @doc Get the AST representation of the function definition in which the 
%% location specified by Pos falls.
%%               
%% @see pos_to_fun_name/2.

pos_to_fun_def(Node, Pos) ->
    case once_tdTU(fun pos_to_fun_def_1/2, Node, Pos) of
      {_, false} -> {error, none};
      {R, true} -> {ok, R}
    end.

pos_to_fun_def_1(Node, Pos) ->
    case refac_syntax:type(Node) of
      function ->
	  {S, E} = get_range(Node),
	  if (S =< Pos) and (Pos =< E) ->
		  {Node, true};
	     true -> {[], false}
	  end;
	_ -> {[], false}
    end.


%% =====================================================================
%% @spec pos_to_var_name(Node::syntaxTree(), Pos::{integer(), integer()})->
%%                      {ok, {VarName,DefPos, Category}} | {error, none}
%%
%%      VarName = atom()
%%      DefPos = [{integer(), integer()}]
%%      Category = expression | pattern | macro_name
%%
%% @doc Get the variable name that occurs at the position specified by Pos.
%% Apart from the variable name, this function all returns other information 
%% including its defining position and its syntax category information.
%%
%% @see pos_to_fun_name/2
%% @see pos_to_fun_def/2
%% @see pos_to_expr/3


pos_to_var_name(Node, UsePos) ->
    case once_tdTU(fun pos_to_var_name_1/2, Node, UsePos) of
      {_, false} -> {error, none};
      {R, true} -> {ok, R}
    end.

pos_to_var_name_1(Node, _Pos = {Ln, Col}) ->
    case refac_syntax:type(Node) of
      variable ->
	  {Ln1, Col1} = refac_syntax:get_pos(Node),
	  case (Ln == Ln1) and (Col1 =< Col) and
		 (Col =< Col1 + length(atom_to_list(refac_syntax:variable_name(Node))) - 1)
	      of
	    true ->
		case lists:keysearch(def, 1, refac_syntax:get_ann(Node)) of
		  {value, {def, DefinePos}} ->
		      lists:keysearch(def, 1, refac_syntax:get_ann(Node)),
		      {value, {category, C}} = lists:keysearch(category, 1, refac_syntax:get_ann(Node)),
		      {{refac_syntax:variable_name(Node), DefinePos, C}, true};
		  false ->
		      {value, {category, C}} = lists:keysearch(category, 1, refac_syntax:get_ann(Node)),
		      {{refac_syntax:variable_name(Node), ?DEFAULT_LOC, C}, true}
		end;
	    false -> {[], false}
	  end;
      _ -> {[], false}
    end.


%% =====================================================================
%% @spec pos_to_expr(Tree::syntaxTree(), Start::Pos, End::Pos) ->
%%                  {ok, syntaxTree()} | {error, none}
%%
%%       Pos={integer(), integer()}
%% @doc Get the largest, left-most expression enclosed by the start and end locations.
%%
%% @see pos_to_fun_name/2
%% @see pos_to_fun_def/2
%% @see pos_to_var_name/2

pos_to_expr(Tree, Start, End) ->
   Es = pos_to_expr_1(Tree, Start, End),
   case Es of 
       [H|_T] -> {ok, H};
       _ -> {error, none}
   end.

pos_to_expr_1(Tree, Start, End) ->
    {S, E} = get_range(Tree),
    if (S >= Start) and (E =< End) ->
	   case is_expr(Tree) of
	     true -> [Tree];
	     _ ->
		 Ts = refac_syntax:subtrees(Tree),
		 R0 = [[pos_to_expr_1(T, Start, End) || T <- G] || G <- Ts],
		 lists:flatten(R0)
	   end;
       (S > End) or (E < Start) -> [];
       (S < Start) or (E > End) ->
	   Ts = refac_syntax:subtrees(Tree),
	   R0 = [[pos_to_expr_1(T, Start, End) || T <- G] || G <- Ts],
	   lists:flatten(R0);
       true -> []
    end.

%% ===========================================================================
%% @spec expr_to_fun(Tree::syntaxTree(), Exp::syntaxTree())->
%%                   {ok, syntaxTree()} | {error, none}
%%
%% @doc Return the AST of the function to which Exp (an expression node) belongs.

expr_to_fun(Tree, Exp) ->
    Res = expr_to_fun_1(Tree, Exp),
    case Res of 
	[H|_T] -> {ok, H};
	_ -> {error, none}
    end.
    
expr_to_fun_1(Tree, Exp) ->
    {Start, End} = get_range(Exp),
    {S, E} = get_range(Tree),
    if (S < Start) and (E >= End) ->
	   case refac_syntax:type(Tree) of
	     function -> [Tree];
	     _ ->
		 Ts = refac_syntax:subtrees(Tree),
		 R0 = [[expr_to_fun_1(T, Exp) || T <- G] || G <- Ts],
		 lists:flatten(R0)
	   end;
       true -> []
    end.

%% =====================================================================
%% @spec is_var_name(Name:: string())-> bool()
%% @doc Return true if a string is lexically a  variable name.

is_var_name(Name) ->
    case Name of
      [H | T] -> (is_upper(H) or (H == 95)) and is_var_name_tail(T);
      [] -> false
    end.

is_var_name_tail(Name) ->
    case Name of
      [H | T] ->
	  (is_upper(H) or is_lower(H) or is_digit(H) or (H == 64) or (H == 95)) and
	    is_var_name_tail(T);
      [] -> true
    end.

is_upper(L) -> (L >= 65) and (90 >= L).

is_lower(L) -> (L >= 97) and (122 >= L).

is_digit(L) -> (L >= 48) and (57 >= L).


%% =====================================================================
%% @spec is_fun_name(Name:: string())-> bool()
%% @doc Return true if a name is lexically a function name.

is_fun_name(Name) ->
    case Name of
      [H | T] -> is_lower(H) and is_var_name_tail(T);
      [] -> false
    end.



%% =====================================================================
%% @spec is_expr(Node:: syntaxTree())-> bool()
%% @doc Return true if an AST node represents an expression.

is_expr(Node) ->
    As = refac_syntax:get_ann(Node),
    case lists:keysearch(category, 1, As) of
      {value, {category, C}} ->
	  case C of
	    expression -> true;
	    guard_expression -> true;
	    _ -> false
	  end;
      _ -> false
    end.

%% =====================================================================
%% @spec is_pattern(Node:: syntaxTree())-> bool()
%% @doc Return true if an AST node represents a pattern.

is_pattern(Node) ->
    As = refac_syntax:get_ann(Node),
    case lists:keysearch(category, 1, As) of
      {value, {category, C}} ->
	  case C of
	    pattern -> true;
	    _ -> false
	  end;
      _ -> false
    end.

%% ============================================================================
%% @spec get_range(Node::syntaxTree())-> {Pos, Pos}
%%       Pos={integer(), integer()}
%%
%% @doc Return the start and end location of the syntax phrase in the code.

get_range(Node) ->
    As = refac_syntax:get_ann(Node),
    case lists:keysearch(range, 1, As) of
      {value, {range, {S, E}}} -> {S, E};
      _ -> {?DEFAULT_LOC,
	   ?DEFAULT_LOC} 
    end.

%% =====================================================================
%% @spec get_var_exports(Node::syntaxTree())-> [atom()]
%% @doc Return the exported variables of an AST node.

get_var_exports(Node) ->
    get_var_exports_1(refac_syntax:get_ann(Node)).

get_var_exports_1([{bound, B} | _Bs]) -> B;
get_var_exports_1([_ | Bs]) -> get_var_exports_1(Bs);
get_var_exports_1([]) -> [].

%% =====================================================================
%% @spec get_free_vars(Node::syntaxTree())-> [atom()]
%% @doc Return the free variables of an AST node.

get_free_vars(Node) ->
    get_free_vars_1(refac_syntax:get_ann(Node)).

get_free_vars_1([{free, B} | _Bs]) -> B;
get_free_vars_1([_ | Bs]) -> get_free_vars_1(Bs);
get_free_vars_1([]) -> [].

%% =====================================================================
%% @spec get_bound_vars(Node::syntaxTree())-> [atom()]
%% @doc Return the bound variables of an AST node.

get_bound_vars(Node) ->
    get_bound_vars_1(refac_syntax:get_ann(Node)).

get_bound_vars_1([{bound, B} | _Bs]) -> B;
get_bound_vars_1([_ | Bs]) -> get_bound_vars_1(Bs);
get_bound_vars_1([]) -> [].


%%===============================================================================
%% @spec inscope_funs(ModuleInfo) -> [{ModName, FunName, Arity}]
%%       ModuleInfo = [{Key, term()}]
%%       Key = attributes | errors | exports | functions | imports | module
%%             | records | rules | warnings
%%       ModName = atom()
%%       FunName = atom()
%%       Arity = integer()
%%
%% @doc Returns the functions that are inscope (either imported by the 
%% module or defined within the module) in the current module.
%% @TODO: Think about the interface of this function again.

inscope_funs(ModuleInfo) ->
    case lists:keysearch(module, 1, ModuleInfo) of
      {value, {module, M}} ->
	  Imps = case lists:keysearch(imports, 1, ModuleInfo) of
		   {value, {imports, I}} ->
		       lists:concat([lists:map(fun ({F, A}) -> {M1, F, A} end, Fs) || {M1, Fs} <- I]);
		   _ -> []
		 end,
	  Funs = case lists:keysearch(functions, 1, ModuleInfo) of
		   {value, {functions, Fs}} -> lists:map(fun ({F, A}) -> {M, F, A} end, Fs);
		   _ -> []
		 end,
	  Imps ++ Funs;
      _ -> []
    end.

%%===============================================================================
%% @spec is_exported({FunName::atom(), Arity::integer},ModuleInfo) -> bool()
%%       ModuleInfo = [{Key, term()}]
%%       Key = attributes | errors | exports | functions | imports | module
%%             | records | rules | warnings
%% @doc Return true if the function is exported by its defining module.
%% @TODO: Think about the interface of this function again.
is_exported({FunName, Arity}, ModInfo) ->
    case lists:keysearch(exports, 1, ModInfo) of
      {value, {exports, ExportList}} ->
	  R = lists:member({FunName, Arity}, ExportList),
	  if R -> R;
	     true ->
		 case lists:keysearch(attributes, 1, ModInfo) of
		   {value, {attributes, Attrs}} -> lists:member({compile, export_all}, Attrs);
		   false -> false
		 end
	  end;
      false ->
	  case lists:keysearch(attributes, 1, ModInfo) of
	    {value, {attributes, Attrs}} -> lists:member({compile, export_all}, Attrs);
	    false -> false
	  end
    end.

%% =====================================================================
%% @spec update_ann(Node::syntaxTree(), {Key::atom(), Val::term()}) -> syntaxTree()
%% @doc Update a specific annotation of the Node with the given one.
%% if the kind of annotation already exists in the AST node, the annotation 
%% value is replaced with the new one, otherwise the given annotation info 
%% is added to the node.

update_ann(Tree, {Key, Val}) ->
    As0 = refac_syntax:get_ann(Tree),
    As1 = case lists:keysearch(Key, 1, As0) of
	    {value, _} -> lists:keyreplace(Key, 1, As0, {Key, Val});
	    _ -> As0 ++ [{Key, Val}]
	  end,
    refac_syntax:set_ann(Tree, As1).

%% =====================================================================
%% @spec reset_attrs(Node::syntaxTree()) -> syntaxTree()
%% @doc Reset all the annotations in the subtree to the default (empty) annotation.

reset_attrs(Node) ->
    refac_util:full_buTP(fun (T, _Others) -> refac_syntax:set_ann(T, []) end, Node, {}).


%%===============================================================================
%% @spec get_client_files(File::filename(), SearchPaths::[Dir]) -> [filename()]
%%       Dir = string
%% @doc Return the list of files (Erlang modules) which make use of the functions 
%% defined in File.

get_client_files(File, SearchPaths) ->
    ValidSearchPaths = lists:all(fun (X) -> filelib:is_dir(X) end, SearchPaths),
    case ValidSearchPaths of
      true -> ok;
      false ->
	  exit("One of the directories sepecified in "
	       "the search paths does not exist, please "
	       "check the customization!")
    end,
    ModuleGraphFile = filename:join([filename:dirname(File), "modulegraph"]),
    File1 = filename:absname(normalise_file_name(File)),
    Dir = filename:dirname(File1),
    ModuleGraph = refac_module_graph:module_graph(lists:usort([Dir | SearchPaths]), ModuleGraphFile, SearchPaths),
    ClientFiles = case lists:keysearch(File1, 1, ModuleGraph) of
		    {value, {_, Clients}} -> lists:delete(File1, Clients);
		    _ -> []
		  end,
    case ClientFiles of
      [] ->
	  io:format("\nWARNING: this module does not have "
		    "any client modules, please check the "
		    "search paths to ensure that this is "
		    "correct!\n");
      _ -> ok
    end,
    HeaderFiles = expand_files(SearchPaths, ".hrl"),
    ClientFiles ++ HeaderFiles.

normalise_file_name(Filename) ->
    filename:join(filename:split(Filename)).


%% =====================================================================
%% @spec expand_files(FileDirs::[filename()|dirname()], Ext::atom()) -> [filename()]
%% @doc Recursively collect all the files with the given file extension 
%%  in the specified directoris/files.
expand_files(FileDirs, Ext) ->
    expand_files(FileDirs, Ext, []).

expand_files([FileOrDir | Left], Ext, Acc) ->
    case filelib:is_dir(FileOrDir) of
      true ->
	  {ok, List} = file:list_dir(FileOrDir),
	  NewFiles = [filename:join(FileOrDir, X)
		      || X <- List, filelib:is_file(filename:join(FileOrDir, X)), filename:extension(X) == Ext],
	  NewDirs = [filename:join(FileOrDir, X) || X <- List, filelib:is_dir(filename:join(FileOrDir, X))],
	  expand_files(NewDirs ++ Left, Ext, NewFiles ++ Acc);
      false ->
	  case filelib:is_regular(FileOrDir) of
	    true ->
		case filename:extension(FileOrDir) == Ext of
		  true -> expand_files(Left, Ext, [FileOrDir | Acc]);
		  false -> expand_files(Left, Ext, [FileOrDir])
		end;
	    _ -> expand_files(Left, Ext, [FileOrDir])
	  end
    end;
expand_files([], _Ext, Acc) -> ordsets:from_list(Acc).


%% =====================================================================
%% @spec get_modules_by_file(Files::[filename()]) -> [{atom(), dirname()}]
%% @doc The a list of files to a list of two-element tuples, with the first 
%% element of the tuple being the module name, and the second element 
%% binding the directory name of the file to which the module belongs.

get_modules_by_file(Files) ->
    get_modules_by_file(Files, []).

get_modules_by_file([File | Left], Acc) ->
    BaseName = filename:basename(File, ".erl"),
    Dir = filename:dirname(File),
    get_modules_by_file(Left, [{BaseName, Dir} | Acc]);
get_modules_by_file([], Acc) -> lists:reverse(Acc).


%% =====================================================================
%% @spec write_refactored_files(Files::[{OldFileName::filename(), NewFileName::filename(),
%%                             AST::syntaxTree()}])-> ok
%% @doc Pretty-print the abstract syntax trees to a files, and add the previous 
%% version to history for undo purpose. <code>Files</code> is a list of three element 
%% tuples. The first element in the tuple is the original file name, the second element 
%% is the new file name if the filename has been changed by the refactoring, otherwise it 
%% should be the same as the first element, and the third element in the tuple is the 
%% AST represention of the file.

write_refactored_files(Files) ->
    F = fun ({{File1, File2}, AST}) ->
		if File1 /= File2 ->
		       file:delete(File1),
		       file:write_file(File2,
				       list_to_binary(refac_prettypr:print_ast(AST)));  
		   true -> file:write_file(File2, list_to_binary(refac_prettypr:print_ast(AST)))
		end
	end,
    Files1 = lists:map(fun ({{OldFileName, NewFileName}, _}) ->
			       {ok, Bin} = file:read_file(OldFileName), {{OldFileName, NewFileName}, Bin}
		       end,
		       Files),
    case erlang:whereis(refactor_undo) of
      undefined ->
	  io:format("\nWARNING: the UNDO process is not working, "
		    "please restart the refactorer!\n");
      _ -> refactor_undo ! {add, Files1}
    end,
    lists:map(F, Files).

%% =====================================================================
%% @spec tokenize(File::filename()) -> [token()]
%% @doc Tokenize an Erlang file into a list of tokens.

tokenize(File) ->
    {ok, Bin} = file:read_file(File),
    S = erlang:binary_to_list(Bin),
    case refac_scan:string(S) of
      {ok, Toks, _} -> Toks;
      _ -> []
    end.

%% =====================================================================
%% @spec parse_annotate_file(FName::filename(), ByPassPreP::bool(), SearchPaths::[dirname()])
%%                           -> {ok, {syntaxTree(), ModInfo}} | {error, term()}
%%
%%       ModInfo = [{Key, term()}]
%%       Key = attributes | errors | exports | functions | imports | module
%%             | records | rules | warnings
%%
%% @doc Parse an Erlang file, and annotate the abstract syntax tree with static semantic 
%% information. As to the parameters, FName is the name of the file to parse;  ByPassPreP 
%% is a boolean value, and 'true' means to use the parse defined in refac_epp_dodger 
%% (which does not expand macros), 'false' means to use the parse defined in refac_epp
%% (which expands macros); SeachPaths is the list of directories to search for related 
%% Erlang files. 
%% The following annotations are added to the AST generated by the parser.
%% <ul>
%%     <li> <code> {env, [Var]}</code>, representing the input enrironment of 
%%     the subtree. </li>
%%
%%     <li> <code> {bound, [Var]} </code>, representing the variables that are 
%%      bound in the subtree. </li>
%%
%%     <li> <code> {free, [Var]}</code>, representing the free variables in the 
%%     subtree </li>
%%   
%%     <li> <code> {range, {Pos, Pos}} </code>, representing the start and end location 
%%     of subtree in the program source. </li>
%%    
%%     <li> <code> {category, atom()} </code>, representing the kind of the syntex phrase 
%%      represented by the subtree. </li>
%%
%%     <li> <code> {def, [Pos]} </code>, representing the defining positions of the variable 
%%     represented by the subtree (only when the subtree does represent a variable). </li>
%%
%%     <li> <code> {fun_def, {Mod, FunName, Arity, Pos, Pos}} </code>, representing the binding 
%%     information of the function represented by the subtree (only when the subtree
%%     represents a function definition, a function application, or an arity qualifier).
%%      </li>
%% </ul>
%%  <code>Var</code>  is a two-element tuple whose first element is an atom representing 
%%   the variable name, second element representing the variable's defining position. 
%%
%% @type syntaxTree(). An abstract syntax tree. The <code>erl_parse</code> "parse tree" 
%%  representation is a subset of the <code>syntaxTree()</code> representation.
%% 
%%  For the data structures used by the AST nodes, please refer to <a href="refac_syntax.html"> refac_syntax </a>.


parse_annotate_file(FName, ByPassPreP, SearchPaths) ->
    R = case ByPassPreP of
	  true -> refac_epp_dodger:parse_file(FName);
	  false -> refac_epp:parse_file(FName, SearchPaths, [])
	end,
    case R of
      {ok, Forms1} ->
	  Forms = if ByPassPreP -> Forms1;
		     true -> tl(Forms1)
		  end,
	  Comments = erl_comment_scan:file(FName),
	  SyntaxTree = refac_recomment:recomment_forms(Forms, Comments),
	  Info = refac_syntax_lib:analyze_forms(SyntaxTree),
	  %%	  case lists:keysearch(errors,1,Info) of
	  %%      {value,{errors, Error}} ->
	  %%	  {error, {"Syntax error in file: " ++ FName++".", Error}};
	  %%    _ ->
	  AnnAST = annotate_bindings(FName, SyntaxTree, Info, 1),
	  if ByPassPreP -> {ok, {AnnAST, Info}};
	     true ->
		 case analyze_free_vars(AnnAST) of
		   {error, Reason} -> {error, Reason};
		   _ ->   {ok, {AnnAST, Info}}
		 end
	  end;
      {error, Reason} -> {error, Reason}
    end.

analyze_free_vars(SyntaxTree) ->
    Ann = refac_syntax:get_ann(SyntaxTree),
    case lists:keysearch(free, 1, Ann) of
      {value, {free, FrVars}} ->
	  case FrVars of
	    [] -> ok;
	    Ls -> {error, "Unbound variable(s) found: " ++ show_fv_vars(Ls)}
	  end;
      _ -> ok
    end.

show_fv_vars([]) -> ".";
show_fv_vars([{A, {Line, Col}} | T]) ->
    T1 = if T == [] -> ".";
	    true -> ", " ++ show_fv_vars(T)
	 end,
    atom_to_list(A) ++ " at: {" ++ integer_to_list(Line) ++ "," ++ integer_to_list(Col) ++ "}" ++ T1.


%% annotate the abstract syntax tree with static semantics information.
annotate_bindings(FName, AST, Info, AnnotateLevel) ->
    AnnAST0 = refac_syntax_lib:annotate_bindings(AST, ordsets:new()),
    AnnAST1 = update_var_define_locations(AnnAST0),
    AnnAST2 = add_category(AnnAST1),
   case AnnotateLevel of
      0 -> add_range(FName, AnnAST2);
      1 ->
	  AnnAST3 = adjust_locations(FName, AnnAST2),
	  AnnAST4 = add_fun_define_locations(AnnAST3, Info),
	  add_range(FName, AnnAST4)
    end.

%% Add  start and end location to each AST node.
add_range(FName, AST) ->
    {ok, Toks} = refac_epp:scan_file(FName, [], []),
    full_buTP(fun do_add_range/2, AST, Toks).

do_add_range(Node, Toks) ->
    {L, C} = refac_syntax:get_pos(Node),
    case refac_syntax:type(Node) of
      variable ->
	  Len = length(refac_syntax:variable_literal(Node)),
	  refac_syntax:add_ann({range, {{L, C}, {L, C + Len - 1}}}, Node);
      atom ->
	  Len = length(atom_to_list(refac_syntax:atom_value(Node))),
	  refac_syntax:add_ann({range, {{L, C}, {L, C + Len - 1}}}, Node);
      operator ->
	  Len = length(atom_to_list(refac_syntax:atom_value(Node))),
	  refac_syntax:add_ann({range, {{L, C}, {L, C + Len - 1}}}, Node);
      char -> refac_syntax:add_ann({range, {{L, C}, {L, C}}}, Node);
      integer ->
	  Len = length(refac_syntax:integer_literal(Node)),
	  refac_syntax:add_ann({range, {{L, C}, {L, C + Len - 1}}}, Node);
      string ->
	  Len = length(refac_syntax:string_literal(Node)),
	  refac_syntax:add_ann({range, {{L, C}, {L, C + Len - 1}}}, Node);
      float ->
	  refac_syntax:add_ann({range, {{L, C}, {L, C}}}, Node); %% This is problematic.
      underscore -> refac_syntax:add_ann({range, {{L, C}, {L, C}}}, Node);
      eof_marker -> refac_syntax:add_ann({range, {{L, C}, {L, C}}}, Node);
      nil -> refac_syntax:add_ann({range, {{L, C}, {L, C + 1}}}, Node);
      module_qualifier ->
	  M = refac_syntax:module_qualifier_argument(Node),
	  F = refac_syntax:module_qualifier_body(Node),
	  {S1, _E1} = get_range(M),
	  {_S2, E2} = get_range(F),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      list ->
	  LP = ghead("refac_util:do_add_range,list", refac_syntax:list_prefix(Node)),
	  {{L1, C1}, {L2, C2}} = get_range(LP),
	  %%  Es = refac_syntax:list_elements(Node),
	  %% 		   case Es of
	  %% 		       [] -> refac_syntax:add_ann({range,{{L,C},{L,C}}}, Node);
	  %% 		       _ -> {S1,_E1} = get_range(hd(Es)),
	  %% 			    {_S2,E2} = get_range(lists:last(Es)),
	  %% 			    refac_syntax:add_ann({range, {S1,E2}}, Node)
	  %% 		   end;
	  Node1 = case refac_syntax:list_suffix(Node) of
		    none -> refac_syntax:add_ann({range, {{L1, C1 - 1}, {L2, C2 + 1}}}, Node);
		    Tail -> {_S2, {L3, C3}} = get_range(Tail), refac_syntax:add_ann({range, {{L1, C1 - 1}, {L3, C3}}}, Node)
		  end,
	  Node1;
      application ->
	  O = refac_syntax:application_operator(Node),
	  Args = refac_syntax:application_arguments(Node),
	  {S1, E1} = get_range(O),
	  {S3, E3} = case Args of
		       [] -> {S1, E1};
		       _ -> La = glast("refac_util:do_add_range, application", Args), {_S2, E2} = get_range(La), {S1, E2}
		     end,
	  E31 = extend_backwards(Toks, E3, ')'),
	  refac_syntax:add_ann({range, {S3, E31}}, Node);
      case_expr ->
	  A = refac_syntax:case_expr_argument(Node),
	  Lc = glast("refac_util:do_add_range,case_expr", refac_syntax:case_expr_clauses(Node)),
	  {S1, _E1} = get_range(A),
	  {_S2, E2} = get_range(Lc),
	  S11 = extend_forwards(Toks, S1, 'case'),
	  E21 = extend_backwards(Toks, E2, 'end'),
	  refac_syntax:add_ann({range, {S11, E21}}, Node);
      clause ->
	  P = refac_syntax:get_pos(Node),
	  Body = glast("refac_util:do_add_range, clause", refac_syntax:clause_body(Node)),
	  {_S2, E2} = get_range(Body),
	  refac_syntax:add_ann({range, {P, E2}}, Node);
      catch_expr ->
	  B = refac_syntax:catch_expr_body(Node),
	  {S, E} = get_range(B),
	  S1 = extend_forwards(Toks, S, 'catch'),
	  refac_syntax:add_ann({range, {S1, E}}, Node);
      if_expr ->
	  Cs = refac_syntax:if_expr_clauses(Node),
	  Hd = ghead("refac_util:do_add_range, if_expr", Cs),
	  La = glast("refac_util:do_add_range, if_expr", Cs),
	  {S1, _E1} = get_range(Hd),
	  {_S2, E2} = get_range(La),
	  S11 = extend_forwards(Toks, S1, 'if'),
	  E21 = extend_backwards(Toks, E2, 'end'),
	  refac_syntax:add_ann({range, {S11, E21}}, Node);
      cond_expr ->
	  Cs = refac_syntax:cond_expr_clauses(Node),
	  Hd = ghead("refac_util:do_add_range, cond_expr", Cs),
	  La = glast("refac_util:do_add_range, cond_expr", Cs),
	  {S1, _E1} = get_range(Hd),
	  {_S2, E2} = get_range(La),
	  S11 = extend_forwards(Toks, S1, 'cond'),
	  E21 = extend_backwards(Toks, E2, 'end'),
	  refac_syntax:add_ann({range, {S11, E21}}, Node);
      infix_expr ->
	  Left = refac_syntax:infix_expr_left(Node),
	  Right = refac_syntax:infix_expr_right(Node),
	  {S1, _E1} = get_range(Left),
	  {_S2, E2} = get_range(Right),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      prefix_expr ->
	  Op = refac_syntax:prefix_expr_operator(Node),
	  Ar = refac_syntax:prefix_expr_argument(Node),
	  {S1, _E1} = get_range(Op),
	  {_S2, E2} = get_range(Ar),
	  E21 = extend_backwards(Toks, E2, ')'),
	  refac_syntax:add_ann({range, {S1, E21}}, Node);
      conjunction ->
	  B = refac_syntax:conjunction_body(Node),
	  H = ghead("refac_util:do_add_range,conjunction", B),
	  La = glast("refac_util:do_add_range,conjunction", B),
	  {S1, _E1} = get_range(H),
	  {_S2, E2} = get_range(La),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      disjunction ->
	  B = refac_syntax:disjunction_body(Node),
	  H = ghead("refac_util:do_add_range, disjunction", B),
	  La = glast("refac_util:do_add_range,disjunction", B),
	  {S1, _E1} = get_range(H),
	  {_S2, E2} = get_range(La),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      function ->
	  F = refac_syntax:function_name(Node),
	  Cs = refac_syntax:function_clauses(Node),
	  Lc = glast("refac_util:do_add_range,function", Cs),
	  {S1, _E1} = get_range(F),
	  {_S2, E2} = get_range(Lc),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      fun_expr ->
	  Cs = refac_syntax:fun_expr_clauses(Node),
	  S = refac_syntax:get_pos(Node),
	  Lc = glast("refac_util:do_add_range, fun_expr", Cs),
	  {_S1, E1} = get_range(Lc),
	  E11 = extend_backwards(Toks, E1,
				 'end'),   %% S starts from 'fun', so there is no need to extend forwards/
	  refac_syntax:add_ann({range, {S, E11}}, Node);
      arity_qualifier ->
	  B = refac_syntax:arity_qualifier_body(Node),
	  A = refac_syntax:arity_qualifier_argument(Node),
	  {S1, _E1} = get_range(B),
	  {_S2, E2} = get_range(A),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      implicit_fun ->
	  S = refac_syntax:get_pos(Node),
	  N = refac_syntax:implicit_fun_name(Node),
	  {_S1, E1} = get_range(N),
	  refac_syntax:add_ann({range, {S, E1}}, Node);
      attribute ->
	  Name = refac_syntax:attribute_name(Node),
	  Arg = glast("refac_util:do_add_range,attribute", refac_syntax:attribute_arguments(Node)),
	  {S1, _E1} = get_range(Name),
	  {_S2, E2} = get_range(Arg),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      generator ->
	  P = refac_syntax:generator_pattern(Node),
	  B = refac_syntax:generator_body(Node),
	  {S1, _E1} = get_range(P),
	  {_S2, E2} = get_range(B),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      tuple ->
	  Es = refac_syntax:tuple_elements(Node),
	  case length(Es) of
	    0 -> refac_syntax:add_ann({range, {{L, C}, {L, C + 1}}}, Node);
	    _ ->
		Hd = ghead("refac_util:do_add_range, tuple", Es),
		La = glast("refac_util:do_add_range, tuple", Es),
		{S1, _E1} = get_range(Hd),
		{_S2, E2} = get_range(La),
		S11 = extend_forwards(Toks, S1, '{'),
		E21 = extend_backwards(Toks, E2, '}'),
		refac_syntax:add_ann({range, {S11, E21}}, Node)
	  end;
      list_comp ->
	  T = refac_syntax:list_comp_template(Node),
	  B = glast("refac_util:do_add_range,list_comp", refac_syntax:list_comp_body(Node)),
	  {S1, _E1} = get_range(T),
	  {_S2, E2} = get_range(B),
	  S11 = extend_forwards(Toks, S1, '['),
	  E21 = extend_backwards(Toks, E2, ']'),
	  refac_syntax:add_ann({range, {S11, E21}}, Node);
      block_expr ->
	  Es = refac_syntax:block_expr_body(Node),
	  Hd = ghead("refac_util:do_add_range, block_expr", Es),
	  La = glast("refac_util:do_add_range, block_expr", Es),
	  {S1, _E1} = get_range(Hd),
	  {_S2, E2} = get_range(La),
	  S11 = extend_forwards(Toks, S1, 'begin'),
	  E21 = extend_backwards(Toks, E2, 'end'),
	  refac_syntax:add_ann({range, {S11, E21}}, Node);
      receive_expr ->
	  case refac_syntax:receive_expr_timeout(Node) of
	    none ->
		Cs = refac_syntax:receive_expr_clauses(Node),
		case length(Cs) of
		  0 -> refac_syntax:add_ann({range, {L, C}, {L, C}}, Node);
		  _ ->
		      Hd = ghead("refac_util:do_add_range, receive_expr1", Cs),
		      La = glast("refac_util:do_add_range, receive_expr1", Cs),
		      {S1, _E1} = get_range(Hd),
		      {_S2, E2} = get_range(La),
		      S11 = extend_forwards(Toks, S1, 'receive'),
		      E21 = extend_backwards(Toks, E2, 'end'),
		      refac_syntax:add_ann({range, {S11, E21}}, Node)
		end;
	    _E ->
		Cs = refac_syntax:receive_expr_clauses(Node),
		A = refac_syntax:receive_expr_action(Node),
		case length(Cs) of
		  0 ->
		      {_S2, E2} = get_range(glast("refac_util:do_add_range, receive_expr2", A)),
		      refac_syntax:add_ann({range, {{L, C}, E2}}, Node);
		  _ ->
		      Hd = ghead("refac_util:do_add_range,receive_expr2", Cs),
		      {S1, _E1} = get_range(Hd),
		      {_S2, E2} = get_range(glast("refac_util:do_add_range, receive_expr3", A)),
		      S11 = extend_forwards(Toks, S1, 'receive'),
		      E21 = extend_backwards(Toks, E2, 'end'),
		      refac_syntax:add_ann({range, {S11, E21}}, Node)
		end
	  end;
      binary ->
	  Fs = refac_syntax:binary_fields(Node),
	  case Fs == [] of
	    true -> refac_syntax:add_ann({range, {{L, C}, {L, C + 3}}}, Node);
	    _ ->
		Hd = ghead("refac_util:do_add_range, binary", Fs),
		La = glast("refac_util:do_add_range, binary", Fs),
		{S1, _E1} = get_range(Hd),
		{_S2, E2} = get_range(La),
		S11 = extend_forwards(Toks, S1, '<<'),
		E21 = extend_backwards(Toks, E2, '>>'),
		refac_syntax:add_ann({range, {S11, E21}}, Node)
	  end;
      binary_field ->
	  Body = refac_syntax:binary_field_body(Node),
	  Types = refac_syntax:binary_field_types(Node),
	  {S1, E1} = get_range(Body),
	  {_S2, E2} = if Types == [] -> {S1, E1};
			 true -> get_range(glast("refac_util:do_add_range,binary_field", Types))
		      end,
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      match_expr ->
	  P = refac_syntax:match_expr_pattern(Node),
	  B = refac_syntax:match_expr_body(Node),
	  {S1, _E1} = get_range(P),
	  {_S2, E2} = get_range(B),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      form_list ->
	  Es = refac_syntax:form_list_elements(Node),
	  Hd = ghead("refac_util:do_add_range, form_list", Es),
	  La = glast("refac_util:do_add_range, form_list", Es),
	  {S1, _E1} = get_range(Hd),
	  {_S2, E2} = get_range(La),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      parentheses ->
	  B = refac_syntax:parentheses_body(Node),
	  {S, E} = get_range(B),
	  S1 = extend_forwards(Toks, S, '('),
	  E1 = extend_backwards(Toks, E, ')'),
	  refac_syntax:add_ann({range, {S1, E1}}, Node);
      class_qualifier ->
	  A = refac_syntax:class_qualifier_argument(Node),
	  B = refac_syntax:class_qualifier_body(Node),
	  {S1, _E1} = get_range(A),
	  {_S2, E2} = get_range(B),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      qualified_name ->
	  Es = refac_syntax:qualified_name_segments(Node),
	  Hd = ghead("refac_util:do_add_range, qualified_name", Es),
	  La = glast("refac_util:do_add_range, qualified_name", Es),
	  {S1, _E1} = get_range(Hd),
	  {_S2, E2} = get_range(La),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      query_expr ->
	  B = refac_syntax:query_expr_body(Node),
	  {S, E} = get_range(B),
	  refac_syntax:add_ann({range, {S, E}}, Node);
      record_field ->
	  Name = refac_syntax:record_field_name(Node),
	  {S1, E1} = get_range(Name),
	  Value = refac_syntax:record_field_value(Node),
	  case Value of
	    none -> refac_syntax:add_ann({range, {S1, E1}}, Node);
	    _ -> {_S2, E2} = get_range(Value), refac_syntax:add_ann({range, {S1, E2}}, Node)
	  end;
      record_expr ->
	  Arg = refac_syntax:record_expr_argument(Node),
	  Type = refac_syntax:record_expr_type(Node),
	  Fields = refac_syntax:record_expr_fields(Node),
	  {S1, E1} = case Arg of
		       none -> get_range(Type);
		       _ -> get_range(Arg)
		     end,
	  case Fields of
	    [] -> E11 = extend_backwards(Toks, E1, '}'), refac_syntax:add_ann({range, {S1, E11}}, Node);
	    _ ->
		{_S2, E2} = get_range(glast("refac_util:do_add_range,record_expr", Fields)),
		E21 = extend_backwards(Toks, E2, '}'),
		refac_syntax:add_ann({range, {S1, E21}}, Node)
	  end;
      record_access ->
	  Arg = refac_syntax:record_access_argument(Node),
	  Field = refac_syntax:record_access_field(Node),
	  {S1, _E1} = get_range(Arg),
	  {_S2, E2} = get_range(Field),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      record_index_expr ->
	  Type = refac_syntax:record_index_expr_type(Node),
	  Field = refac_syntax:record_index_expr_field(Node),
	  {S1, _E1} = get_range(Type),
	  {_S2, E2} = get_range(Field),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      comment ->
	  T = refac_syntax:comment_text(Node),
	  Lines = length(T),
	  refac_syntax:add_ann({range,
				{{L, C}, {L + Lines - 1, length(glast("refac_util:do_add_range,comment", T))}}},
			       Node);
      macro ->
	  Name = refac_syntax:macro_name(Node),
	  Args = refac_syntax:macro_arguments(Node),
	  {S1, E1} = get_range(Name),
	  case Args of
	    none -> refac_syntax:add_ann({range, {S1, E1}}, Node);
	    Ls ->
		La = glast("refac_util:do_add_range,macor", Ls),
		{_S2, E2} = get_range(La),
		refac_syntax:add_ann({range, {S1, E2}}, Node)
	  end;
      size_qualifier ->
	  Body = refac_syntax:size_qualifier_body(Node),
	  Arg = refac_syntax:size_qualifier_argument(Node),
	  {S1, _E1} = get_range(Body),
	  {_S2, E2} = get_range(Arg),
	  refac_syntax:add_ann({range, {S1, E2}}, Node);
      _ ->
	  %%io:format("Unhandled syntax category:\n~p\n", [refac_syntax:type(Node)]),
	  %%io:format("Node:\n~p\n", [Node]),
	  Node
    end.

%% TOAdd:
%%       {bin_element, _, _, _, _} -> binary_field;
%%       {rule, _, _, _, _} -> rule;
%%       {'try', _, _, _, _, _} -> try_expr;


extend_forwards(Toks, StartLoc, Val) ->
    Toks1 = lists:takewhile(fun (T) -> token_loc(T) < StartLoc end, Toks),
    Toks2 = lists:dropwhile(fun (T) -> token_val(T) =/= Val end, lists:reverse(Toks1)),
    case Toks2 of
      [] -> StartLoc;
      _ -> token_loc(hd(Toks2))
    end.

extend_backwards(Toks, EndLoc, Val) ->
    Toks1 = lists:dropwhile(fun (T) -> token_loc(T) =< EndLoc end, Toks),
    Toks2 = lists:dropwhile(fun (T) -> token_val(T) =/= Val end, Toks1),
    case Toks2 of
      [] -> EndLoc;
      _ ->
	  {Ln, Col} = token_loc(hd(Toks2)),
	  {Ln, Col + length(atom_to_list(Val)) - 1}
    end.

token_loc(T) ->
    case T of
      {_, L, _V} -> L;
      {_, L1} -> L1
    end.

token_val(T) ->
    case T of
      {_, _, V} -> V;
      {V, _} -> V
    end.

%% =====================================================================
%% @spec add_category(Node::syntaxTree()) -> syntaxTree()
%% @doc Attach syntax category information to AST nodes.
%% =====================================================================
add_category(Node) ->
    case refac_syntax:type(Node) of
      form_list ->
	  Es = refac_syntax:form_list_elements(Node),
	  Es1 = lists:map(fun (E) -> add_category(E) end, Es),
	  Node1 = refac_syntax:copy_attrs(Node, refac_syntax:form_list(Es1)),
	  refac_syntax:add_ann({category, form_list}, Node1);
      attribute -> add_category(Node, attribute);
      function -> add_category(Node, function);
      rule -> add_category(Node, rule);
      error_marker -> add_category(Node, error_marker);
      warning_marker -> add_category(Node, warning_marker);
      eof_marker -> add_category(Node, eof_marker);
      comment -> add_category(Node, comment);
      macro -> add_category(Node, macro);
      _ -> add_category(Node, unknown)
    end.

add_category(Node, C) -> {Node1, _} = stop_tdTP(fun do_add_category/2, Node, C),
			 Node1.
	     
do_add_category(Node, C) ->
    if is_list(Node) -> {lists:map(fun (E) -> add_category(E, C) end, Node), true};
       true ->
	   case refac_syntax:type(Node) of
	     clause ->
		 B = refac_syntax:clause_body(Node),
		 P = refac_syntax:clause_patterns(Node),
		 G = refac_syntax:clause_guard(Node),
		 B1 = add_category(B, expression),
		 P1 = add_category(P, pattern),
		 G1 = case G of
			none -> none;
			_ -> add_category(G, guard_expression)
		      end,
		 Node1 = refac_syntax:copy_attrs(Node, refac_syntax:clause(P1, G1, B1)),
		 {refac_syntax:add_ann({category, clause}, Node1), true};
	     match_expr ->
		 P = refac_syntax:match_expr_pattern(Node),
		 B = refac_syntax:match_expr_body(Node),
		 P1 = add_category(P, pattern),
		 B1 = add_category(B, expression),
		 Node1 = refac_syntax:copy_attrs(Node, refac_syntax:match_expr(P1, B1)),
		 {refac_syntax:add_ann({category, C}, Node1), true};
	     operator -> {refac_syntax:add_ann({category, operator}, Node), true}; %% added to fix bug 13/09/2008.
	     arity_qualifier ->
		 Fun = add_category(refac_syntax:arity_qualifier_body(Node), arity_qualifier),
		 A = add_category(refac_syntax:arity_qualifier_argument(Node), arity_qualifier),
		 Node1 = refac_syntax:arity_qualifier(Fun, A),
		 {refac_syntax:add_ann({category, arity_qualifier}, Node1), true};
	     macro ->
		 Name = refac_syntax:macro_name(Node),
		 Args = refac_syntax:macro_arguments(Node),
		 Name1 = add_category(Name, macro_name),
		 Args1 = case Args of
			   none -> none;
			   _ -> add_category(Args, expresssion) %% should 'expression' by 'macro_args'?
			 end,
		 Node1 = refac_syntax:copy_attrs(Node, refac_syntax:macro(Name1, Args1)),
		 {refac_syntax:add_ann({category, macro}, Node1), true};
	     attribute ->
		 case refac_syntax:atom_value(refac_syntax:attribute_name(Node)) of
		   define ->
		       Name = refac_syntax:attribute_name(Node),
		       Args = refac_syntax:attribute_arguments(Node),
		       MacroHead = ghead("Refac_util:do_add_category:MacroHead", Args),
		       MacroBody = ghead("Refac_util:do_add_category:MacroBody", tl(Args)),
		       MacroHead1 = case refac_syntax:type(MacroHead) of
				      application ->
					  Operator = add_category(refac_syntax:application_operator(MacroHead), macro_name),
					  Arguments = add_category(refac_syntax:application_arguments(MacroHead), attribute),
					  refac_syntax:copy_attrs(MacroHead, refac_syntax:application(Operator, Arguments));
				      _ -> add_category(MacroHead, macro_name)
				    end,
		       MacroBody1 = add_category(MacroBody, attribute),
		       Node1 = refac_syntax:copy_attrs(Node, refac_syntax:attribute(Name, [MacroHead1, MacroBody1])),
		       {refac_syntax:add_ann({category, attribute}, Node1), true};
		   _ -> {refac_syntax:add_ann({category, C}, Node), false}
		 end;
	     %% TO ADD: other cases such as fields. Refer to the Erlang Specification.
	     _ -> {refac_syntax:add_ann({category, C}, Node), false}
	   end
    end.


%% Adjust the locations of F and A in an implicit function application (fun F/A)
%% to their actual occurrence locations. Originally, both of their locations refer
%% to that of the keyword 'fun'.
%% Qn: Any other cases in need of location adjustment?
adjust_locations(FName, AST) ->
    %% {ok, Toks} =  refac_epp:scan_file(FName, [],[]),
    Toks = tokenize(FName),
    F = fun (T) ->
		case refac_syntax:type(T) of
		  implicit_fun ->
		      Pos = refac_syntax:get_pos(T),
		      Name = refac_syntax:implicit_fun_name(T),
		      case refac_syntax:type(Name) of
			arity_qualifier ->
			    Fun = refac_syntax:arity_qualifier_body(Name),
			    A = refac_syntax:arity_qualifier_argument(Name),
			    case {refac_syntax:type(Fun), refac_syntax:type(A)} of
			      {atom, integer} ->
				  Toks1 = lists:dropwhile(fun (B) -> element(2, B) =/= Pos end, Toks),
				  Fun1 = refac_syntax:atom_value(Fun),
				  Toks2 = lists:dropwhile(fun (B) ->
								  case B of
								    {atom, _, Fun1} -> false;
								    _ -> true
								  end
							  end,
							  Toks1),
				  P = element(2, ghead("refac_util: adjust_locations,P", Toks2)),
				  Fun2 = refac_syntax:set_pos(Fun, P),
				  Toks3 = lists:dropwhile(fun (B) ->
								  case B of
								    {integer, _, _} -> false;
								    _ -> true
								  end
							  end,
							  Toks2),
				  A2 = refac_syntax:set_pos(A,
							    element(2, ghead("refac_util:adjust_locations:A2", Toks3))),
				  refac_syntax:copy_attrs(T,
							  refac_syntax:implicit_fun(refac_syntax:set_pos(refac_syntax:copy_attrs(Name,
																 refac_syntax:arity_qualifier(Fun2, A2)),
													 P)));
			      _ -> T
			    end;
			_ -> T
		      end;
		  _ -> T
		end
	end,
    refac_syntax_lib:map(F, AST).

%% =====================================================================
%% @spec update_var_define_locations(Node::syntaxTree()) -> syntaxTree()
%% @doc  Update the defining locations of those binding occurrences which are
%% associated with more than one binding occurrence.
update_var_define_locations(Node) ->
    F1 = fun (T, S) ->
		 case refac_syntax:type(T) of
		   variable ->
		       R = lists:keysearch(def, 1, refac_syntax:get_ann(T)),
		       case R of
			 {value, {def, P}} -> S ++ [P];
			 _ -> S
		       end;
		   _ -> S
		 end
	 end,
    DefineLocs = lists:usort(refac_syntax_lib:fold(F1, [], Node)),
    F = fun (T) ->
		case refac_syntax:type(T) of
		  variable ->
		      case lists:keysearch(def, 1, refac_syntax:get_ann(T)) of
			{value, {def, Define}} ->
			    Defs = lists:merge([V1
						|| V1 <- DefineLocs,
						   ordsets:intersection(ordsets:from_list(V1), ordsets:from_list(Define)) /= []]),
			    update_ann(T, {def, lists:usort(Defs)});
			_ -> T
		      end;
		  _ -> T
		end
	end,
    refac_syntax_lib:map(F, Node).


add_fun_define_locations(Node,
			 Info) ->  %% DOSE INFO CONTAIN ANY LOCATION INFO? ANSWER: no.
    ModName = case lists:keysearch(module, 1, Info) of
		{value, {module, ModName1}} -> ModName1;
		_ -> ?DEFAULT_MODULE
	      end,
    Funs = fun (T, S) ->
		   case refac_syntax:type(T) of
		     function ->
			 ordsets:add_element({ModName, refac_syntax:data(refac_syntax:function_name(T)),
					      refac_syntax:function_arity(T), refac_syntax:get_pos(T)},
					     S);
		     _ -> S
		   end
	   end,
    Defined_Funs = refac_syntax_lib:fold(Funs, ordsets:new(), Node),
    Imps = case lists:keysearch(imports, 1, Info) of
	     {value, {imports, I}} ->
		 lists:concat([lists:map(fun ({F, A}) -> {M1, F, A, ?DEFAULT_LOC} end, Fs) || {M1, Fs} <- I]);
	     _ -> []
	   end,
    Inscope_Funs = Imps ++ Defined_Funs,
    Define_Mod_Loc = fun (Name, Arity) ->
			     Fs = ordsets:filter(fun ({_M, F, A, _Pos}) -> (F == Name) and (Arity == A) end, Inscope_Funs),
			     case Fs of
			       [] -> {erlang, ?DEFAULT_LOC};   %% is this correct? what about the function is not a BIF?
			       [{M, _, _, Pos} | _] -> {M, Pos}
			     end
		     end,
    F1 = fun (T) ->
		 case refac_syntax:type(T) of
		   function ->
		       Name = refac_syntax:function_name(T),
		       Fun_Name = refac_syntax:atom_value(Name),
		       Arity = refac_syntax:function_arity(T),
		       Pos = refac_syntax:get_pos(T),
		       T2 = [update_ann(C, {fun_def, {ModName, Fun_Name, Arity, refac_syntax:get_pos(C), Pos}})
			     || C <- refac_syntax:function_clauses(T)],
		       Name1 = update_ann(Name, {fun_def, {ModName, Fun_Name, Arity, Pos, Pos}}),
		       T3 = refac_syntax:copy_pos(T, refac_syntax:copy_attrs(T, refac_syntax:function(Name1, T2))),
		       update_ann(T3, {fun_def, {ModName, Fun_Name, Arity, Pos, Pos}});
		   application ->
		       Operator = refac_syntax:application_operator(T),
		       Arguments = refac_syntax:application_arguments(T),
		       case refac_syntax:type(Operator) of
			 atom ->
			     Op = refac_syntax:atom_value(Operator),
			     Arity = length(Arguments),
			     {DefMod, DefLoc} = Define_Mod_Loc(Op, Arity),
			     Operator1 = update_ann(Operator, {fun_def, {DefMod, Op, Arity, refac_syntax:get_pos(Operator), DefLoc}}),
			     refac_syntax:copy_pos(T, refac_syntax:copy_attrs(T, refac_syntax:application(Operator1, Arguments)));
			 module_qualifier ->
			     Mod = refac_syntax:module_qualifier_argument(Operator),
			     Fun = refac_syntax:module_qualifier_body(Operator),
			     case {refac_syntax:type(Mod), refac_syntax:type(Fun)} of
			       {atom, atom} ->
				   M = refac_syntax:atom_value(Mod),
				   Fun_Name = refac_syntax:atom_value(Fun),
				   Arity = length(Arguments),
				   DefLoc = if M == ModName -> {_ModName, DefLoc1} = Define_Mod_Loc(Fun_Name, Arity), DefLoc1;
					       true -> ?DEFAULT_LOC
					    end,
				   Operator1 = refac_syntax:copy_attrs(Operator, refac_syntax:module_qualifier(Mod, Fun)),
				   Operator2 = update_ann(Operator1, {fun_def, {M, Fun_Name, Arity, refac_syntax:get_pos(T), DefLoc}}),
				   refac_syntax:copy_attrs(T, refac_syntax:application(Operator2, Arguments));
			       _ -> T
			     end;
			 _ -> T
		       end;
		   arity_qualifier ->
		       Fun = refac_syntax:arity_qualifier_body(T),
		       A = refac_syntax:arity_qualifier_argument(T),
		       FunName = refac_syntax:atom_value(Fun),
		       Arity = refac_syntax:integer_value(A),
		       {DefMod, DefLoc} = Define_Mod_Loc(FunName, Arity),
		       Fun1 = update_ann(Fun, {fun_def, {DefMod, FunName, Arity, refac_syntax:get_pos(Fun), DefLoc}}),
		       update_ann(refac_syntax:copy_attrs(T, refac_syntax:arity_qualifier(Fun1, A)),
				  {fun_def, {DefMod, FunName, Arity, refac_syntax:get_pos(Fun), DefLoc}});
		   _ -> T
		 end
	 end,
    refac_syntax_lib:map(F1, Node).


%%=================================================================
%% @doc Return true if the abstract syntax tree represented by Node has side effect, 
%%      otherwise return false. As to parameters, File represents filename of the
%%      code to which Node belongs,  Node is the abstract syntax tree representaion of 
%%      the syntax phrase of interest, and SearchPaths specifies the directories to 
%%      search for related local Erlang source files.
%% @spec has_side_effect(File::filename(), Node::syntaxTree(), SearchPaths::[dirname()])-> bool()

has_side_effect(File, Node, SearchPaths) ->
    LibSideEffectFile = filename:join(?WRANGLER_DIR, "plt/side_effect_plt"),
    LibPlt = from_dets(lib_side_effect_plt, LibSideEffectFile),
    CurrentDir = filename:dirname(normalise_file_name(File)),
    LocalSideEffectFile = filename:join(CurrentDir, "local_side_effect_tab"),
    build_local_side_effect_tab(LocalSideEffectFile, SearchPaths),
    LocalPlt = from_dets(local_side_effect_plt, LocalSideEffectFile),
    Res = check_side_effect(Node, LibPlt, LocalPlt),
    dets:close(LibSideEffectFile),
    dets:close(LocalSideEffectFile),
    ets:delete(LocalPlt),
    ets:delete(LibPlt),
    Res.


%%=================================================================
%% @spec build_local_side_effect_tab(File::filename(), SearchPaths::[dirname()]) -> ok
%% @doc Build a local side effect table for File and the files contained in SearchPaths, and
%% put the result to the dets file: local_side_effect_tab. 
%%
%% @see build_lib_side_effect_tab/2.
build_local_side_effect_tab(File, SearchPaths) ->
    ValidSearchPaths = lists:all(fun (X) -> filelib:is_dir(X) end, SearchPaths),
    case ValidSearchPaths of
      true -> ok;
      false ->
	  exit("One of the directories sepecified in "
	       "the search paths does not exist, please "
	       "check the customization!")
    end,
    CurrentDir = filename:dirname(normalise_file_name(File)),
    SideEffectFile = filename:join(CurrentDir, "local_side_effect_tab"),
    LibSideEffectFile = filename:join(?WRANGLER_DIR, "plt/side_effect_plt"),
    LibPlt = from_dets(lib_side_effect_plt, LibSideEffectFile),
    Dirs = lists:usort([CurrentDir | SearchPaths]),
    Files = refac_util:expand_files(Dirs, ".erl"),
    SideEffectFileModifiedTime = filelib:last_modified(SideEffectFile),
    FilesToAnalyse = [F || F <- Files, SideEffectFileModifiedTime < filelib:last_modified(F)],
    LocalPlt = case filelib:is_file(SideEffectFile) of
		 true -> from_dets(local_side_effect_tab, SideEffectFile);
		 _ -> ets:new(local_side_effect_tab, [set, public])
	       end,
    {Sccs, _E} = build_call_graph(FilesToAnalyse),
    build_side_effect_tab(Sccs, LocalPlt, LibPlt),
    to_dets(LocalPlt, SideEffectFile),
    dets:close(LibSideEffectFile),
    ets:delete(LocalPlt),
    ets:delete(LibPlt).


%%=================================================================
%% @spec build_lib_side_effect_tab(FileOrDirs::[fileName()|dirname()]) -> ok
%% @doc Build the side effect table for Erlang libraries specified in FileOrDirs, and
%% put the result to the dets file: plt/side_effect_plt. 
%%
%% @see build_local_side_effect_tab/2.
build_lib_side_effect_tab(FileOrDirs) ->
    Plt = ets:new(side_effect_table, [set, public]),
    {Sccs, _E} = build_call_graph(FileOrDirs),
    build_side_effect_tab(Sccs, Plt, ets:new(dummy_tab, [set, public])),
    ets:insert(Plt, bifs_side_effect_table()),
    File = filename:join(?WRANGLER_DIR, "plt/side_effect_plt"),
    to_dets(Plt, File),
    ets:delete(Plt).

from_dets(Name, Dets) when is_atom(Name) ->
    Plt = ets:new(Name, [set, public]),
    case dets:open_file(Dets, [{access, read}]) of
      {ok, D} ->
	  true = ets:from_dets(Plt, D),
	  ok = dets:close(D),
	  Plt;
      {error, Reason} -> erlang:error(Reason)
    end.

to_dets(Plt, Dets) ->
    file:delete(Dets),
    MinSize = ets:info(Plt, size),
    {ok, Dets} = dets:open_file(Dets, [{min_no_slots, MinSize}]),
    ok = dets:from_ets(Dets, Plt),
    ok = dets:sync(Dets),
    ok = dets:close(Dets).


build_side_effect_tab([Scc | Left], Side_Effect_Tab, OtherTab) ->
    R = side_effect_scc(Scc, Side_Effect_Tab, OtherTab),
    true = ets:insert(Side_Effect_Tab,
		      [{{Mod, Fun, Arg}, R} || {{Mod, Fun, Arg}, _F} <- Scc]),
    build_side_effect_tab(Left, Side_Effect_Tab, OtherTab);
build_side_effect_tab([], Side_Effect_Tab, _) -> Side_Effect_Tab.

side_effect_scc([{{_M, _F, _A}, Def}, F | Left], Side_Effect_Tab, OtherTab) ->
    case check_side_effect(Def, Side_Effect_Tab, OtherTab) of
      true -> true;
      _ -> side_effect_scc([F | Left], Side_Effect_Tab, OtherTab)
    end;
side_effect_scc([{{_M, _F, _A}, Def}], Side_Effect_Tab, OtherTab) ->
    check_side_effect(Def, Side_Effect_Tab, OtherTab).

check_side_effect(Node, LibPlt, LocalPlt) ->
    case refac_syntax:type(Node) of
      receive_expr -> true;
      infix_expr -> Op = refac_syntax:operator_literal(refac_syntax:infix_expr_operator(Node)), Op == "!";
      application ->
	  Operator = refac_syntax:application_operator(Node),
	  Arity = length(refac_syntax:application_arguments(Node)),
	  case refac_syntax:type(Operator) of
	    atom ->
		Op = refac_syntax:atom_value(Operator),
		{value, {fun_def, {M, _N, _A, _P1, _P}}} = lists:keysearch(fun_def, 1, refac_syntax:get_ann(Operator)),
		case lookup(LibPlt, {M, Op, Arity}) of
		  {value, S} -> S;
		  _ ->
		      case lookup(LocalPlt, {M, Op, Arity}) of
			{value, S} -> S;
			_ -> unknown
		      end
		end;
	    module_qualifier ->
		Mod = refac_syntax:module_qualifier_argument(Operator),
		Body = refac_syntax:module_qualifier_body(Operator),
		case {refac_syntax:type(Mod), refac_syntax:type(Body)} of
		  {atom, atom} ->
		      M = refac_syntax:atom_value(Mod),
		      Op = refac_syntax:atom_value(Body),
		      case lookup(LibPlt, {M, Op, Arity}) of
			{value, S} -> S;
			_ ->
			    case lookup(LocalPlt, {M, Op, Arity}) of
			      {value, S} -> S;
			      _ -> unknown
			    end
		      end;
		  _ -> unknown
		end;
	    _ -> unknown
	  end;
      arity_qualifier ->
	  Fun = refac_syntax:arity_qualifier_body(Node),
	  A = refac_syntax:arity_qualifier_argument(Node),
	  case {refac_syntax:type(Fun), refac_syntax:type(A)} of
	    {atom, integer} ->
		FunName = refac_syntax:atom_value(Fun),
		Arity = refac_syntax:integer_value(A),
		{value, {fun_def, {M, _N, _A, _P1, _P}}} = lists:keysearch(fun_def, 1, refac_syntax:get_ann(Node)),
		case lookup(LibPlt, {M, FunName, Arity}) of
		  {value, S} -> S;
		  _ ->
		      case lookup(LocalPlt, {M, FunName, Arity}) of
			{value, S} -> S;
			_ -> unknown
		      end
		end;
	    _ -> unknown
	  end;
      _ ->
	  case refac_syntax:subtrees(Node) of
	    [] -> false;
	    Ts ->
		Res = lists:flatten([[check_side_effect(T, LibPlt, LocalPlt) || T <- G] || G <- Ts]),
		case lists:member(true, Res) of
		  true -> true;
		  false ->
		      case lists:member(unknown, Res) of
			true -> unknown;
			_ -> false
		      end
		end
	  end
    end.

lookup(Plt, {M, F, A}) ->
    case ets:lookup(Plt, {M, F, A}) of
      [] -> none;
      [{_MFA, S}] -> {value, S}
    end.

%% trim_call_graph(DirList) ->
%%     {Sccs, E} = build_call_graph(DirList),
%%     trim_scc(Sccs).


%% trim_scc([], Sccs1) ->
%%      Sccs1;
%% trim_scc([Scc|T], Sccs1) ->


%%====================================================================================
%%@spec build_call_graph(DirList::[dirname()]) -> #callgraph{}
%%@doc Build a function call graph out of the Erlang files contained in the given directories.

build_call_graph(DirList) ->
    Files = refac_util:expand_files(DirList, ".erl"),
    CallGraph = build_call_graph(Files, []),
    %% io:format("CallGraph:\n~p\n", [CallGraph]),
    #callgraph{scc_order = Sccs, external_calls = E} = refac_callgraph:construct(CallGraph),
   %%  Sccs1 =[[Fun||{Fun, _FunDef}<-Scc]||Scc<-Sccs],
%%     io:format("Scc1:\n~p\n", [Sccs1]),
%%     ok.
    {Sccs, E}.
   

build_call_graph([FileName | Left], Acc) ->
    case refac_util:parse_annotate_file(FileName, true, []) of
      {ok, {AnnAST, Info}} ->
	  case lists:keysearch(errors,1, Info) of 
	      {value, {errors, _Errors}} -> erlang:error("Syntax error in " ++ FileName);
	      _ ->  G1 = build_call_graph(AnnAST, Info, FileName),
		    Acc1 = Acc ++ G1,
		    build_call_graph(Left, Acc1)
	  end;
      {error, Reason} -> erlang:error(Reason)
    end;
build_call_graph([], Acc) -> Acc.

build_call_graph(Node, Info, _FileName) ->
    {value, {module, ModName}} = lists:keysearch(module, 1, Info),
    Inscope_Funs = [{erlang, Fun, Arity} || {Fun, Arity} <- auto_imported_bifs()] ++
		     refac_util:inscope_funs(Info),  %% NOTE: orders matters here.
    HandleSpecialFuns = fun (Arguments, S) ->
				case Arguments of
				  [F, A] ->
				      case {refac_syntax:type(F), refac_syntax:type(A)} of
					{atom, list} ->
					    FunName = refac_syntax:atom_value(F),
					    Arity = refac_syntax:list_length(A),
					    ordsets:add_element({ModName, FunName, Arity}, S);
					_ -> S
				      end;
				  [M, F, A] ->
				      case {refac_syntax:type(M), refac_syntax:type(F), refac_syntax:type(A)} of
					{atom, atom, list} ->
					    ModName = refac_syntax:atom_value(M),
					    FunName = refac_syntax:atom_value(F),
					    Arity = refac_syntax:list_length(A),
					    ordsets:add_element({ModName, FunName, Arity}, S);
					_ -> S
				      end;
				  [M, F, A, _O] ->
				      case {refac_syntax:type(M), refac_syntax:type(F), refac_syntax:type(A)} of
					{atom, atom, list} ->
					    ModName = refac_syntax:atom_value(M),
					    FunName = refac_syntax:atom_value(F),
					    Arity = refac_syntax:list_length(A),
					    ordsets:add_element({ModName, FunName, Arity}, S);
					_ -> S
				      end
				end
			end,
    F2 = fun (T, S) ->
		 case refac_syntax:type(T) of
		   application ->
		       Operator = refac_syntax:application_operator(T),
		       Arguments = refac_syntax:application_arguments(T),
		       Arity = length(Arguments),
		       case refac_syntax:type(Operator) of
			 atom ->
			     Op = refac_syntax:atom_value(Operator),
			     R = lists:filter(fun ({_M, F, A}) -> (F == Op) and (A == Arity) end, Inscope_Funs),
			     if R == [] ->
				    ordsets:add_element({unknown, Op, Arity},
							S);  %% Should we give an error message here?
				true ->
				    {M, Op, Arity} = hd(R),
				    S1 = ordsets:add_element({M, Op, Arity}, S),
				    case {Op, Arity} of
				      {apply, 2} -> HandleSpecialFuns(Arguments, S1);
				      {apply, 3} -> HandleSpecialFuns(Arguments, S1);
				      {spawn, 3} -> HandleSpecialFuns(Arguments, S1);
				      {spawn, 4} -> HandleSpecialFuns(Arguments, S1);
				      {spawn_link, 3} -> HandleSpecialFuns(Arguments, S1);
				      {spawn_link, 4} -> HandleSpecialFuns(Arguments, S1);
				      _ -> S1
				    end
			     end;
			 module_qualifier ->
			     Mod = refac_syntax:module_qualifier_argument(Operator),
			     Body = refac_syntax:module_qualifier_body(Operator),
			     case {refac_syntax:type(Mod), refac_syntax:type(Body)} of
			       {atom, atom} ->
				   Mod1 = refac_syntax:atom_value(Mod),
				   Op = refac_syntax:atom_value(Body),
				   S1 = ordsets:add_element({Mod1, Op, Arity}, S),
				   case {Mod1, Op, Arity} of
				     {erlang, apply, 2} -> HandleSpecialFuns(Arguments, S1);
				     {erlang, apply, 3} -> HandleSpecialFuns(Arguments, S1);
				     {erlang, spawn, 3} -> HandleSpecialFuns(Arguments, S1);
				     {erlang, spawn, 4} -> HandleSpecialFuns(Arguments, S1);
				     {erlang, spawn_link, 3} -> HandleSpecialFuns(Arguments, S1);
				     {erlang, spawn_link, 4} -> HandleSpecialFuns(Arguments, S1);
				     _ -> S1
				   end;
			       _ -> S
			     end;
			 _ -> S
		       end;
		   arity_qualifier ->
		       Fun = refac_syntax:arity_qualifier_body(T),
		       A = refac_syntax:arity_qualifier_argument(T),
		       case {refac_syntax:type(Fun), refac_syntax:type(A)} of
			 {atom, integer} ->
			     FunName = refac_syntax:atom_value(Fun),
			     Arity = refac_syntax:integer_value(A),
			     ordsets:add_element({ModName, FunName, Arity}, S);
			 _ -> S
		       end;
		   _ -> S
		 end
	 end,
    F1 = fun (T, S) ->
		 case refac_syntax:type(T) of
		   function ->
		       FunName = refac_syntax:data(refac_syntax:function_name(T)),
		       Arity = refac_syntax:function_arity(T),
		       Caller = {{ModName, FunName, Arity}, T},
		       CalledFuns = lists:usort(refac_syntax_lib:fold(F2, [], T)),
		       ordsets:add_element({Caller, CalledFuns}, S);
		   _ -> S
		 end
	 end,
    lists:usort(refac_syntax_lib:fold(F1, [], Node)).

%% =====================================================================
%% @spec bifs_side_effect_table()->[{{atom(), atom(), integer()}, bool()}]
%% @doc The side effect table of BIFs.
bifs_side_effect_table() ->
    [{{erlang, abs, 1}, false}, {{erlang, append_element, 2}, false}, {{erlang, atom_to_list, 1}, false},
     {{erlang, binary_to_list, 1}, false}, {{erlang, binary_to_list, 3}, false}, {{erlang, binary_to_term, 1}, false},
     {{erlang, bump_reductions, 1}, false}, {{erlang, cancel_timer, 1}, true}, {{erlang, check_process_code, 1}, false},
     {{erlang, concat_binary, 1}, false}, {{erlang, data, 3}, false}, {{erlang, delete_module, 1}, true},
     {{erlang, demonitor, 1}, false}, {{erlang, disconnect_node, 1}, true}, {{erlang, display, 1}, true},
     {{erlang, element, 2}, false}, {{erlang, erase, 0}, true}, {{erlang, erase, 1}, true}, {{erlang, error, 1}, true},
     {{erlang, error, 2}, true}, {{erlang, exit, 1}, true}, {{erlang, exit, 2}, true}, {{erlang, fault, 1}, true},
     {{erlang, fault, 2}, true}, {{erlang, float, 1}, false}, {{erlang, float_to_list, 1}, false},
     {{erlang, fun_info, 2}, false}, {{erlang, fun_info, 1}, false}, {{erlang, fun_to_list, 1}, false},
     {{erlang, function_exported, 3}, true}, {{erlang, garbage_collect, 1}, true}, {{erlang, garbage_collect, 0}, true},
     {{erlang, get, 0}, true}, {{erlang, get, 1}, true}, {{erlang, get_cookie, 0}, true}, {{erlang, get_keys, 1}, true},
     {{erlang, get_stacktrace, 0}, true}, {{erlang, group_leader, 0}, true}, {{erlang, group_leader, 2}, true},
     {{erlang, halt, 0}, true}, {{erlang, halt, 1}, true}, {{erlang, hash, 2}, false}, {{erlang, hd, 1}, false},
     {{erlang, hibernate, 3}, true}, {{erlang, info, 1}, true}, {{erlang, integer_to_list, 1}, false},
     {{erlang, iolist_to_binary, 1}, false}, {{erlang, iolist_size, 1}, false}, {{erlang, is_atom, 1}, false},
     {{erlang, is_binary, 1}, false}, {{erlang, is_boolean, 1}, false}, {{erlang, is_builtin, 3}, false},
     {{erlang, is_float, 1}, false}, {{erlang, is_function, 1}, false}, {{erlang, is_function, 2}, false},
     {{erlang, is_integer, 1}, false}, {{erlang, is_list, 1}, false}, {{erlang, is_number, 1}, false},
     {{erlang, is_pid, 1}, true}, {{erlang, is_port, 1}, false}, {{erlang, is_process_alive, 1}, true},
     {{erlang, is_record, 2}, false}, {{erlang, is_record, 3}, false}, {{erlang, is_reference, 1}, false},
     {{erlang, is_tuple, 1}, false}, {{erlang, length, 1}, false}, {{erlang, link, 1}, true},
     {{erlang, list_to_atom, 1}, false}, {{erlang, list_to_binary, 1}, false},
     {{erlang, list_to_existing_atom, 1}, false}, {{erlang, list_to_float, 1}, false},
     {{erlang, list_to_integer, 1}, false}, {{erlang, list_to_integer, 2}, false}, {{erlang, list_to_pid, 1}, false},
     {{erlang, list_to_tuple, 1}, false}, {{erlang, load_module, 2}, true}, {{erlang, loaded, 0}, true},
     {{erlang, localtime, 0}, true}, {{erlang, localtime_to_universaltime, 1}, false},
     {{erlang, localtime_to_iniversaltime, 2}, false}, {{erlang, make_ref, 0}, true}, {{erlang, make_tuple, 2}, true},
     {{erlang, md5, 1}, false}, {{erlang, md5_final, 1}, false}, {{erlang, md5_init, 0}, false},
     {{erlang, md5_update, 2}, false}, {{erlang, memory, 0}, true}, {{erlang, memory, 1}, true},
     {{erlang, module_loaded, 1}, true}, {{erlang, monitor, 2}, true}, {{erlang, monitor_node, 2}, true},
     {{erlang, node, 0}, true}, {{erlang, node, 1}, true}, {{erlang, nodes, 0}, true}, {{erlang, nodes, 1}, true},
     {{erlang, now, 0}, true}, {{erlang, open_port, 2}, true}, {{erlang, phash, 2}, false}, {{erlang, phash2, 2}, false},
     {{erlang, pid_to_list, 1}, true}, {{erlang, port_close, 1}, true}, {{erlang, port_command, 2}, true},
     {{erlang, port_connect, 2}, true}, {{erlang, port_control, 3}, true}, {{erlang, port_call, 3}, true},
     {{erlang, port_info, 1}, true}, {{erlang, port_info, 2}, true}, {{erlang, port_to_list, 1}, true},
     {{erlang, ports, 0}, true}, {{erlang, pre_loaded, 0}, true}, {{erlang, process_diaplay, 2}, true},
     {{erlang, process_flag, 2}, true}, {{erlang, process_flag, 3}, true}, {{erlang, process_info, 1}, true},
     {{erlang, process_info, 2}, true}, {{erlang, processes, 0}, true}, {{erlang, purge_module, 1}, true},
     {{erlang, put, 2}, true}, {{erlang, raise, 3}, true}, {{erlang, read_timer, 1}, true},
     {{erlang, ref_to_list, 1}, false}, {{erlang, register, 2}, true}, {{erlang, registered, 0}, true},
     {{erlang, resume_process, 1}, true}, {{erlang, round, 1}, false}, {{erlang, self, 0}, true},
     {{erlang, send, 2}, true}, {{erlang, send, 3}, true}, {{erlang, send_after, 3}, true},
     {{erlang, send_nosuspend, 2}, true}, {{erlang, send_nosuspend, 3}, true}, {{erlang, set_cookie, 2}, true},
     {{erlang, setelement, 3}, false}, {{erlang, size, 1}, false}, {{erlang, spawn, 1}, true}, {{erlang, spawn, 2}, true},
     {{erlang, spawn, 3}, true}, {{erlang, spawn, 4}, true}, {{erlang, spawn_link, 1}, true},
     {{erlang, spawn_link, 2}, true}, {{erlang, spawn_link, 3}, true}, {{erlang, spawn_link, 4}, true},
     {{erlang, spawn_opt, 2}, true}, {{erlang, spawn_opt, 3}, true}, {{erlang, spawn_opt, 4}, true},
     {{erlang, spawn_opt, 5}, true}, {{erlang, aplit_binary, 2}, false}, {{erlang, start_timer, 3}, true},
     {{erlang, statistics, 1}, true}, {{erlang, suspend_process, 1}, false}, {{erlang, system_flag, 2}, true},
     {{erlang, system_info, 1}, true}, {{erlang, system_monitor, 0}, true}, {{erlang, system_monitor, 1}, true},
     {{erlang, system_monitor, 2}, true}, {{erlang, term_to_binary, 1}, false}, {{erlang, term_to_binary, 2}, false},
     {{erlang, throw, 1}, true}, {{erlang, time, 1}, true}, {{erlang, tl, 1}, false}, {{erlang, trace, 1}, true},
     {{erlang, trace_info, 2}, true}, {{erlang, trace_pattern, 2}, true}, {{erlang, trace_pattern, 3}, true},
     {{erlang, trunc, 1}, false}, {{erlang, unregister, 1}, false}, {{erlang, unregister, 1}, true},
     {{erlang, tuple_to_list, 1}, false}, {{erlang, universaltime, 1}, false},
     {{erlang, universaltime_to_localtime, 1}, false}, {{erlang, unlink, 1}, true}, {{erlang, whereis, 1}, true},
     {{erlang, yield, 1}, true}].


%% =====================================================================
%% @spec auto_imported_bifs()->[{atom(), integer()}]
%% @doc The list of automatically imported BIFs.
auto_imported_bifs() ->
    [{abs, 1}, {apply, 2}, {apply, 3}, {atom_to_list, 1}, {binary_to_list, 1},
     {binary_to_list, 3}, {binary_to_term, 1}, {check_process_code, 2},
     {concat_binary, 1}, {data, 3}, {delete_module, 1}, {disconnect_node, 1},
     {element, 2}, {erase, 0}, {erase, 1}, {exit, 1}, {exit, 2}, {float, 1},
     {float_to_list, 1}, {garbage_collect, 1}, {garbage_collect, 0}, {get, 0},
     {get, 1}, {get_keys, 1}, {group_leader, 0}, {group_leader, 2}, {halt, 0},
     {halt, 1}, {hd, 1}, {integer_to_list, 1}, {iolist_to_binary, 1},
     {iolist_size, 1}, {is_atom, 1}, {is_binary, 1}, {is_boolean, 1},
     {is_float, 1}, {is_function, 1}, {is_function, 2}, {is_integer, 1},
     {is_list, 1}, {is_number, 1}, {is_pid, 1}, {is_port, 1},
     {is_process_alive, 1}, {is_record, 2}, {is_record, 3}, {is_reference, 1},
     {is_tuple, 1}, {length, 1}, {link, 1}, {list_to_atom, 1},
     {list_to_binary, 1}, {list_to_existing_atom, 1}, {list_to_float, 1},
     {list_to_integer, 1}, {list_to_pid, 1}, {list_to_tuple, 1},
     {load_module, 2}, {make_ref, 0}, {module_loaded, 1}, {monitor_node, 2},
     {node, 0}, {node, 1}, {nodes, 0}, {nodes, 1}, {now, 0}, {open_port, 2},
     {pid_to_list, 1}, {port_close, 1}, {port_command, 2}, {port_connect, 2},
     {port_control, 3}, {pre_loaded, 0}, {process_flag, 2}, {process_flag, 3},
     {process_info, 1}, {process_info, 2}, {processes, 0}, {purge_module, 1},
     {put, 2}, {register, 2}, {registered, 0}, {round, 1}, {self, 0},
     {setelement, 3}, {size, 1}, {spawn, 1}, {spawn, 2}, {spawn, 3},
     {spawn, 4}, {spawn_link, 1}, {spawn_link, 2}, {spawn_link, 3},
     {spawn_link, 4}, {spawn_opt, 2}, {spawn_opt, 3}, {spawn_opt, 4},
     {spawn_opt, 5}, {aplit_binary, 2}, {statistics, 1}, {term_to_binary, 1},
     {term_to_binary, 2}, {throw, 1}, {time, 1}, {tl, 1}, {trunc, 1},
     {unregister, 1}, {unregister, 1}, {tuple_to_list, 1}, {unlink, 1},
     {whereis, 1}].


%% =====================================================================
%% @spec callback_funs(Behaviour)->[{FunName, Arity}]
%%       Behaviour = gen_server | gen_event | gen_fsm | supervisor
%%       FunName = atom()
%%       Arity = integer()
%% @doc Pre-defined callback functions by the standard Erlang behaviours.
callback_funs(Behaviour) ->
    case Behaviour of
      gen_server ->
	  [{init, 1}, {handle_call, 3}, {handle_cast, 2}, {handle_info, 2},
	   {terminate, 2}, {code_change, 3}];
      gen_event ->
	  [{init, 1}, {handle_event, 2}, {handle_call, 2}, {handle_info, 2},
	   {terminate, 2}, {code_change, 3}];
      gen_fsm ->
	  [{init, 1}, {handle_event, 3}, {handle_sync_event, 4}, {handle_info, 3},
	   {terminate, 3}, {code_change, 4}];
      supervisor -> [{init, 1}];
      _ -> []
    end.


%% =====================================================================
%% functions not used at the moment.
%% collect_var_mod_qualifiers(FileName) ->
%%     case refac_util:parse_annotate_file(FileName, true, []) of
%%       {ok, {AnnAST, Info}} ->
%% 	  {ok, ModName} = get_module_name(Info), collect_var_mod_qualifiers_1(AnnAST, ModName);
%%       {error, _Reason} -> {error, "Error with parsing/annotating file " ++ FileName}
%%     end.

%% collect_var_mod_qualifiers_1(Tree, ModName) ->
%%     F = fun (T, S) ->
%% 		case refac_syntax:type(T) of
%% 		  function ->
%% 		      Arity = refac_syntax:function_arity(T),
%% 		      S ++ contains_var_mod_qualifier(T, ModName, Arity);
%% 		  _ -> S
%% 		end
%% 	end,
%%     refac_syntax_lib:fold(F, [], Tree).

%% contains_var_mod_qualifier(Node, ModName, Arity) ->
%%     FunName = refac_syntax:atom_value(refac_syntax:function_name(Node)),
%%     Clauses = refac_syntax:function_clauses(Node),
%%     F2 = fun (T, S) ->
%% 		 case refac_syntax:type(T) of
%% 		   module_qualifier ->
%% 		       Mod = refac_syntax:module_qualifier_argument(T),
%% 		       case refac_syntax:type(Mod) of
%% 			 variable ->
%% 			     case lists:keysearch(def, 1, refac_syntax:get_ann(Mod)) of
%% 			       {value, {def, _DefinePos}} -> S ++ [{ModName, FunName, Arity}];
%% 			       %% ,refac_syntax:variable_name(Mod), DefinePos}];
%% 			       _ -> S
%% 			     end;
%% 			 atom -> S;
%% 			 _ -> S ++ [{ModName, FunName, Arity}] %%{refac_syntax:atom_value
%% 		       end;
%% 		   _ -> S
%% 		 end
%% 	 end,
%%     F1 = fun (Clause) ->
%% 		 As = refac_syntax:get_ann(Clause),
%% 		 case lists:keysearch(bound, 1, As) of
%% 		   {value, {bound, _BdVars}} -> refac_syntax_lib:fold(F2, [], Clause);
%% 		   _ -> []
%% 		 end
%% 	 end,
%%     lists:flatmap(F1, Clauses).

%% get_module_name(ModInfo) ->
%%     case lists:keysearch(module, 1, ModInfo) of
%%       {value, {module, ModName}} -> {ok, ModName};
%%       false -> {error, "Can not get the current module name."}
%%     end.