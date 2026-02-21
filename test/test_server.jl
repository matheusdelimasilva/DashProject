@testset "Server" begin
    @testset "Router" begin
        router = Dash2.Router()

        handler1 = (req, state; kwargs...) -> HTTP.Response(200, body="layout")
        handler2 = (req, state; namespace, path) -> HTTP.Response(200, body="resource:$namespace/$path")

        Dash2.add_route!(handler1, router, "/_dash-layout")
        Dash2.add_route!(handler2, router, "/_dash-component-suites/<namespace>/<path>")

        # Static route
        req = HTTP.Request("GET", "/_dash-layout")
        resp = Dash2.handle(router, req, nothing)
        @test resp.status == 200
        @test String(resp.body) == "layout"

        # Dynamic route
        req = HTTP.Request("GET", "/_dash-component-suites/dash_html/file.js")
        resp = Dash2.handle(router, req, nothing)
        @test resp.status == 200
        @test String(resp.body) == "resource:dash_html/file.js"

        # 404
        req = HTTP.Request("GET", "/nonexistent")
        resp = Dash2.handle(router, req, nothing)
        @test resp.status == 404
    end

    @testset "Fingerprint" begin
        fp = Dash2.build_fingerprint("dash_html/file.min.js", "2.0.12", "abc123")
        @test occursin("v2_0_12", fp)
        @test occursin("mabc123", fp)

        (orig, is_fp) = Dash2.parse_fingerprint_path(fp)
        @test is_fp == true
        @test orig == "dash_html/file.min.js"

        (orig2, is_fp2) = Dash2.parse_fingerprint_path("plain/file.js")
        @test is_fp2 == false
        @test orig2 == "plain/file.js"
    end

    @testset "Compression handler" begin
        inner = Dash2.RequestHandlerFunction(
            (req) -> HTTP.Response(200, ["Content-Type" => "application/json"],
                                   body=Vector{UInt8}(repeat("x", 1000)))
        )
        handler = Dash2.compress_handler(inner)

        req = HTTP.Request("GET", "/test")
        HTTP.setheader(req, "Accept-Encoding" => "gzip")
        resp = Dash2.handle(handler, req)
        @test resp.status == 200
        ce = HTTP.header(resp, "Content-Encoding")
        @test ce == "gzip"
        @test length(resp.body) < 1000  # compressed
    end

    @testset "Exception handling handler" begin
        inner = Dash2.RequestHandlerFunction(
            (req) -> error("test error")
        )
        handler = Dash2.exception_handling_handler(inner) do ex
            HTTP.Response(500, body="caught")
        end

        req = HTTP.Request("GET", "/test")
        resp = Dash2.handle(handler, req)
        @test resp.status == 500
        @test String(resp.body) == "caught"
    end

    @testset "Make handler creates valid handler" begin
        app = dash()
        app.layout = html_div("Hello"; id="main")

        callback!(app, Output("main", "children"), Input("in", "value")) do val
            return val
        end

        Dash2.enable_dev_tools!(app; debug=false, dev_tools_hot_reload=false)
        handler = Dash2.make_handler(app)

        # Test index page
        req = HTTP.Request("GET", "/")
        HTTP.setheader(req, "Accept-Encoding" => "gzip")
        resp = Dash2.handle(handler, req)
        @test resp.status == 200

        # Test layout endpoint
        req = HTTP.Request("GET", "/_dash-layout")
        resp = Dash2.handle(handler, req)
        @test resp.status == 200
        body = String(resp.body)
        @test occursin("Div", body)

        # Test dependencies endpoint
        req = HTTP.Request("GET", "/_dash-dependencies")
        resp = Dash2.handle(handler, req)
        @test resp.status == 200
        body = String(resp.body)
        @test occursin("main.children", body)

        # Test health endpoint
        req = HTTP.Request("GET", "/_dash-health")
        resp = Dash2.handle(handler, req)
        @test resp.status == 200
        @test occursin("ok", String(resp.body))

        # Test 404
        req = HTTP.Request("GET", "/_nonexistent-endpoint-xyz")
        resp = Dash2.handle(handler, req)
        # Catch-all route serves index for unknown paths
        @test resp.status == 200
    end
end
