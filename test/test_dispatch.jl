@testset "Dispatch" begin
    @testset "NoUpdate" begin
        @test Dash2.is_no_update(no_update) == true
        @test Dash2.is_no_update(NoUpdate()) == true
        @test Dash2.is_no_update(Dict("_dash_no_update" => "_dash_no_update")) == true
        @test Dash2.is_no_update("string") == false
        @test Dash2.is_no_update(42) == false
    end

    @testset "NoUpdate JSON" begin
        json_str = String(JSON3.rawbytes(no_update))
        @test json_str == "{\"_dash_no_update\":\"_dash_no_update\"}"
    end

    @testset "PreventUpdate" begin
        @test PreventUpdate() isa Exception
        @test_throws PreventUpdate throw(PreventUpdate())
    end

    @testset "split_callback_id" begin
        # Single output
        result = Dash2.split_single_callback_id("my-id.children")
        @test result.id == "my-id"
        @test result.property == "children"

        # Multi output
        result = Dash2.split_callback_id("..out1.children...out2.value..")
        @test length(result) == 2
    end

    @testset "Grouping utilities" begin
        # flatten_grouping
        @test Dash2.flatten_grouping([1, 2, 3]) == [1, 2, 3]
        @test Dash2.flatten_grouping([[1, 2], 3]) == [1, 2, 3]
        @test Dash2.flatten_grouping(Dict("a" => 1, "b" => 2)) == [1, 2]
        @test Dash2.flatten_grouping(42) == [42]

        # grouping_len
        @test Dash2.grouping_len([1, 2, 3]) == 3
        @test Dash2.grouping_len([[1, 2], 3]) == 3

        # make_grouping_by_index
        schema = [[nothing, nothing], nothing]
        result = Dash2.make_grouping_by_index(schema, [10, 20, 30])
        @test result == [[10, 20], 30]

        # map_grouping
        result = Dash2.map_grouping(x -> x * 2, [[1, 2], 3])
        @test result == [[2, 4], 6]
    end

    @testset "Callback execution" begin
        app = dash()
        app.layout = html_div(id="out")

        callback!(app, Output("out", "children"), Input("in", "value")) do val
            return "Result: $val"
        end

        # Simulate a callback dispatch
        cb_key = first(keys(app.callback_map))
        cb = app.callback_map[cb_key]
        result = cb.func("test_value")
        @test result == "Result: test_value"
    end

    @testset "Multi-output callback execution" begin
        app = dash()
        app.layout = html_div(id="out1")

        callback!(app,
            [Output("out1", "children"), Output("out2", "value")],
            Input("in", "value")
        ) do val
            return ("Text: $val", val)
        end

        cb_key = first(keys(app.callback_map))
        cb = app.callback_map[cb_key]
        result = cb.func("hello")
        @test result == ("Text: hello", "hello")
    end

    @testset "set_props via context" begin
        ctx = Dash2.CallbackContext(
            HTTP.Response(200),
            [(id="out", property="children")],
            [(id="in", property="value", value="hello")],
            [],
            ["in.value"]
        )

        Dash2.with_callback_context(ctx) do
            Dash2.set_props("other-comp", Dict("value" => 42))
        end

        @test haskey(ctx.updated_props, "other-comp")
        @test ctx.updated_props["other-comp"]["value"] == 42
    end
end
