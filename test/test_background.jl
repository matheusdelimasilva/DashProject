@testset "Background Callbacks" begin
    @testset "ThreadPoolManager construction" begin
        mgr = ThreadPoolManager()
        @test mgr isa AbstractBackgroundManager
        @test isempty(mgr.results)
        @test isempty(mgr.progress)
        @test isempty(mgr.jobs)
    end

    @testset "Job lifecycle: submit, poll, get result" begin
        mgr = ThreadPoolManager()
        key = "test-key-1"

        # Submit a simple job
        job_id = Dash2.call_job_fn(mgr, key, (args...) -> sum(args), (1, 2, 3), Dict{String,Any}())
        @test job_id == key

        # Wait for completion
        sleep(0.2)

        @test Dash2.result_ready(mgr, key)
        result = Dash2.get_result(mgr, key)
        @test result == 6

        # After retrieval, result is cleared
        @test !Dash2.result_ready(mgr, key)
        @test Dash2.get_result(mgr, key) isa Dash2._Undefined
    end

    @testset "Job running check" begin
        mgr = ThreadPoolManager()
        key = "test-key-running"

        Dash2.call_job_fn(mgr, key, (_...) -> (sleep(1.0); 42), (), Dict{String,Any}())

        # Job should be running
        @test Dash2.job_running(mgr, key)

        # Terminate it
        Dash2.terminate_job(mgr, key)
        sleep(0.1)

        @test !Dash2.job_running(mgr, key)
    end

    @testset "Progress updates" begin
        mgr = ThreadPoolManager()
        key = "test-key-progress"

        # Set progress
        Dash2.set_progress(mgr, key, [50, "halfway"])

        # Get progress
        progress = Dash2.get_progress(mgr, key)
        @test progress == [50, "halfway"]

        # After retrieval, progress is cleared
        @test isnothing(Dash2.get_progress(mgr, key))
    end

    @testset "Updated props" begin
        mgr = ThreadPoolManager()
        key = "test-key-props"

        Dash2.set_updated_props(mgr, key, Dict{String,Any}("comp1" => Dict("value" => 42)))
        props = Dash2.get_updated_props(mgr, key)
        @test props["comp1"]["value"] == 42

        # After retrieval, cleared
        @test isempty(Dash2.get_updated_props(mgr, key))
    end

    @testset "PreventUpdate in background job" begin
        mgr = ThreadPoolManager()
        key = "test-key-prevent"

        Dash2.call_job_fn(mgr, key, (_...) -> throw(PreventUpdate()), (), Dict{String,Any}())
        sleep(0.2)

        @test Dash2.result_ready(mgr, key)
        result = Dash2.get_result(mgr, key)
        @test result isa NoUpdate
    end

    @testset "Error in background job" begin
        mgr = ThreadPoolManager()
        key = "test-key-error"

        Dash2.call_job_fn(mgr, key, (_...) -> error("test error"), (), Dict{String,Any}())
        sleep(0.2)

        @test Dash2.result_ready(mgr, key)
        result = Dash2.get_result(mgr, key)
        @test result isa Dict
        @test result["error"] == true
        @test occursin("test error", result["message"])
    end

    @testset "Cache key generation" begin
        key1 = Dash2.make_cache_key("cb1", [1, 2], ["x.y"])
        key2 = Dash2.make_cache_key("cb1", [1, 2], ["x.y"])
        key3 = Dash2.make_cache_key("cb2", [1, 2], ["x.y"])

        @test key1 == key2  # Same inputs = same key
        @test key1 != key3  # Different callback = different key
        @test length(key1) == 32  # MD5 hex
    end

    @testset "Background key generation" begin
        key1 = Dash2.make_background_key("cb1", identity)
        @test length(key1) == 32
    end

    @testset "Callback struct with background fields" begin
        deps = Dash2.CallbackDeps(Output("out", "children"), [Input("in", "value")])

        # Default (non-background)
        cb = Dash2.Callback(identity, deps, false)
        @test cb.background == false
        @test isnothing(cb.background_key)
        @test cb.interval == 1000

        # With background fields
        cb2 = Dash2.Callback(identity, deps, false;
            background=true,
            background_key="abc123",
            interval=500,
            progress=[Output("prog", "value")],
            progress_default=[0],
            cancel=[Dict{String,Any}("id" => "cancel-btn", "property" => "n_clicks")]
        )
        @test cb2.background == true
        @test cb2.background_key == "abc123"
        @test cb2.interval == 500
        @test length(cb2.progress) == 1
        @test cb2.progress_default == [0]
        @test length(cb2.cancel) == 1
    end

    @testset "Background callback registration" begin
        mgr = ThreadPoolManager()
        app = dash(background_callback_manager=mgr, suppress_callback_exceptions=true)
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"), Input("btn", "n_clicks");
            background=true, interval=500
        ) do n_clicks
            return "result: $n_clicks"
        end

        @test length(app.callback_list) == 1
        entry = app.callback_list[1]
        @test haskey(entry, "background")
        @test entry["background"]["interval"] == 500

        cb_key = first(keys(app.callback_map))
        cb = app.callback_map[cb_key]
        @test cb.background == true
        @test cb.interval == 500
    end

    @testset "Background callback list entry with running/cancel" begin
        mgr = ThreadPoolManager()
        app = dash(background_callback_manager=mgr, suppress_callback_exceptions=true)
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"), Input("btn", "n_clicks");
            background=true,
            running=[(Output("btn", "disabled"), true, false)],
            cancel=[Input("cancel-btn", "n_clicks")]
        ) do n_clicks
            return "done"
        end

        entry = app.callback_list[1]
        @test haskey(entry, "running")
        @test haskey(entry, "runningOff")
        @test haskey(entry, "cancel")
        @test length(entry["cancel"]) == 1
    end

    @testset "Background callback with progress registration" begin
        mgr = ThreadPoolManager()
        app = dash(background_callback_manager=mgr, suppress_callback_exceptions=true)
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"), Input("btn", "n_clicks");
            background=true,
            progress=[Output("progress-bar", "value")],
            progress_default=[0]
        ) do set_progress, n_clicks
            set_progress([50])
            return "done"
        end

        entry = app.callback_list[1]
        @test haskey(entry, "progress")
        @test haskey(entry, "progressDefault")
        @test entry["progressDefault"] == [0]
    end
end
