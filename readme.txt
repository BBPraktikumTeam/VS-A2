
==================================
||				||
||	   Koordinator		||
||				||
==================================

Start des Koordinators:

	koordinator:start().

% Ab hier wartet der Koordinator auf die GGT-Prozesse

Koordinator in den Bereitmodus setzen:

	Koordinatorname ! work.

% Ab hier wird der Ring aufgebaut

GGT-Berechnung starten:

	Koordinatorname ! start. 	% Beliebiger GGT in Bereich von 1-100
	Koordinatorname ! {start,GGT}.	% Berechnung mit dem Wert GGT starten


Koordinator neustarten:

	Koordinator ! reset. % Alle GGT-Prozesse bekommen kill und der Ring wird "geleert".


Koordinator "töten":
	
	Koordinator ! kill. % Koordinator bekommt kill, sendet kill an alle Prozese und exited sich



==================================
||				||
||	      Starter		||
||				||
==================================

Starten des Starters:

	starter:start(). 	% startet einen Starter
	starter:start(X). 	% starte X Starter.

