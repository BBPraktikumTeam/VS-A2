-module(koordinator).
-compile(export_all).
-record(state,{processes,arbeitszeit,termzeit,ggtprozessnummer,nameservicenode,koordinatorname}).

%%==================
%% Start up
%%==================
start()-> spawn(fun init/0).

init()->
    {ok,ConfigListe} = file:consult("koordinator.cfg"),
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
                log("Nachricht an Nameservicenode gesendet");
	{error,Reason} -> 
	    log(lists:concat(["Cannot reach nameservicenode because of ",Reason,". Therefore, shutting down"])),
	    terminate()
    end,
    initial(S).

%%================
%% LOOPS
%%================
initial(S=#state{processes=Processes,arbeitszeit=Arbeitszeit,termzeit=Termzeit,ggtprozessnummer=GGTProzessnummer})->
    receive
	{getsteeringval,Starter}-> 
	    Starter ! {steeringval,Arbeitszeit,Termzeit,GGTProzessnummer},
	    initial(S);
	{hello,Clientname} ->
	    case lists:member(Clientname,Processes) of
		true ->    
		    initial(S);
		false ->
		    initial(S#state{processes=[Clientname|Processes]})
	    end;
	reset -> 
	    kill_all(S),
	    initial(S#state{processes=[]});
	work -> prepare_ready(S);
	kill -> 
	    kill_all(S),
	    terminate()
    end.
%
% transition to ready loop
%
prepare_ready(S=#state{processes=Processes})->
    RandomProcesses=random_list:random_ordering(Processes),
    log("Setting neighbors for GGT processes"),
    lists:map(fun({X,{Left,Right}})-> send_message(X,{setneighbors,Left,Right},S) end, circular_list:get_neighbors_list(RandomProcesses)),
    ready(S#state{processes=RandomProcesses}).

ready(S)->
    receive
	{briefmi,{Clientname,CMi,CZeit}} ->
	    log(lists:concat([Clientname," calculated new Mi ",CMi," at ",CZeit])),
	    ready(S);
	{briefterm,{Clientname,CMi,CZeit}} ->
	    log(lists:concat([Clientname," terminated with Mi ",CMi," at ",CZeit])),
	    ready(S);
	{start,GGT} ->
	    start_ggt_process(GGT,S),
	    ready(S);
	reset ->
	    kill_all(S),
	    initial(S#state{processes=[]});
	kill ->
	    kill_all(S),
	    terminate()
    end.

%%===================================
%% Starting ggt processes
%%===================================
start_ggt_process(GGT,S=#state{processes=Processes})->
    ProcessesWithValue=lists:map(fun(X)->{X,calc_start_value(GGT)} end,Processes),
    log(lists:concat(["Sending initial Mi to all ",length(Processes)," processes"])),
    lists:map(fun({Process,StartValue})->
		      log(lists:concat(["Setting initial Mi of ",StartValue," for process ",Process])),
		      send_message(Process,{setpm,StartValue},S) 
	      end,ProcessesWithValue),
    N=number_of_processes_to_start(Processes),
    ProcessesToStart=random_list:get_first_n(N,Processes),
    log(lists:concat(["Starting ",N," processes"])),
    ProcessesWithY=lists:map(fun(X)->{X,calc_start_value(GGT)} end,ProcessesToStart),
    lists:map(fun({Process,Y})->
		      log(lists:concat(["Sending initial y of ",Y," to process ",Process])),
		      send_message(Process,{sendy,Y},S)
	      end,ProcessesWithY).
		      
number_of_processes_to_start(Processes) when is_list(Processes)->
    case round(length(Processes)*15/100) of
	N  when N < 2 -> 2;
	N -> N
    end.

calc_start_value(GGT)->
    round(GGT* math:pow(3,random_no())*math:pow(5,random_no())* math:pow(11,random_no())* math:pow(13,random_no())* math:pow(23,random_no())* math:pow(37,random_no())).

random_no()->
    random:uniform(3)-1.

%%===================================
%% Helper functions for communication
%%===================================

send_message(Name,Message,S)->
    case get_service(Name,S) of
	Error={error,Reason} ->
	    log(lists:concat(["Cannot send message to ",Name," because of ",Reason])),
	    Error;
	{ok,Service} ->
	    log(lists:concat(["Sending message to ",Name])),
	    Service ! Message
    end.

get_service(Name,S=#state{nameservicenode=Nameservicenode})->
    case get_nameservice(Nameservicenode) of
	Error={error,Reason}->
	    log(lists:concat(["Cannot get service ",Name," because of ",Reason])),
	    Error;
	{ok,Nameservice} ->
	    Nameservice ! {self(),{lookup,Name}},
	    receive
		not_found ->
		    log(lists:concat(["Cannot find ",Name])),
		    {error,service_not_found};
		kill ->
		    kill_all(S),
		    terminate();
		Service={_,_} -> 
		    {ok,Service}
	    end
    end.

get_nameservice(Nameservicenode) -> 
    case net_adm:ping(Nameservicenode) of
        pang -> 
            log(["Cannot reach nameservicenode!"]),
            {error,no_nameservicenode};
        pong -> 
	    global:sync(),
	    Nameservice = global:whereis_name(nameservice),
	    {ok, Nameservice}
    end.


%%========================
%% Killer functions
%%========================

kill_all(S=#state{processes=Processes}) when is_list(Processes)->
    log("Killing all processes"),
    lists:map(fun(X)-> kill_service(X,S) end, Processes).

kill_service(X,S)->
    send_message(X,kill,S).

terminate()->
    log("Received kill command"),
    exit(killed).


%%=========================
%% Logging
%%=========================
log(Message)->
    Name = lists:concat(["Koordinator@",net_adm:localhost()]),
    NewMessage = lists:concat([Name,werkzeug:timeMilliSecond()," ",Message,io_lib:nl()]),
    werkzeug:logging(lists:concat([Name,".log"]),NewMessage).


%%=========================
%% Debugging
%%=========================
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

