-module(socketio_handler).
-behaviour(cowboy_http_handler).

-include("socketio_internal.hrl").

-export([init/3, handle/2, info/3, terminate/2]).

init({tcp, http}, Req, [Config]) ->
    {PathInfo, _} = cowboy_req:path_info(Req),
    case PathInfo of
        [] ->
            {ok, Req, {create_session, Config}};
        [<<"xhr-polling">>, Sid] ->
            case socketio_session:find(Sid) of
                {ok, Pid} ->
                    case socketio_session:pull(Pid, self()) of
                        session_in_use ->
                            {ok, Req, {session_in_use, Config}};
                        [] ->
                            {loop, Req, {heartbeat, Config}, Config#config.heartbeat, hibernate};
                        Messages ->
                            {ok, Req, {data, Messages, Config}}
                    end;
                {error, not_found} ->
                    {ok, Req, {not_found, Sid, Config}}
            end;
        [<<"xhr-polling">>, Sid, <<"send">>] ->
            case socketio_session:find(Sid) of
                {ok, Pid} ->
                    socketio_session:send(Pid, <<"MESSAGE">>),
                    {ok, Req, {send, Config}};
                {error, not_found} ->
                    {ok, Req, {not_found, Sid, Config}}
            end
    end.

handle(Req, {create_session, Config = #config{heartbeat = Heartbeat,
                                              session_timeout = SessionTimeout,
                                              callback = Callback}}) ->

    error_logger:info_msg("Create session~n", []),
    Sid = uuids:new(),

    HeartbeatBin = list_to_binary(integer_to_list(Heartbeat)),
    SessionTimeoutBin = list_to_binary(integer_to_list(SessionTimeout)),

    _Pid = socketio_session:create(Sid, SessionTimeout, Callback),

    Result = <<":", HeartbeatBin/binary, ":", SessionTimeoutBin/binary, ":xhr-polling">>,
    {ok, Req1} = cowboy_req:reply(200, [], <<Sid/binary, Result/binary>>, Req),
    {ok, Req1, Config};

handle(Req, {data, Messages, Config}) ->
    error_logger:info_msg("Messages ~p~n", [Messages]),
    {ok, Req, Config};

handle(Req, {not_found, Sid, Config}) ->
    error_logger:info_msg("Session ~p not found~n", [Sid]),
    {ok, Req, Config};

handle(Req, {send, Config}) ->
    {ok, Req1} = cowboy_req:reply(200, [], <<>>, Req),
    {ok, Req1, Config};

handle(Req, {session_in_use, Config}) ->
    {ok, Req1} = cowboy_req:reply(404, [], <<>>, Req),
    {ok, Req1, Config};

handle(Req, Config) ->
    {ok, Req1} = cowboy_req:reply(404, [], <<>>, Req),
    {ok, Req1, Config}.

info({message_arrived, Pid}, Req, {heartbeat, Config}) ->
    Messages = socketio_session:poll(Pid),
    error_logger:info_msg("Messages arrived ~p~n", [Messages]),
    {ok, Req, Config};

info(Info, Req, State) ->
    error_logger:info_msg("Skip Info ~p not found~n", [Info]),
    {ok, Req, State}.

terminate(_Req, State) ->
    error_logger:info_msg("terminate ~p~n", [State]),
    ok.
%% ---------------