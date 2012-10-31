-module(ggt).
-compile(export_all).
-include("ggt.hrl").

%% %%%%%%%%%%%
% TODO:
% abstimmung in loop inplementen
%% %%%%%%%%%%%


init(Vzeit, Tzeit, Startnr, Gruppe, Team, Namensdienst, Koordinator, Starternr) -> 
    Name=get_name(Gruppe, Team, Startnr, Starternr),
    file:write_file(lists:concat(["GGTP_",Name,"@",net_adm:localhost(),".log"]),"",[write]),
    register(Name, self()),
    Namensdienst ! {self(),{rebind,Name,node()}},
    log(["Nachricht an Namensdienst gesendet"],Name),
    receive
        ok -> log(["Bind done"],Name)
    end,
    Koordinator ! {hello, Name},
    log(["warte auf Nachbarmessage vom Koordinator"], Name),
    receive
        {setneighbors,Left,Right} ->    
            log(["Neighbors set, starting loop"], Name),
            loop(#state{left=Left, right=Right, namensdienst = Namensdienst,koordinator = Koordinator, name = Name, vzeit = Vzeit, tzeit=Tzeit});
        kill -> exit(normal)
    end.
    
loop(S= #state{mi = Mi, name = Name}) -> 
    receive
        {setpm,MiNeu} ->
            %% eventuell auslagern in eigene Loop, da nur zum Starten gebraucht
            log(["Starting with MI: ", MiNeu], Name),
            loop(S#state{mi = MiNeu});
        {sendy,Y} ->
            NewState = calc_ggt(S,Y),
            loop(NewState);
        {abstimmung,Initiator} ->        
            %% mal gucken
            loop(S);
        {tellmi,From} ->
            log(["Tellmi to: ", From],Name),
            From ! Mi,
            loop(S);
        kill -> exit(normal)
    end.  
    
    
calc_ggt(S = #state{vzeit = Vzeit, mi = Mi, left = Left, right = Right, koordinator = Koordinator, name = Name}, Y) when Y < Mi-> 
    NewMi = ((Mi-1) rem Y) + 1,
    log(["Caculating new MI: ",NewMi," Y: ",Y],Name),
    timer:sleep(Vzeit),
    Left ! {sendy, NewMi},
    Right ! {sendy, NewMi},
    Koordinator ! {briefmi, Name},
    S#state{mi = NewMi};
calc_ggt(S,_) -> S.

get_name(A,B,C,D) -> erlang:list_to_atom(lists:concat([p,A,B,C,D])).
   
log(Nachricht,Name) ->
    NewNachricht = lists:concat([werkzeug:timeMilliSecond(),"|",Name,": ",lists:concat(Nachricht),io_lib:nl()]),
    werkzeug:logging(lists:concat(["GGTP_",Name,"@",net_adm:localhost(),".log"]), NewNachricht).