@testset "Components" begin
    @testset "html_div" begin
        div = html_div("Hello"; id="test")
        @test Dash2.get_type(div) == "Div"
        @test Dash2.get_namespace(div) == "dash_html_components"
        @test div.id == "test"
        @test div.children == "Hello"
    end

    @testset "html_div with do-block" begin
        div = html_div(id="parent") do
            html_h1("Title"; id="h1"),
            html_p("Body"; id="p")
        end
        @test div.id == "parent"
        @test length(div.children) == 2
    end

    @testset "dcc_input" begin
        inp = dcc_input(id="inp", value="test", type="text")
        @test Dash2.get_type(inp) == "Input"
        @test Dash2.get_namespace(inp) == "dash_core_components"
        @test inp.value == "test"
        @test inp.type == "text"
    end

    @testset "Component property access" begin
        div = html_div(id="test", style=Dict("color" => "red"))
        @test div.style == Dict("color" => "red")
        @test div.className === nothing  # unset property returns nothing

        # Setting a property
        div.className = "my-class"
        @test div.className == "my-class"
    end

    @testset "Component wildcard props" begin
        div = html_div(id="test")
        div.var"data-value" = "42"
        @test div.var"data-value" == "42"
    end

    @testset "Component JSON serialization" begin
        div = html_div("Hello"; id="test")
        json_str = JSON3.write(div)
        parsed = JSON3.read(json_str)
        @test parsed.type == "Div"
        @test parsed.namespace == "dash_html_components"
        @test parsed.props.id == "test"
        @test parsed.props.children == "Hello"
    end

    @testset "Component tree lookup" begin
        layout = html_div(id="root") do
            html_h1("Title"; id="title"),
            html_p("Body"; id="body")
        end
        @test layout["title"] !== nothing
        @test Dash2.get_type(layout["title"]) == "H1"
    end

    @testset "dash_datatable exists" begin
        @test isdefined(Dash2, :dash_datatable)
    end
end
