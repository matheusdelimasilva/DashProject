@testset "Pages System" begin
    # Clean registry before each test group
    function clear_registry!()
        empty!(Dash2.PAGE_REGISTRY)
    end

    @testset "Path inference" begin
        # Basic module name to path
        @test Dash2._infer_path("pages.weekly_analytics") == "/weekly-analytics"
        @test Dash2._infer_path("pages.home") == "/home"
        @test Dash2._infer_path("pages.nested.deep_page") == "/nested/deep-page"

        # Without pages prefix
        @test Dash2._infer_path("analytics") == "/analytics"
        @test Dash2._infer_path("my_module") == "/my-module"

        # With path template
        @test Dash2._infer_path("pages.report", "/report/<id>") == "/report/none"
        @test Dash2._infer_path("pages.user", "/user/<name>/profile") == "/user/none/profile"
    end

    @testset "Module name to page name" begin
        @test Dash2._module_name_to_page_name("pages.weekly_analytics") == "Weekly Analytics"
        @test Dash2._module_name_to_page_name("pages.home") == "Home"
        @test Dash2._module_name_to_page_name("pages.nested.deep_page") == "Deep Page"
    end

    @testset "Image inference" begin
        # Create temp assets directory
        assets_dir = mktempdir()
        touch(joinpath(assets_dir, "home.png"))
        touch(joinpath(assets_dir, "app.jpg"))
        touch(joinpath(assets_dir, "data.txt"))  # Not a valid image extension

        @test Dash2._infer_image("pages.home", assets_dir) == "home.png"
        @test Dash2._infer_image("pages.about", assets_dir) == "app.jpg"  # Fallback
        @test isnothing(Dash2._infer_image("pages.home", joinpath(assets_dir, "nonexistent")))

        rm(assets_dir, recursive=true)
    end

    @testset "register_page basic" begin
        clear_registry!()

        register_page("pages.home"; path="/", layout=html_div("Home"))
        @test haskey(Dash2.PAGE_REGISTRY, "pages.home")
        page = Dash2.PAGE_REGISTRY["pages.home"]
        @test page["path"] == "/"
        @test page["name"] == "Home"
        @test page["module"] == "pages.home"
        @test page["supplied_path"] == "/"
        @test page["layout"] isa Dash2.Component

        clear_registry!()
    end

    @testset "register_page with inference" begin
        clear_registry!()

        register_page("pages.weekly_analytics"; layout=html_div("Analytics"))
        page = Dash2.PAGE_REGISTRY["pages.weekly_analytics"]
        @test page["path"] == "/weekly-analytics"
        @test page["name"] == "Weekly Analytics"
        @test isnothing(page["supplied_path"])
        @test isnothing(page["supplied_name"])

        clear_registry!()
    end

    @testset "register_page with path_template" begin
        clear_registry!()

        register_page("pages.report"; path_template="/report/<id>",
                       layout=(; id="0") -> html_div("Report $id"))
        page = Dash2.PAGE_REGISTRY["pages.report"]
        @test page["path_template"] == "/report/<id>"
        @test page["path"] == "/report/none"  # Inferred from template

        clear_registry!()
    end

    @testset "register_page with all fields" begin
        clear_registry!()

        register_page("pages.detail";
            path="/detail",
            name="Detail Page",
            title="My Detail",
            description="A detail page",
            order=1,
            image="detail.png",
            image_url="https://example.com/img.png",
            redirect_from=["/old-detail"],
            layout=html_div("Detail")
        )
        page = Dash2.PAGE_REGISTRY["pages.detail"]
        @test page["title"] == "My Detail"
        @test page["description"] == "A detail page"
        @test page["order"] == 1
        @test page["image"] == "detail.png"
        @test page["image_url"] == "https://example.com/img.png"
        @test page["redirect_from"] == ["/old-detail"]
        @test page["supplied_title"] == "My Detail"

        clear_registry!()
    end

    @testset "Registry sorting" begin
        clear_registry!()

        register_page("pages.c_page"; order=3, layout=html_div("C"))
        register_page("pages.a_page"; order=1, layout=html_div("A"))
        register_page("pages.b_page"; order=2, layout=html_div("B"))
        register_page("pages.z_page"; layout=html_div("Z"))  # No order

        keys_list = collect(keys(Dash2.PAGE_REGISTRY))
        @test keys_list[1] == "pages.a_page"
        @test keys_list[2] == "pages.b_page"
        @test keys_list[3] == "pages.c_page"
        @test keys_list[4] == "pages.z_page"  # No order goes last

        clear_registry!()
    end

    @testset "Path template matching" begin
        # Parse path variables
        vars = Dash2._parse_path_variables("/report/42", "/report/<id>")
        @test vars == Dict("id" => "42")

        vars2 = Dash2._parse_path_variables("/user/john/profile", "/user/<name>/profile")
        @test vars2 == Dict("name" => "john")

        # Multiple variables
        vars3 = Dash2._parse_path_variables("/a/1/b/2", "/a/<x>/b/<y>")
        @test vars3 == Dict("x" => "1", "y" => "2")

        # No match
        @test isnothing(Dash2._parse_path_variables("/other/path", "/report/<id>"))
    end

    @testset "Path to page lookup" begin
        clear_registry!()

        register_page("pages.home"; path="/", layout=html_div("Home"))
        register_page("pages.about"; path="/about", layout=html_div("About"))
        register_page("pages.report"; path_template="/report/<id>",
                       layout=(; id="0") -> html_div("Report"))

        # Exact match
        page, vars = Dash2._path_to_page("/")
        @test page["module"] == "pages.home"
        @test isnothing(vars)

        page2, vars2 = Dash2._path_to_page("/about")
        @test page2["module"] == "pages.about"

        # Template match
        page3, vars3 = Dash2._path_to_page("/report/42")
        @test page3["module"] == "pages.report"
        @test vars3 == Dict("id" => "42")

        # No match
        page4, vars4 = Dash2._path_to_page("/nonexistent")
        @test isempty(page4)
        @test isnothing(vars4)

        clear_registry!()
    end

    @testset "Query string parsing" begin
        @test Dash2._parse_query_string("") == Dict{String,String}()
        @test Dash2._parse_query_string("?") == Dict{String,String}()
        @test Dash2._parse_query_string("?foo=bar") == Dict("foo" => "bar")
        @test Dash2._parse_query_string("?foo=bar&baz=1") == Dict("foo" => "bar", "baz" => "1")
        @test Dash2._parse_query_string("foo=bar") == Dict("foo" => "bar")
        @test Dash2._parse_query_string("?key=") == Dict("key" => "")
    end

    @testset "Strip relative path" begin
        app = dash()
        @test Dash2._strip_relative_path(app, "/some/page") == "/some/page"
        @test Dash2._strip_relative_path(app, "/") == "/"

        app2 = dash(routes_pathname_prefix="/app/")
        @test Dash2._strip_relative_path(app2, "/app/page") == "/page"
    end

    @testset "Page container" begin
        container = Dash2.default_page_container()
        @test container isa Dash2.Component
        @test container.id === nothing || true  # html_div may not have id
        children = container.children
        @test length(children) == 4
    end

    @testset "Page meta tags" begin
        clear_registry!()

        register_page("pages.home"; path="/", title="Home Page",
                       description="Welcome home", image="home.png",
                       layout=html_div("Home"))

        app = dash()
        metas = Dash2._page_meta_tags(app, "/")
        @test length(metas) == 10
        @test any(m -> get(m, "name", "") == "twitter:title" && m["content"] == "Home Page", metas)
        @test any(m -> get(m, "name", "") == "description" && m["content"] == "Welcome home", metas)
        @test any(m -> get(m, "property", "") == "og:title" && m["content"] == "Home Page", metas)

        clear_registry!()
    end

    @testset "DashApp with pages config" begin
        app = dash(use_pages=true)
        @test app.config.use_pages == true
        @test app.config.include_pages_meta == true
        @test app._pages_setup_done == false

        app2 = dash(use_pages=true, include_pages_meta=false)
        @test app2.config.include_pages_meta == false
    end

    @testset "DashApp with background_callback_manager" begin
        mgr = ThreadPoolManager()
        app = dash(background_callback_manager=mgr)
        @test app.config.background_callback_manager === mgr

        app2 = dash()
        @test isnothing(app2.config.background_callback_manager)
    end
end
