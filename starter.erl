-module(starter).
-compile(export_all).
-record(state,{koordinatorname,team,gruppe,nameservicenode,starternr}).

start()-> start(1).

start(AnzahlStarter) when AnzahlStarter > 0 -> lists:map(fun(X)->spawn(fun()->init(X) end) end,lists:seq(1,AnzahlStarter)).

init(Starternr)->
    {ok,ConfigListe} = file:consult("ggt.cfg"),
    {ok, Praktikumsgruppe} = werkzeug:get_config_value(praktikumsgruppe,ConfigListe),
    {ok, Teamnummer} = werkzeug:get_config_value(teamnummer, ConfigListe),
    {ok, Nameservicenode} = werkzeug:get_config_value(nameservicenode, ConfigListe),
    {ok, Koordinatorname} = werkzeug:get_config_value(koordinatorname, ConfigListe),
    S=#state{koordinatorname=Koordinatorname,nameservicenode=Nameservicenode,team=Teamnummer,gruppe=Praktikumsgruppe,starternr=Starternr},
    case get_koordinator(S) of
	{ok,Koordinator}->
	    log("Asking Koordinator for steeringval",Starternr),
	    Koordinator ! {getsteeringval,self()},
	    loop_steeringval(S);
	{error,Reason}->
	    log(lists:concat(["Error getting Koordinator: ",Reason]),Starternr),
	    loop_commands(S)
    end.
    
    
loop_steeringval(S=#state{koordinatorname=Koordinatorname,team=Team,gruppe=Gruppe,nameservicenode=Nameservicenode,starternr=Starternr})->    
    receive
	{steeringval,ArbeitsZeit,TermZeit,GGTProzessnummer} ->
	    log(lists:concat(["Starting ",GGTProzessnummer," processes with ",ArbeitsZeit," working delay and ",TermZeit," time to termination"]),Starternr),
	    lists:map(fun(X)-> ggt:start(ArbeitsZeit,TermZeit,X,Gruppe,Team,Nameservicenode,Koordinatorname,Starternr) end, lists:seq(1,GGTProzessnummer));
	kill -> 
	    terminate(S);
        _Any -> 
	    log("Unexpected message",Starternr),
	    loop_steeringval(S)
    end.

loop_commands(S=#state{starternr=Starternr})->
    receive
	askagain -> 
	    case get_koordinator(S) of
		{ok,Koordinator}->
		    log("Asking Koordinator for steeringval",Starternr),
		    Koordinator ! {getsteeringval,self()},
		    loop_steeringval(S);
		{error,Reason}->
		    log(lists:concat(["Error getting Koordinator: ",Reason]),Starternr),
		    log("Expecting new command",Starternr),
		    loop_commands(S)
	    end;
        kill -> 
	    terminate(S);
	_Any ->
	    log("Unexpected Command",Starternr),
	    loop_commands(S)
    end.
			  
get_koordinator(S=#state{koordinatorname=Koordinatorname,nameservicenode=Nameservicenode,starternr=Starternr})->    
    net_adm:ping(Nameservicenode),
    receive
	kill ->
	    terminate(S);
	pang -> 
	    log("Cannot reach nameserivenode!",Starternr),
	    {error,no_nameservicenode};
	pong -> 
	    Nameservice = global:whereis_name(nameservice),
	    Nameservice ! {self(),{lookup,Koordinatorname}},
	    receive
		not_found ->
		    log("Koordinator not found",Starternr),
		    {error,no_koordinator};
		kill ->
		    terminate(S);
		Koordinator -> 
		    log("Found koordinator",Starternr),
		    {ok,Koordinator}
	    end
    end.    


terminate(#state{starternr=Starternr})->
    	    log("Received kill command",Starternr),
	    exit(normal).

log(Message,Starternr)->
    Name = lists:concat(["ggt",Starternr,"@",net_adm:localhost()]),
    NewMessage = lists:concat([Name,werkzeug:timeMilliSecond()," | ",Message,io_lib:nl()]),
    werkzeug:logging(lists:concat([Name,".log"]),NewMessage).
