-module(ggt).
-compile(export_all).
-import("ggt.hrl").

init(Verzzeit, Termzeit, Startnr, Gruppe, Team, Namensdienst, Koordinator, Starternummer) -> 
    loop(#state{namensdienst = Namesdienst,koordinator = Koordinator, name = {Gruppe, Team, Startnummer, Starternummer}, vzeit = Vzeit, tzeit=Tzeit}).
    
loop(S= #state(Left = left, Right = right, Mi = mi)) -> 
    receive
        {setneighbors,LeftN,RightN} ->
            loop(S#state(left = LeftN, right = RightN));
        {setpm,MiNeu} ->
            loop(S#state(mi = MiNeu));
        {sendy,Y} ->
            NewState = calc_ggt(S,Y),
            loop(NewState);
        {abstimmung,Initiator} ->
            %% mal gucken
        {tellmi,From} ->
            From ! Mi,
            loop(S);
        {kill} -> exit(normal);
    end.  
    
    
calc_ggt(S = #state(VZeit = vzeit, Mi = mi, Left = left, Right = right, Koordiantor = koordinator, Name = name), Y) when Y < Mi -> 
    NewMi = ((Mi-1) rem Y) + 1,
    Left ! {sendy, NewMi},
    Right ! {sendy, NewMi},
    Koordinator ! {briefmi, get_name}
calc_ggt(S,Y) -> S.

get_name({A,B,C,D}) -> lists:concat([A,B,C,D]).
    