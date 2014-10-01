-module(jsg_links).

-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_dynamic_cluster.hrl").

-compile(export_all).


%%-define(debug,true).

-ifdef(debug).
-define(LOG(X,Y),
	io:format("{~p,~p}: ~s~n", [?MODULE,?LINE,io_lib:format(X,Y)])).
-else.
-define(LOG(X,Y),true).
-endif.


%% Given a set of file corresponding to JSON schemas,
%% traverse the schemas to find (non-relative) link definitions.

compute_uri(Link={link,LinkData}) ->
  L = proplists:get_value(link,LinkData),
  Href = jsg_jsonschema:propertyValue(L,"href"),
  Template = uri_template:parse(binary_to_list(Href)),
  Variables = 
    case proplists:get_value(object,LinkData) of
      undefined ->
	[];
      {struct,Proplist} ->
	lists:map
	  (fun ({Key,Value}) ->
	       {list_to_atom(binary_to_list(Key)),Value}
	   end, Proplist)
    end,
  ?LOG("Variables are ~p~n",[Variables]),
  uri_template:sub(Variables,binary_to_list(Href)).

generate_argument(Link={link,LinkData}) ->
  L = proplists:get_value(link,LinkData),
  S = proplists:get_value(schema,LinkData),
  Schema = 
    case jsg_jsonschema:propertyValue(L,"schema") of
      undefined ->
	undefined;
      Sch ->
	get_schema(Sch,S)
    end,
  QuerySchema = 
    case jsg_jsonschema:propertyValue(L,"querySchema") of
      undefined ->
	undefined;
      QSch ->
	get_schema(QSch,S)
    end,
  RequestType = request_type(Link),
  Body = 
    case may_have_body(RequestType) of
      true when Schema=/=undefined -> 
	BodyGen = jsongen:json(Schema),
	{ok,eqc_gen:pick(BodyGen)};
      _ -> 
	undefined
    end,
  QueryParameters =
    case may_have_body(RequestType) of
      true when QuerySchema=/=undefined ->
	QGen = jsongen:json(QuerySchema),
	{ok,eqc_gen:pick(QGen)};
      false when QuerySchema=/=undefined ->
	QGen = jsongen:json(QuerySchema),
	{ok,eqc_gen:pick(QGen)};
      false when Schema=/=undefined ->
	QGen = jsongen:json(Schema),
	{ok,eqc_gen:pick(QGen)};
      _ ->
	undefined
    end,
  {Body,QueryParameters}.

may_have_body(get) ->
  false;
may_have_body(delete) ->
  false;
may_have_body(_) ->
  true.

request_type(Link={link,LinkData}) ->
  L = proplists:get_value(link,LinkData),
  RequestType = jsg_jsonschema:propertyValue(L,"method"),
  case RequestType of
    undefined -> get;
    Other -> list_to_atom(string:to_lower(binary_to_list(Other)))
  end.

extract_dynamic_links(Link={link,LinkData},JSONBody) ->
  L = proplists:get_value(link,LinkData),
  S = proplists:get_value(schema,LinkData),
  case jsg_jsonschema:propertyValue(L,"targetSchema") of
    undefined ->
      [];
    SchemaDesc ->
      %%io:format("Schema is ~p~n",[SchemaDesc]),
      Schema = {struct,Proplist} = get_schema(SchemaDesc,S),
      case proplists:get_value(<<"type">>,Proplist) of
	undefined ->
	  %% Could be a union schema; we don't handle this yet
	  throw(bad);
	Type ->
	  case Type of
	    <<"object">> ->
	      Links = js_links_machine:collect_schema_links(Schema,true),
	      %%io:format("schema links are:~n~p~n",[Links]),
	      lists:map
		(fun ({link,Props}) -> {link,[{object,JSONBody}|Props]} end,
		 Links);
	    <<"array">> ->
	      case proplists:get_value(<<"additionalItems">>,Proplist) of
		false ->
		  ItemSchemaDesc = proplists:get_value(<<"items">>,Proplist),
		  %%io:format("itemSchema is ~p~n",[ItemSchemaDesc]),
		  ItemSchema = get_schema(ItemSchemaDesc,S),
		  Links = js_links_machine:collect_schema_links(ItemSchema,true),
		  %%io:format("schema links are:~n~p~n",[Links]),
		  lists:flatmap
		    (fun ({link,Props}) ->
			 lists:map
			   (fun (Item) ->
				{link,[{object,Item}|Props]}
			    end, JSONBody)
		     end, Links)
	      end
	  end
      end
  end.

get_schema(Value={struct,Proplist},Root) ->
  case proplists:get_value(<<"$ref">>,Proplist) of
    undefined ->
      Value;
    Ref ->
      %%io:format("Ref is ~p Root is~n~p~n",[Ref,Root]),
      jsg_jsonref:unref(Value,Root)
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

link_title(Link) ->
  {link,LD} = Link,
  proplists:get_value(title,LD).

link_schema(Link) ->
  {link,LD} = Link,
  proplists:get_value(schema,LD).

link_link(Link) ->
  {link,LD} = Link,
  proplists:get_value(link,LD).
		 
	     
      
  
