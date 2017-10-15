%%% ocs_rest_res_product.erl
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
%%% @doc This library module implements resource handling functions
%%% 	for a REST server in the {@link //ocs. ocs} application.
%%%
-module(ocs_rest_res_product).
-copyright('Copyright (c) 2016 - 2017 SigScale Global Inc.').

-export([content_types_accepted/0, content_types_provided/0]).

-export([add_product_offering/1, add_product_inventory/1]).
-export([get_product_offering/1, get_product_offerings/2]).
-export([get_catalog/2, get_catalogs/1]).
-export([get_category/2, get_categories/1]).
-export([get_product_spec/2, get_product_specs/1]).

-include("ocs.hrl").

-define(offerPath, "/catalogManagement/v2/productOffering/").

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations accepted.
content_types_accepted() ->
	["application/json", "application/json-patch+json",
	"application/merge-patch+json"].

-spec content_types_provided() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations available.
content_types_provided() ->
	["application/json"].

-spec add_product_offering(ReqData) -> Result when
	ReqData	:: [tuple()],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 500 .
%% @doc Respond to `POST /catalogManagement/v2/productOffering'.
%% 	Add a new Product Offering.
add_product_offering(ReqData) ->
	try
		case ocs:add_product(offer(mochijson:decode(ReqData))) of
			{ok, ProductOffering} ->
				ProductOffering;
			{error, Reason} ->
				throw(Reason)
		end
	of
		Offer ->
			Body = mochijson:encode(offer(Offer)),
			Etag = ocs_rest:etag(Offer#product.last_modified),
			Href = ?offerPath ++ Offer#product.name,
			Headers = [{location, Href}, {etag, Etag}],
			{ok, Headers, Body}
	catch
		throw:_Reason ->
			{error, 500};
		_:_ ->
			{error, 400}
	end.

-spec add_product_inventory(ReqData) -> Result when
	ReqData	:: [tuple()],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 500 .
%% @doc Respond to `POST /productInventoryManagement/v2/product'.
%% 	Add a new instance of a Product Offering subscription.
add_product_inventory(ReqData) ->
	try
		{struct, Object} = mochijson:decode(ReqData),
		Headers = [{content_type, "application/json"}],
		{ok, Headers, []}
	catch
		_:_ ->
			{error, 400}
	end.

-spec get_product_offering(ID) -> Result when
	ID			:: string(),
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/productOffering/{id}'.
%% 	Retrieve a Product Offering.
get_product_offering(ID) ->
	try
		case ocs:find_product(ID) of
			{ok, ProductOffering} ->
				ProductOffering;
			{error, not_found} ->
				{throw, 404};
			{error, _} ->
				{throw, 500}
		end
	of
		Offer ->
			Body = mochijson:encode(offer(Offer)),
			Etag = ocs_rest:etag(Offer#product.last_modified),
			Href = ?offerPath ++ Offer#product.name,
			Headers = [{location, Href}, {etag, Etag}],
			{ok, Headers, Body}
	catch
		throw:_Reason ->
			{error, 500};
		_:_ ->
			{error, 400}
	end.

-spec get_product_offerings(Query, Headers) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 412 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/productOffering'.
%% 	Retrieve all Product Offerings.
%% @todo Filtering
get_product_offerings(Query, Headers) ->
	case lists:keytake("fields", 1, Query) of
		{value, {_, Filters}, NewQuery} ->
			get_product_offerings1(NewQuery, Filters, Headers);
		false ->
			get_product_offerings1(Query, [], Headers)
	end.
%% @hidden
get_product_offerings1(Query, Filters, Headers) ->
	case {lists:keyfind("if-match", 1, Headers),
			lists:keyfind("if-range", 1, Headers),
			lists:keyfind("range", 1, Headers)} of
		{{"if-match", Etag}, false, {"range", Range}} ->
			case global:whereis_name(Etag) of
				undefined ->
					{error, 412};
				PageServer ->
					case ocs_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_page(PageServer, Etag, Query, Filters, Start, End)
					end
			end;
		{{"if-match", Etag}, false, false} ->
			case global:whereis_name(Etag) of
				undefined ->
					{error, 412};
				PageServer ->
					query_page(PageServer, Etag, Query, Filters, undefined, undefined)
			end;
		{false, {"if-range", Etag}, {"range", Range}} ->
			case global:whereis_name(Etag) of
				undefined ->
					case ocs_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_start(Query, Filters, Start, End)
					end;
				PageServer ->
					case ocs_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_page(PageServer, Etag, Query, Filters, Start, End)
					end
			end;
		{{"if-match", _}, {"if-range", _}, _} ->
			{error, 400};
		{_, {"if-range", _}, false} ->
			{error, 400};
		{false, false, {"range", Range}} ->
			case ocs_rest:range(Range) of
				{error, _} ->
					{error, 400};
				{ok, {Start, End}} ->
					query_start(Query, Filters, Start, End)
			end;
		{false, false, false} ->
			query_start(Query, Filters, undefined, undefined)
	end.

-spec get_catalog(Id, Query) -> Result when
	Id :: string(),
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/catalog/{id}'.
%% 	Retrieve a catalog .
get_catalog("1", [] =  _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(product_catalog()),
	{ok, Headers, Body};
get_catalog(_Id,  [] = _Query) ->
	{error, 404};
get_catalog(_Id, _Query) ->
	{error, 400}.

-spec get_catalogs(Query) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/catalog'.
%% 	Retrieve all catalogs .
get_catalogs([] =  _Query) ->
	Headers = [{content_type, "application/json"}],
	Object = {array, [product_catalog()]},
	Body = mochijson:encode(Object),
	{ok, Headers, Body};
get_catalogs(_Query) ->
	{error, 400}.

-spec get_category(Id, Query) -> Result when
	Id :: string(),
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/category/{id}'.
%% 	Retrieve a category.
get_category("1", [] =  _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(prepaid_category()),
	{ok, Headers, Body};
get_category(_Id,  [] = _Query) ->
	{error, 404};
get_category(_Id, _Query) ->
	{error, 400}.

-spec get_categories(Query) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/catalog'.
%% 	Retrieve all catalogs .
get_categories([] =  _Query) ->
	Headers = [{content_type, "application/json"}],
	Object = {array, [prepaid_category()]},
	Body = mochijson:encode(Object),
	{ok, Headers, Body};
get_categories(_Query) ->
	{error, 400}.

-spec get_product_spec(Id, Query) -> Result when
	Id :: string(),
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManegment/v2/productSpecification/{id}'.
%% 	Retrieve a product specification.
get_product_spec("1", [] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(spec_product_network()),
	{ok, Headers, Body};
get_product_spec("2", [] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(spec_product_fixed_quantity_pkg()),
	{ok, Headers, Body};
get_product_spec("3", [] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(spec_product_rate_plane()),
	{ok, Headers, Body};
get_product_spec("4", [] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(spec_product_wlan()),
	{ok, Headers, Body};
get_product_spec(_Id, [] = _Query) ->
	{error, 404};
get_product_spec(_Id, _Query) ->
	{error, 400}.

-spec get_product_specs(Query) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManegment/v2/productSpecification'.
%% 	Retrieve all product specifications.
get_product_specs([] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Object = {array, [spec_product_network(),
					spec_product_fixed_quantity_pkg(),
					spec_product_rate_plane(),
					spec_product_wlan()]},
	Body = mochijson:encode(Object),
	{ok, Headers, Body};
get_product_specs(_Query) ->
	{error, 400}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
product_catalog() ->
	Id = {"id", "1"},
	Href = {"href", "/catalogManagement/v2/catalog/1"},
	Type = {"type", "Product Catalog"},
	Name = {"name", "SigScale OCS"},
	Status = {"lifecycleStatus", "Active"},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-04T00:00:00Z"},
	Category = {"category", {array, [prepaid_category()]}},
	{struct, [Id, Href, Type, Name, Status, Version, LastUpdate, Category]}.

%% @hidden
prepaid_category() ->
	Id = {"id", "1"},
	Href = {"href", "/catalogManagement/v2/category/1"},
	Name = {"name", "Prepaid"},
	Description = {"description", "Services provided with realtime credit management"},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-04T00:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	IsRoot = {"isRoot", true},
	{struct, [Id, Href, Name, Description, Version, Status, LastUpdate, IsRoot]}.

%% @hidden
spec_product_network() ->
	Id = {"id", "1"},
	Href = {"href", "/catalogManagement/v2/productSpecification/1"},
	Name = {"name", "NetworkProductSpec"},
	Description = {"description", "Represents the common behaviour and description of an installed network product that will be provisioned in the network and that enables usages."},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-06T12:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	{struct, [Id, Name, Href, Description, Version, LastUpdate, Status]}.

%% @hidden
spec_product_fixed_quantity_pkg() ->
	Id = {"id", "2"},
	Href = {"href", "/catalogManagement/v2/productSpecification/2"},
	Name = {"name", "FixedQuantityPackageProductSpec"},
	Description = {"description", "Defines buckets of usage from which Usages will debit the bucket."},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-06T12:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	{struct, [Id, Name, Href, Description, Version, LastUpdate, Status]}.

%% @hidden
spec_product_rate_plane() ->
	Id = {"id", "3"},
	Href = {"href", "/catalogManagement/v2/productSpecification/3"},
	Name = {"name", "RatedPlanProductSpec"},
	Description = {"description", "Defines criteria to be used to gain special usage tariffs like the period (day, evening) or phone number."},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-06T12:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	{struct, [Id, Name, Href, Description, Version, LastUpdate, Status]}.

%% @hidden
spec_product_wlan() ->
	Id = {"id", "4"},
	Href = {"href", "/catalogManagement/v2/productSpecification/4"},
	Name = {"name", "WLANProductSpec"},
	Description = {"description", "Defines characteristics specific to pulic Wi-Fi use."},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-06T12:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	DepType = {"type", "dependency"},
	DepId = {"id", "1"},
	DepHref = {"href", "productCatalogManagement/productSpecification/1"},
	Depend = {struct, [DepId, DepHref, DepType]},
	Dependency = {"productSpecificationRelationship", {array, [Depend]}},
	Chars = {"productSpecCharacteristic", {array, characteristic_product_wlan()}},
	{struct, [Id, Name, Href, Description, Version, LastUpdate, Status, Chars, Dependency]}.

%% @hidden
characteristic_product_wlan() ->
	Name1 = {"name", "subscriberIdentity"},
	Description1 = {"description",
			"Uniquely identifies subscriber (e.g. MSISDN, IMSI, username)."},
	Type1 = {"valueType", "string"},
	Value1 = {"productSpecCharacteristicValue", {array, [{struct, [Type1]}]}},
	Char1 = {struct, [Name1, Description1, Type1, Value1]},
	Name2 = {"name", "subscriberPassword"},
	Description2 = {"description", "Shared secret used in authentication."},
	Type2 = {"valueType", "string"},
	Value2 = {"productSpecCharacteristicValue", {array, [{struct, [Type2]}]}},
	Char2 = {struct, [Name2, Description2, Type2, Value2]},
	Name3 = {"name", "topUpDuration"},
	Description3 = {"description", "Validity period of each top up."},
	Type3 = {"valueType", "integer"},
	Value3 = {"productSpecCharacteristicValue", {array, [{struct, [Type2]}]}},
	Char3 = {struct, [Name3, Description3, Type3, Value3]},
	[Char1, Char2, Char3].

-spec offer_status(Status) -> Status
	when
		Status :: atom() | string().
%% @doc CODEC for life cycle status of Product instance.
%% @private
offer_status("In Study") -> in_study;
offer_status("In Design") -> in_design;
offer_status("In Test") -> in_test;
offer_status("Active") -> active;
offer_status("Rejected") -> rejected;
offer_status("Launched") -> launched;
offer_status("Retired") -> retired;
offer_status("Obsolete") -> obsolete;
offer_status(in_study) -> "In Study";
offer_status(in_design) -> "In Design";
offer_status(in_test) -> "In Test";
offer_status(active) -> "Active";
offer_status(rejected) -> "Rejected";
offer_status(launched) -> "Launched";
offer_status(retired) -> "Retired";
offer_status(obsolete) -> "Obsolete".

-spec product_status(Status) -> Status
	when
		Status :: atom() | string().
%% @doc CODEC for life cycle status of Product Offering.
%% @private
product_status("Created") -> created;
product_status("Pending Active") -> pending_active;
product_status("Aborted") -> aborted;
product_status("Cancelled") -> cancelled;
product_status("Active") -> active;
product_status("Suspended") -> suspended;
product_status("Pending Terminate") -> pending_terminate;
product_status("Terminated") -> terminated;
product_status(created) -> "Created";
product_status(pending_active) -> "Pending Active";
product_status(aborted) -> "Aborted";
product_status(cancelled) -> "Cancelled";
product_status(active) -> "Active";
product_status(suspended) -> "Suspended";
product_status(pending_terminate) -> "Pending Terminate";
product_status(terminated) -> "Terminated".

-spec price_type(Type) -> Type
	when
		Type :: string() | atom().
%% @doc CODEC for Price Type.
%% @private
price_type("usage") -> usage;
price_type("recurring") -> recurring;
price_type("one_time") -> one_time;
price_type(usage) -> "usage";
price_type(recurring) -> "recurring";
price_type(one_time) -> "one_time".

-spec price_period(Period) -> Period
	when
		Period :: string() | atom().
%% @doc CODEC for Recurring Charge Period.
%% @private
price_period(daily) -> "daily";
price_period(weekly) -> "weekly";
price_period(monthly) -> "monthly";
price_period(yearly) -> "yearly";
price_period("daily") -> daily;
price_period("weekly") -> weekly;
price_period("monthly") -> monthly;
price_period("yearly") -> yearly.

-spec offer(Product) -> Product
	when
		Product :: #product{} | {struct, [tuple()]}.
%% @doc CODEC for Product Offering.
%% @private
offer(#product{} = Product) ->
	offer(record_info(fields, product), Product, []);
offer({struct, ObjectMembers}) when is_list(ObjectMembers) ->
	offer(ObjectMembers, #product{}).
%% @hidden
offer([name | T], #product{name = Name} = P, Acc) when is_list(Name) ->
	offer(T, P, [{"name", Name} | Acc]);
offer([description | T], #product{description = Description} = P,
		Acc) when is_list(Description) ->
	offer(T, P, [{"description", Description} | Acc]);
offer([start_date | T], #product{start_date = Start,
		end_date = undefined} = P, Acc) when is_integer(Start) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)}]},
	offer(T, P, [{"validFor", ValidFor} | Acc]);
offer([start_date | T], #product{start_date = undefined,
		end_date = End} = P, Acc) when is_integer(End) ->
	ValidFor = {struct, [{"endDateTime", ocs_rest:iso8601(End)}]},
	offer(T, P, [{"validFor", ValidFor} | Acc]);
offer([start_date | T], #product{start_date = Start,
		end_date = End} = P, Acc) when is_integer(Start), is_integer(End) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)},
			{"endDateTime", ocs_rest:iso8601(End)}]},
	offer(T, P, [{"validFor", ValidFor} | Acc]);
offer([end_date | T], P, Acc) ->
	offer(T, P, Acc);
offer([is_bundle | T], #product{is_bundle = IsBundle} = P, Acc)
		when is_boolean(IsBundle) ->
	offer(T, P, [{"isBunde", IsBundle} | Acc]);
offer([status | T], #product{status = Status} = P, Acc)
		when Status /= undefined ->
	StatusString = offer_status(Status),
	offer(T, P, [{"lifecycleStatus", StatusString} | Acc]);
offer([price | T], #product{price = Prices1} = P, Acc)
		when is_list(Prices1) ->
	Prices2 = [price(Price) || Price <- Prices1],
	offer(T, P, [{"price", Prices2} | Acc]);
offer([characteristics | T],
		#product{characteristics = Chars} = P, Acc) when is_list(Chars) ->
	offer(T, P, [{"characteristic", characteristics(Chars)} | Acc]);
offer([last_modified | T], #product{last_modified = {Last, _}} = P, Acc)
		when is_integer(Last) ->
	offer(T, P, [{"lastUpdate", ocs_rest:iso8601(Last)} | Acc]);
offer([_ | T], P, Acc) ->
	offer(T, P, Acc);
offer([], #product{name = Name}, Acc) ->
	H = [{"id", Name}, {"href", ?offerPath ++ Name}],
	{struct, [H | lists:reverse(Acc)]}.
%% @hidden
offer([{"id", ID} | T], Acc) when is_list(ID) ->
	offer(T, Acc);
offer([{"href", URI} | T], Acc) when is_list(URI) ->
	offer(T, Acc);
offer([{"name", Name} | T], Acc) when is_list(Name) ->
	offer(T, Acc#product{name = Name});
offer([{"description", Description} | T], Acc) when is_list(Description) ->
	offer(T, Acc#product{description = Description});
offer([{"validFor", {struct, L}} | T], Acc) ->
	Acc1 = case lists:keyfind("startDateTime", 1, L) of
		{_, Start} ->
			Acc#product{start_date = ocs_rest:iso8601(Start)};
		false ->
			Acc
	end,
	Acc2 = case lists:keyfind("endDateTime", 1, L) of
		{_, End} ->
			Acc1#product{end_date = ocs_rest:iso8601(End)};
		false ->
			Acc
	end,
	offer(T, Acc2);
offer([{"is_bundle", Bundle} | T], Acc) when is_boolean(Bundle) ->
	offer(T, Acc#product{is_bundle = Bundle});
offer([{"lifecycleStatus", Status} | T], Acc) when is_list(Status) ->
	offer(T, Acc#product{status = offer_status(Status)});
offer([{"price", {array, Prices1}} | T], Acc) when is_list(Prices1) ->
	Prices2 = [price(Price) || Price <- Prices1],
	offer(T, Acc#product{price = Prices2});
offer([{"characteristic", Chars} | T], Acc) when is_list(Chars) ->
	offer(T, Acc#product{characteristics = characteristics(Chars)});
offer([], Acc) ->
	Acc.

-spec price(Price) -> Price
	when
		Price :: #price{} | {struct, list()}.
%% @doc CODEC for Product Offering Price.
%% @private
price(#price{} = Price) ->
	price(record_info(fields, price), Price, []);
price({struct, ObjectMembers}) when is_list(ObjectMembers) ->
	price(ObjectMembers, #price{}).
%% @hidden
price([name| T], #price{name = Name} = P, Acc) when is_list(Name) ->
	price(T, P, [{"name", Name} | Acc]);
price([description | T], #price{description = Description} = P, Acc)
		when is_list(Description) ->
	price(T, P, [{"description", Description} | Acc]);
price([start_date | T], #price{start_date = Start,
		end_date = undefined} = P, Acc) when is_integer(Start) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)}]},
	price(T, P, [{"validFor", ValidFor} | Acc]);
price([start_date | T], #price{start_date = undefined,
		end_date = End} = P, Acc) when is_integer(End) ->
	ValidFor = {struct, [{"endDateTime", ocs_rest:iso8601(End)}]},
	price(T, P, [{"validFor", ValidFor} | Acc]);
price([start_date | T], #price{start_date = Start,
		end_date = End} = P, Acc) when is_integer(Start), is_integer(End) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)},
			{"endDateTime", ocs_rest:iso8601(End)}]},
	price(T, P, [{"validFor", ValidFor} | Acc]);
price([end_date | T], P, Acc) ->
	price(T, P, Acc);
price([type | T], #price{type = one_time, units = cents} = P, Acc) ->
	price(T, P, [{"priceType", price_type(one_time)} | Acc]);
price([type | T], #price{type = recurring, period = Period,
		units = cents} = P, Acc) when Period /= undefined ->
	Recurring = [{"priceType", price_type(recurring)},
			{"recurringChargePeriod", price_period(Period)}],
	price(T, P, Recurring ++ Acc);
price([type | T], #price{type = usage, units = octets,
		size = Size} = P, Acc) when is_integer(Size) ->
	UsageType = [{"priceType", price_type(usage)},
			{"unitOfMeasure", integer_to_list(Size) ++ "b"}],
	price(T, P, UsageType ++ Acc);
price([type | T], #price{type = usage, units = seconds,
		size = Size} = P, Acc) when is_integer(Size) ->
%	UsageType = [{"priceType", price_type(usage)},
%			{"unitOfMeasure", integer_to_list(Size) ++ "s"}],
%	price(T, P, UsageType ++ Acc);
	price(T, P, Acc);
price([period | T], P, Acc) ->
	price(T, P, Acc);
price([units | T], P, Acc) ->
	price(T, P, Acc);
price([size | T], P, Acc) ->
	price(T, P, Acc);
price([amount | T], #price{amount = Amount, currency = Currency} = P, Acc)
		when is_integer(Amount), is_list(Currency) ->
	Price = {struct, [{"taxIncludedAmount", integer_to_list(Amount)},
			{"currencyCode", Currency}]},
	price(T, P, [{"price", Price} | Acc]);
price([amount | T], #price{amount = Amount} = P, Acc)
		when is_integer(Amount) ->
	Price = {struct, [{"taxIncludedAmount", integer_to_list(Amount)}]},
	price(T, P, [{"price", Price} | Acc]);
price([currency | T], P, Acc) ->
	price(T, P, Acc);
price([alteration | T], #price{alteration = Alteration} = P, Acc)
		when is_record(Alteration, alteration) ->
	price(T, P, [{"alteration", alteration(Alteration)} | Acc]);
price([_ | T], P, Acc) ->
	price(T, P, Acc);
price([], _P, Acc) ->
	{struct, lists:reverse(Acc)}.
%% @hidden
price([{"id", _ID} | T], Acc) ->
	price(T, Acc);
price([{"href", _URI} | T], Acc) ->
	price(T, Acc);
price([{"name", Name} | T], Acc) when is_list(Name) ->
	price(T, Acc#price{name = Name});
price([{"description", Description} | T], Acc) when is_list(Description) ->
	price(T, Acc#price{description = Description});
price([{"validFor", {struct, L}} | T], Acc) when is_list(L) ->
	Acc1 = case lists:keyfind("startDateTime", 1, L) of
		{_, Start} ->
			Acc#price{start_date = ocs_rest:iso8601(Start)};
		false ->
			Acc
	end,
	Acc2 = case lists:keyfind("endDateTime", 1, L) of
		{_, End} ->
			Acc1#price{end_date = ocs_rest:iso8601(End)};
		false ->
			Acc
	end,
	price(T, Acc2);
price([{"priceType", Type} | T], Acc) when is_list(Type) ->
	price(T, Acc#price{type = price_type(Type)});
price([{"unitOfMeasure", UnitOfMeasure} | T], Acc)
		when is_list(UnitOfMeasure) ->
	case lists:last(UnitOfMeasure) of
		$b ->
			N = lists:sublist(UnitOfMeasure, length(UnitOfMeasure) - 1),
			price(T, Acc#price{units = octets, size = list_to_integer(N)});
		$s ->
			N = lists:sublist(UnitOfMeasure, length(UnitOfMeasure) - 1),
			price(T, Acc#price{units = seconds, size = list_to_integer(N)});
		_ ->
			price(T, Acc#price{size = list_to_integer(UnitOfMeasure)})
	end;
price([{"price", {struct, L}} | T], Acc) when is_list(L) ->
	Acc1 = case lists:keyfind("taxIncludedAmount", 1, L) of
		{_, Amount} when is_integer(Amount) ->
			Acc#price{amount = Amount};
		_ ->
			Acc
	end,
	Acc2 = case lists:keyfind("currency", 1, L) of
		{_, Currency} when is_list(Currency) ->
			Acc1#price{currency = Currency};
		_ ->
			Acc1
	end,
	price(T, Acc2);
price([{"recurringChargePeriod", Period} | T], Acc) when is_list(Period) ->
	price(T, Acc#price{period = price_period(Period)});
price([{"productOfferPriceAlteration", {struct, L} = Alteration} | T], Acc)
		when is_list(L) ->
	price(T, Acc#price{alteration = alteration(Alteration)});
price([], Acc) ->
	Acc.

-spec alteration(Alteration) -> Alteration
	when
		Alteration :: #alteration{} | {struct, [tuple()]}.
%% @doc CODEC for Product Offering Price Alteration.
%% @private
alteration(#alteration{} = A) ->
	alteration(record_info(fields, alteration), A, []);
alteration({struct, ObjectMembers}) when is_list(ObjectMembers) ->
	alteration(ObjectMembers, #alteration{}).
%% @hidden
alteration([name| T], #alteration{name = Name} = A, Acc) when is_list(Name) ->
	alteration(T, A, [{"name", Name} | Acc]);
alteration([description | T], #alteration{description = Description} = A, Acc)
		when is_list(Description) ->
	alteration(T, A, [{"description", Description} | Acc]);
alteration([start_date | T], #alteration{start_date = Start,
		end_date = undefined} = A, Acc) when is_integer(Start) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)}]},
	alteration(T, A, [{"validFor", ValidFor} | Acc]);
alteration([start_date | T], #alteration{start_date = undefined,
		end_date = End} = A, Acc) when is_integer(End) ->
	ValidFor = {struct, [{"endDateTime", ocs_rest:iso8601(End)}]},
	alteration(T, A, [{"validFor", ValidFor} | Acc]);
alteration([start_date | T], #alteration{start_date = Start,
		end_date = End} = A, Acc) when is_integer(Start), is_integer(End) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)},
			{"endDateTime", ocs_rest:iso8601(End)}]},
	alteration(T, A, [{"validFor", ValidFor} | Acc]);
alteration([end_date | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([type | T], #alteration{type = one_time, units = cents} = A, Acc) ->
	alteration(T, A, [{"priceType", price_type(one_time)} | Acc]);
alteration([type | T], #alteration{type = recurring, period = Period,
		units = cents} = A, Acc) when Period /= undefined ->
	Recurring = [{"priceType", price_type(recurring)},
			{"recurringChargePeriod", price_period(Period)}],
	alteration(T, A, Recurring ++ Acc);
alteration([type | T], #alteration{type = usage, units = octets,
		size = Size} = A, Acc) when is_integer(Size) ->
	UsageType = [{"priceType", price_type(usage)},
			{"unitOfMeasure", integer_to_list(Size) ++ "b"}],
	alteration(T, A, UsageType ++ Acc);
alteration([type | T], #alteration{type = usage, units = seconds,
		size = Size} = A, Acc) when is_integer(Size) ->
	UsageType = [{"priceType", price_type(usage)},
			{"unitOfMeasure", integer_to_list(Size) ++ "s"}],
	alteration(T, A, UsageType ++ Acc);
alteration([period | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([units | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([size | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([amount | T], #alteration{amount = Amount, currency = Currency} = A, Acc)
		when is_integer(Amount), is_list(Currency) ->
	Price = {struct, [{"taxIncludedAmount", integer_to_list(Amount)},
			{"currencyCode", Currency}]},
	alteration(T, A, [{"price", Price} | Acc]);
alteration([amount | T], #alteration{amount = Amount} = A, Acc)
		when is_integer(Amount) ->
	Price = {struct, [{"taxIncludedAmount", integer_to_list(Amount)}]},
	alteration(T, A, [{"price", Price} | Acc]);
alteration([currency | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([_ | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([], _A, Acc) ->
	{struct, lists:reverse(Acc)}.
%% @hidden
alteration([{"id", _ID} | T], Acc) ->
	alteration(T, Acc);
alteration([{"href", _URI} | T], Acc) ->
	alteration(T, Acc);
alteration([{"name", Name} | T], Acc) when is_list(Name) ->
	alteration(T, Acc#alteration{name = Name});
alteration([{"description", Description} | T], Acc) when is_list(Description) ->
	alteration(T, Acc#alteration{description = Description});
alteration([{"validFor", {struct, L}} | T], Acc) ->
	Acc1 = case lists:keyfind("startDateTime", 1, L) of
		{_, Start} ->
			Acc#alteration{start_date = ocs_rest:iso8601(Start)};
		false ->
			Acc
	end,
	Acc2 = case lists:keyfind("endDateTime", 1, L) of
		{_, End} ->
			Acc1#alteration{end_date = ocs_rest:iso8601(End)};
		false ->
			Acc
	end,
	alteration(T, Acc2);
alteration([{"priceType", Type} | T], Acc) ->
	alteration(T, Acc#alteration{type = price_type(Type)});
alteration([{"unitOfMeasure", UnitOfMeasure} | T], Acc) ->
	case lists:last(UnitOfMeasure) of
		$b ->
			N = lists:sublist(UnitOfMeasure, length(UnitOfMeasure) - 1),
			alteration(T, Acc#alteration{units = octets, size = list_to_integer(N)});
		$s ->
			N = lists:sublist(UnitOfMeasure, length(UnitOfMeasure) - 1),
			alteration(T, Acc#alteration{units = seconds, size = list_to_integer(N)});
		_ ->
			alteration(T, Acc#alteration{size = list_to_integer(UnitOfMeasure)})
	end;
alteration([{"alteration", {struct, L}} | T], Acc) ->
	Acc1 = case lists:keyfind("taxIncludedAmount", 1, L) of
		{_, Amount} when is_integer(Amount) ->
			Acc#alteration{amount = Amount};
		_ ->
			Acc
	end,
	Acc2 = case lists:keyfind("currency", 1, L) of
		{_, Currency} when is_list(Currency) ->
			Acc1#alteration{currency = Currency};
		_ ->
			Acc1
	end,
	alteration(T, Acc2);
alteration([{"recurringChargePeriod", Period} | T], Acc) ->
	alteration(T, Acc#alteration{period = price_period(Period)});
alteration([], Acc) ->
	Acc.

-spec characteristics(Characteristics) -> Characteristics
	when
		Characteristics :: [tuple()].
%% @doc CODEC for Product Specification Characteristics.
%% @private
characteristics([]) -> [].

%% @hidden
query_start(Query, Filters, RangeStart, RangeEnd) ->
	Name =  proplists:get_value("name", Query),
	Des = proplists:get_value("description", Query),
	Status = case lists:keyfind("licecycleStatus", 1, Query) of
		false ->
			undefined;
		{_, S} ->
			product_status(S)
	end,
	SDT = proplists:get_value("startDate", Query),
	EDT = proplists:get_value("endDate", Query),
	Price = proplists:get_value("price", Query),
	case supervisor:start_child(ocs_rest_pagination_sup,
				[[ocs, query_product, [Name, Des, Status, SDT, EDT, Price]]]) of
		{ok, PageServer, Etag} ->
			query_page(PageServer, Etag, Query, Filters, RangeStart, RangeEnd);
		{error, _Reason} ->
			{error, 500}
	end.

%% @hidden
query_page(PageServer, Etag, Query, Filters, Start, End) ->
	case gen_server:call(PageServer, {Start, End}) of
		{error, Status} ->
			{error, Status};
		{Products, ContentRange} ->
			try
				case lists:keytake("sort", 1, Query) of
					{value, {_, "name"}, Q1} ->
						{lists:keysort(#product.name, Products), Q1};
					{value, {_, "-name"}, Q1} ->
						{lists:reverse(lists:keysort(#product.name, Products)), Q1};
					{value, {_, "description"}, Q1} ->
						{lists:keysort(#product.description, Products), Q1};
					{value, {_, "-description"}, Q1} ->
						{lists:reverse(lists:keysort(#product.description, Products)), Q1};
					{value, {_, "licecycleStatus"}, Q1} ->
						{lists:keysort(#product.status, Products), Q1};
					{value, {_, "-lifecycleStatus"}, Q1} ->
						{lists:reverse(lists:keysort(#product.status, Products)), Q1};
					{value, {_, "startDate"}, Q1} ->
						{lists:keysort(#product.start_date, Products), Q1};
					{value, {_, "-startDate"}, Q1} ->
						{lists:reverse(lists:keysort(#product.start_date, Products)), Q1};
					{value, {_, "endDate"}, Q1} ->
						{lists:keysort(#product.end_date, Products), Q1};
					{value, {_, "-endDate"}, Q1} ->
						{lists:reverse(lists:keysort(#product.end_date, Products)), Q1};
					{value, {_, "price"}, Q1} ->
						{lists:keysort(#product.price, Products), Q1};
					{value, {_, "-price"}, Q1} ->
						{lists:reverse(lists:keysort(#product.price, Products)), Q1};
					false ->
						{Products, Query};
					_ ->
						throw(400)
				end
			of
				{SortedProducts, _NewQuery} ->
					JsonObj = query_page1(lists:map(fun offer/1, SortedProducts), Filters, []),
					JsonArray = {array, JsonObj},
					Body = mochijson:encode(JsonArray),
					Headers = [{content_type, "application/json"},
							{etag, Etag}, {accept_ranges, "items"},
							{content_range, ContentRange}],
					{ok, Headers, Body}
			catch
				throw:{error, Status} ->
					{error, Status}
			end
	end.
%% @hidden
query_page1(Json, [], []) ->
	Json;
query_page1([H | T], Filters, Acc) ->
	query_page1(T, Filters, [ocs_rest:filter(Filters, H) | Acc]);
query_page1([], _, Acc) ->
	lists:reverse(Acc).

