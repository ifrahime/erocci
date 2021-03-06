%% @author Jean Parpaillon <jean.parpaillon@free.fr>
%% @copyright 2013 Jean Parpaillon.
%%% 
%%% This file is provided to you under the Apache License,
%%% Version 2.0 (the "License"); you may not use this file
%%% except in compliance with the License.  You may obtain
%%% a copy of the License at
%%% 
%%%   http://www.apache.org/licenses/LICENSE-2.0
%%% 
%%% Unless required by applicable law or agreed to in writing,
%%% software distributed under the License is distributed on an
%%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%%% KIND, either express or implied.  See the License for the
%%% specific language governing permissions and limitations
%%% under the License.
%%% 
%% @doc Example webmachine_resource.

-module(occi_http_handler).
-compile({parse_transform, lager_transform}).

-include("occi.hrl").

%% REST Callbacks
-export([init/3, 
	 rest_init/2,
	 allowed_methods/2,
	 allow_missing_post/2,
	 resource_exists/2,
	 delete_resource/2,
	 content_types_provided/2,
	 content_types_accepted/2]).

%% Callback callbacks
-export([to_occi/2,
	 to_plain/2,
	 to_uri_list/2,
	 to_json/2,
	 to_xml/2,
	 from_plain/2,
	 from_occi/2,
	 from_json/2,
	 from_xml/2]).

-record(content_type, {parser   :: atom(),
		       renderer :: atom(),
		       mimetype :: binary()}).

-define(ct_plain,    #content_type{parser=occi_parser_plain, renderer=occi_renderer_plain, 
				   mimetype="text/plain"}).
-define(ct_occi,     #content_type{parser=occi_parser_occi, renderer=occi_renderer_occi, 
				   mimetype="text/occi"}).
-define(ct_uri_list, #content_type{parser=occi_parser_uri_list, renderer=occi_renderer_uri_list, 
				   mimetype="text/uri-list"}).
-define(ct_json,     #content_type{parser=occi_parser_json, renderer=occi_renderer_json, 
				   mimetype="application/json"}).
-define(ct_xml,      #content_type{parser=occi_parser_xml, renderer=occi_renderer_xml, 
				   mimetype="application/xml"}).

init(_Transport, _Req, []) -> 
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, _Opts) ->
    {ok, cowboy_req:set_resp_header(<<"server">>, ?HTTP_SERVER_ID, Req), #occi_node{}}.

allowed_methods(Req, State) ->
    Methods = [<<"GET">>, <<"DELETE">>, <<"OPTIONS">>, <<"POST">>, <<"PUT">>],
    << ", ", Allow/binary >> = << << ", ", M/binary >> || M <- Methods >>,
    {Methods, occi_http_common:set_cors(Req, Allow), State}.

content_types_provided(Req, State) ->
    {[
      {{<<"text">>,            <<"plain">>,     []}, to_plain},
      {{<<"text">>,            <<"occi">>,      []}, to_occi},
      {{<<"text">>,            <<"uri-list">>,  []}, to_uri_list},
      {{<<"application">>,     <<"json">>,      []}, to_json},
      {{<<"application">>,     <<"occi+json">>, []}, to_json},
      {{<<"application">>,     <<"xml">>,       []}, to_xml},
      {{<<"application">>,     <<"occi+xml">>,  []}, to_xml}
     ],
     Req, State}.

content_types_accepted(Req, State) ->
    {[
      {{<<"text">>,            <<"plain">>,     []}, from_plain},
      {{<<"text">>,            <<"occi">>,      []}, from_occi},
      {{<<"application">>,     <<"json">>,      []}, from_json},
      {{<<"application">>,     <<"occi+json">>, []}, from_json},
      {{<<"application">>,     <<"xml">>,       []}, from_xml},
      {{<<"application">>,     <<"occi+xml">>,  []}, from_xml}
     ],
     Req, State}.

allow_missing_post(Req, State) ->
    case cowboy_req:method(Req) of
	{<<"POST">>, _} ->
	    {false, Req, State};
	{<<"PUT">>, _} ->
	    {true, Req, State}
    end.

resource_exists(Req, State) ->
    {Path, _} = cowboy_req:path(Req),
    Id = occi_uri:parse(Path),
    case occi_store:find(#occi_node{id=#uri{path=Id#uri.path}, _='_'}) of
	{ok, []} ->
	    {false, Req, State};
	{ok, [#occi_node{type=occi_collection, objid=#occi_cid{class=kind}}=Node]} ->
	    case cowboy_req:method(Req) of
		{<<"PUT">>, _} ->
		    {ok, Req2} = cowboy_req:reply(405, Req),
		    {halt, Req2, State};
		{_, _} ->
		    lager:debug("Resource: ~p~n", [lager:pr(Node, ?MODULE)]),
		    {true, Req, Node}
	    end;
	{ok, [#occi_node{}=Node]} ->
	    lager:debug("Resource: ~p~n", [lager:pr(Node, ?MODULE)]),
	    {true, Req, Node}
    end.

delete_resource(Req, #occi_node{id=Id}=Node) ->
    case occi_store:delete(Node) of
	{error, undefined_backend} ->
	    lager:error("Internal error deleting node: ~p~n", [lager:pr(Id, ?MODULE)]),
	    {ok, Req2} = cowboy_req:reply(500, Req),
	    {halt, Req2, Node};
	{error, Reason} ->
	    lager:error("Error deleting node: ~p~n", [Reason]),
	    {false, Req, Node};
	ok ->
	    {true, Req, Node}
    end.

to_occi(Req, #occi_node{}=Node) ->
    render(Req, Node, ?ct_occi).

to_plain(Req, #occi_node{}=Node) ->
    render(Req, Node, ?ct_plain).

to_uri_list(Req, #occi_node{type=occi_collection}=Node) ->
    render(Req, Node, ?ct_uri_list);
to_uri_list(Req, #occi_node{type=dir}=Node) ->
    render(Req, Node, ?ct_uri_list);
to_uri_list(Req, State) ->
    {ok, Req2} = cowboy_req:reply(400, Req),
    {halt, Req2, State}.

to_json(Req, #occi_node{}=Node) ->
    render(Req, Node, ?ct_json).

to_xml(Req, #occi_node{}=Node) ->
    render(Req, Node, ?ct_xml).

from_plain(Req, State) ->
    from(Req, State, ?ct_plain).

from_occi(Req, State) ->
    from(Req, State, ?ct_occi).

from_json(Req, State) ->
    from(Req, State, ?ct_json).

from_xml(Req, State) ->
    from(Req, State, ?ct_xml).

%%%
%%% Private
%%%
from(Req, #occi_node{type=occi_collection, objid=#occi_cid{class=kind}}=State, CT) ->
    case cowboy_req:qs_val(<<"action">>, Req) of
	{undefined, Req2} ->
	    save_entity(Req2, State, CT);
	{Action, Req2} ->
	    action(Req2, State, Action, CT)
    end;

from(Req, #occi_node{type=occi_collection, objid=#occi_cid{class=mixin}}=State, CT) ->
    case cowboy_req:method(Req) of
	{<<"PUT">>, _} ->
	    save_collection(Req, State, CT);
	{<<"POST">>, _} ->
	    case cowboy_req:qs_val(<<"action">>, Req) of
		{undefined, Req2} ->
		    update_collection(Req2, State, CT);
		{Action, Req2} ->
		    action(Req2, State, Action, CT)
	    end
    end;

from(Req, #occi_node{type=occi_collection, objid=#occi_cid{class=usermixin}}=State, CT) ->
    case cowboy_req:method(Req) of
	{<<"PUT">>, _} ->
	    save_collection(Req, State, CT);
	{<<"POST">>, _} ->
	    case cowboy_req:qs_val(<<"action">>, Req) of
		{undefined, Req2} ->
		    update_collection(Req2, State, CT);
		{Action, Req2} ->
		    action(Req2, State, Action, CT)
	    end
    end;

from(Req, #occi_node{type=occi_user_mixin}=State, CT) ->
    case cowboy_req:method(Req) of
	{<<"PUT">>, _} ->
	    save_collection(Req, State, CT);
	{<<"POST">>, _} ->
	    case cowboy_req:qs_val(<<"action">>, Req) of
		{undefined, Req2} ->
		    update_collection(Req2, State, CT);
		{Action, Req2} ->
		    action(Req2, State, Action, CT)
	    end
    end;

from(Req, #occi_node{type=occi_resource}=State, CT) ->
    case cowboy_req:method(Req) of
	{<<"PUT">>, _} ->
	    save_entity(Req, State, CT);
	{<<"POST">>, _} ->
	    case cowboy_req:qs_val(<<"action">>, Req) of
		{undefined, Req2} ->
		    update_entity(Req2, State, CT);
		{Action, Req2} ->
		    action(Req2, State, Action, CT)
	    end
    end;

from(Req, #occi_node{type=occi_link}=State, CT) ->
    case cowboy_req:method(Req) of
	{<<"PUT">>, _} ->
	    save_entity(Req, State, CT);
	{<<"POST">>, _} ->
	    case cowboy_req:qs_val(<<"action">>, Req) of
		{undefined, Req2} ->
		    update_entity(Req2, State, CT);
		{Action, Req2} ->
		    action(Req2, State, Action, CT)
	    end
    end;

from(Req, #occi_node{type=dir}=State, _) ->
    {ok, Req2} = cowboy_req:reply(405, Req),
    {halt, Req2, State};

from(Req, #occi_node{type=undefined}=State, CT) ->
    save_entity(Req, State, CT).

render(Req, State, #content_type{renderer=Renderer}) ->
    case occi_store:load(State) of
	{ok, Node} ->
	    {Body, Req2} = Renderer:render(Node, Req),
	    {Body, Req2, Node};
	{error, Err} ->
	    lager:error("Error loading object: ~p~n", [Err]),
	    {ok, Req2} = cowboy_req:reply(500, Req),
	    {halt, Req2, State}
    end.

save_entity(Req, State, #content_type{parser=Parser}) ->
    {ok, Body, Req2} = cowboy_req:body(Req),
    Entity = prepare_entity(Req, State),
    case Parser:parse_entity(Body, Req2, Entity) of
	{error, {parse_error, Err}} ->
	    lager:error("Error processing request: ~p~n", [Err]),
	    {false, Req2, State};
	{error, Err} ->
	    lager:error("Internal error: ~p~n", [Err]),
	    {ok, Req3} = cowboy_req:reply(500, Req2),
	    {false, Req3, State};	    
	{ok, #occi_resource{}=Res} ->
	    Node = create_resource_node(Req2, Res),
	    case occi_store:save(Node) of
		ok ->
		    Req3 = cowboy_req:set_resp_body("OK\n", Req2),
		    {true, set_location_header(Node, Req3), State};
		{error, Reason} ->
		    lager:error("Error creating resource: ~p~n", [Reason]),
		    {ok, Req3} = cowboy_req:reply(500, Req2),
		    {halt, Req3, State}
	    end;
	{ok, #occi_link{}=Link} ->
	    Node = create_link_node(Req2, Link),
	    case occi_store:save(Node) of
		ok ->
		    Req3 = cowboy_req:set_resp_body("OK\n", Req2),
		    {true, set_location_header(Node, Req3), State};
		{error, Reason} ->
		    lager:error("Error creating link: ~p~n", [Reason]),
		    {ok, Req3} = cowboy_req:reply(500, Req2),
		    {halt, Req3, State}
	    end
    end.

update_entity(Req, State, #content_type{parser=Parser}) ->
    {ok, Body, Req2} = cowboy_req:body(Req),
    case occi_store:load(State) of
	{ok, #occi_node{data=Entity}=Node} ->
	    case Parser:parse_entity(Body, Req2, Entity) of
		{error, {parse_error, Err}} ->
		    lager:error("Error processing request: ~p~n", [Err]),
		    {false, Req2, State};
		{error, Err} ->
		    lager:error("Internal error: ~p~n", [Err]),
		    {ok, Req3} = cowboy_req:reply(500, Req2),
		    {false, Req3, State};	    
		{ok, #occi_resource{}=Res} ->
		    Node2 = occi_node:set_data(Node, Res),
		    case occi_store:update(Node2) of
			ok ->
			    {true, cowboy_req:set_resp_body("OK\n", Req2), State};
			{error, Reason} ->
			    lager:error("Error updating resource: ~p~n", [Reason]),
			    {ok, Req3} = cowboy_req:reply(500, Req2),
			    {halt, Req3, State}
		    end;
		{ok, #occi_link{}=Link} ->
		    Node2 = occi_node:set_data(Node, Link),
		    case occi_store:update(Node2) of
			ok ->
			    {true, cowboy_req:set_resp_body("OK\n", Req2), State};
			{error, Reason} ->
			    lager:error("Error updating link: ~p~n", [Reason]),
			    {ok, Req3} = cowboy_req:reply(500, Req2),
			    {halt, Req3, State}
		    end
	    end;	    
	{error, Err} ->
	    lager:error("Error loading object: ~p~n", [Err]),
	    {ok, Req2} = cowboy_req:reply(500, Req),
	    {halt, Req2, State}
    end.

save_collection(Req, #occi_node{objid=Cid}=State, #content_type{parser=Parser}) ->
    {ok, Body, Req2} = cowboy_req:body(Req),
    case Parser:parse_collection(Body, Req2) of
	{error, {parse_error, Err}} ->
	    lager:error("Error processing request: ~p~n", [Err]),
	    {false, Req2, State};
	{error, Err} ->
	    lager:error("Internal error: ~p~n", [Err]),
	    {ok, Req3} = cowboy_req:reply(500, Req2),
	    {halt, Req3, State};	    
	{ok, #occi_collection{}=C} ->
	    Coll = occi_collection:new(Cid, occi_collection:get_entities(C)),
	    case occi_store:save(State#occi_node{type=occi_collection, data=Coll}) of
		ok ->
		    {true, Req, State};
		{error, {no_such_entity, Uri}} ->
		    lager:debug("Invalid entity: ~p~n", [occi_uri:to_string(Uri)]),
			    {false, Req2, State};
		{error, Reason} ->
		    lager:error("Error saving collection: ~p~n", [Reason]),
		    {ok, Req3} = cowboy_req:reply(500, Req2),
		    {halt, Req3, State}
	    end
    end.

update_collection(Req, #occi_node{objid=Cid}=State, #content_type{parser=Parser}) ->
    {ok, Body, Req2} = cowboy_req:body(Req),
    case Parser:parse_collection(Body, Req2) of
	{error, {parse_error, Err}} ->
	    lager:error("Error processing request: ~p~n", [Err]),
	    {false, Req2, State};
	{error, Err} ->
	    lager:error("Internal error: ~p~n", [Err]),
	    {ok, Req3} = cowboy_req:reply(500, Req2),
	    {halt, Req3, State};	    
	{ok, #occi_collection{}=C} ->
	    Coll = occi_collection:new(Cid, occi_collection:get_entities(C)),
	    Node = State#occi_node{type=occi_collection, data=Coll},
	    case occi_store:update(Node) of
		ok ->
		    {true, Req, State};
		{error, {no_such_entity, Uri}} ->
		    lager:debug("Invalid entity: ~p~n", [lager:pr(Uri, ?MODULE)]),
		    {false, Req2, State};
		{error, Reason} ->
		    lager:error("Error updating collection: ~p~n", [Reason]),
		    {ok, Req3} = cowboy_req:reply(500, Req2),
		    {halt, Req3, State}
	    end
    end.

action(Req, Node, ActionName, #content_type{parser=Parser}) ->
    {ok, Body, Req2} = cowboy_req:body(Req),
    case Parser:parse_action(Body, Req2, prepare_action(Req2, Node, ActionName)) of
	{error, {parse_error, Err}} ->
	    lager:error("Error processing action: ~p~n", [Err]),
	    {false, Req2, Node};
	{error, Err} ->
	    lager:error("Internal error: ~p~n", [Err]),
	    {ok, Req3} = cowboy_req:reply(500, Req2),
	    {halt, Req3, Node};	    
	{ok, #occi_action{}=Action} ->
	    case occi_store:action(Node, Action) of
		ok ->
		    {true, Req2, Node};
		{error, Err} ->
		    lager:error("Error triggering action: ~p~n", [Err]),
		    {ok, Req3} = cowboy_req:reply(500, Req2),
		    {halt, Req3, Node}
	    end
    end.

prepare_action(Req, State, Name) when is_binary(Name)->
    prepare_action(Req, State, list_to_atom(binary_to_list(Name)));
prepare_action(_Req, _State, Name) ->
    occi_action:new(#occi_cid{term=Name, class=action}).

prepare_entity(_Req, #occi_node{type=occi_collection, objid=Cid}) ->
    case occi_store:find(Cid) of
	{ok, [#occi_kind{parent=#occi_cid{term=resource}}=Kind]} ->
	    occi_resource:new(Kind);
	{ok, [#occi_kind{parent=#occi_cid{term=link}}=Kind]} ->
	    occi_link:new(Kind);
	_ ->
	    throw({error, internal_error})
    end;

prepare_entity(_Req, #occi_node{type=occi_resource}=Node) ->
    case occi_store:load(Node) of
	{ok, #occi_node{data=Res}} ->
	    occi_resource:reset(Res);
	{error, Err} ->
	    throw({error, Err})
    end;

prepare_entity(_Req, #occi_node{type=occi_link}=Node) ->
    case occi_store:load(Node) of
	{ok, #occi_node{data=Link}} ->
	    occi_link:reset(Link);
	{error, Err} ->
	    throw({error, Err})
    end;

prepare_entity(Req, #occi_node{type=undefined}) ->
    {Path, _} = cowboy_req:path(Req),
    #occi_entity{id=occi_config:to_url(occi_uri:parse(Path))}.

create_resource_node(Req, #occi_resource{id=undefined}=Res) ->
    {Prefix, _} = cowboy_req:path(Req),
    Id = occi_config:gen_id(Prefix),
    occi_node:new(Id, occi_resource:set_id(Res, Id));
create_resource_node(_Req, #occi_resource{}=Res) ->
    occi_node:new(occi_resource:get_id(Res), Res).

create_link_node(Req, #occi_link{id=undefined}=Link) ->
    {Prefix, _} = cowboy_req:path(Req),
    Id = occi_config:gen_id(Prefix),
    occi_node:new(Id, occi_link:set_id(Link, Id));
create_link_node(_Req, #occi_link{}=Link) ->
    occi_node:new(occi_link:get_id(Link), Link).

set_location_header(#occi_node{objid=Id}, Req) ->
    cowboy_req:set_resp_header(<<"location">>,
			       occi_uri:to_binary(Id), Req).
