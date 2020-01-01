%%% ocs_eap_akap_SUITE.erl
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
%%%  @doc Test suite for authentication using Extensible Authentication
%%% 	Protocol (EAP) using only a password (EAP-AKA)
%%% 	of the {@link //ocs. ocs} application.
%%%
-module(ocs_eap_akap_SUITE).
-copyright('Copyright (c) 2016 - 2019 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include("ocs_eap_codec.hrl").
-include("ocs.hrl").
-include_lib("radius/include/radius.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("../include/diameter_gen_eap_application_rfc4072.hrl").
-include_lib("kernel/include/inet.hrl").

-define(BASE_APPLICATION_ID, 0).
-define(EAP_APPLICATION_ID, 5).
-define(IANA_PEN_3GPP, 10415).
-define(IANA_PEN_SigScale, 50386).

%% support deprecated_time_unit()
-define(MILLISECOND, milli_seconds).
%-define(MILLISECOND, millisecond).

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{userdata, [{doc, "Test suite for authentication with EAP-AKA in OCS"}]},
	{timetrap, {seconds, 8}},
	{require, mcc}, {default_config, mcc, "001"},
	{require, mnc}, {default_config, mnc, "001"},
	{require, radius_shared_secret},{default_config, radius_shared_secret, "xyzzy5461"}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
init_per_suite(Config) ->
	ok = ocs_test_lib:initialize_db(),
	RadiusPort = rand:uniform(64511) + 1024,
	Options = [{eap_method_prefer, akap}, {eap_method_order, [akap]}],
	RadiusAppVar = [{auth, [{{127,0,0,1}, RadiusPort, Options}]}],
	ok = application:set_env(ocs, radius, RadiusAppVar, [{persistent, true}]),
	DiameterPort = rand:uniform(64511) + 1024,
	DiameterAppVar = [{auth, [{{127,0,0,1}, DiameterPort, Options}]}],
	ok = application:set_env(ocs, diameter, DiameterAppVar, [{persistent, true}]),
	ok = ocs_test_lib:start(),
	{ok, ProdID} = ocs_test_lib:add_offer(),
	{ok, DiameterConfig} = application:get_env(ocs, diameter),
	{auth, [{Address, Port, _} | _]} = lists:keyfind(auth, 1, DiameterConfig),
	Host = atom_to_list(?MODULE),
	Realm = "mnc" ++ ct:get_config(mnc) ++ ".mcc"
			++ ct:get_config(mcc) ++ ".3gppnetwork.org",
	Config1 = [{host, Host}, {realm, Realm}, {product_id, ProdID},
		{diameter_client, Address} | Config],
	ok = diameter:start_service(?MODULE, client_service_opts(Config1)),
	true = diameter:subscribe(?MODULE),
	{ok, _Ref} = connect(?MODULE, Address, Port, diameter_tcp),
	receive
		#diameter_event{service = ?MODULE, info = Info}
				when element(1, Info) == up ->
			Config1;
		_Other ->
			{skip, diameter_client_service_not_started}
	end.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = application:unset_env(ocs, radius, [{persistent, true}]),
	ok = application:unset_env(ocs, diameter, [{persistent, true}]),
	ok = diameter:stop_service(?MODULE),
	ok = ocs_test_lib:stop(),
	Config.

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before each test case.
%%
init_per_testcase(aka_prf, Config) ->
	Config;
init_per_testcase(TestCase, Config)
		when TestCase == akap_identity_diameter ->
	{ok, DiameterConfig} = application:get_env(ocs, diameter),
	{auth, [{Address, _, _} | _]} = lists:keyfind(auth, 1, DiameterConfig),
	{ok, _} = ocs:add_client(Address, undefined, diameter, undefined, true, false),
	[{diameter_client, Address} | Config];
init_per_testcase(TestCase, Config)
		when TestCase == akap_identity_diameter_trusted ->
	{ok, DiameterConfig} = application:get_env(ocs, diameter),
	{auth, [{Address, _, _} | _]} = lists:keyfind(auth, 1, DiameterConfig),
	{ok, _} = ocs:add_client(Address, undefined, diameter, undefined, true, true),
	[{diameter_client, Address} | Config];
init_per_testcase(TestCase, Config)
		when TestCase == akap_identity_radius ->
	{ok, RadiusConfig} = application:get_env(ocs, radius),
	{auth, [{RadIP, _, _} | _]} = lists:keyfind(auth, 1, RadiusConfig),
	{ok, Socket} = gen_udp:open(0, [{active, false}, inet, {ip, RadIP}, binary]),
	SharedSecret = ct:get_config(radius_shared_secret),
	Protocol = radius,
	{ok, _} = ocs:add_client(RadIP, undefined, Protocol, SharedSecret, true, false),
	NasId = atom_to_list(node()),
	[{nas_id, NasId}, {socket, Socket}, {radius_client, RadIP} | Config];
init_per_testcase(TestCase, Config)
		when TestCase == akap_identity_radius_trusted; TestCase == akap_identity_radius_trusted_no_service->
	{ok, RadiusConfig} = application:get_env(ocs, radius),
	{auth, [{RadIP, _, _} | _]} = lists:keyfind(auth, 1, RadiusConfig),
	{ok, Socket} = gen_udp:open(0, [{active, false}, inet, {ip, RadIP}, binary]),
	SharedSecret = ct:get_config(radius_shared_secret),
	Protocol = radius,
	{ok, _} = ocs:add_client(RadIP, undefined, Protocol, SharedSecret, true, true),
	NasId = atom_to_list(node()),
	[{nas_id, NasId}, {socket, Socket}, {radius_client, RadIP} | Config];
init_per_testcase(TestCase, Config)
		when TestCase == akap_identity_diameter_no_client ->
	{ok, DiameterConfig} = application:get_env(ocs, diameter),
	{auth, [{Address, _, _} | _]} = lists:keyfind(auth, 1, DiameterConfig),
	[{diameter_client, Address} | Config];
init_per_testcase(TestCase, Config)
		when TestCase == akap_identity_radius_no_client ->
	{ok, RadiusConfig} = application:get_env(ocs, radius),
	{auth, [{RadIP, _, _} | _]} = lists:keyfind(auth, 1, RadiusConfig),
	{ok, Socket} = gen_udp:open(0, [{active, false}, inet, {ip, RadIP}, binary]),
	NasId = atom_to_list(node()),
	[{nas_id, NasId}, {socket, Socket}, {radius_client, RadIP} | Config].

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(aka_prf, Config) ->
	Config;
end_per_testcase(TestCase, Config)
		when TestCase == akap_identity_diameter;
		TestCase == akap_identity_diameter_trusted ->
	DClient = ?config(diameter_client, Config),
	ok = ocs:delete_client(DClient);
end_per_testcase(_TestCase, Config) ->
	Socket = ?config(socket, Config),
	RadClient = ?config(radius_client, Config),
	ok = ocs:delete_client(RadClient),
	ok = gen_udp:close(Socket).

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() ->
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() ->
	[akap_identity_radius, akap_identity_diameter, akap_identity_radius_trusted,
			akap_identity_diameter_trusted, akap_identity_radius_no_client].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

akap_identity_radius() ->
   [{userdata, [{doc, "Send an EAP-Identity/Response using RADIUS"}]}].

akap_identity_radius(Config) ->
	Socket = ?config(socket, Config),
	{ok, RadiusConfig} = application:get_env(ocs, radius),
	{auth, [{Address, Port, _} | _]} = lists:keyfind(auth, 1, RadiusConfig),
	NasId = ?config(nas_id, Config),
	ReqAuth = radius:authenticator(),
	RadId = 1, EapId = 1,
	Secret = ct:get_config(radius_shared_secret),
	Realm = ?config(realm, Config),
	MSIN = msin(),
	PeerId = "6" ++ ct:get_config(mcc) ++ ct:get_config(mcc)
			++ MSIN ++ "@wlan." ++ Realm,
	PeerId1 = list_to_binary(PeerId),
	ok = send_radius_identity(Socket, Address, Port, NasId,
			PeerId1, Secret, ReqAuth, EapId, RadId),
	NextEapId = EapId + 1,
	{NextEapId, _ServerID} = receive_radius_id(Socket, Address,
			Port, Secret, ReqAuth, RadId).

akap_identity_diameter() ->
   [{userdata, [{doc, "Send an EAP-Identity/Response using DIAMETER"}]}].

akap_identity_diameter(Config) ->
	Ref = erlang:ref_to_list(make_ref()),
	SId = diameter:session_id(Ref),
	EapId = 1,
	Realm = ?config(realm, Config),
	MSIN = msin(),
	PeerId = "6" ++ ct:get_config(mcc) ++ ct:get_config(mcc)
			++ MSIN ++ "@wlan." ++ Realm,
	PeerId1 = list_to_binary(PeerId),
	DEA = send_diameter_identity(SId, EapId, PeerId1),
	SIdbin = list_to_binary(SId),
	#diameter_eap_app_DEA{'Session-Id' = SIdbin, 'Auth-Application-Id' = ?EAP_APPLICATION_ID,
			'Auth-Request-Type' =  ?'DIAMETER_BASE_AUTH-REQUEST-TYPE_AUTHORIZE_AUTHENTICATE',
			'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_MULTI_ROUND_AUTH',
			'EAP-Payload' = [Payload]} = DEA,
	NextEapId = EapId + 1,
	#eap_packet{code = request, type = ?AKAprime, identifier = NextEapId,
			data = _EapData} = ocs_eap_codec:eap_packet(Payload).

akap_identity_radius_trusted() ->
   [{userdata, [{doc, "Send an trusted EAP-Identity/Response using RADIUS"}]}].

akap_identity_radius_trusted(Config) ->
	Socket = ?config(socket, Config),
	{ok, RadiusConfig} = application:get_env(ocs, radius),
	{auth, [{Address, Port, _} | _]} = lists:keyfind(auth, 1, RadiusConfig),
	NasId = ?config(nas_id, Config),
	ReqAuth = radius:authenticator(),
	RadId = 1, EapId = 1,
	Secret = ct:get_config(radius_shared_secret),
	Realm = ?config(realm, Config),
	MSIN = msin(),
	Name = ct:get_config(mcc) ++ ct:get_config(mcc) ++ MSIN,
	PeerId = "6" ++ Name ++ "@wlan." ++ Realm,
	PeerId1 = list_to_binary(PeerId),
	P1 = price(usage, octets, rand:uniform(1000000), rand:uniform(100)),
	OfferId = add_offer([P1], 4),
	ProdRef = add_product(OfferId),
	#service{password = #aka_cred{k = K, opc = OPc, dif = DIF}} = add_service(Name, ProdRef),
	ok = send_radius_identity(Socket, Address, Port, NasId,
			PeerId1, Secret, ReqAuth, EapId, RadId),
	EapMsg = radius_access_challenge(Socket, Address, Port,
			Secret, RadId, ReqAuth),
	#eap_packet{code = request, type = ?AKAprime, identifier = _EapID,
			data = EapData} = ocs_eap_codec:eap_packet(EapMsg),
	#eap_aka_challenge{rand = RAND, autn = _AUTN, mac = MAC} = ocs_eap_codec:eap_aka(EapData),
	{_XRES, CK, IK, <<AK:48>>} = ocs_milenage:f2345(OPc, K, RAND),
	SQN = sqn(DIF),
	<<CKprime:16/binary, IKprime:16/binary>> = kdf(CK, IK, "WLAN", SQN, AK),
	<<_:16/binary, Kaut:32/binary, _:32/binary, _:64/binary,
                        _:64/binary, _/binary>> = prf(<<IKprime/binary,
	CKprime/binary>>, <<"EAP-AKA'", PeerId1/binary>>, 7),
	EapMsg1 = ocs_eap_codec:aka_clear_mac(EapMsg),
	MAC = crypto:hmac(sha256, Kaut, EapMsg1, 16),
	RAND1 = ocs_milenage:f0(),
	{RES, CK1, IK1, <<AK1:48>>} = ocs_milenage:f2345(OPc, K, RAND1),
	SQN1 = sqn(DIF),
	<<CKprime1:16/binary, IKprime1:16/binary>> = kdf(CK1, IK1, "WLAN", SQN1, AK1),
	AkaChallenge = #eap_aka_challenge{res = RES, mac = <<0:128>>},
	<<_:16/binary, Kaut1:32/binary, _:32/binary, _:64/binary,
		_:64/binary, _/binary>> = prf(<<IKprime1/binary,
		CKprime1/binary>>, <<"EAP-AKA'", PeerId1/binary>>, 7),
	EapData1 = ocs_eap_codec:eap_aka(AkaChallenge),
	NextEapId1 = EapId + 1,
	EapPacket1 = #eap_packet{code = request, type = ?AKAprime,
			identifier = NextEapId1, data = EapData1},
	EapMessage1 = ocs_eap_codec:eap_packet(EapPacket1),
	MAC1 = crypto:hmac(sha256, Kaut1, EapMessage1, 16),
	EapMessage2 = ocs_eap_codec:aka_set_mac(MAC1, EapMessage1),
	ok = send_radius_identity(Socket, Address, Port, NasId,
			PeerId1, Secret, ReqAuth, EapId, RadId),
	ok = gen_udp:send(Socket, Address, Port, EapMessage2),
	{ok, {Address, Port, _RespPacket1}} = gen_udp:recv(Socket, 0).

akap_identity_diameter_trusted() ->
   [{userdata, [{doc, "Send an EAP-Identity/Response using DIAMETER"}]}].

akap_identity_diameter_trusted(Config) ->
	Ref = erlang:ref_to_list(make_ref()),
	SId = diameter:session_id(Ref),
	EapId = 1,
	Realm = ?config(realm, Config),
	MSIN = msin(),
	Name = ct:get_config(mcc) ++ ct:get_config(mcc) ++ MSIN,
	PeerId = "6" ++ Name ++ "@wlan." ++ Realm,
	PeerId1 = list_to_binary(PeerId),
	P1 = price(usage, octets, rand:uniform(1000000), rand:uniform(100)),
	OfferId = add_offer([P1], 4),
	ProdRef = add_product(OfferId),
	_Service = add_service(Name, ProdRef),
	DEA = send_diameter_identity(SId, EapId, PeerId1),
	SIdbin = list_to_binary(SId),
	#diameter_eap_app_DEA{'Session-Id' = SIdbin, 'Auth-Application-Id' = ?EAP_APPLICATION_ID,
			'Auth-Request-Type' =  ?'DIAMETER_BASE_AUTH-REQUEST-TYPE_AUTHORIZE_AUTHENTICATE',
			'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_MULTI_ROUND_AUTH',
			'EAP-Payload' = [Payload]} = DEA,
	NextEapId = EapId + 1,
	#eap_packet{code = request, type = ?AKAprime, identifier = NextEapId,
			data = _EapData} = ocs_eap_codec:eap_packet(Payload).

akap_identity_radius_no_client() ->
   [{userdata, [{doc, "Send an EAP-Identity/Response using RADIUS"}]}].

akap_identity_radius_no_client(Config) ->
	Socket = ?config(socket, Config),
	{ok, RadiusConfig} = application:get_env(ocs, radius),
	{auth, [{Address, Port, _} | _]} = lists:keyfind(auth, 1, RadiusConfig),
	NasId = ?config(nas_id, Config),
	ReqAuth = radius:authenticator(),
	RadId = 1, EapId = 1,
	Secret = ct:get_config(radius_shared_secret),
	Realm = ?config(realm, Config),
	MSIN = msin(),
	PeerId = "6" ++ ct:get_config(mcc) ++ ct:get_config(mcc) ++ MSIN ++ "@wlan." ++ Realm,
	PeerId1 = list_to_binary(PeerId),
	ok = send_radius_identity(Socket, Address, Port, NasId,
			PeerId1, Secret, ReqAuth, EapId, RadId),
	{error,timeout} = gen_udp:recv(Socket, 0, 5000).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

%% @hidden
client_service_opts(Config) ->
	[{'Origin-Host', ?config(host, Config)},
			{'Origin-Realm', ?config(realm, Config)},
			{'Vendor-Id', ?IANA_PEN_SigScale},
			{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
			{'Product-Name', "SigScale Test Client (auth)"},
			{'Auth-Application-Id', [?BASE_APPLICATION_ID, ?EAP_APPLICATION_ID]},
			{string_decode, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, diameter_test_client_cb}]},
			{application, [{alias, eap_app_test},
					{dictionary, diameter_gen_eap_application_rfc4072},
					{module, diameter_test_client_cb}]}].

%% @doc Add a transport capability to diameter service.
%% @hidden
connect(SvcName, Address, Port, Transport) when is_atom(Transport) ->
	connect(SvcName, [{connect_timer, 30000} | transport_opts(Address, Port, Transport)]).

%% @hidden
connect(SvcName, Opts)->
	diameter:add_transport(SvcName, {connect, Opts}).

%% @hidden
transport_opts(Address, Port, Trans) when is_atom(Trans) ->
	transport_opts1({Trans, Address, Address, Port}).

%% @hidden
transport_opts1({Trans, LocalAddr, RemAddr, RemPort}) ->
	[{transport_module, Trans}, {transport_config,
			[{raddr, RemAddr}, {rport, RemPort},
			{reuseaddr, true}, {ip, LocalAddr}]}].

%% @hidden
radius_access_request(Socket, Address, Port, NasId,
		UserName, Secret, Auth, RadId, EapMsg)
		when is_binary(UserName) ->
	radius_access_request(Socket, Address, Port, NasId,
			binary_to_list(UserName), Secret, Auth, RadId, EapMsg);
radius_access_request(Socket, Address, Port, NasId,
		UserName, Secret, Auth, RadId, EapMsg) ->
	A0 = radius_attributes:new(),
	A1 = radius_attributes:add(?UserName, UserName, A0),
	A2 = radius_attributes:add(?NasPortType, 19, A1),
	A3 = radius_attributes:add(?NasIdentifier, NasId, A2),
	A4 = radius_attributes:add(?CallingStationId, mac(), A3),
	A5 = radius_attributes:add(?CalledStationId, mac(), A4),
	A6 = radius_attributes:add(?EAPMessage, EapMsg, A5),
	A7 = radius_attributes:add(?MessageAuthenticator, <<0:128>>, A6),
	Request1 = #radius{code = ?AccessRequest, id = RadId,
		authenticator = Auth, attributes = A7},
	ReqPacket1 = radius:codec(Request1),
	MsgAuth1 = crypto:hmac(md5, Secret, ReqPacket1),
	A8 = radius_attributes:store(?MessageAuthenticator, MsgAuth1, A7),
	Request2 = Request1#radius{attributes = A8},
	ReqPacket2 = radius:codec(Request2),
	gen_udp:send(Socket, Address, Port, ReqPacket2).

radius_access_challenge(Socket, Address, Port, Secret, RadId, ReqAuth) ->
	receive_radius(?AccessChallenge, Socket, Address, Port, Secret, RadId, ReqAuth).

radius_access_accept(Socket, Address, Port, Secret, RadId, ReqAuth) ->
	receive_radius(?AccessAccept, Socket, Address, Port, Secret, RadId, ReqAuth).

radius_access_reject(Socket, Address, Port, Secret, RadId, ReqAuth) ->
	receive_radius(?AccessReject, Socket, Address, Port, Secret, RadId, ReqAuth).

receive_radius(Code, Socket, Address, Port, Secret, RadId, ReqAuth) ->
	{ok, {Address, Port, RespPacket1}} = gen_udp:recv(Socket, 0),
	Resp1 = radius:codec(RespPacket1),
	#radius{code = Code, id = RadId, authenticator = RespAuth,
			attributes = BinRespAttr1} = Resp1,
	Resp2 = Resp1#radius{authenticator = ReqAuth},
	RespPacket2 = radius:codec(Resp2),
	RespAuth = binary_to_list(crypto:hash(md5, [RespPacket2, Secret])),
	RespAttr1 = radius_attributes:codec(BinRespAttr1),
	{ok, MsgAuth} = radius_attributes:find(?MessageAuthenticator, RespAttr1),
	RespAttr2 = radius_attributes:store(?MessageAuthenticator, <<0:128>>, RespAttr1),
	Resp3 = Resp2#radius{attributes = RespAttr2},
	RespPacket3 = radius:codec(Resp3),
	MsgAuth = crypto:hmac(md5, Secret, RespPacket3),
	{ok, EapMsg} = radius_attributes:find(?EAPMessage, RespAttr1),
	EapMsg.

%% @hidden
receive_radius_id(Socket, Address, Port, Secret, ReqAuth, RadId) ->
	EapMsg = radius_access_challenge(Socket, Address, Port,
			Secret, RadId, ReqAuth),
	#eap_packet{code = request, type = ?AKAprime, identifier = EapId,
			data = EapData} = ocs_eap_codec:eap_packet(EapMsg),
	#eap_aka_identity{permanent_id_req = false,
			any_id_req = false,fullauth_id_req = true,
			identity = ServerId} = ocs_eap_codec:eap_aka(EapData),
	{EapId, ServerId}.

%% @hidden
send_radius_identity(Socket, Address, Port, NasId,
		PeerId, Secret, Auth, EapId, RadId) ->
	EapPacket  = #eap_packet{code = response, type = ?Identity,
			identifier = EapId, data = PeerId},
	EapMsg = ocs_eap_codec:eap_packet(EapPacket),
	radius_access_request(Socket, Address, Port, NasId,
			PeerId, Secret, Auth, RadId, EapMsg).

%% @hidden
send_diameter_identity(SId, EapId, PeerId) ->
	EapPacket  = #eap_packet{code = response, type = ?Identity,
			identifier = EapId, data = PeerId},
	EapMsg = ocs_eap_codec:eap_packet(EapPacket),
	DER = #diameter_eap_app_DER{'Session-Id' = SId,
			'Auth-Application-Id' = ?EAP_APPLICATION_ID,
			'Auth-Request-Type' = ?'DIAMETER_BASE_AUTH-REQUEST-TYPE_AUTHORIZE_AUTHENTICATE',
			'EAP-Payload' = EapMsg},
	{ok, Answer} = diameter:call(?MODULE, eap_app_test, DER, []),
	Answer.

%% @hidden
mac() ->
	mac([]).
%% @hidden
mac(Acc) when length(Acc) =:= 12 ->
	Acc;
mac(Acc) ->
	mac([integer_to_list(rand:uniform(255), 16) | Acc]).

-spec msin(Length) -> string()
	when
		Length :: pos_integer().
%% @doc Generate a random mobile subscription identification number (MSIN).
%% @private
msin() ->
	msin([]).
%% @hidden
msin(Acc) when length(Acc) =:= 10 ->
	Acc;
msin(Acc) ->
	msin([rand:uniform(10) + 47 | Acc]).

%% @hidden
price(Type, Units, Size, Amount) ->
	Name = ocs:generate_identity(),
	#price{name = Name,
			type = Type, units = Units,
			size = Size, amount = Amount}.

%% @hidden
add_offer(Prices, Spec) when is_integer(Spec) ->
	add_offer(Prices, integer_to_list(Spec));
add_offer(Prices, Spec) ->
	Name = ocs:generate_identity(),
	Offer = #offer{name = Name,
			price = Prices, specification = Spec},
	{ok, #offer{name = OfferId}} = ocs:add_offer(Offer),
	OfferId.

%% @hidden
add_product(OfferId) ->
	add_product(OfferId, []).
add_product(OfferId, Chars) ->
	{ok, #product{id = ProdRef}} = ocs:add_product(OfferId, Chars),
	ProdRef.

%% @hidden
add_service(Name, ProdRef) ->
	K = crypto:strong_rand_bytes(16),
	OPc = crypto:strong_rand_bytes(16),
	Credentials = #aka_cred{k = K, opc = OPc},
	{ok, Service} = ocs:add_service(Name, Credentials,
			ProdRef, []),
	Service.

-spec sqn(DIF) -> SQN
	when
		DIF :: integer(),
		SQN :: integer().
%% @doc Sequence Number (SQN).
%%
%%      3GPP RTS 33.102 Annex C.1.1.3.
%% @private
sqn(DIF) when is_integer(DIF) ->
	(erlang:system_time(10) - DIF) bsl 5.

-spec amf() -> AMF
	when
		AMF :: binary().
%% @doc Authentication Management Field (AMF).
%%
%%      See 3GPP TS 33.102 Annex F.
%% @private
amf() ->
	<<1:1, 0:15>>.

-spec kdf(CK, IK, ANID, SQN, AK) -> MSK
        when
                CK :: binary(),
                IK :: binary(),
                ANID :: string(),
                SQN :: integer(),
                AK :: integer(),
                MSK :: binary().
%% @doc Key Derivation Function (KDF).
%%
%%      See 3GPP TS 33.402 Annex A,
%%          3GPP TS 32.220 Annex B.
%% @private
kdf(CK, IK, "WLAN", SQN, AK)
		when byte_size(CK) =:= 16, byte_size(IK) =:= 16,
		is_integer(SQN), is_integer(AK) ->
	SQNi = SQN bxor AK,
	crypto:hmac(sha256, <<CK/binary, IK/binary>>,
			<<16#20, "WLAN", 4:16, SQNi:48, 6:16>>).

-spec prf(K, S, N) -> MK
	when
		K :: binary(),
		S :: binary(),
		N :: pos_integer(),
		MK :: binary().
%% @doc Pseudo-RANDom Number Function (PRF).
%%
%%      See RFC5448 3.4.
%% @private
prf(K, S, N) when is_binary(K), is_binary(S), is_integer(N), N > 1 ->
	prf(K, S, N, 1, <<>>, []).
%% @hidden
prf(_, _, N, P, _, Acc) when P > N ->
	iolist_to_binary(lists:reverse(Acc));
prf(K, S, N, P, T1, Acc) ->
	T2 = crypto:hmac(sha256, K, <<T1/binary, S/binary, P>>),
	prf(K, S, N, P + 1, T2, [T2 | Acc]).

-spec autn(SQN, AK, AMF, MAC) -> AUTN
	when
		SQN :: integer(),
		AK :: integer(),
		AMF :: binary(),
		MAC :: binary(),
		AUTN :: binary().
%% @doc Network Authentication Token (AUTN).
%%
%% @private
autn(SQN, AK, AMF, MAC)
		when is_integer(SQN), is_integer(AK),
		byte_size(AMF) =:= 2, byte_size(MAC) =:= 8 ->
	SQNa = SQN bxor AK,
	<<SQNa:48, AMF/binary, MAC/binary>>.

