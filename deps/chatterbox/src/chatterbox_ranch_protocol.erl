-module(chatterbox_ranch_protocol).

%% While it implements the behaviour, uncommenting the line below
%% would fail to compile unless I make ranch a dependency of
%% chatterbox, which I don't plan on

%%-behaviour(ranch_protocol).

-export([
         start_link/3,
         init/3
        ]).

start_link(Ref, Transport, Opts) ->
    Pid = proc_lib:spawn_link(?MODULE, init, [Ref, Transport, Opts]),
    {ok, Pid}.

init(Ref, Transport, Opts) ->
    {ok, Socket} = ranch:handshake(Ref),
    Http2Settings = proplists:get_value(http2_settings, Opts, chatterbox:settings(server)),
    h2_connection:become({transport(Transport), Socket}, Http2Settings).

transport(ranch_ssl) ->
    ssl;
transport(ranch_tcp) ->
    gen_tcp;
transport(tcp) ->
    gen_tcp;
transport(gen_tcp) ->
    gen_tcp;
transport(ssl) ->
    ssl;
transport(_Other) ->
    error(unknown_protocol).
