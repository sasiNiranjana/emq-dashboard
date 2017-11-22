%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 EMQ Enterprise, Inc. (http://emqtt.io).
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_dashboard).

-import(proplists, [get_value/2]).

-export([start_listeners/0, stop_listeners/0, listeners/0]).

-export([http_handlers/0, handle_request/3]).

-define(APP, ?MODULE).

%%--------------------------------------------------------------------
%% Start/Stop listeners.
%%--------------------------------------------------------------------

start_listeners() ->
    lists:foreach(fun(Listener) -> start_listener(Listener) end, listeners()).

%% Start HTTP Listener
start_listener({Proto, Port, Options}) when Proto == http; Proto == https ->
    minirest:start_http(listener_name(Proto), Port, Options, http_handlers()).

stop_listeners() ->
    lists:foreach(fun(Listener) -> stop_listener(Listener) end, listeners()).

stop_listener({Proto, Port, _}) ->
    minirest:stop_http(listener_name(Proto), Port).

listeners() ->
    application:get_env(?APP, listeners, []).

listener_name(Proto) ->
    list_to_atom("dashboard:" ++ atom_to_list(Proto)).

%%--------------------------------------------------------------------
%% HTTP Handlers and Dispatcher
%%--------------------------------------------------------------------

http_handlers() ->
    ApiProviders = application:get_env(?APP, api_providers, []),
    [{"/api/v2/", minirest:handler(#{apps => ApiProviders}),
      [{authorization, fun is_authorized/1}]},
     {"/", {?MODULE, handle_request, [docroot()]}}].

handle_request(Path, Req, DocRoot) ->
    handle_request(Req:get(method), Path, Req, DocRoot).

handle_request('GET', "/" ++ Path, Req, DocRoot) ->
    mochiweb_request:serve_file(Path, DocRoot, Req);

handle_request(_Method, _Path, Req, _DocRoot) ->
    Req:not_found().

docroot() ->
    {file, Here} = code:is_loaded(?MODULE),
    Dir = filename:dirname(filename:dirname(Here)),
    filename:join([Dir, "priv", "www"]).

%%--------------------------------------------------------------------
%% Basic Authorization
%%--------------------------------------------------------------------

is_authorized(Req) ->
    is_authorized(Req:get(path), Req).

is_authorized("/api/v2/auth" ++ _, _Req) ->
    true;
is_authorized(_Path, Req) ->
    case Req:get_header_value("Authorization") of
        "Basic " ++ BasicAuth ->
            {Username, Password} = user_passwd(BasicAuth),
            case emqx_dashboard_admin:check(iolist_to_binary(Username),
                                            iolist_to_binary(Password)) of
                ok -> true;
                {error, Reason} ->
                    lager:error("Dashboard Authorization Failure: username=~s, reason=~p",
                                [Username, Reason]),
                    false
            end;
         _  -> false
    end.

user_passwd(BasicAuth) ->
    list_to_tuple(binary:split(base64:decode(BasicAuth), <<":">>)).

