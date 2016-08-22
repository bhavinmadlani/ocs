%%% ocs_radius_authentication.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This {@link //radius/radius. radius} behaviour callback
%%% 	module performs authentication procedures in the
%%% 	{@link //ocs. ocs} application.
%%%
-module(ocs_radius_authentication).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-behaviour(radius).

%% export the radius behaviour callbacks
-export([init/2, request/4, terminate/2]).

%% @headerfile "include/radius.hrl"
-include_lib("radius/include/radius.hrl").

-record(state,
		{eap_server :: atom() | pid()}).

%%----------------------------------------------------------------------
%%  The radius callbacks
%%----------------------------------------------------------------------

-spec init(Address :: inet:ip_address(), Port :: pos_integer()) ->
	{ok, State :: #state{}} | {error, Reason :: term()}.
%% @doc This callback function is called when a
%% 	{@link //radius/radius_server. radius_server} behaviour process
%% 	initializes.
init(Address, Port) when is_tuple(Address), is_integer(Port) ->
	case global:whereis_name({ocs, Address, Port}) of
		EapServer when is_pid(EapServer) ->
			{ok, #state{eap_server = EapServer}};
		undefined ->
			{error, eap_server_not_found}
	end.

-spec request(Address :: inet:ip_address(), Port :: pos_integer(),
		Packet :: binary(), State :: #state{}) ->
	{ok, Response :: binary()} | {error, Reason :: ignore | term()}.
%% @doc This function is called when a request is received on the port.
%%
request(Address, Port, Packet, #state{eap_server = Server} = _State)
		when is_tuple(Address) ->
	try
		Radius = radius:codec(Packet),
		#radius{code = ?AccessRequest, attributes = AttributeData} = Radius,
		Attributes - radius_attributes:codec(Attributes),
		MessageAuthenticator = radius_attributes:fetch(?MessageAuthenticator,
				Attributes),
		Attributes1 = radius_attributes:store(?MessageAuthenticator,
				lists:duplicate(16, 0)),
		Packet1 = radius:codec(Radius#radius{attributes = Attributes1}),
		{ok, SharedSecret} = ocs:find_client(Address),
		MessageAuthenticator = crypto:hmac(md5, SharedSecret, Packet1),
		{SharedSecret, Radius}
	of
		{Secret, AccessRequest} ->
			gen_server:call(Server,
					{request, Address, Port, Secret, AccessRequest})
	catch
		_:_ ->
			{error, ignore}
	end.

-spec terminate(Reason :: term(), State :: #state{}) -> ok.
%% @doc This callback function is called just before the server exits.
%%
terminate(_Reason, _State) ->
	ok.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

