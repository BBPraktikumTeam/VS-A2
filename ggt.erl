-module(ggt).
-compile(export_all).
-include("ggt.hrl").

%% %%%%%%%%%%%
% TODO:
% abstimmung in loop inplementen
% Timer für Terminierung
% loop für weiteres empfangen
% Mehrere Berechnungen mit gleichem Ring
% Koordinatorname und Nameservice müssen erst erfragt werden (siehe Starter)
%% %%%%%%%%%%%

%% Mögliche Fehler des Algorithmus
% Stop nach Start: da nur Prozesse starten die nur Nachbarn mit kleineren Zahlen haben -> Stillstand
% Zu frühes Ende:  da Probleme bei der Abstimmung entstehen können -> Abbruch zu früh -> falscher ggt

% Nameservicenode auf lab22
% Kommunikation über Name, Node

start(Vzeit, Tzeit, Startnr, Gruppe, Team, Nameservicenode, Koordinatorname, Starternr) ->
    spawn(fun()->init(Vzeit, Tzeit, Startnr, Gruppe, Team, Nameservicenode, Koordinatorname, Starternr) end).

init(Vzeit, Tzeit, Startnr, Gruppe, Team, Nameservicenode, Koordinatorname, Starternr) -> 
    Name=get_name(Gruppe, Team, Startnr, Starternr),
    file:write_file(lists:concat(["GGTP_",Name,"@",net_adm:localhost(),".log"]),"",[write]),
    register(Name, self()),
    S = #state{nameservicenode = Nameservicenode,koordinatorname = Koordinatorname, name = Name, vzeit = Vzeit, tzeit=Tzeit},
    case get_nameservice(S) of
        {ok,Nameservice} ->
                Nameservice ! {self(),{rebind,Name,node()}},
                log(["Nachricht an Nameservicenode gesendet"],Name),
                receive
                    ok -> log(["Bind done"],Name);
                    kill -> terminate(Name)
                end,
                case get_koordinator(S) of
                    {ok,Koordinator} -> 
                        Koordinator ! {hello, Name},
                        log(["warte auf Nachbarmessage vom Koordinator"], Name),
                        receive
                            {setneighbors,Left,Right} ->    
                                log(["Neighbors set, starting loop"], Name),
                                loop(S = #state{left=Left, right=Right});
                            kill -> terminate(Name)
                        end;
                    {error, Reason} -> 
                        log(["Error: ", Reason], Name),
                        exit(Reason)
                end;
        {error, Reason} ->
             log(["Error: ", Reason], Name),
             exit(Reason)
    end.

    
    
loop(S= #state{mi = Mi, name = Name, lastworked = Lastworked, tzeit = Tzeit, timer = Timer}) -> 
    receive
        {setpm,MiNeu} ->
            Lastworked = get_timestamp(),
            %% New Timer Setzten 
            if (Timer == undefined) ->
                Newtimer = spawn(fun() -> start_abstimmung(S) end);
            true ->
                % timer killen
                exit(Timer, normal),
                Newtimer = spawn(fun() -> start_abstimmung(S) end)
            end,
            %% eventuell auslagern in eigene Loop, da nur zum Starten gebraucht
            log(["Starting with MI: ", MiNeu], Name),
            loop(S#state{mi = MiNeu, lastworked = Lastworked, timer = Newtimer});
        {sendy,Y} ->
            Lastworked = get_timestamp(),
            %% New Timer Setzten 
            if (Timer == undefined) ->
                Newtimer = spawn(fun() -> start_abstimmung(S) end);
                true ->
                % timer killen
                    exit(Timer, normal),
                    Newtimer = spawn(fun() -> start_abstimmung(S) end)
            end,
        % timer starten -> spawn timer
            NewState = calc_ggt(S,Y),
            loop(NewState#state{lastworked = Lastworked, timer = Newtimer});
        {abstimmung,Initiator} ->        
            %% mal gucken
            % Initiator wichtig. Wenn man selber startet, dann self() ansonsten durchreichen. Wenn Nachricht ankommt mit meinem Namen, dann Term senden -> Also abstimmung erfolgreich
            Now = get_timestamp(),
            if Now - Lastworked >= (Tzeit/2) ->
                    case get_right(S) of
                        {ok, Right} -> Right ! {abstimmung,Initiator};
                        {error, Reason} -> log(["ERROR in Abstimmung: ", Reason], Name)
                    end
                
            end,
            loop(S);
        {tellmi,From} ->
            log(["Tellmi to: ", From],Name),
            From ! Mi,
            loop(S);
        kill -> terminate(Name)
    end.  
    
get_timestamp() -> {_,Seconds,_} = erlang:now(), Seconds.


 
calc_ggt(S = #state{vzeit = Vzeit, mi = Mi, left = Left, right = Right, koordinatorname = Koordinatorname, name = Name}, Y) when Y < Mi-> 
    NewMi = ((Mi-1) rem Y) + 1,
    log(["Caculating new MI: ",NewMi," Y: ",Y],Name),
    timer:sleep(Vzeit),
    Left ! {sendy, NewMi},
    Right ! {sendy, NewMi},
    Koordinatorname ! {briefmi, Name},
    S#state{mi = NewMi};
calc_ggt(S,_) -> S.

get_name(A,B,C,D) -> erlang:list_to_atom(lists:concat([A,B,C,D])).

get_nameservice(#state{nameservicenode = Nameservicenode, name = Name}) -> 
    case net_adm:ping(Nameservicenode) of
        pang -> 
            log(["Cannot reach nameservicenode!\n"],Name),
            io:format("Cannot reach nameserivenode!\n"),
            {error,no_nameservicenode};
        pong -> 
        global:sync(),
	    Nameservice = global:whereis_name(nameservice),
        {ok, Nameservice}
    end.

get_koordinator(#state{nameservicenode = Nameservicenode, koordinatorname = Koordinatorname, name = Name}) ->
    get_dienst(Nameservicenode, Koordinatorname, Name).
    
get_right(#state{nameservicenode = Nameservicenode, right = Right, name = Name}) ->
    get_dienst(Nameservicenode, Right, Name).

get_left(#state{nameservicenode = Nameservicenode, left = Left, name = Name}) ->
    get_dienst(Nameservicenode, Left, Name).
    
get_dienst(Nameservicenode, Dienstname, Name) -> 
    case get_nameservice(Nameservicenode) of 
        {ok, Nameservice} ->
            Nameservice ! {self(),{lookup,Dienstname}},
            receive
                not_found ->
                    io:format("Koordinatorname not found.\n"),
                    {error,no_koordinator};
                kill ->
                    terminate(Name);
                Dienst -> 
                    io:format("Found Dienst: ~p.\n",[Dienst]),
                    {ok,Dienst}
            end;
        {error, Reason} ->
            io:format("Nameservice not found.\n"),
            {error,Reason}
    end.        
   
log(Nachricht,Name) ->
    NewNachricht = lists:concat([werkzeug:timeMilliSecond(),"|",Name,": ",lists:concat(Nachricht),io_lib:nl()]),
    werkzeug:logging(lists:concat(["GGTP_",Name,"@",net_adm:localhost(),".log"]), NewNachricht).
    
terminate(Name) -> 
    log("Killed", Name),
    exit(normal).
       
start_abstimmung(S = #state{name = Name, tzeit = Tzeit}) ->
    timer:sleep(Tzeit* 1000),
    case get_right(S) of
        {ok, Right} ->
            Right ! {abstimmung,self()};
        {error, Reason} ->
            log(["Abstimmung Error: ", Reason], Name),
            terminate(Name)
    end.
    
        
    
 
    
