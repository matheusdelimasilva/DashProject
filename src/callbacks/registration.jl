# ─── Callback Registration ───────────────────────────────────────────────────

"""
    callback!(func, app, output, input, [state]; prevent_initial_call=nothing, background=false, ...)

Register a callback that updates `output` properties when `input` properties change.
Supports do-block syntax for idiomatic Julia callbacks.

# Background Callback Options
- `background=false` — run callback in background thread
- `interval=1000` — polling interval in ms
- `progress=nothing` — Vector of Output targets for progress updates
- `progress_default=nothing` — default progress values
- `running=nothing` — pairs of (Output, running_value, off_value)
- `cancel=nothing` — Vector of Input specs that cancel the background job
- `manager=nothing` — per-callback background manager override

# Examples

```julia
# Single output, single input
callback!(app, Output("out", "children"), Input("in", "value")) do value
    return "Hello \$value"
end

# Multiple outputs
callback!(app,
    [Output("out1", "children"), Output("out2", "value")],
    Input("in", "value"),
    State("state", "value")
) do input_val, state_val
    return ("Result: \$input_val", state_val)
end

# Background callback with progress
callback!(app, Output("out", "children"), Input("btn", "n_clicks");
    background=true, progress=[Output("progress", "value")],
    manager=ThreadPoolManager()
) do set_progress, n_clicks
    for i in 1:10
        set_progress([i * 10])
        sleep(0.5)
    end
    return "Done!"
end
```
"""
function callback!(func::Union{Function,ClientsideFunction,String},
                   app::DashApp,
                   output::Union{Vector{<:Output},Output},
                   input::Union{Vector{<:Input},Input},
                   state::Union{Vector{<:State},State}=State[];
                   prevent_initial_call=nothing,
                   background=false,
                   interval=1000,
                   progress=nothing,
                   progress_default=nothing,
                   running=nothing,
                   cancel=nothing,
                   manager=nothing)
    return _callback!(func, app, CallbackDeps(output, input, state);
                       prevent_initial_call=prevent_initial_call,
                       background=background, interval=interval,
                       progress=progress, progress_default=progress_default,
                       running=running, cancel=cancel, manager=manager)
end

# Flat deps version: callback!(func, app, Output(...), Output(...), Input(...), State(...))
function callback!(func::Union{Function,ClientsideFunction,String},
                   app::DashApp,
                   deps::Dependency...;
                   prevent_initial_call=nothing,
                   background=false,
                   interval=1000,
                   progress=nothing,
                   progress_default=nothing,
                   running=nothing,
                   cancel=nothing,
                   manager=nothing)
    output = Output[]
    input = Input[]
    state = State[]
    _process_callback_args(deps, (output, input, state))
    return _callback!(func, app, CallbackDeps(output, input, state, length(output) > 1);
                       prevent_initial_call=prevent_initial_call,
                       background=background, interval=interval,
                       progress=progress, progress_default=progress_default,
                       running=running, cancel=cancel, manager=manager)
end

# Process flat deps into separate output/input/state vectors
function _process_callback_args(args::Tuple{T,Vararg}, dest::Tuple{Vector{T},Vararg}) where {T}
    push!(dest[1], args[1])
    _process_callback_args(Base.tail(args), dest)
end
function _process_callback_args(args::Tuple{}, dest::Tuple{Vector{T},Vararg}) where {T}
end
function _process_callback_args(args::Tuple, dest::Tuple{Vector{T},Vararg}) where {T}
    _process_callback_args(args, Base.tail(dest))
end
function _process_callback_args(args::Tuple, dest::Tuple{})
    error("The callback method must receive first all Outputs, then all Inputs, then all States")
end
function _process_callback_args(args::Tuple{}, dest::Tuple{})
end

# Core registration logic
function _callback!(func::Union{Function,ClientsideFunction,String}, app::DashApp, deps::CallbackDeps;
                    prevent_initial_call,
                    background=false,
                    interval=1000,
                    progress=nothing,
                    progress_default=nothing,
                    running=nothing,
                    cancel=nothing,
                    manager=nothing)
    check_callback(func, app, deps; background=background, progress=progress)

    any_allow_dup = any(o -> o.allow_duplicate, deps.output)

    # allow_duplicate callbacks always get a unique @hash key — no conflict possible.
    # Non-duplicate callbacks use the plain key and must not collide.
    out_id_str = output_string_with_duplicate(deps)
    base_out_id = output_string(deps)

    if !any_allow_dup && haskey(app.callback_map, base_out_id)
        error("Multiple callbacks cannot target the same output. Offending output: $(base_out_id)")
    end

    callback_func = make_callback_func!(app, func, deps)

    # Build background-related fields
    bg_key = nothing
    running_dict = nothing
    running_off_dict = nothing

    if background
        bg_key = make_background_key(out_id_str, callback_func)

        # Process running pairs: Vector of (Output, running_value, off_value)
        if !isnothing(running)
            running_dict = Dict{String,Any}()
            running_off_dict = Dict{String,Any}()
            for (out, run_val, off_val) in running
                out_str = dependency_string(out)
                running_dict[out_str] = run_val
                running_off_dict[out_str] = off_val
            end
        end

        # Wrap the user function to inject set_progress if progress outputs are defined
        if !isnothing(progress)
            orig_func = callback_func
            mgr_for_wrap = something(manager, app.config.background_callback_manager, ThreadPoolManager())
            callback_func = function(cache_key::String, args...)
                progress_fn = (values) -> set_progress(mgr_for_wrap, cache_key, values)
                return orig_func(progress_fn, args...)
            end
        else
            orig_func = callback_func
            callback_func = function(cache_key::String, args...)
                return orig_func(args...)
            end
        end
    end

    cb = Callback(callback_func, deps,
                  isnothing(prevent_initial_call) ? app.config.prevent_initial_callbacks : prevent_initial_call;
                  background=background,
                  background_key=bg_key,
                  interval=interval,
                  progress=progress,
                  progress_default=progress_default,
                  running=running_dict,
                  running_off=running_off_dict,
                  cancel=_process_cancel(cancel),
                  manager=manager)

    # Store in callback_map for dispatch (use deduplicated key)
    app.callback_map[out_id_str] = cb

    # Store in callback_list for _dash-dependencies serialization (use deduplicated output)
    cb_entry = _make_callback_list_entry(deps, cb, out_id_str)
    push!(app.callback_list, cb_entry)

    return nothing
end

# Process cancel input specs into standardized format
function _process_cancel(cancel)
    isnothing(cancel) && return nothing
    result = Dict{String,Any}[]
    for c in cancel
        if c isa Input
            push!(result, Dict{String,Any}("id" => dep_id_string(c), "property" => c.property))
        elseif c isa Dict
            push!(result, c)
        end
    end
    return result
end

function _make_callback_list_entry(deps::CallbackDeps, cb::Callback, out_id_str::String)
    func = cb.func
    entry = Dict{String,Any}(
        "output" => out_id_str,
        "inputs" => [Dict("id" => dep_id_string(d), "property" => d.property) for d in deps.input],
        "state" => [Dict("id" => dep_id_string(d), "property" => d.property) for d in deps.state],
        "prevent_initial_call" => cb.prevent_initial_call
    )
    if func isa ClientsideFunction
        entry["clientside_function"] = Dict(
            "namespace" => func.namespace,
            "function_name" => func.function_name
        )
    end

    # Phase 3: Background callback fields for frontend
    if cb.background
        entry["background"] = Dict{String,Any}("interval" => cb.interval)
        if !isnothing(cb.running)
            entry["running"] = cb.running
            entry["runningOff"] = cb.running_off
        end
        if !isnothing(cb.cancel)
            entry["cancel"] = cb.cancel
        end
        if !isnothing(cb.progress)
            entry["progress"] = [Dict("id" => dep_id_string(d), "property" => d.property)
                                 for d in cb.progress]
        end
        if !isnothing(cb.progress_default)
            entry["progressDefault"] = cb.progress_default
        end
    end

    return entry
end

make_callback_func!(::DashApp, func::Union{Function,ClientsideFunction}, ::CallbackDeps) = func

function make_callback_func!(app::DashApp, func::String, deps::CallbackDeps)
    first_out = first(deps.output)
    namespace = replace("_dashprivate_$(first_out.id)", "\"" => "\\\"")
    function_name = replace("$(first_out.property)", "\"" => "\\\"")

    function_string = """
        var clientside = window.dash_clientside = window.dash_clientside || {};
        var ns = clientside["$namespace"] = clientside["$namespace"] || {};
        ns["$function_name"] = $func;
    """
    push!(app.inline_scripts, function_string)
    return ClientsideFunction(namespace, function_name)
end

function check_callback(func, app::DashApp, deps::CallbackDeps;
                        background=false, progress=nothing)
    isempty(deps.output) && error("The callback method requires that one or more properly formatted outputs are passed.")
    isempty(deps.input) && error("The callback method requires that one or more properly formatted inputs are passed.")
    args_count = length(deps.state) + length(deps.input)
    # Background callbacks with progress get an extra set_progress argument
    if background && !isnothing(progress)
        args_count += 1
    end
    check_callback_func(func, args_count)
end

function check_callback_func(func::Function, args_count)
    !hasmethod(func, NTuple{args_count,Any}) &&
        error("The arguments of the specified callback function do not align with the currently defined callback; please ensure that the arguments to `func` are properly defined.")
end

check_callback_func(func, args_count) = nothing

# ─── Background Cancel Callback Setup ─────────────────────────────────────

"""
    _setup_background_cancels!(app)

Register cancel callbacks for all background callbacks that have cancel inputs.
"""
function _setup_background_cancels!(app::DashApp)
    for (key, cb) in app.callback_map
        cb.background && !isnothing(cb.cancel) || continue
        for cancel_input in cb.cancel
            cancel_id = cancel_input["id"]
            cancel_prop = cancel_input["property"]
            mgr = something(cb.manager, app.config.background_callback_manager)
            callback!(app,
                Output(cancel_id, "id"; allow_duplicate=true),
                Input(cancel_id, cancel_prop);
                prevent_initial_call=true
            ) do _
                # Terminate all jobs for this callback
                if !isnothing(mgr)
                    lock(mgr.lock) do
                        for (job_key, task) in mgr.jobs
                            if !istaskdone(task)
                                try
                                    schedule(task, InterruptException(); error=true)
                                catch
                                end
                            end
                        end
                    end
                end
                return no_update
            end
        end
    end
end

# ─── @callback Macro ─────────────────────────────────────────────────────────

"""
    @callback(app, output, input, [state]) do args...
        ...
    end

Module-level callback registration macro. Equivalent to `callback!` but
can be used at the top level of a module.

# Example
```julia
@callback(app, Output("out", "children"), Input("in", "value")) do value
    return "Hello \$value"
end
```
"""
macro callback(ex)
    return esc(:(callback!($(ex))))
end
