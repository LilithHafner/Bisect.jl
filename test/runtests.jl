using Bisect
using Test
using Aqua
using Markdown

@testset "Bisect.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Bisect, deps_compat=false)
        Aqua.test_deps_compat(Bisect, check_extras=false)
    end
    @testset "Successful bisection examples" begin
        @test startswith(string(bisect(@__DIR__, """length(read("runtests.jl"))""", old="49093a00f4850120d17fa9ef9cae3ff0f37cacfb")), """
        ### ✅ Bisect succeeded! The first new commit is 06051c5cf084fefc43b06bf2527960db6489a6ec

        | Commit                                       | **Exit code** | stdout  | stderr                                                                                           |
        |:-------------------------------------------- |:------------- |:------- |:------------------------------------------------------------------------------------------------ |
        | 49093a00f4850120d17fa9ef9cae3ff0f37cacfb     | ❌ (1)         |         | ERROR: SystemError: opening file \"runtests.jl\": No such file or directory⏎Stacktrace:⏎ [1] sy... |
        | **06051c5cf084fefc43b06bf2527960db6489a6ec** | **✅ (0)**     | **178** | ****                                                                                             |
        """)

        res = bisect(@__DIR__, """length(read("runtests.jl")) == 178""", old="06051c5cf084fefc43b06bf2527960db6489a6ec")
        @test startswith(string(res), """
        ### ✅ Bisect succeeded! The first new commit is 5da09c5e603fcbe72adf6ae2c8e3dbbfd07058c5

        | Commit                                       | **stdout** |
        |:-------------------------------------------- |:---------- |
        | """)
        @test occursin("""
        | 437431697efdadcb5c04ef4707442a8ab25f6d84     | true       |
        | **5da09c5e603fcbe72adf6ae2c8e3dbbfd07058c5** | **false**  |
        """, string(res))
    end

    @testset "Failed bisection examples" begin
        @test startswith(string(bisect(@__DIR__, "@assert 1+1 == 2", old="49093a00f4850120d17fa9ef9cae3ff0f37cacfb")), """
        ### ❌ Bisect failed

        | Commit                                   | stdout  |
        |:---------------------------------------- |:------- |
        | 49093a00f4850120d17fa9ef9cae3ff0f37cacfb | nothing |
        | """)

        @test startswith(string(bisect(@__DIR__, "@assert 1+1 == 3", old="49093a00f4850120d17fa9ef9cae3ff0f37cacfb")), """
        ### ❌ Bisect failed

        | Commit                                   | Exit code | stderr                                                                          |
        |:---------------------------------------- |:--------- |:------------------------------------------------------------------------------- |
        | 49093a00f4850120d17fa9ef9cae3ff0f37cacfb | ❌ (1)     | ERROR: AssertionError: 1 + 1 == 3⏎Stacktrace:⏎ [1] top-level scope⏎   @ none:2⏎ |
        | """)

        @test startswith(string(bisect(@__DIR__, "rand()", old="49093a00f4850120d17fa9ef9cae3ff0f37cacfb")), "### ❌ Bisect failed\n\n|")

        @test startswith(string(bisect("rand()", old="49093a00f4850120d17fa9ef9cae3ff0f37cacfb", auto_print=false)), """
        ### ❌ Bisect failed

        | Commit                                   | Exit code | stdout | stderr |
        |:---------------------------------------- |:--------- |:------ |:------ |
        | 49093a00f4850120d17fa9ef9cae3ff0f37cacfb | ✅ (0)     |        |        |
        | """)
    end

    @testset "Workflow error messages" begin
        @test string(Bisect._workflow("link", """
        `new = main`
        `old = deadbeef`
        ```julla
        1+1 == 2
        ```
        """, @__DIR__, verbose=false)) == """
        ### ❗ Internal Error

        Could not find `@LilithHafnerBot bisect`
        """

        @test string(Bisect._workflow("link", """
        @LilithHafnerBot bisect(new = main, old = deadbeef)

        ```julla
        1+1 == 2
        ```
        """, @__DIR__, verbose=false)) == """
        ### ⚠️ Parse Error

        I found `@LilithHafnerBot bisect(<args>)` and a code block, but the code block was not tagged with "julla", not "julia". I can currently only handle julia code.
        """

        @test string(Bisect._workflow("link", """
        @LilithHafnerBot bisect(new = main, old = deadbeef)

        ```julia
        1+1 == 2
        ```
        """, @__DIR__, verbose=false)) == """
        ### ⚠️ Parse Error

        I don't understand the ref "deadbeef".

        `git checkout deadbeef` failed.
        """

        @test string(Bisect._workflow("link", """
        @LilithHafnerBot bisect(old=livebeef, new = deadbeef)

        ```julia
        1+1 == 2
        ```
        """, @__DIR__, verbose=false)) == """### ⚠️ Parse Error

        I don't understand the refs "livebeef" or "deadbeef".

        Both `git checkout livebeef` and `git checkout deadbeef` failed.
        """
    end

    @testset "Workflow usage produces the same results and standard usage" begin
        file = tempname()
        default_old = Bisect.default_old()
        default_new = Bisect.default_new()
        @test default_new == "HEAD"
        @test default_old isa String

        comment = """

            Let's `bisect()` this

            `@LilithHafnerBot bisect(old=06051c5cf084fefc43b06bf2527960db6489a6ec)`

            ```julia
            length(read("runtests.jl")) == 178
            ```
            """
        link = "ho link"
        workflow = Bisect._workflow("no link",  """

        Let's `bisect()` this

        @LilithHafnerBot

         bisect(old=06051c5cf084fefc43b06bf2527960db6489a6ec)

        ```julia
        length(read("runtests.jl")) == 178
        ```
        """, @__DIR__, verbose=false)
        standard = bisect(@__DIR__, """length(read("runtests.jl")) == 178""", old="06051c5cf084fefc43b06bf2527960db6489a6ec", new="HEAD")
        @test workflow == standard
        @test occursin("Bisect succeeded", string(workflow))

        # Strange newline characters
        comment = "`@LilithHafnerBot bisect(new=main, old=06051c5cf084fefc43b06bf2527960db6489a6ec)`\r \r `new=main`\r `old = 06051c5cf084fefc43b06bf2527960db6489a6ec`\r \r ```julia\r @assert 1+1 == 2\r ```\n"
        workflow2 = Bisect._workflow("no link", comment, @__DIR__, verbose=false)
        standard2 = bisect(@__DIR__, """@assert 1+1 == 2""", old="06051c5cf084fefc43b06bf2527960db6489a6ec", new="main")
        @test workflow2 == standard2
        @test occursin("Bisect failed", string(workflow2))
    end

    @testset "get_link_info" begin
        @test Bisect.get_link_info("https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1834044633") == (repo="LilithHafner/Bisect.jl", bare_name="Bisect", comment="hello from a file\n")
        @test Bisect.get_link_info("https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1833915675") == (repo="LilithHafner/Bisect.jl", bare_name="Bisect", comment="@LilithHafnerBot bisect()")
        @test Bisect.get_link_info("https://github.com/LilithHafner/Bisect.jl/issues/8") == (repo="LilithHafner/Bisect.jl", bare_name="Bisect", comment="Ref: https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1833079041")
        @test Bisect.get_link_info("https://github.com/JuliaCollections/SortingAlgorithms.jl/issues/81") == (repo="JuliaCollections/SortingAlgorithms.jl", bare_name="SortingAlgorithms", comment="Following [this](https://app.slack.com/client/T68168MUP) slack thread, it would be nice to have an implementation of [std::partition](https://en.cppreference.com/w/cpp/algorithm/partition).")
        @test Bisect.get_link_info("https://github.com/JuliaLang/julia/pull/50372") == (repo="JuliaLang/julia", bare_name="julia", comment="Fix for #50352 ")
    end

    @testset "parse_comment parse errors" begin
        @test Bisect.parse_comment("Hi!") isa Markdown.MD
        @test Bisect.parse_comment("""
            @LilithHafnerBot bisect
            """) isa Markdown.MD
        @test Bisect.parse_comment("""
            @LilithHafnerBot bisect()
            """) isa Markdown.MD
        @test Bisect.parse_comment("""
            @LilithHafnerBot bisect(<args>)

            ```Julia
            code
            ```
            """) isa Markdown.MD
        @test Bisect.parse_comment("""
            @LilithHafnerBot bisect(<args>)

            ```
            code
            ```
            """) isa Markdown.MD
        @test Bisect.parse_comment("""
            @LilithHafnerBot bisect

            ```julia
            code
            ```
            """) isa Markdown.MD
    end

    @testset "parse_comment success" begin
        @test Bisect.parse_comment("""
            @LilithHafnerBot bisect(<args>)

            ```julia
            code
            ```
            """) == ("<args>", "code")

        @test Bisect.parse_comment("""
            ```julia
            codddeee
            ```

            @LilithHafnerBot bisect(new=1 old = 2)
            """) == ("new=1 old = 2", "codddeee")


        @test Bisect.parse_comment("""
            ```julia
            # Yes, even here: @LilithHafnerBot bisect()
            codddeee
            ```

            Though I still need to notify @LilithHafnerBot
            """) == ("", "# Yes, even here: @LilithHafnerBot bisect()\ncodddeee")

        @test Bisect.parse_comment("""
            ````julia
            @assert 1+1 == 2
            ```` @LilithHafnerBot bisect()
            """) == ("", "@assert 1+1 == 2")
    end

    @testset "parse_args errors" begin
        @test occursin("has no \"=\" sign", string(Bisect.parse_args("new")::Markdown.MD))
        @test occursin("multiple \"=\" signs", string(Bisect.parse_args("n=e=w")::Markdown.MD))
        @test occursin("multiple \"=\" signs", string(Bisect.parse_args("new = 1 old = 2")::Markdown.MD))
        @test occursin("It looks like you kept the placeholder", string(Bisect.parse_args("<args>")::Markdown.MD))
        err = string(Bisect.parse_args("abc=3, abc=4")::Markdown.MD)
        @test occursin("is not a valid key", err)
        @test occursin("Duplicate key", err)
        @test occursin("is not a valid key", string(Bisect.parse_args("abc=3")::Markdown.MD))
        @test occursin("Duplicate key", string(Bisect.parse_args("new=3, new=3")::Markdown.MD))
        @test occursin("is not a valid key", string(Bisect.parse_args("new=3, Old=asjd")::Markdown.MD))
        @test Bisect.parse_args("new=3, old=asjd,") isa Markdown.MD
    end

    @testset "parse_args success" begin
        @test Bisect.parse_args("new=1, old \t= 2") == Dict("new" => "1", "old" => "2")
        @test Bisect.parse_args("") isa Dict{String, String}
        @test Bisect.parse_args("") == Dict{String, String}()
        @test Bisect.parse_args("  \t") == Dict{String, String}()
        @test Bisect.parse_args("old= <s.%h:q @v ") == Dict("old" => "<s.%h:q @v")
        @test Bisect.parse_args("old=HEAD~10, new=HEAD") == Dict("old" => "HEAD~10", "new" => "HEAD")
    end

    @testset "get_tags(), get_first_commit(), and default_old()" begin
        cd(mktempdir()) do
            run(`git init -b main`)

            if get(ENV, "CI", "false") == "true"
                run(`git config user.email "CI@example.com"`)
                run(`git config user.name "CI"`)
            end

            run(`git commit --allow-empty -m "first commit"`)
            root = readchomp(`git rev-parse --verify HEAD`)
            @testset "no tags" begin
                @test isempty(Bisect.get_tags())
                @test Bisect.get_first_commit() == root
                @test Bisect.default_old() == root

                run(`git commit --allow-empty -m "second commit"`)

                @test isempty(Bisect.get_tags())
                @test Bisect.get_first_commit() == root
                @test Bisect.default_old() == root

                run(`git checkout --orphan second-root`)
                run(`git commit --allow-empty -m "first commit on second root"`)
                root2 = readchomp(`git rev-parse --verify HEAD`)

                @test isempty(Bisect.get_tags())
                @test Bisect.get_first_commit() == root2
                @test Bisect.default_old() == root2

                run(`git checkout main`)
                run(`git merge --allow-unrelated-histories --no-edit second-root`)

                @test isempty(Bisect.get_tags())
                @test Bisect.get_first_commit() == root
                @test Bisect.default_old() == root

                sleep(1.1)

                run(`git checkout --orphan third-root`)
                run(`git commit --allow-empty -m "first commit on third root"`)
                root3 = readchomp(`git rev-parse --verify HEAD`)

                @test isempty(Bisect.get_tags())
                @test Bisect.get_first_commit() == root3
                @test Bisect.default_old() == root3

                run(`git checkout main`)
                run(`git merge --allow-unrelated-histories --no-edit third-root`)

                @test isempty(Bisect.get_tags())
                @test Bisect.get_first_commit() == root
                @test Bisect.default_old() == root
            end

            @testset "tags" begin
                run(`git tag -a -m "first tag" first-tag`)

                @test isempty(Bisect.get_tags())
                @test Bisect.get_first_commit() == root
                @test Bisect.default_old() == root

                run(`git commit --allow-empty -m "another commit"`)
                run(`git tag -a -m "v1.0.0-beta" v1.0.0-beta`)

                @test Bisect.get_tags() == [v"1-beta" => "v1.0.0-beta"]
                @test Bisect.get_first_commit() == root
                @test Bisect.default_old() == "v1.0.0-beta"

                run(`git commit --allow-empty -m "another commit 2"`)
                run(`git tag -a -m "v0.0.0" v0.0.0`)

                @test sort(Bisect.get_tags()) == [v"0" => "v0.0.0", v"1-beta" => "v1.0.0-beta"]
                @test Bisect.get_first_commit() == root
                @test Bisect.default_old() == "v0.0.0"

                run(`git commit --allow-empty -m "yet another commit"`)
                run(`git tag -a -m "0.0.1" 0.0.1`)
                @test sort(Bisect.get_tags()) == [v"0" => "v0.0.0", v"0.0.1" => "0.0.1", v"1-beta" => "v1.0.0-beta"]
                @test Bisect.default_old() == "v0.0.0"

                run(`git commit --allow-empty -m "1.0+1"`)
                run(`git tag -a -m "1.0+1" 1.0+1`)
                @test sort(Bisect.get_tags()) == [v"0" => "v0.0.0", v"0.0.1" => "0.0.1", v"1-beta" => "v1.0.0-beta", v"1+1" => "1.0+1"]
                @test Bisect.default_old() == "1.0+1"

                run(`git commit --allow-empty -m "1.0"`)
                run(`git tag -a -m "1.0" 1.0`)
                @test sort(Bisect.get_tags()) == [v"0" => "v0.0.0", v"0.0.1" => "0.0.1", v"1-beta" => "v1.0.0-beta", v"1.0" => "1.0", v"1+1" => "1.0+1"]
                @test Bisect.default_old() == "1.0"

                run(`git commit --allow-empty -m "1.1"`)
                run(`git tag -a -m "1.1" 1.1`)
                @test sort(Bisect.get_tags()) == [v"0" => "v0.0.0", v"0.0.1" => "0.0.1", v"1-beta" => "v1.0.0-beta", v"1.0" => "1.0", v"1+1" => "1.0+1", v"1.1" => "1.1"]
                @test Bisect.default_old() == "1.0"

                run(`git commit --allow-empty -m "2.0"`)
                run(`git tag -a -m "2.0" 2.0`)
                @test sort(Bisect.get_tags()) == [v"0" => "v0.0.0", v"0.0.1" => "0.0.1", v"1-beta" => "v1.0.0-beta", v"1.0" => "1.0", v"1+1" => "1.0+1", v"1.1" => "1.1", v"2.0" => "2.0"]
                @test Bisect.default_old() == "2.0"
            end
        end
    end
end


const HTTP_LOG = Tuple{String, String}[]
@eval Bisect.HTTP.post(url::String; body) = push!(HTTP_LOG, (url, body)) # Terrible piracy, but this is a test and we clean it up
try
    @testset "workflow()" begin
        ENV["BISECT_AUTH"] = "test_key"
        ENV["BISECT_TRIGGER_LINK"] = "https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1837292185"
        response = invokelatest(Bisect.workflow)
        @test response === HTTP_LOG

        @test only(HTTP_LOG) == ("https://lilithhafner.com/lilithhafnerbot/trigger_2.php", """
        test_key,https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1837292185,### ✅ Bisect succeeded! The first new commit is 06051c5cf084fefc43b06bf2527960db6489a6ec

        | Commit                                       | **Exit code** | stdout   | stderr                                                                                           |
        |:-------------------------------------------- |:------------- |:-------- |:------------------------------------------------------------------------------------------------ |
        | 49093a00f4850120d17fa9ef9cae3ff0f37cacfb     | ❌ (1)         |          | ERROR: SystemError: opening file \"test/runtests.jl\": No such file or directory⏎Stacktrace:⏎ [... |
        | **06051c5cf084fefc43b06bf2527960db6489a6ec** | **✅ (0)**     | **true** | ****                                                                                             |
        | 21443987ee59b3d9225b8d2f162c9f766b2c84a4     | ✅ (0)         | true     |                                                                                                  |
        | 0e50dedd40e9726302803650df950ea17e9f758a     | ✅ (0)         | true     |                                                                                                  |
        | 437431697efdadcb5c04ef4707442a8ab25f6d84     | ✅ (0)         | true     |                                                                                                  |
        | 534fc58d4c6b2a767189ddf12449f3604c037529     | ✅ (0)         | false    |                                                                                                  |
        """)

        empty!(HTTP_LOG)
        ENV["BISECT_TRIGGER_LINK"] = "https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1837292489"
        @test_throws ProcessFailedException invokelatest(Bisect.workflow)
        @test only(HTTP_LOG) == ("https://lilithhafner.com/lilithhafnerbot/trigger_2.php", """
        test_key,https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1837292489,### ❗ Internal Error

        Check the [public logs](https://github.com/LilithHafnerBot/bisect/actions/workflows/Bisect.yml) for more information.
        """)
    end
finally
    Base.delete_method(Base.which(Bisect.HTTP.post, Tuple{String}))
end
