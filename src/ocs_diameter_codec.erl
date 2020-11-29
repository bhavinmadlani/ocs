%%% ocs_diameter_codec.erl 
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2020 SigScale Global Inc.
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
%%% @doc This library module performs specialized CODEC functions
%%% 	for DIAMETER in the {@link //ocs. ocs} application.
%%%
-module(ocs_diameter_codec).
-copyright('Copyright (c) 2020 SigScale Global Inc.').

-export(['APN-Configuration'/3, 'APN-Configuration'/4,
		'EPS-Subscribed-QoS-Profile'/3, 'EPS-Subscribed-QoS-Profile'/4,
		'AMBR'/3, 'AMBR'/4, 'Specific-APN-Info'/3, 'Specific-APN-Info'/4,
		'WLAN-offloadability'/3, 'WLAN-offloadability'/4]).

-include("diameter_gen_3gpp_swm_application.hrl").

%%----------------------------------------------------------------------
%%  ocs_diameter_codec public API
%%----------------------------------------------------------------------

-spec 'APN-Configuration'(Operation, Type, Data) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Result :: {#'3gpp_swm_APN-Configuration'{}, list()}.
%% @doc Specialized CODEC for 3GPP APN-Configurationo (legacy API).
'APN-Configuration'(decode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'APN-Configuration', Data);
'APN-Configuration'(encode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'APN-Configuration', Data).

-spec 'APN-Configuration'(Operation, Type, Data, Opts) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Opts :: map(),
		Result :: {#'3gpp_swm_APN-Configuration'{}, list()}.
%% @doc Specialized CODEC for 3GPP APN-Configuration.
'APN-Configuration'(decode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'APN-Configuration', Data, Opts);
'APN-Configuration'(encode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'APN-Configuration', Data, Opts).

-spec 'EPS-Subscribed-QoS-Profile'(Operation, Type, Data) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Result :: {#'3gpp_swm_EPS-Subscribed-QoS-Profile'{}, list()}.
%% @doc Specialized CODEC for 3GPP EPS-Subscribed-QoS-Profile (legacy API).
'EPS-Subscribed-QoS-Profile'(decode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'EPS-Subscribed-QoS-Profile', Data);
'EPS-Subscribed-QoS-Profile'(encode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'EPS-Subscribed-QoS-Profile', Data).

-spec 'EPS-Subscribed-QoS-Profile'(Operation, Type, Data, Opts) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Opts :: map(),
		Result :: {#'3gpp_swm_EPS-Subscribed-QoS-Profile'{}, list()}.
%% @doc Specialized CODEC for 3GPP EPS-Subscribed-QoS-Profile.
'EPS-Subscribed-QoS-Profile'(decode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'EPS-Subscribed-QoS-Profile', Data, Opts);
'EPS-Subscribed-QoS-Profile'(encode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'EPS-Subscribed-QoS-Profile', Data, Opts).

-spec 'AMBR'(Operation, Type, Data) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Result :: {#'3gpp_swm_AMBR'{}, list()}.
%% @doc Specialized CODEC for 3GPP AMBR (legacy API).
'AMBR'(decode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'AMBR', Data);
'AMBR'(encode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'AMBR', Data).

-spec 'AMBR'(Operation, Type, Data, Opts) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Opts :: map(),
		Result :: {#'3gpp_swm_AMBR'{}, list()}.
%% @doc Specialized CODEC for 3GPP AMBR.
'AMBR'(decode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'AMBR', Data, Opts);
'AMBR'(encode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'AMBR', Data, Opts).

-spec 'Specific-APN-Info'(Operation, Type, Data) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Result :: {#'3gpp_swm_Specific-APN-Info'{}, list()}.
%% @doc Specialized CODEC for 3GPP Specific-APN-Info (legacy API).
'Specific-APN-Info'(decode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'Specific-APN-Info', Data);
'Specific-APN-Info'(encode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'Specific-APN-Info', Data).

-spec 'Specific-APN-Info'(Operation, Type, Data, Opts) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Opts :: map(),
		Result :: {#'3gpp_swm_Specific-APN-Info'{}, list()}.
%% @doc Specialized CODEC for 3GPP Specific-APN-Info.
'Specific-APN-Info'(decode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'Specific-APN-Info', Data, Opts);
'Specific-APN-Info'(encode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'Specific-APN-Info', Data, Opts).

-spec 'WLAN-offloadability'(Operation, Type, Data) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Result :: {#'3gpp_swm_WLAN-offloadability'{}, list()}.
%% @doc Specialized CODEC for 3GPP WLAN-offloadability (legacy API).
'WLAN-offloadability'(decode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'WLAN-offloadability', Data);
'WLAN-offloadability'(encode = Operation, 'Grouped' = _Type, Data) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'WLAN-offloadability', Data).

-spec 'WLAN-offloadability'(Operation, Type, Data, Opts) -> Result
	when
		Operation :: decode | encode,
		Type :: 'Grouped',
		Data :: binary(),
		Opts :: map(),
		Result :: {#'3gpp_swm_WLAN-offloadability'{}, list()}.
%% @doc Specialized CODEC for 3GPP WLAN-offloadability.
'WLAN-offloadability'(decode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swm_application,
	Mod:grouped_avp(Operation, 'WLAN-offloadability', Data, Opts);
'WLAN-offloadability'(encode = Operation, 'Grouped' = _Type, Data, Opts) ->
	Mod = diameter_gen_3gpp_swx_application,
	Mod:grouped_avp(Operation, 'WLAN-offloadability', Data, Opts).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

