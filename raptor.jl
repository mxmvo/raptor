#%%

using DataFrames
using CSV

#%%
function select_minrow(t, p, tr)
    i = argmin(t)
    return [t[i] p[i] tr[i]]
end



function make_Q(df, df_sr)
    Q = Dict()

    # For each marked stop
    for row ∈ eachrow(df[df.marked .== true,:])
        p = row.stop_id
        
        # Find the routes serving this stop
        for rrow ∈ eachrow(df_sr[df_sr.stop_id .== p,:])
            r = rrow.route_id
            s = rrow.stop_sequence

            # Check if the stop is before an already added stop.
            # ifso replace it. Otherwise add it.
            if r ∈ keys(Q)
                _, ss = Q[r]
                if s < ss
                    Q[r] = (p,s)
                end
            else
                Q[r] = (p,s)
            end
        end
    end
    return Q
end

"""
earliest trip in route r that one can catch at stop p
returns trip_id
"""
function et(r, p, df_stop,gdf_stop_times_rp)
    τ_kmin1 = df_stop[df_stop.stop_id .== p,:arrival_s][1] # fix or assert
    df_trips = gdf_stop_times_rp[(r,p)]
    df_trips_filtered = filter(:departure_s => (τ_dep -> τ_dep >= τ_kmin1), df_trips)
    if isempty(df_trips_filtered.departure_s)
        trip_id = -1 # check if this is ok
    else
        et, et_i = findmin(df_trips_filtered.departure_s)
        trip_id = df_trips_filtered[et_i,:trip_id]
    end
    return trip_id
end


"""
arrival and departure time of trip t at station p
"""
function arr_dep(t, p, stop_times)
    arr, dep = eachcol(stop_times[(stop_times.trip_id .== t) .& (stop_times.stop_id .== p),[:arrival_s,:departure_s]])
    return arr[1], dep[1] # Fix please
end


function traverse_routes(Q, gdf_routes, stop_times, df_stop, gdf_stop_times_rp, τ_star)
    
    for (r,(p,s)) in Q
        t = -1  # current trip 

        # All stops on route r
        df_stop_id = gdf_routes[(r,)]
        
        
        # All stops after p on route r
        df_stop_id_filtered = filter(:stop_sequence => (seq -> seq > s), df_stop_id)

        for row ∈ eachrow(df_stop_id_filtered)
            pᵢ = row.stop_id 
            mask = df_stop.stop_id .== pᵢ # mask to select stop pᵢ in df_stop

            τᵢ_star = df_stop[mask, :arrival_s][1] # earliest (found) arrival time at pᵢ 
            τ_kmin1 = τᵢ_star

            if t !== -1
                τ_arr, τ_dep = arr_dep(t, pᵢ, stop_times) # arrival time of trip t at stop pᵢ
                can_be_improved = τ_arr < minimum(τᵢ_star,τ_star)
                if can_be_improved
                    df_stop[mask,[:arrival_s,:marked]] .= [τ_arr, true] # "set tau star in alg"
                end
            end
            
            t = et(r, pᵢ, df_stop, gdf_stop_times_rp) # can we catch an earlier trip?

        end


    end
end




function stage_2(df, g_stops, g_trips, stops; τ⁺ = Inf32)
    
    # Run over the marked stops
    potential_new_stops = []

    for r ∈ eachrow(df[df.marked .== true,[:stop_id,:arrival_s]])
        s_id, τ = r.stop_id, r.arrival_s
        
        # Find the trips through this stop after the arrival time 
        ((stop_id = s_id,) ∉ keys(g_stops)) && continue

        dff = g_stops[(s_id,)]
        trps = unique(filter(:arrival_s => (t -> t > τ), dff)[:,:trip_id])
        
        # Different platforms?
        p_id = stops[stops.stop_id .== s_id, :parent_station][1]
        if !ismissing(p_id)
            dfp = stops[isequal.(stops.parent_station, p_id),[:stop_id]]
            dfp[!,:arrival_s] .= τ + 120 #2 min overstap tijd
            dfp[!,:parent] .= s_id
            dfp[!,:trip] .= -1
            append!(potential_new_stops, [dfp])
        end

        # For those trips find the stops that can be reached. 
        for t_id ∈ trps
            dff = g_trips[(t_id,)]
            τ_stop = dff[dff.stop_id .== s_id, :arrival_s][1]
            stp = filter(:arrival_s => (t -> t > τ_stop), dff)[:,[:stop_id,:arrival_s]]
            stp[!,:parent] .= s_id
            stp[!,:trip] .= t_id
            append!(potential_new_stops, [stp])
        end
    end

    # Add all the stops to a DataFrame
    # Select the minimal arrival time per stop. 
    dff = vcat(potential_new_stops...)
    println(size(dff))
    combine(groupby(dff,:stop_id), [:arrival_s, :parent,:trip] => select_minrow => [:arrival_s, :parent,:trip])
end


function update_df!(df, new_stops)
    df[!,:marked] .= false
    for r ∈ eachrow(new_stops)
        if r.arrival_s < df[df.stop_id .== r.stop_id,:arrival_s][1]
            df[df.stop_id .== r.stop_id, [:arrival_s,:marked,:parent,:trip]] = [r.arrival_s true r.parent r.trip]
        end    
    end
end

function get_trip(df, stops, arr_id)

    t = [arr_id]
    p = df[df.stop_id .== arr_id,:parent][1]
    while p !== ""
        append!(t,[p])
        p = df[df.stop_id .== p,:parent][1]
    end
    dff = sort(filter(r -> r.stop_id ∈ t, df), :arrival_s)
    names = []
    for r ∈ eachrow(dff)
        n = stops[stops.stop_id .== r.stop_id,:stop_name][1]
        append!(names, [n])
    end
    dff.name = names
    return dff
    # transform(dff, :stop_id => (t -> stops[stops.stop_id .== t, :stop_name]) => :stop_name)
end