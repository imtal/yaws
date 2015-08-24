%%%-------------------------------------------------------------------
%%% File    : xattr.erl
%%% Created : 25 Feb 2014
%%% Purpose : use exentended attributes of a Linux/OSX filesystem
%%%           this module needs the xattr_drv.so driver
%%%           only the user namespace is used (by adding the "user." prefix)
%%%
%%%-------------------------------------------------------------------
-module(xattr).
-behaviour(gen_server).

-compile(export_all).

%%--------------------------------------------------------------------
%% External exports
-export([start/0,start_link/0,stop/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% API
%
% get(File,Name) -> {ok,Value}|{error,Reason}
% set(File,Name,Value) -> ok|{error,Reason}
% remove(File,Name) -> ok|{error,Reason}
% list(File) -> {ok,Names}|{error,Reason}
%
-export([get/2,set/3,remove/2,list/1]).


-ifdef(debug).
-define(DEBUG(X), io:format(X)).
-define(DEBUG(X,Y), io:format(X,Y)).
-else.
-define(DEBUG(X), true).
-define(DEBUG(X,Y), true).
-endif.


%%====================================================================
%% External functions
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link/0
%% Description: Starts the server
%%--------------------------------------------------------------------
start() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
stop() ->
    gen_server:call(?MODULE,stop).


set(Filename,Name,Value) when is_atom(Name) ->
    set(Filename,atom_to_list(Name),Value);
set(Filename,Name,Value) ->
    gen_server:call(?MODULE,{set,Filename,Name,Value}).
get(Filename,Name) when is_atom(Name) ->
    get(Filename,atom_to_list(Name));
get(Filename,Name) ->
    gen_server:call(?MODULE,{get,Filename,Name}).
remove(Filename,Name) ->
    gen_server:call(?MODULE,{remove,Filename,Name}).
list(Filename) ->
    gen_server:call(?MODULE,{list,Filename}).

%%====================================================================
%% Server functions
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%%--------------------------------------------------------------------

init([]) ->
    Path0 = code:which(?MODULE),
    Path1 = filename:dirname(Path0),
    Path2 = filename:join([Path1,"..","priv","lib"]),
    case erl_ddll:load_driver(Path2, "xattr_drv") of
        ok ->
            Port = open_port({spawn, "xattr_drv"}, []),
            {ok,Port};
        {error, already_loaded} ->
            ignore;
        {error,Message} ->
            {stop,erl_ddll:format_error(Message)}
    end.


%%--------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------
handle_call(stop, _From, Port) ->
    {stop, stopped, Port};
handle_call(Msg, _From, Port) ->
    Port ! {self(), {command, encode(Msg)}},
    receive
        {Port, {data, Data}} -> {reply,decode(Data), Port}
    end.

%%--------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------
handle_info({'EXIT', Port, _}, Port) ->
    error_logger:format("xattr port driver died \n",[]),
    {stop, stopped, Port}.

%%--------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
-define(SET,1).
-define(GET,2).
-define(REMOVE,3).
-define(LIST,4).

encode({set,Filename,Name,Value}) ->
    lists:flatten([?SET,Filename,0,"user.",Name,0,Value,0]);
encode({get,Filename,Name}) ->
    lists:flatten([?GET,Filename,0,"user.",Name,0]);
encode({remove,Filename,Name}) ->
    lists:flatten([?REMOVE,Filename,0,"user.",Name,0]);
encode({list,Filename}) ->
    lists:flatten([?LIST,Filename,0]).


decode([0]) ->
    ok;
decode([0,?GET|Rest]) ->
    {ok,lists:sublist(Rest,length(Rest)-1)}; % drop last null character
decode([0,?LIST|Rest]) ->
    Fun = fun(Term,Acc) ->
              case Term of
                  "user."++Name -> [Name|Acc];
                  _Oher -> Acc
              end
          end,
    List = lists:foldl(Fun, [], string:tokens(Rest,[0]) ),
    {ok,List};
decode([2]) ->
    {error,enoent};
decode([61]) ->
    {error,enodata};
decode([95]) ->
    {error,enotsup};
decode(E) ->
    {error,E}.
