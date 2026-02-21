# ─── Background Callback Manager ─────────────────────────────────────────────
# Phase 3 — Full implementation with ThreadPoolManager.

"""
    AbstractBackgroundManager

Abstract type for background callback managers.
Subtype this to implement custom background task execution.
"""
abstract type AbstractBackgroundManager end

# Sentinel for "result not yet available"
struct _Undefined end
const UNDEFINED = _Undefined()

"""
    ThreadPoolManager <: AbstractBackgroundManager

Default background callback manager using Julia's built-in threading.
Uses `Threads.@spawn` for task execution. Stores results, progress,
and updated props in thread-safe dictionaries.
"""
mutable struct ThreadPoolManager <: AbstractBackgroundManager
    results::Dict{String,Any}
    progress::Dict{String,Any}
    set_props_data::Dict{String,Any}
    jobs::Dict{String,Task}
    lock::ReentrantLock
end

ThreadPoolManager() = ThreadPoolManager(Dict{String,Any}(), Dict{String,Any}(),
                                         Dict{String,Any}(), Dict{String,Task}(),
                                         ReentrantLock())

"""
    call_job_fn(mgr, key, func, args, context) → job_id

Spawn a background task that calls `func(args...)`.
Stores the result (or error) in `mgr.results[key]`.
Returns the cache key as the job ID.
"""
function call_job_fn(mgr::ThreadPoolManager, key::String, func::Function, args, context::Dict)
    task = Threads.@spawn begin
        try
            result = func(args...)
            lock(mgr.lock) do
                mgr.results[key] = result
            end
        catch e
            if e isa PreventUpdate
                lock(mgr.lock) do
                    mgr.results[key] = NoUpdate()
                end
            else
                lock(mgr.lock) do
                    mgr.results[key] = Dict{String,Any}(
                        "error" => true,
                        "message" => sprint(showerror, e),
                        "type" => string(typeof(e))
                    )
                end
            end
        end
    end
    lock(mgr.lock) do
        mgr.jobs[key] = task
    end
    return key
end

"""
    job_running(mgr, job_id) → Bool

Check if the background task is still running.
"""
function job_running(mgr::ThreadPoolManager, job_id::String)
    lock(mgr.lock) do
        task = get(mgr.jobs, job_id, nothing)
        isnothing(task) && return false
        return !istaskdone(task)
    end
end

"""
    terminate_job(mgr, job_id)

Attempt to cancel a running background task.
"""
function terminate_job(mgr::ThreadPoolManager, job_id::String)
    lock(mgr.lock) do
        task = get(mgr.jobs, job_id, nothing)
        if !isnothing(task) && !istaskdone(task)
            try
                schedule(task, InterruptException(); error=true)
            catch
                # Task may have already finished
            end
        end
        delete!(mgr.jobs, job_id)
        delete!(mgr.results, job_id)
        delete!(mgr.progress, job_id * "-progress")
        delete!(mgr.set_props_data, job_id * "-set_props")
    end
end

"""
    get_result(mgr, key) → Any

Returns the result for the given key, or `UNDEFINED` if not ready.
Deletes from cache after retrieval.
"""
function get_result(mgr::ThreadPoolManager, key::String)
    lock(mgr.lock) do
        if haskey(mgr.results, key)
            result = mgr.results[key]
            delete!(mgr.results, key)
            delete!(mgr.jobs, key)
            return result
        end
        return UNDEFINED
    end
end

"""
    result_ready(mgr, key) → Bool

Check if the result for the given key is available.
"""
function result_ready(mgr::ThreadPoolManager, key::String)
    lock(mgr.lock) do
        return haskey(mgr.results, key)
    end
end

"""
    set_progress(mgr, key, values)

Write progress values for a running background callback.
Called from within the background task.
"""
function set_progress(mgr::ThreadPoolManager, key::String, values)
    progress_key = key * "-progress"
    lock(mgr.lock) do
        mgr.progress[progress_key] = values
    end
end

"""
    get_progress(mgr, key) → Union{Any,Nothing}

Read and delete progress data for the given key.
Returns `nothing` if no progress is available.
"""
function get_progress(mgr::ThreadPoolManager, key::String)
    progress_key = key * "-progress"
    lock(mgr.lock) do
        if haskey(mgr.progress, progress_key)
            data = mgr.progress[progress_key]
            delete!(mgr.progress, progress_key)
            return data
        end
        return nothing
    end
end

"""
    set_updated_props(mgr, key, props)

Store updated props (from set_props calls within background callbacks).
"""
function set_updated_props(mgr::ThreadPoolManager, key::String, props::Dict)
    props_key = key * "-set_props"
    lock(mgr.lock) do
        existing = get(mgr.set_props_data, props_key, Dict{String,Any}())
        mgr.set_props_data[props_key] = merge(existing, props)
    end
end

"""
    get_updated_props(mgr, key) → Dict

Read and delete updated props data for the given key.
"""
function get_updated_props(mgr::ThreadPoolManager, key::String)
    props_key = key * "-set_props"
    lock(mgr.lock) do
        if haskey(mgr.set_props_data, props_key)
            data = mgr.set_props_data[props_key]
            delete!(mgr.set_props_data, props_key)
            return data
        end
        return Dict{String,Any}()
    end
end

"""
    make_cache_key(callback_id, args, triggered)

Generate a unique cache key for a specific background callback invocation.
"""
function make_cache_key(callback_id::String, args, triggered)
    data = callback_id * string(args) * string(triggered)
    return bytes2hex(MD5.md5(data))
end

"""
    make_background_key(callback_id, func)

Generate a key identifying the background callback function definition.
"""
function make_background_key(callback_id::String, func)
    data = callback_id * string(func)
    return bytes2hex(MD5.md5(data))
end
