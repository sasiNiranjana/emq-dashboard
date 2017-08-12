%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
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

-module (emq_dashboard_config).

-export ([register/0, unregister/0]).

-define(APP, emq_dashboard).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
register() ->
    clique_config:load_schema([code:priv_dir(?APP)], ?APP),
    register_formatter(),
    register_config().

unregister() ->
    unregister_config(),
    unregister_formatter(),
    clique_config:unload_schema(?APP).

%%--------------------------------------------------------------------
%% Get ENV Register formatter
%%--------------------------------------------------------------------
register_formatter() ->
    [clique:register_formatter(cuttlefish_variable:tokenize(Key), 
     fun formatter_callback/2) || Key <- keys()].
formatter_callback([_, _, Key], Params) ->
    proplists:get_value(port, Params);
formatter_callback([_, _, _, Key], Params) ->
    proplists:get_value(list_to_atom(Key), proplists:get_value(opts, Params)).

%%--------------------------------------------------------------------
%% UnRegister formatter
%%--------------------------------------------------------------------
unregister_formatter() ->
    [clique:unregister_formatter(cuttlefish_variable:tokenize(Key)) || Key <- keys()].

%%--------------------------------------------------------------------
%% Set ENV Register Config
%%--------------------------------------------------------------------
register_config() ->
    Keys = keys(),
    [clique:register_config(Key , fun config_callback/2) || Key <- Keys],
    clique:register_config_whitelist(Keys, ?APP).

config_callback([_, _, _], Value) ->
    {ok, Env} = application:get_env(?APP, listeners),
    application:set_env(?APP, listeners, lists:keyreplace(port, 1, Env, {port, Value})),
    " successfully\n";
config_callback([_, _, _, Key0], Value) ->
    {ok, Env} = application:get_env(?APP, listeners),
    Env2 = proplists:get_value(opts, Env),
    Key = list_to_atom(Key0),
    Env3 = lists:keyreplace(Key, 1, Env2, {Key, Value}),
    application:set_env(?APP, listeners, lists:keyreplace(opts, 1, Env, {opts, Env3})),
    " successfully\n".

%%--------------------------------------------------------------------
%% UnRegister config
%%--------------------------------------------------------------------
unregister_config() ->
    Keys = keys(),
    [clique:unregister_config(Key) || Key <- Keys],
    clique:unregister_config_whitelist(Keys, ?APP).

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------
keys() ->
    ["dashboard.listener.http",
     "dashboard.listener.http.acceptors",
     "dashboard.listener.http.max_clients"].