@testset "DashApp" begin
    @testset "dash() factory" begin
        app = dash()
        @test app.config.routes_pathname_prefix == "/"
        @test app.config.requests_pathname_prefix == "/"
        @test app.config.serve_locally == true
        @test app.config.compress == true
        @test app.config.update_title == "Updating..."
        @test app.config.health_endpoint == "_dash-health"
        @test app.config.use_pages == false
        @test app.title == "Dash"
    end

    @testset "dash() with kwargs" begin
        app = dash(
            suppress_callback_exceptions=true,
            prevent_initial_callbacks=true,
            update_title="Loading...",
            show_undo_redo=true
        )
        @test app.config.suppress_callback_exceptions == true
        @test app.config.prevent_initial_callbacks == true
        @test app.config.update_title == "Loading..."
        @test app.config.show_undo_redo == true
    end

    @testset "Layout assignment" begin
        app = dash()

        # Component layout
        app.layout = html_div("Hello")
        @test app.layout isa Dash2.Component

        # Function layout
        app.layout = () -> html_div("Dynamic")
        @test app.layout isa Function
    end

    @testset "Do-block layout" begin
        app = dash() do
            html_div() do
                html_h1("Title"),
                html_p("Body")
            end
        end
        @test app.layout isa Dash2.Component
    end

    @testset "Title assignment" begin
        app = dash()
        app.title = "My App"
        @test app.title == "My App"
    end

    @testset "Read-only properties" begin
        app = dash()
        @test_throws ErrorException app.config = nothing
        @test_throws ErrorException app.root_path = "/tmp"
    end

    @testset "Index string validation" begin
        app = dash()
        @test_throws ErrorException app.index_string = "<html>no placeholders</html>"
    end

    @testset "DevTools" begin
        app = dash()
        Dash2.enable_dev_tools!(app; debug=true)
        @test Dash2.get_devsetting(app, :ui) == true
        @test Dash2.get_devsetting(app, :props_check) == true
    end

    @testset "pathname_configs" begin
        # Default
        (base, req, routes) = Dash2.pathname_configs(nothing, nothing, nothing)
        @test routes == "/"
        @test req == "/"

        # Custom base
        (base, req, routes) = Dash2.pathname_configs("/app/", nothing, nothing)
        @test routes == "/app/"
        @test req == "/app/"

        # Conflicting settings
        @test_throws ErrorException Dash2.pathname_configs("/app/", "/other/", nothing)
    end
end
