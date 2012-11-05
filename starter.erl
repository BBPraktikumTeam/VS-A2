-module(starter).
-compile(export_all).
-record(state,{koordinatorname,team,gruppe,nameservicenode}).

%% %%%%%%%%%%%%%%%%%
% TODO:
% Logger einbauen
% wie bekommt der Starter ne eindeutige Nummer?
%% %%%%%%%%%%%%%%%%%

start()-> spawn(fun init/0).

init()->
    {ok,ConfigListe} = file:consult("ggt.cfg"),
    {ok, Praktikumsgruppe} = werkzeug:get_config_value(praktikumsgruppe,ConfigListe),
    {ok, Teamnummer} = werkzeug:get_config_value(teamnummer, ConfigListe),
    {ok, Nameservicenode} = werkzeug:get_config_value(nameservicenode, ConfigListe),
    {ok, Koordinatorname} = werkzeug:get_config_value(koordinatorname, ConfigListe),
    S=#state{koordinatorname=Koordinatorname,nameservicenode=Nameservicenode,team=Teamnummer,gruppe=Praktikumsgruppe},
    case get_koordinator(S) of
	{ok,Koordinator}->
	    Koordinator ! {getsteeringval,self()},
	    loop_steeringval(S);
	{error,Reason}->
	    io:format("Error getting Koordinator: ~p\nExpecting new command\n",[Reason]),
	    loop_commands(S)
    end.
    
    
loop_steeringval(S=#state{koordinatorname=Koordinatorname,team=Team,gruppe=Gruppe,nameservicenode=Nameservicenode})->    
    receive
	{steeringval,ArbeitsZeit,TermZeit,GGTProzessnummer} ->
	    lists:map(fun(X)-> ggt:start(ArbeitsZeit,TermZeit,X,Gruppe,Team,Nameservicenode,Koordinatorname,1) end, lists:seq(1,GGTProzessnummer));
	kill -> 
	    io:format("Received kill command\n"),
	    exit(normal);
        Any -> 
	    io:format("Not expecting: ~p\n",[Any]),
	    loop_steeringval(S)
    end.

loop_commands(S)->
    receive
	askagain -> 
	    case get_koordinator(S) of
		{ok,Koordinator}->
		    Koordinator ! {getsteeringval,self()},
		    loop_steeringval(S);
		{error,Reason}->
		    io:format("Error getting Koordinator: ~p\nExpecting new command\n",[Reason]),
		    loop_commands(S)
	    end;
        kill -> 
	    terminate();
	Any ->
	    io:format("Not expecting: ~p\n",[Any]),
	    loop_commands(S)
    end.
			  
get_koordinator(#state{koordinatorname=Koordinatorname,nameservicenode=Nameservicenode})->    
    net_adm:ping(Nameservicenode),
    receive
	kill ->
	    terminate();
	pang -> 
	    io:format("Cannot reach nameserivenode!\n"),
	    {error,no_nameservicenode};
	pong -> 
	    Nameservice = global:whereis_name(nameservice),
	    Nameservice ! {self(),{lookup,Koordinatorname}},
	    receive
		not_found ->
		    io:format("Koordinator not found.\n"),
		    {error,no_koordinator};
		kill ->
		    terminate();
		Koordinator -> 
		    io:format("Found koordinator: ~p.\n",[Koordinator]),
		    {ok,Koordinator}
	    end
    end.    
    
terminate()->
    	    io:format("Received kill command\n"),
	    exit(normal).
