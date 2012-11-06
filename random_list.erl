-module(random_list).
-export([get_first_n/2,random_ordering/1]).

get_first_n(N,List) when is_integer(N) and is_list(List) ->
    Length = length(List),
    if (N < 1) or (N > Length) -> {error, n_bigger_than_list};
       true -> lists:sublist(random_ordering(List),N)
    end.

random_ordering(List) when is_list(List) ->
    TupleList=lists:map(fun(X)-> {random:uniform(),X} end,List),
    SortedTupleList=lists:keysort(1,TupleList),
    lists:map(fun({_,X})-> X end,SortedTupleList).
		     
    
