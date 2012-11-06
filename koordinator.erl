-module(koordinator).
-compile(export_all).

start()-> spawn(fun init/0).

init()->
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
		     
