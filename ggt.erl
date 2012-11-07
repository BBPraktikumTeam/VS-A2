-module(ggt).
-compile(export_all).
-include("ggt.hrl").

%% %%%%%%%%%%%
% TODO:
% loop für weiteres empfangen
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
                log(["Sende Nachricht an Nameservicenode: ", Nameservicenode], Name),
                Nameservice ! {self(),{rebind,Name,node()}},
                log(["Nachricht an Nameservicenode gesendet"],Name),
                receive
                    ok -> log(["Bind done"],Name);
                    kill -> terminate(Name)
                end,
                case get_koordinator(S) of
                    {ok,Koordinator} -> 
                        log(["Sende Nachricht an Koordinator: ", Koordinatorname], Name),
                        Koordinator ! {hello, Name},
                       log(["warte auf Nachbarmessage vom Koordinator"], Name),
                        receive
                            {setneighbors,Left,Right} ->    
                                log(["Neighbors set. Left: ",Left," Right: ",Right,"|starting loop"], Name),
                                loop(S#state{left=Left, right=Right});
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
            log(["Starting with MI: ", MiNeu], Name),
            Now = get_timestamp(),
            %% New Timer Setzten 
            if  (Timer == undefined) ->ok;
                true ->
                % timer killen
                    log(["Killing old timer in Mi"], Name),
                    exit(Timer, normal)
            end,
            log(["Starting new timer"], Name),
            Self=self(),
            Newtimer = spawn(fun() -> start_abstimmung(Self,Tzeit) end),
            %% eventuell auslagern in eigene Loop, da nur zum Starten gebraucht
            loop(S#state{mi = MiNeu, lastworked = Now, timer = Newtimer});
        {sendy,Y} ->
            log(["Got Y: ", Y],Name),
            Now = get_timestamp(),
            %% New Timer Setzten 
            if (Timer == undefined) ->ok;
                true ->
                % timer killen
                    log(["Killing old timer in Y"], Name),
                    exit(Timer, normal)
            end,
            log(["Starting new timer"], Name),
            Self=self(),
            Newtimer = spawn(fun() -> start_abstimmung(Self,Tzeit) end),
        % timer starten -> spawn timer
            NewState = calc_ggt(S,Y),
            loop(NewState#state{lastworked = Now, timer = Newtimer});
        {abstimmung,Initiator} ->     
			log(["Got Abstimmung"], Name),
            %% mal gucken
            % Initiator wichtig. Wenn man selber startet, dann self() ansonsten durchreichen. Wenn Nachricht ankommt mit meinem Namen, dann Term senden -> Also abstimmung erfolgreich
            if Initiator == self() ->
                log(["Got it from myself"], Name),
				%% Init = Self -> Abstimmung erfogreich
				case get_koordinator(S) of
					{ok,KoordinatorPid} ->
			%% CZeit = werkzeug:timeMillis?!?!??!
						log(["ABSTIMMUNG: Erfolgreich. Sending Mi: ", Mi, " to Koordinator"],Name),
						KoordinatorPid ! {briefterm,{Name,Mi,werkzeug:timeMilliSecond()}};
					{error, ReasonKoordinator} ->
						log(["ERROR: Cannot send Term and Erg Message to Koordinator ", ReasonKoordinator],Name)
				end;
				%% Init != Self also Abstimmung eventuell weiter senden.
				true ->
                    log(["Got it from someone else"], Name),
					Now = get_timestamp(),
                    TimeDiff = Now - Lastworked,
					if TimeDiff >= (Tzeit/2) ->
						%% Hier auch den Timer killen? 
                        log(["TimeDiff of ", TimeDiff, " big enough"],Name),
						case get_right(S) of
							{ok, Right} -> 
								log(["Abstimmung yes, sending to Next One"], Name),
								Right ! {abstimmung,Initiator};
							{error, Reason} -> log(["ERROR in Abstimmung: ", Reason], Name)
						end;
                        true ->
                           log(["TimeDiff of ", TimeDiff, " NOT big enough"],Name)
					end
            end,
            loop(S);
        start_abstimmung ->
            case get_right(S) of
							{ok, Right} -> 
								log(["ABSTIMMUNG start"], Name),
								Right ! {abstimmung,self()};
							{error, Reason} -> log(["ERROR in Abstimmung: ", Reason], Name)
            end,
            loop(S#state{timer = undefined});
        {tellmi,From} ->
            log(["Tellmi to: ", From],Name),
            From ! Mi,
            loop(S);
        kill -> terminate(Name)
    end.  
    
get_timestamp() -> {_,Seconds,_} = erlang:now(), Seconds.


 
calc_ggt(S = #state{vzeit = Vzeit, mi = Mi, name = Name}, Y) when Y < Mi-> 
    NewMi = ((Mi-1) rem Y) + 1,
    log(["Caculating new MI: ",NewMi," Y: ",Y],Name),
    timer:sleep(Vzeit),
	case get_left(S) of
		{ok, LeftPid} ->
			log(["Sending Y: ", NewMi, " to Left"],Name),
			LeftPid ! {sendy, NewMi};
		{error, ReasonLeft} ->
			log(["ERROR: get_left ", ReasonLeft], Name)
	end,
	case get_right(S) of
		{ok, RightPid} ->
			log(["Sending Y: ", NewMi, " to Right"],Name),
			RightPid ! {sendy, NewMi};
		{error, ReasonRight} ->
			log(["ERROR: get_right ", ReasonRight], Name)
	end,
	case get_koordinator(S) of
		{ok,KoordinatorPid} ->
            log(["BriefMi to Koord: ", NewMi], Name),
			KoordinatorPid ! {briefmi, {Name, NewMi, werkzeug:timeMilliSecond()}};
		{error,ReasonKoord} -> 
			log(["ERROR: get_koordinator ", ReasonKoord], Name)
	end,
    S#state{mi = NewMi};
calc_ggt(S = #state{name = Name, mi = Mi},Y) -> 
    log(["New Y: " ,Y, " >= Mi: ", Mi], Name),
    S.

get_name(A,B,C,D) -> erlang:list_to_atom(lists:concat([A,B,C,D])).

get_nameservice(#state{nameservicenode = Nameservicenode, name = Name}) -> 
    case net_adm:ping(Nameservicenode) of
        pang -> 
            log(["ERROR: Cannot reach nameservicenode: ", Nameservicenode],Name),
            {error,no_nameservicenode};
        pong -> 
        global:sync(),
	    Nameservice = global:whereis_name(nameservice),
        log(["Got Nameservice: ", Nameservicenode], Name),
        {ok, Nameservice}
    end.

get_koordinator(S = #state{koordinatorname = Koordinatorname, name = Name}) ->
    log(["Get Koordinator -> Get Dienst"], Name),
    get_dienst(S, Koordinatorname).
    
get_right(S = #state{right = Right}) ->
    get_dienst(S, Right).

get_left(S = #state{left = Left}) ->
    get_dienst(S, Left).
    
get_dienst(S = #state{nameservicenode = Nameservicenode, name = Name}, Dienstname) -> 
    log(["Trying to get Nameservice: ", Nameservicenode],Name),
    case get_nameservice(S) of 
        {ok, Nameservice} ->
            log(["Got Nameservice, trying to contact it for: ", Dienstname], Name),
            Nameservice ! {self(),{lookup,Dienstname}},
            receive
                Dienst={NameOfService,Node} when is_atom(NameOfService) and is_atom(Node) -> 
                    log([Dienstname," found, Name: ", NameOfService, " Node: ",Node], Name),
                    {ok,Dienst};
                not_found ->
                    log(["ERROR: ",Dienstname," not found"], Name),
                    {error,no_koordinator};
                kill ->
                    terminate(Name)
                
           %     _Any ->
            %        log(["Nameservice send CRAP"],Name),
           %         {error,nameservice_crap}
            end;
        {error, Reason} ->
            log(["ERROR Nameservice: ", Nameservicenode, " not found"], name),
            {error,Reason}
    end.        
   
log(Nachricht,Name) ->
    NewNachricht = lists:concat([werkzeug:timeMilliSecond(),Name,": ",lists:concat(Nachricht),io_lib:nl()]),
    werkzeug:logging(lists:concat(["GGTP_",Name,"@",net_adm:localhost(),".log"]), NewNachricht).
    
terminate(Name) -> 
    log(["Killed"], Name),
    exit(normal).
       
start_abstimmung(GGT, Tzeit) ->
    timer:sleep(Tzeit* 1000),
 %   case get_dienst(S, Name) of
 %       {ok, Self} ->
            GGT ! start_abstimmung.
 %       {error, Reason} ->
%            log(["Abstimmung Error: ", Reason], Name),
%            terminate(Name)
%    end.
    
        
    
 
    
