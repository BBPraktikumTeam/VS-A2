-module(koordinator).
-compile(export_all).
-record(state,(processes,arbeitszeit,termzeit,ggtprozessnummer,nameservicenode,koordinatorname)).

start()-> spawn(fun init/0).

init()->
    {ok,ConfigListe} = file:consult("ggt.cfg"),
    {ok,Arbeitszeit} = werkzeug:get_config_value(arbeitszeit,ConfigListe),
    {ok,Termzeit} = werkzeug:get_config_value(termzeit,ConfigListe),
    {ok,GGTProzessnummer} = werkzeug:get_config_value(ggtprozessnummer,ConfigListe),
    {ok,Nameservicenode} = werkzeug:get_config_value(nameservicenode,ConfigListe),
    {ok,Koordinatorname} = werkzeug:get_config_value(koordinatorname,ConfigListe),
    S=#state{processes=[],arbeitszeit=Arbeitszeit,termzeit=Termzeit,ggtprozessnummer=GGTProzessnummer,nameservicenode=Nameservicenode,koordinatorname=Koordinatorname},
    register(Koordinatorname,self()),
    case get_nameservice(Nameservicenode) of
	{ok,Nameservice} ->
                Nameservice ! {self(),{rebind,Koordinatorname,node()}},
                log(["Nachricht an Nameservicenode gesendet"],Name);
	{error,Reason} -> terminate()
    end,
    initial(S).

initial(S=#state{processes=Processes})->
    receive
	{getsteeringval,Starter}-> initial(S);
	{hello,Clientname} -> initial(S);
	reset -> 
	    kill_all(Processes),
	    initial(S);
	work -> prepare_ready(S);
	kill -> 
	    kill_all(Processes),
	    terminate().
    end.

prepare_ready(S=#state)->
    lists:map(fun(X,{Left,Right})-> send_message(X,{setneighbors,Left,Right},Nameservicenode) end, circular_list:get_neighbors_list(Processes)),
    ready(S).

ready(S)->
    receive
	
    end.

send_message(Name,Message,Nameservicenode)->
    case get_nameservice(Nameservicenode) of
	{error,Reason} ->
	    log(lists:concat(["Cannot send message to ",Name," because of ",Reason]));
	{ok,Nameservice} ->
    end.

get_nameservice(Nameservicenode) -> 
    case net_adm:ping(Nameservicenode) of
        pang -> 
            log(["Cannot reach nameservicenode!\n"]),
            {error,no_nameservicenode};
        pong -> 
	    global:sync(),
	    Nameservice = global:whereis_name(nameservice),
	    {ok, Nameservice}
    end.

kill_all(Processes) when is_list(Processes)->
    lists:map(fun(X)-> kill_service(X) end, Processes).

kill_service(X)->
    .

log(Message)->
    Name = lists:concat(["Koordinator@",net_adm:localhost()]),
    NewMessage = lists:concat([Name,werkzeug:timeMilliSecond()," ",Message,io_lib:nl()]),
    werkzeug:logging(lists:concat([Name,".log"]),NewMessage).

stub()->
    register(chef,self()),
    case net_adm:ping('nameservice@klaus-MM061') of
	pong -> 
	    global:sync(),
	    Nameservice = global:whereis_name(nameservice),
	    Nameservice ! {self(),{rebind,chef,node()}},
	    receive
		ok -> io:format("Service bound successfully\n");
		_Any -> {error_received_something_else}
	    end;
	pang -> {error,cannot_reach_nameservice}
    end.

terminate()->
    log("Received kill command"),
    exit(killed).
