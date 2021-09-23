#%%
using Pkg; Pkg.activate(".") # Activate virtual env


using DataFrames
using CSV
using Revise
using BenchmarkTools

#%%

includet("raptor.jl")


#%%

# Read data in GTFS format
path_to_gtfs_data = joinpath("./gtfs-openov-nl")

routes     = CSV.read(joinpath(path_to_gtfs_data,"routes.txt"),     DataFrame)
trips      = CSV.read(joinpath(path_to_gtfs_data,"trips.txt"),      DataFrame)
stops      = CSV.read(joinpath(path_to_gtfs_data,"stops.txt"),      DataFrame)
stop_times = CSV.read(joinpath(path_to_gtfs_data,"stop_times.txt"), DataFrame)
# shapes     = CSV.read(joinpath(path_to_gtfs_data,"shapes.txt"),     DataFrame)

#%%

"""
Transform time string to seconds of the day
"""
function parse_time(t)
    h,m,s = parse.(Int, split(t,":"))
    return h * 3600 + m * 60 + s
end

# function get_parent_station(s_id)
#     a = stops[stops.stop_id .== s_id,:parent_station][1]
#     ismissing(a) ? s_id : a
# end

#%%
# Transform time strings to seconds of the day
# Transform stop_id to string
transform!(stop_times, :arrival_time   => (t -> parse_time.(t)) => :arrival_s)
transform!(stop_times, :departure_time => (t -> parse_time.(t)) => :departure_s)
transform!(stop_times, :stop_id        => (t -> string.(t) )    => :stop_id)

#%%
# Add route_id and parent_station to stop_times
stop_times = leftjoin(stop_times, trips[:,[:trip_id,:route_id]],       on = :trip_id)
stop_times = leftjoin(stop_times, stops[:,[:stop_id,:parent_station]], on = :stop_id)

# Groupby route_id and stop_id
gdf_stop_times_rp = groupby(stop_times[:,[:route_id,:stop_id,:trip_id,:arrival_s,:departure_s]],[:route_id,:stop_id])

#%%

df_stop_routes = unique(stop_times[:,[:stop_id,:route_id,:stop_sequence]])
gdf_routes = groupby(df_stop_routes,:route_id)


#%%

# function plot_stops(lat, lon)
#     marker = attr(size=1, color="black")
#     trace = scattergeo(;mode ="markers",
#                         lat = lat,
#                         lon = lon,
#                         marker = marker)

#     geo = attr(scope = "europe",
#                 lataxis_range = [50.,54.],
#                 lonaxis_range = [2,7])
#     layout = Layout(;title = "Stops Netherlands", showlegend = false, geo = geo)
#     plot(trace, layout)
# end

# plot_stops(stops[:,:stop_lat], stops[:,:stop_lon])

# %%

# g_stops = groupby(stop_times, :stop_id)
# g_trips = groupby(stop_times, :trip_id)

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

Q = make_Q(df_stop, df_stop_routes)


# %%
ett = et(41217,"2324508",df_stop,gdf_stop_times_rp)
arr_dep(ett, "2324508", stop_times)

# %%
τ_star = df_stop[df_stop.stop_id .== arr_id,:arrival_s][1]
traverse_routes(Q, gdf_routes, stop_times, df_stop, gdf_stop_times_rp, τ_star)

# %%
for k ∈ 1:10
    new_nodes = stage_2(df_stop, g_stops, g_trips, stops)
    update_df!(df_stop, new_nodes)
    println(df_stop[df_stop.stop_id .== arr_id,:])
end

# %%


get_trip(df_stop,stops, arr_id)

#%%
