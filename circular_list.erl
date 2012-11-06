-module(circular_list).
-export([get_neighbors_list/1]).

get_neighbors_list(List) when is_list(List) ->
    Length = length(List),
    if Length < 2 -> {error, list_to_small};
       true -> ListWithIndex=lists:zip(lists:seq(1,length(List)),List),
	       lists:map(fun({N,Element})-> {Element,get_neighbors(N,List)} end,ListWithIndex)
    end.

get_neighbors(N,List) when is_integer(N) and is_list(List) ->
    Length=length(List),
    if N ==1 -> {lists:nth(Length,List),lists:nth(N+1,List)};
       N == Length -> {lists:nth(N-1,List),lists:nth(1,List)};
       true -> {lists:nth(N-1,List),lists:nth(N+1,List)}
    end.

		      
