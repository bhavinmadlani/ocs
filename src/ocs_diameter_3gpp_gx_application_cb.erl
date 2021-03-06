%%% ocs_diameter_3gpp_gx_application_cb.erl 
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2017 SigScale Global Inc.
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
%%% @doc This {@link //stdlib/gen_server. gen_server} behaviour callback
%%% 	module receives {@link //diameter. diameter} messages on a port assigned
%%% 	for the 3GPP DIAMETER Gx in the {@link //ocs. ocs} application.
%%%
%%% @reference 3GPP TS 29.212 Policy and Charging Control (PCC)&#59; Reference points
%%%
-module(ocs_diameter_3gpp_gx_application_cb).
-copyright('Copyright (c) 2016 - 2020 SigScale Global Inc.').

-export([peer_up/3, peer_down/3, pick_peer/4, prepare_request/3,
			prepare_retransmit/3, handle_answer/4, handle_error/4,
			handle_request/3]).

-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_gx_application.hrl").
-include("ocs.hrl").

-record(state, {}).

-define(EPOCH_OFFSET, 2208988800).
-define(IANA_PEN_3GPP, 10415).
-define(Gx_APPLICATION_ID, 16777238).
-define(DIAMETER_ERROR_INITIAL_PARAMETERS, 5140).

-type state() :: #state{}.
-type capabilities() :: #diameter_caps{}.
-type packet() ::  #diameter_packet{}.
-type message() ::  tuple() | list().
-type peer() :: {Peer_Ref :: term(), Capabilities :: capabilities()}.

%%----------------------------------------------------------------------
%%  The DIAMETER application callbacks
%%----------------------------------------------------------------------

-spec peer_up(ServiceName, Peer, State) -> NewState
	when
		ServiceName :: diameter:service_name(),
		Peer ::  peer(),
		State :: state(),
		NewState :: state().
%% @doc Invoked when the peer connection is available
peer_up(_ServiceName, _Peer, State) ->
    State.

-spec peer_down(ServiceName, Peer, State) -> NewState
	when
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		State :: state(),
		NewState :: state().
%% @doc Invoked when the peer connection is not available
peer_down(_ServiceName, _Peer, State) ->
    State.

-spec pick_peer(LocalCandidates, RemoteCandidates, ServiceName, State) -> Result
	when
		LocalCandidates :: [peer()],
		RemoteCandidates :: [peer()],
		ServiceName :: diameter:service_name(),
		State :: state(),
		NewState :: state(),
		Selection :: {ok, Peer} | {Peer, NewState},
		Peer :: peer() | false,
		Result :: Selection | false.
%% @doc Invoked as a consequence of a call to diameter:call/4 to select
%% a destination peer for an outgoing request. 
pick_peer([Peer | _] = _LocalCandidates, _RemoteCandidates, _ServiceName, _State) ->
	{ok, Peer}.

-spec prepare_request(Packet, ServiceName, Peer) -> Action
	when
		Packet :: packet(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Action :: Send | Discard | {eval_packet, Action, PostF},
		Send :: {send, packet() | message()},
		Discard :: {discard, Reason} | discard,
		Reason :: term(),
		PostF :: diameter:evaluable().
%% @doc Invoked to return a request for encoding and transport 
prepare_request(#diameter_packet{} = Packet, _ServiceName, _Peer) ->
	{send, Packet}.

-spec prepare_retransmit(Packet, ServiceName, Peer) -> Action
	when
		Packet :: packet(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Action :: Send | Discard | {eval_packet, Action, PostF},
		Send :: {send, packet() | message()},
		Discard :: {discard, Reason} | discard,
		Reason :: term(),
		PostF :: diameter:evaluable().
%% @doc Invoked to return a request for encoding and retransmission.
%% In case of peer connection is lost alternate peer is selected.
prepare_retransmit(Packet, ServiceName, Peer) ->
	prepare_request(Packet, ServiceName, Peer).

-spec handle_answer(Packet, Request, ServiceName, Peer) -> Result
	when
		Packet :: packet(),
		Request :: message(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Result :: term().
%% @doc Invoked when an answer message is received from a peer.
handle_answer(_Packet, _Request, _ServiceName, _Peer) ->
    not_implemented.

-spec handle_error(Reason, Request, ServiceName, Peer) -> Result
	when
		Reason :: timeout | failover | term(),
		Request :: message(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Result :: term().
%% @doc Invoked when an error occurs before an answer message is received
%% in response to an outgoing request.
handle_error(_Reason, _Request, _ServiceName, _Peer) ->
	not_implemented.

-spec handle_request(Packet, ServiceName, Peer) -> Action
	when
		Packet :: packet(),
		ServiceName :: term(),
		Peer :: peer(),
		Action :: Reply | {relay, [Opt]} | discard
			| {eval | eval_packet, Action, PostF},
		Reply :: {reply, packet() | message()}
			| {answer_message, 3000..3999|5000..5999}
			| {protocol_error, 3000..3999},
		Opt :: diameter:call_opt(),
		PostF :: diameter:evaluable().
%% @doc Invoked when a request message is received from the peer.
handle_request(#diameter_packet{msg = Request, errors = []} = _Packet,
		ServiceName, {_, Caps} = _Peer) ->
	request(ServiceName, Caps, Request);
handle_request(#diameter_packet{msg = Request, errors = Errors} = _Packet,
		ServiceName, {_, Caps} = _Peer) ->
	errors(ServiceName, Caps, Request, Errors).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec request(Svc, Capabilities, Request) -> Action
	when
		Svc :: atom(),
		Capabilities :: capabilities(),
		Request :: message(),
		Action :: Reply | {relay, [Opt]} | discard
			| {eval|eval_packet, Action, PostF},
		Reply :: {reply, packet() | message()}
			| {answer_message, 3000..3999|5000..5999}
			| {protocol_error, 3000..3999},
		Opt :: diameter:call_opt(),
		PostF :: diameter:evaluable().
%% @doc Handle received request.
%% 	Authorize client then forward capabilities and request
%% 	to the accounting port server matching the service the
%% 	request was received on.
%% @private
request(ServiceName, Capabilities, Request) ->
	#diameter_caps{host_ip_address = {_, HostIpAddresses}} = Capabilities,
	request(ServiceName, Capabilities, Request, HostIpAddresses).
%% @hidden
request({_, Address, Port} = ServiceName, Capabilities, Request, [H | T]) ->
	case ocs:find_client(H) of
		{ok, #client{protocol = diameter}} ->
			{reply, process_request(Address, Port, Capabilities, Request)};
		{error, not_found} ->
			request(ServiceName, Capabilities, Request, T)
	end;
request(_, _, _, []) ->
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_UNKNOWN_PEER'}.

-spec errors(ServiceName, Capabilities, Request, Errors) -> Action
	when
		ServiceName :: atom(),
		Capabilities :: capabilities(),
		Request :: message(),
		Errors :: [Error],
		Error :: {Code, #diameter_avp{}} | Code,
		Code :: 0..4294967295,
		Action :: Reply | {relay, [Opt]} | discard
			| {eval | eval_packet, Action, PostF},
		Reply :: {reply, packet() | message()}
			| {answer_message, 3000..3999|5000..5999}
			| {protocol_error, 3000..3999},
		Opt :: diameter:call_opt(),
		PostF :: diameter:evaluable().
%% @doc Handle errors in requests.
%% @private
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_UNSUPPORTED', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP unsupported",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_AVP_UNSUPPORTED'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_VALUE', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP invalid",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_VALUE'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_MISSING_AVP', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP missing",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_MISSING_AVP'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_CONTRADICTING_AVPS', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVPs contradicting",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_CONTRADICTING_AVPS'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_NOT_ALLOWED', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP not allowed",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_AVP_NOT_ALLOWED'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_OCCURS_TOO_MANY_TIMES', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP too many times",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_AVP_OCCURS_TOO_MANY_TIMES'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_LENGTH', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP invalid length",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_LENGTH'};
errors(_ServiceName, _Capabilities, _Request, [{ResultCode, _} | _]) ->
	{answer_message, ResultCode};
errors(_ServiceName, _Capabilities, _Request, [ResultCode | _]) ->
	{answer_message, ResultCode};
errors(ServiceName, Capabilities, Request, []) ->
	request(ServiceName, Capabilities, Request).

-spec process_request(Address, Port, Caps, Request) -> Result
	when
		Address :: inet:ip_address(),
		Port :: inet:port_number(),
		Request :: #'3gpp_gx_CCR'{},
		Caps :: capabilities(),
		Result :: packet() | message().
%% @doc Process a received DIAMETER Accounting packet.
%% @private
process_request(_Address, _Port,
		#diameter_caps{origin_host = {OHost, _DHost}, origin_realm = {ORealm, _DRealm}},
		#'3gpp_gx_CCR'{'Session-Id' = SId,
				'Auth-Application-Id' = ?Gx_APPLICATION_ID,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Subscription-Id' = []} = Request) ->
			error_logger:warning_report(["Unable to process DIAMETER request",
					{origin_host, OHost}, {origin_realm, ORealm},
					{session_id, SId}, {request, Request},
					{error, missing_subscription_id}]),
			diameter_error(SId, ?'DIAMETER_ERROR_INITIAL_PARAMETERS',
					OHost, ORealm, RequestType, RequestNum);
process_request(_Address, _Port,
		#diameter_caps{origin_host = {OHost, _DHost}, origin_realm = {ORealm, _DRealm}},
		#'3gpp_gx_CCR'{'Session-Id' = SId,
				'Auth-Application-Id' = ?Gx_APPLICATION_ID,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Subscription-Id' = [#'3gpp_gx_Subscription-Id'{
						'Subscription-Id-Data' = Subscriber} | _]} = Request) ->
	try
		QosInformation = #'3gpp_gx_QoS-Information'{
				'QoS-Class-Identifier' = [?'3GPP_GX_QOS-CLASS-IDENTIFIER_QCI_9'],
				'Max-Requested-Bandwidth-UL' = [1000000000],
				'Max-Requested-Bandwidth-DL' = [1000000000]},
		FlowInformationUp1 = #'3gpp_gx_Flow-Information'{
				 'Flow-Description' = ["permit in ip from any to 10/8"],
				 'Flow-Direction' = [?'3GPP_GX_FLOW-DIRECTION_UPLINK']},
		FlowInformationDown1 = #'3gpp_gx_Flow-Information'{
				 'Flow-Description' = ["permit out ip from 10/8 to any"],
				 'Flow-Direction' = [?'3GPP_GX_FLOW-DIRECTION_DOWNLINK']},
		FlowInformationUp2 = #'3gpp_gx_Flow-Information'{
				 'Flow-Description' = ["permit in ip from any to 172.16/12"],
				 'Flow-Direction' = [?'3GPP_GX_FLOW-DIRECTION_UPLINK']},
		FlowInformationDown2 = #'3gpp_gx_Flow-Information'{
				 'Flow-Description' = ["permit out ip from 172.16/12 to any"],
				 'Flow-Direction' = [?'3GPP_GX_FLOW-DIRECTION_DOWNLINK']},
		FlowInformationUp3 = #'3gpp_gx_Flow-Information'{
				 'Flow-Description' = ["permit in ip from any to 192.168/16"],
				 'Flow-Direction' = [?'3GPP_GX_FLOW-DIRECTION_UPLINK']},
		FlowInformationDown3 = #'3gpp_gx_Flow-Information'{
				 'Flow-Description' = ["permit out ip from 192.168/16 to any"],
				 'Flow-Direction' = [?'3GPP_GX_FLOW-DIRECTION_DOWNLINK']},
		FlowInformationUp4 = #'3gpp_gx_Flow-Information'{
				 'Flow-Description' = ["permit in ip from any to any"],
				 'Flow-Direction' = [?'3GPP_GX_FLOW-DIRECTION_UPLINK']},
		FlowInformationDown4 = #'3gpp_gx_Flow-Information'{
				 'Flow-Description' = ["permit out ip from any to any"],
				 'Flow-Direction' = [?'3GPP_GX_FLOW-DIRECTION_DOWNLINK']},
		ChargingRuleDefinition1 = #'3gpp_gx_Charging-Rule-Definition'{
				'Charging-Rule-Name' = ["internal"],
				'QoS-Information' = [QosInformation],
				'Rating-Group' = [1],
				'Flow-Information' = [FlowInformationUp1, FlowInformationDown1,
						FlowInformationUp2, FlowInformationDown2,
						FlowInformationUp3, FlowInformationDown3],
				'Precedence' = [2]},
		ChargingRuleDefinition2 = #'3gpp_gx_Charging-Rule-Definition'{
				'Charging-Rule-Name' = ["external"],
				'QoS-Information' = [QosInformation],
				'Rating-Group' = [32],
				'Flow-Information' = [FlowInformationUp4, FlowInformationDown4],
				'Precedence' = [1]},
		ChargingRuleInstall = #'3gpp_gx_Charging-Rule-Install'{
				'Charging-Rule-Definition' = [ChargingRuleDefinition1,
						ChargingRuleDefinition2]},
		#'3gpp_gx_CCA'{'Session-Id' = SId,
				'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS'],
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Auth-Application-Id' = ?Gx_APPLICATION_ID,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Online' = [?'3GPP_GX_ONLINE_ENABLE_ONLINE'],
				'Charging-Rule-Install' = [ChargingRuleInstall]}
	catch
		_:Reason ->
			error_logger:warning_report(["Unable to process DIAMETER request",
					{origin_host, OHost}, {origin_realm, ORealm},
					{session_id, SId}, {request, Request}, {error, Reason}]),
			diameter_error(SId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum)
	end.

-spec diameter_error(SessionId, ResultCode, OriginHost,
		OriginRealm, RequestType, RequestNum) -> Reply
	when
		SessionId :: string(),
		ResultCode :: integer(),
		OriginHost :: string(),
		OriginRealm :: string(),
		RequestType :: integer(),
		RequestNum :: integer(),
		Reply :: #'3gpp_gx_CCA'{}.
%% @doc Send CCA to DIAMETER client indicating an operation failure.
%% @hidden
diameter_error(SId, ?'DIAMETER_ERROR_INITIAL_PARAMETERS' = ResultCode,
		OHost, ORealm, RequestType, RequestNum) ->
	#'3gpp_gx_CCA'{'Session-Id' = SId,
			'Experimental-Result' = [#'3gpp_gx_Experimental-Result'{
					'Vendor-Id' = ?IANA_PEN_3GPP,
					'Experimental-Result-Code' = ResultCode}],
			'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
			'Auth-Application-Id' = ?Gx_APPLICATION_ID,
			'CC-Request-Type' = RequestType, 'CC-Request-Number' = RequestNum};
diameter_error(SId, ResultCode, OHost, ORealm, RequestType, RequestNum) ->
	#'3gpp_gx_CCA'{'Session-Id' = SId, 'Result-Code' = [ResultCode],
			'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
			'Auth-Application-Id' = ?Gx_APPLICATION_ID,
			'CC-Request-Type' = RequestType, 'CC-Request-Number' = RequestNum}.

