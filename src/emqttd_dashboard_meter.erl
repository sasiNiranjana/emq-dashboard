%%-------------------------------------------------------------------------
%% Copyright (c) 2012-2016 Feng Lee <feng@emqtt.io>.
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
%%-------------------------------------------------------------------------
-module(emqttd_dashboard_meter).

-include("emqttd_dashboard_meter.hrl").
-include_lib("stdlib/include/qlc.hrl").

-behaviour(gen_server).

-define(SERVER, ?MODULE).
-define(INTERVAL, 10 * 1000).
-define(Suffix, ".dets").

-record(meter_state, {interval = ?INTERVAL}).

-http_api({"m_chart", m_chart, [{"minutes", int, 60}]}).

%% gen_server Function Exports
-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        code_change/3,
        terminate/2]).
%% API Function Exports
-export([start_link/0,
         get_report/2,
         m_chart/1,
         collect_interval/0]).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

get_report(Metric, Minutes) ->
    get_metrics(Metric, Minutes).

m_chart(Minutes) ->
    {ok, get_report(all, Minutes)}.

collect_interval() ->
    gen_server:call(?SERVER, collect_interval).

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init([]) ->
    lists:foreach(fun create_table/1, ?METRICS),
    {ok, MState} =
    case application:get_env(emqttd_dashboard, interval) of
        {ok, Interval} ->
            {ok, #meter_state{interval = Interval}};
        undefined ->
            {ok, #meter_state{}}
    end,
    erlang:send_after(MState#meter_state.interval, self(), collect_meter),
    {ok, MState}.

handle_call(collect_interval, _From, State) ->
    {reply, State#meter_state.interval, State};

handle_call(Req, _From, State) ->
    Reply = Req,
    {reply, Reply, State}.

handle_cast(Info, State) ->
    lager:info("unexpectd info ~p", [Info]),
    {noreply, State}.

handle_info(collect_meter,
            #meter_state{interval = Interval} = State) ->
    save(emqttd_metrics:all()),
    erlang:send_after(Interval, self(), collect_meter),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    close_table().

%% ====================================================================
%% Internal functions
%% ====================================================================
create_table(Tab) ->
    Path = filename:join([code:root_dir(), "data", "metrics"]),
    case file:make_dir(Path) of
        ok -> ok;
        {error, eexist} -> ignore
    end,
    FileName = filename_replace(atom_to_list(Tab)),
    File = filename:join(Path, FileName),
    case dets:open_file(Tab, [{file, File}]) of
        {ok, Tab} -> ok;
        {error, _Reason} -> exit(edestOpen)
    end.

close_table() ->
    CloseTab = fun(Tab) -> dets:close(Tab) end,
    lists:foreach(CloseTab, ?METRICS).

filename_replace(Src) when is_list(Src) ->
    Des = re:replace(Src, "/", "_", [global, {return, list}]),
    Des ++ ?Suffix.

save(Data) ->
    Ts = timestamp(),
    Fun = 
    fun(Metric) ->
        case proplists:get_value(Metric, Data) of
            undefined -> ignore;
            Value     ->
                dets:insert(Metric, {Ts, Value})
        end
    end,
    lists:foreach(Fun, ?METRICS).

timestamp() ->
    {MegaSecs, Secs, _MicroSecs} = os:timestamp(),
    MegaSecs * 1000000 + Secs.

get_metrics(all, Minutes) ->
    get_metrics(?METRICS, Minutes);

get_metrics(Metric, Minutes) when is_atom(Metric) ->
    TotalNum = dets:info(Metric, size),
    Qh = qlc:sort(dets:table(Metric)),
    %Qh = qlc:q([R || R <- dets:table(Metric)]),
    Start = timestamp() - (Minutes * 60),
    Limit = (Minutes * 60 * 1000) div collect_interval(),
    Cursor = qlc:cursor(Qh),
    case TotalNum > Limit of
        true  -> qlc:next_answers(Cursor, TotalNum - Limit);
        false -> ignore
    end,
    Rows = 
    case TotalNum >= 1 of
        true  -> qlc:next_answers(Cursor, TotalNum);
        false -> []
    end,
    qlc:delete_cursor(Cursor),
    L = [[{x, Ts}, {y, V}] || {Ts, V} <- Rows, Ts >= Start],
    {Metric, L};

get_metrics(Metrics, Minutes) when is_list(Metrics) ->
    [get_metrics(M, Minutes) || M <- Metrics].

