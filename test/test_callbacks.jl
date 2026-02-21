@testset "Callbacks" begin
    @testset "Dependency types" begin
        o = Output("id", "children")
        @test o.id == "id"
        @test o.property == "children"
        @test o.allow_duplicate == false

        i = Input("id", "value")
        @test i.id == "id"
        @test i.property == "value"

        s = State("id", "data")
        @test s.id == "id"
        @test s.property == "data"
    end

    @testset "Output with allow_duplicate" begin
        o = Output("id", "children"; allow_duplicate=true)
        @test o.allow_duplicate == true
    end

    @testset "Dependency string" begin
        o = Output("my-id", "children")
        @test Dash2.dependency_string(o) == "my-id.children"
    end

    @testset "Wildcards" begin
        @test Dash2.is_wild(MATCH) == true
        @test Dash2.is_wild(ALL) == true
        @test Dash2.is_wild(ALLSMALLER) == true
        @test Dash2.is_wild("string") == false
    end

    @testset "Callback registration (do-block)" begin
        app = dash()
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"), Input("in", "value")) do val
            return "Hello $val"
        end

        @test length(app.callback_list) == 1
        @test length(app.callback_map) == 1
        @test haskey(app.callback_map, "in.value")  == false  # key is output-based
    end

    @testset "Multi-output callback" begin
        app = dash()
        app.layout = html_div(id="out1")

        callback!(app,
            [Output("out1", "children"), Output("out2", "children")],
            Input("in", "value")
        ) do val
            return ("A: $val", "B: $val")
        end

        @test length(app.callback_list) == 1
        entry = app.callback_list[1]
        @test startswith(entry["output"], "..")
    end

    @testset "Flat deps callback" begin
        app = dash()
        app.layout = html_div(id="out1")

        callback!(app,
            Output("out1", "children"),
            Output("out2", "children"),
            Input("in", "value"),
            State("state", "data")
        ) do val, state_val
            return ("$val", "$state_val")
        end

        @test length(app.callback_list) == 1
        entry = app.callback_list[1]
        @test length(entry["inputs"]) == 1
        @test length(entry["state"]) == 1
    end

    @testset "allow_duplicate: single callback gets @hash key" begin
        app = dash(suppress_callback_exceptions=true)
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"; allow_duplicate=true),
                  Input("in1", "value"); prevent_initial_call=true) do val
            return val
        end

        # Key in callback_map must have @hash suffix (not the plain "out.children")
        @test !haskey(app.callback_map, "out.children")
        cb_key = only(keys(app.callback_map))
        @test startswith(cb_key, "out.children@")

        # The dependency list entry output string must match the map key
        @test app.callback_list[1]["output"] == cb_key
    end

    @testset "allow_duplicate: two callbacks get distinct @hash keys" begin
        app = dash(suppress_callback_exceptions=true)
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"; allow_duplicate=true),
                  Input("in1", "value"); prevent_initial_call=true) do val
            return "from in1: $val"
        end
        callback!(app, Output("out", "children"; allow_duplicate=true),
                  Input("in2", "value"); prevent_initial_call=true) do val
            return "from in2: $val"
        end

        @test length(app.callback_list) == 2
        @test length(app.callback_map) == 2

        # Both keys have @hash suffix
        keys_list = collect(keys(app.callback_map))
        @test all(k -> startswith(k, "out.children@"), keys_list)

        # The two keys are distinct (different inputs → different hashes)
        @test keys_list[1] != keys_list[2]

        # The dependency list entries match the map keys
        outputs_in_list = [e["output"] for e in app.callback_list]
        @test sort(outputs_in_list) == sort(keys_list)
    end

    @testset "allow_duplicate: response uses clean property (no @hash)" begin
        # Simulates the full dispatch path: the response JSON must have the
        # plain property name so the renderer can apply it correctly.
        app = dash(suppress_callback_exceptions=true)
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"; allow_duplicate=true),
                  Input("btn", "n_clicks"); prevent_initial_call=true) do n
            return "clicked"
        end

        cb_key = only(keys(app.callback_map))
        @test startswith(cb_key, "out.children@")

        # Simulate the dispatch the frontend would send
        body = JSON3.write(Dict(
            "output" => cb_key,
            "inputs" => [Dict("id" => "btn", "property" => "n_clicks", "value" => 1)],
            "changedPropIds" => ["btn.n_clicks"],
            "state" => []
        ))
        req = HTTP.Request("POST", "/_dash-update-component",
                           ["Content-Type" => "application/json"], body)
        registry = Dash2.main_registry()
        state = Dash2.HandlerState(app, registry)

        result = Dash2.process_callback(req, state)
        @test result.status == 200

        data = JSON3.read(String(result.body))
        # Response key must be "children" — NOT "children@<hash>"
        @test haskey(data["response"]["out"], "children")
        @test !any(k -> occursin("@", String(k)), keys(data["response"]["out"]))
        @test data["response"]["out"]["children"] == "clicked"
    end

    @testset "allow_duplicate: first plain callback, then duplicate" begin
        app = dash(suppress_callback_exceptions=true)
        app.layout = html_div(id="out")

        # First: plain output (no allow_duplicate)
        callback!(app, Output("out", "children"), Input("in1", "value")) do val
            return val
        end

        # Second: same output with allow_duplicate — must NOT error
        callback!(app, Output("out", "children"; allow_duplicate=true),
                  Input("in2", "value"); prevent_initial_call=true) do val
            return val
        end

        @test length(app.callback_list) == 2
        # Plain key for first, hashed for second
        @test haskey(app.callback_map, "out.children")
        hashed_keys = filter(k -> occursin("@", k), collect(keys(app.callback_map)))
        @test length(hashed_keys) == 1
    end

    @testset "Duplicate output without allow_duplicate errors" begin
        app = dash()
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"), Input("in1", "value")) do val
            return val
        end

        @test_throws ErrorException callback!(app, Output("out", "children"), Input("in2", "value")) do val
            return val
        end
    end

    @testset "Clientside callback" begin
        app = dash()
        app.layout = html_div(id="out")

        Dash2.make_callback_func!(app, "function(v) { return v; }",
            Dash2.CallbackDeps(Output("out", "children"), [Input("in", "value")]))

        @test length(app.inline_scripts) == 1
        @test occursin("dash_clientside", app.inline_scripts[1])
    end

    @testset "CallbackContext" begin
        ctx = Dash2.CallbackContext(
            HTTP.Response(200),
            [(id="out", property="children")],
            [(id="in", property="value", value="hello")],
            [],
            ["in.value"]
        )
        @test ctx.inputs["in.value"] == "hello"
        @test length(ctx.triggered) == 1
        @test ctx.triggered[1].prop_id == "in.value"
    end

    @testset "Callback validation" begin
        app = dash()
        app.layout = html_div(id="out")

        # Wrong number of arguments
        @test_throws ErrorException callback!(app, Output("out", "children"), Input("in", "value")) do
            return "no args"
        end
    end
end
