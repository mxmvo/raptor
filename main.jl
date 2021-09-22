#%%

using DataFrames
using CSV
using PlotlyJS
using Revise
using BenchmarkTools

#%%

includet("raptor.jl")

#%%

routes = CSV.read("gtfs-openov-nl/routes.txt", DataFrame)
trips = CSV.read("gtfs-openov-nl/trips.txt", DataFrame)
stops = CSV.read("gtfs-openov-nl/stops.txt", DataFrame)
stop_times = CSV.read("gtfs-openov-nl/stop_times.txt", DataFrame)
shapes = CSV.read("gtfs-openov-nl/shapes.txt", DataFrame);
 
pif_stop_times = size(stop_times)

#%%

function parse_time(t)
    h,m,s = parse.(Int, split(t,":"))
    return h*3600+m*60+s
end

function get_parent_station(s_id)
    a = stops[stops.stop_id .== s_id,:parent_station][1]
    ismissing(a) ? s_id : a
end

#%%

transform!(stop_times, :arrival_time => (t -> parse_time.(t)) => :arrival_s)
transform!(stop_times, :stop_id => (t -> string.(t) ) => :stop_id)
# transform!(stop_times, :stop_id => (t -> get_parent_station.(t)) => :parent_station)

#%%

stop_times = leftjoin(stop_times, trips[:,[:trip_id,:route_id]], on = :trip_id)
stop_times = leftjoin(stop_times, stops[:,[:stop_id,:parent_station]], on = :stop_id)
#%%

df_stop_routes = unique(stop_times[:,[:stop_id,:route_id,:stop_sequence]])
gdf_routes = groupby(df_stop_routes,:route_id)



#%%

function plot_stops(lat, lon)
    marker = attr(size=1, color="black")
    trace = scattergeo(;mode ="markers",
                        lat = lat,
                        lon = lon,
                        marker = marker)

    geo = attr(scope = "europe",
                lataxis_range = [50.,54.],
                lonaxis_range = [2,7])
    layout = Layout(;title = "Stops Netherlands", showlegend = false, geo = geo)
    plot(trace, layout)
end

# plot_stops(stops[:,:stop_lat], stops[:,:stop_lon])

# %%

g_stops = groupby(stop_times, :stop_id)
g_trips = groupby(stop_times, :trip_id)

dep_id = "2324508"
dep_time = parse_time("12:45:00")
arr_id = "2324634"

# %%

df_stop = DataFrame()
df_stop[!,:stop_id] = stops[:,:stop_id]
df_stop[!,:arrival_s] .= Inf32
df_stop[!,:parent] .= ""
df_stop[!,:marked] .= false
df_stop[!,:trip] .= zero(Int)

df_stop[df_stop.stop_id .== dep_id,[:arrival_s, :marked]] = [dep_time true]

# %%

make_Q(df_stop, df_stop_routes)

# %%
for T ∈ 1:10
    new_nodes = stage_2(df_stop, g_stops, g_trips, stops)
    update_df!(df_stop, new_nodes)
    println(df_stop[df_stop.stop_id .== arr_id,:])
end

# %%


get_trip(df_stop,stops, arr_id)

#%%
