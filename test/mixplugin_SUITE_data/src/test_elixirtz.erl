-module(test_elixirtz).

-export( [ensure_started/0, local_from_utc/2] ).


ensure_started() ->
	%% Start hackney as early as possible.
	ok = application:ensure_started( unicode_util_compat ),
	ok = application:ensure_started( idna ),
	ok = application:ensure_started( mimerl ),
	ok = application:ensure_started( certifi ),
	ok = application:ensure_started( syntax_tools ),
	ok = application:ensure_started( parse_trans ),
	ok = application:ensure_started( ssl_verify_fun ),
	ok = application:ensure_started( metrics ),
	ok = application:ensure_started( hackney ),
	ok = application:ensure_started( compiler ),
	ok = application:ensure_started( elixir ),
	ok = application:ensure_started( logger ),
	ok = application:ensure_started( tzdata ).

local_from_utc( Date_time, Time_zone  ) ->
	Naive_date_time = 'Elixir.NaiveDateTime':'from_erl!'( Date_time ),
	Elixir_date_time = 'Elixir.DateTime':'from_naive!'( Naive_date_time, <<"Etc/UTC">> ),
	B = binary:list_to_bin( Time_zone ),
	{ok, Local} = 'Elixir.DateTime':shift_zone( Elixir_date_time, B, 'Elixir.Tzdata.TimeZoneDatabase' ),
	#{std_offset := STD, utc_offset := UTC} = Local,
	{'Elixir.NaiveDateTime':to_erl( Local ), local_from_utc_offset( STD + UTC )}.


local_from_utc_offset( Seconds ) when Seconds < 0 ->
	{$-, local_from_utc_offset_hours_minutes( Seconds * -1 )};
local_from_utc_offset( Seconds ) ->
	{$+, local_from_utc_offset_hours_minutes( Seconds )}.

local_from_utc_offset_hours_minutes( Seconds ) ->
	[Seconds div 3600, (Seconds rem 3600) div 60].
