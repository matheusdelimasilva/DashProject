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

    @testset "allow_duplicate outputs" begin
        app = dash(suppress_callback_exceptions=true)
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"), Input("in1", "value")) do val
            return val
        end

        # This should not error because allow_duplicate=true
        callback!(app, Output("out", "children"; allow_duplicate=true), Input("in2", "value")) do val
            return val
        end

        @test length(app.callback_list) == 2
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
