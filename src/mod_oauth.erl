%%% mod_oauth.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2020 SigScale Global Inc.
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
%%%

-module(mod_oauth).
-copyright('Copyright (c) 2016 - 2020 SigScale Global Inc.').

%% The functions that the webbserver call on startup stop
%% and when the server traverse the modules.
-export([do/1, load/2, store/2]).

-include_lib("inets/include/httpd.hrl").
-include_lib("inets/include/mod_auth.hrl").
-include_lib("inets/src/http_server/httpd_internal.hrl").
-include_lib("public_key/include/public_key.hrl").

%%----------------------------------------------------------------------
%%  The mod_oauth API
%%----------------------------------------------------------------------

do(#mod{data = Data} = Info) ->
	case lists:keyfind(status, 1, Data) of
		false ->
erlang:display({?MODULE, ?LINE}),
			case lists:keyfind(response, 1, Data) of
				false ->
erlang:display({?MODULE, ?LINE}),
					do1(Data, Info);
				_ ->
erlang:display({?MODULE, ?LINE}),
					{proceed, Data}
			end;
		{_StatusCode, _PhraseArgs, _Reason} ->
erlang:display({?MODULE, ?LINE}),
			{proceed, Data}
	end.
do1(Data, #mod{config_db = ConfigDb,
		request_uri= RequestUri} = Info) ->
erlang:display({?MODULE, ?LINE}),
	Path = mod_alias:path(Data, ConfigDb, RequestUri),
	case directory_path(Path, ConfigDb) of
		{yes, {Directory, DirectoryData}} ->
erlang:display({?MODULE, ?LINE}),
			case proplists:get_value(auth_type, DirectoryData) of
				undefined ->
erlang:display({?MODULE, ?LINE}),
					{proceed, Data};
				none ->
erlang:display({?MODULE, ?LINE}),
					{proceed, Data};
				AuthType ->
erlang:display({?MODULE, ?LINE}),
					handle_auth(Info, Directory, DirectoryData, AuthType)
			end;
		no ->
erlang:display({?MODULE, ?LINE}),
			{proceed, Data}
	end.

-spec load(Directory, DirectoryData) -> Result
	when
		Directory :: string(),
		DirectoryData :: [tuple()],
		Result ::  {ok, NewDirectoryData} | {error, Reason},
		Reason :: term(),
		NewDirectoryData :: [tuple()].
%% @doc Look up a directory and set a new context.
load(Directory, DirectoryData)
		when is_list(Directory), is_list(DirectoryData) ->
erlang:display({?MODULE, ?LINE}),
	mod_auth:load(Directory, DirectoryData).

-spec store(Options, Config) -> Result
	when
		Options :: {Option, Value},
		Config :: [{Option, Value}],
		Option :: atom(),
		Value :: term(),
		Result :: {ok, {Option, NewValue}} | {error, Reason},
		NewValue :: term(),
		Reason :: term().
%% @doc Check the validity of configuration options and save them in the internal database
store({oauth_key, Value}, _ConfigList)
		when is_list(Value) ->
erlang:display({?MODULE, ?LINE}),
	case file:read_file(Value) of
		{ok, PemBin} ->
erlang:display({?MODULE, ?LINE}),
			store1(public_key:pem_decode(PemBin));
		{error, Reason} ->
erlang:display({?MODULE, ?LINE}),
			{error, Reason}
end;
store({oauth_key, #'RSAPublicKey'{} = Value}, _ConfigList) ->
	{ok, {oauth_key, Value}};
store(Options, ConfigList) ->
	mod_auth:store(Options, ConfigList).

%% @hidden
store1([{'Certificate', DerCert, _}]) ->
	case public_key:pkix_decode_cert(DerCert, otp) of
		#'OTPCertificate'{tbsCertificate = TbsCert}  ->
			SubPublicKeyInfo = TbsCert#'OTPTBSCertificate'.subjectPublicKeyInfo,
			NewValue = SubPublicKeyInfo#'OTPSubjectPublicKeyInfo'.subjectPublicKey,
			application:set_env(ocs, oauth_key, NewValue),
			{ok, {oauth_key, NewValue}};
		_ ->
			{error, invalid_pem_entry}
	end;
store1([#'RSAPublicKey'{} = RSAPubEntry]) ->
	case public_key:pem_entry_decode(RSAPubEntry) of
		#'RSAPublicKey'{} = RSAPublicKey ->
			application:set_env(ocs, oauth_key, RSAPublicKey),
			{ok, {oauth_key, RSAPublicKey}};
		_ ->
			{error, invalid_pem_entry}
	end.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

-spec handle_auth(Info, Directory, DirectoryData, AuthType) -> Result
	when
		Info :: #mod{},
		Directory :: string(),
		DirectoryData :: [tuple],
		AuthType :: plain | mnesia | dets,
		Result :: {proceed, #mod{}}.
handle_auth(#mod{data = Data, config_db = ConfigDb} = Info,
		Directory, DirectoryData, _AuthType) ->
erlang:display({?MODULE, ?LINE}),
	case require(Info, Directory, DirectoryData) of
		authorized ->
erlang:display({?MODULE, ?LINE}),
			{proceed, Data};
		{authorized, User} ->
erlang:display({?MODULE, ?LINE}),
			{proceed, [{remote_user, User} | Data]};
		{authorization_required, Realm} ->
erlang:display({?MODULE, ?LINE}),
			Message = httpd_util:message(401, none, ConfigDb),
			{proceed,
					[{response, {401, ["WWW-Authenticate: Bearer realm=\"",Realm,
					"\"\r\n\r\n","<HTML>\n<HEAD>\n<TITLE>", "Unauthorized","</TITLE>\n",
					"</HEAD>\n<BODY>\n<H1>","Unauthorized",
					"</H1>\n",Message,"\n</BODY>\n</HTML>\n"]}} | Data]};
		{status, {StatusCode, PhraseArgs, Reason}} ->
			{proceed, [{status, {StatusCode, PhraseArgs, Reason}} | Data]}
	end.

require(#mod{parsed_header = ParsedHeader} = Info, Directory, DirectoryData) ->
erlang:display({?MODULE, ?LINE}),
erlang:display({?MODULE, ?LINE, lists:keyfind(require_user, 1, DirectoryData)}),
	ValidUsers  = proplists:get_value(require_user, DirectoryData),
	ValidGroups = proplists:get_value(require_group, DirectoryData),
erlang:display({?MODULE, ?LINE}),
	case ValidGroups of
		undefined when ValidUsers =:= undefined ->
			authorized;
		_ ->
erlang:display({?MODULE, ?LINE}),
			case proplists:get_value("authorization", ParsedHeader) of
				false ->
erlang:display({?MODULE, ?LINE}),
					authorization_required(DirectoryData);
				"Bearer" ++ EncodedString = Credentials ->
					case string:tokens(EncodedString, ".") of
						[EncodedHeader, EncodedPayload, EncodedSignature] ->
erlang:display({?MODULE, ?LINE}),
							require1(Info, Directory, DirectoryData, ValidUsers, ValidGroups,
									EncodedHeader, EncodedPayload, EncodedSignature);
						_ ->
							{status, {401, none, "mod_oauth : " ++ "Bad credentials" ++ Credentials}}
					end;
				BadCredentials ->
					{status, {401, none, "mod_auth : " ++ "Bad credentials" ++ BadCredentials}}
			end
	end.
%% @hidden
require1(Info, Directory, DirectoryData, ValidUsers, ValidGroups,
		EncodedHeader, EncodedPayload, EncodedSignature)
		when is_list(EncodedHeader), is_list(EncodedPayload), is_list(EncodedSignature) ->
erlang:display({?MODULE, ?LINE}),
	case validate_header(EncodedHeader) of
	{valid, _DecodedHeader} ->
erlang:display({?MODULE, ?LINE}),
		case validate_payload(EncodedPayload) of
		{valid, DecodedPayload} ->
erlang:display({?MODULE, ?LINE}),
			case validate_cert(EncodedHeader, EncodedPayload, EncodedSignature) of
					authenticated ->
erlang:display({?MODULE, ?LINE}),
						validate_user(Info, Directory, DirectoryData,
								ValidUsers, ValidGroups, DecodedPayload);
					{error, _Reason} ->
erlang:display({?MODULE, ?LINE}),
						authorization_required(DirectoryData)
			end;
		{error, _Reason} ->
			authorization_required(DirectoryData)
		end;
	{error, _Reason} ->
		authorization_required(DirectoryData)
	end.

%% @hidden
authorization_required(DirectoryData) ->
	case lists:keyfind(auth_name, 1, DirectoryData) of
		false ->
			{status, {500, none, "mod_auth : " ++ "AuthName directive not specified"}};
		Realm ->
			{authorization_required, Realm}
	end.

-spec validate_cert(EncodedHeader, EncodedPayLoad, EncodedSignature) -> Result
	when
		EncodedHeader :: string(),
		EncodedPayLoad :: string(),
		EncodedSignature :: string(),
		Result :: authenticated | {error, Reason},
		Reason :: term().
%% @doc Validate a JWT certificate.
validate_cert(EncodedHeader, EncodedPayLoad, EncodedSignature) ->
		DecodedSignature = decode_base64url(EncodedSignature),
		validate_cert1(EncodedHeader, EncodedPayLoad, iolist_to_binary(DecodedSignature)).
%% @hidden
validate_cert1(EncodedHeader, EncodedPayLoad, DecodedSignature)
		when is_binary(DecodedSignature), DecodedSignature =/= <<>> ->
	try
		{ok, Value} = application:get_env(ocs, oauth_key),
		{ok, {_, RSAPublicKey}} = store({oauth_key, Value}, []),
		Msg = iolist_to_binary([string:strip(EncodedHeader, left), <<".">>, EncodedPayLoad]),
		public_key:verify(Msg, sha256, DecodedSignature, RSAPublicKey)
	of
		true ->
			authenticated;
		false ->
			{error, not_authenticated}
	catch
		_:Reason ->
			{error, Reason}
	end;
validate_cert1(_, _, _DecodedSignature) ->
	{error, invalid}.

-spec validate_payload(EncodedPayload) -> Result
	when
		EncodedPayload :: string(),
		Result :: {valid, DecodedPayload} | {error, Reason},
		DecodedPayload :: map(),
		Reason :: term().
%% @doc Validate a JWT payload.
validate_payload(EncodedPayload) ->
		{ok, DecodedPayLoad} = zj:decode(decode_base64url(EncodedPayload)),
		validate_payload1(DecodedPayLoad).
%% @hidden
validate_payload1(#{"aud" := AudList, "iss" := Iss, "exp" := Exp} = DecodedPayload)
		when is_list(AudList), is_list(Iss) ->
	try
		{ok, Aud} = application:get_env(ocs, oauth_audience),
		true = check_aud(Aud, AudList),
		{ok, IssValue} = application:get_env(ocs, oauth_issuer),
		true = IssValue == Iss,
		Exp < os:system_time(seconds)
	of
		true ->
			{valid, DecodedPayload};
		false ->
			{error, invalid}
	catch
		_:Reason ->
			{error, Reason}
	end;
validate_payload1(_DecodedPayload) ->
	{error, invalid}.

%% @hidden
check_aud(_Aud, []) ->
	false;
check_aud(Aud, AudList) ->
	case lists:member(Aud, AudList) of
		true ->
			true;
		false ->
			Aud == AudList
	end.

-spec validate_header(EncodedHeader) -> Result
	when
		EncodedHeader :: string(),
		Result :: {valid, DecodedPayload} | {error, Reason},
		DecodedPayload :: map(),
		Reason :: term().
%% @doc Validate a JWT header.
validate_header(EncodedHeader) ->
	EncodedHeader1 = string:strip(EncodedHeader, left),
	{ok, DecodedHeader} = zj:decode(decode_base64url(EncodedHeader1)),
	validate_header1(DecodedHeader).
%% @hidden
validate_header1(#{"alg" := "RS256", "typ" := "JWT"} = DecodedHeader) ->
	{valid, DecodedHeader};
validate_header1(_DecodedHeader) ->
	{error, invalid}.

-spec validate_user(Info, Directory, DirectoryData,
		ValidUsers, ValidGroups, DecodedPayload) -> Result
	when
		Info :: #mod{},
		Directory :: string(),
		DirectoryData :: [tuple()],
		ValidUsers :: list(),
		ValidGroups :: list(),
		DecodedPayload :: map(),
		Result :: {authorized, User} | {authorization_required, Reason} |
				{'status',{StatusCode ,none, Reason}},
		StatusCode :: integer(),
		User :: string(),
		Reason :: term().
validate_user(Info, Directory, DirectoryData,
		ValidUsers, ValidGroups, #{"email" := Email}) when is_list(Email) ->
erlang:display({?MODULE, ?LINE}),
	case user_accepted(Email, ValidUsers) of
		true ->
erlang:display({?MODULE, ?LINE}),
			{yes, Email};
		false ->
erlang:display({?MODULE, ?LINE}),
			case user_group_check(Info, Email,
					ValidGroups, Directory,  DirectoryData) of
				true ->
erlang:display({?MODULE, ?LINE}),
					{authorized, Email};
				false ->
erlang:display({?MODULE, ?LINE}),
					authorization_required(DirectoryData)
			end
	end;
validate_user(Info, Directory, DirectoryData,
		ValidUsers, ValidGroups, #{"preferred_username" := PrefUserName})
		when is_list(PrefUserName) ->
erlang:display({?MODULE, ?LINE, PrefUserName, ValidUsers}),
	case user_accepted(PrefUserName, ValidUsers) of
		true ->
erlang:display({?MODULE, ?LINE}),
			{yes, PrefUserName};
		false ->
erlang:display({?MODULE, ?LINE}),
			case user_group_check(Info, PrefUserName,
					ValidGroups, Directory, DirectoryData) of
				true ->
erlang:display({?MODULE, ?LINE}),
					{authorized, PrefUserName};
				_ ->
erlang:display({?MODULE, ?LINE}),
					authorization_required(DirectoryData)
			end
	end.

%% @hidden
user_accepted(_User, undefined) ->
	false;
user_accepted(User, ValidUsers) ->
	lists:member(User, ValidUsers).

-spec user_group_check(Info, User, UserGroups,
		Directory, DirectoryData) -> Result
	when
		Info :: #mod{},
		User :: string(),
		UserGroups :: list(),
		Directory :: string(),
		DirectoryData :: [tuple()],
		Result :: true | false.
user_group_check(_Info, _User, undefined,
		_Directory, _DirectoryData) ->
	false;
user_group_check(_Info, _User, [],
		_Directory, _DirectoryData) ->
	false;
user_group_check(Info, User, [Group | Rest],
		Directory, DirectoryData) ->
	case get_user_list(DirectoryData, Group) of
		{ok, UserList} ->
			case lists:member(User, UserList) of
				true ->
					true;
				false ->
					user_group_check(Info, User, Rest,
							Directory, DirectoryData)
				end;
		_ ->
			false
	end.

-spec get_user_list(DirectoryData, Group) -> Result
	when
		DirectoryData :: [tuple()],
		Group :: string(),
		Result :: {ok, UserList} | {error, Reason},
		UserList :: list(),
		Reason :: term().
get_user_list(DirectoryData, Group) ->
	case lists:keyfind(auth_type, 1, DirectoryData) of
		{auth_type, plain} ->
			mod_auth_plain:list_group_members(DirectoryData, Group);
		{auth_type, mnesia} ->
			mod_auth_mnesia:list_group_members(DirectoryData, Group);
		{auth_type, dets} ->
			mod_auth_dets:list_group_members(DirectoryData, Group)
	end.

-spec decode_base64url(EncodedValue) -> DecodedValue
	when
		EncodedValue :: string(),
		DecodedValue :: list().
%% @doc Decode a base64url encoded value.
decode_base64url(EncodedValue)
		when is_list(EncodedValue) ->
	EncodedValue1 = sub_chars(EncodedValue),
	base64:decode_to_string(EncodedValue1).

%% @hidden
sub_chars(List) ->
	case length(List) rem 4 of
		2 ->
			sub_chars1(List ++ "==", []);
		3 ->
			sub_chars1(List ++ "=", []);
		_ ->
			sub_chars1(List, [])
	end.

%% @hidden
sub_chars1([$_ | T], Acc) ->
	sub_chars1(T, [$/ | Acc]);
sub_chars1([$- | T], Acc) ->
	sub_chars1(T, [$+ | Acc]);
sub_chars1([H | T], Acc) ->
	sub_chars1(T, [H | Acc]);
sub_chars1([], Acc) ->
	lists:reverse(Acc).

-spec directory_path(Path, ConfigDb) -> Result
	when
		Path :: string(),
		ConfigDb :: term(),
		Result :: {yes, Directory} | no,
		Directory :: list().
%% @doc Look up the configuration directory.
directory_path(Path, ConfigDB)
		when is_list(Path) ->
	Directories = ets:match(ConfigDB,{directory, {'$1','_'}}),
	case path_check(Path, lists:usort(Directories)) of
		{yes,Directory} ->
			{yes, {Directory,
					lists:flatten(ets:match(ConfigDB,{directory, {Directory,'$1'}}))}};
		no ->
			no
	end.
	
%% @hidden
path_check(_Path, []) ->
	no;
path_check(Path, Directories) ->
	List = convert(Path, Directories, []),
	F = fun(A, B)
			when length(A) > length(B) ->
			true;
		(_A, _B) ->
			false
	end,
	[{_, Directory} | _] = lists:sort(F, List),
	{yes, Directory}.
			
%% @hidden
convert(Path,[[H] | T], Acc) ->
	convert(Path, T, [{Path, H} | Acc]);
convert(Path, [], Acc) ->
	[{Path, []} | Acc].

