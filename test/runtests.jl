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

    @testset "get_comment" begin
        @test Bisect.get_comment("https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1834044633") == "hello from a file\n"
        @test Bisect.get_comment("https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1833915675") == "@LilithHafnerBot bisect()"
        @test_broken Bisect.get_comment("https://github.com/LilithHafner/Bisect.jl/issues/8#issue-2017841366") == "Ref: https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1833079041"
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

    @testset "workflow() doesn't throw" begin
        ENV["BISECT_AUTH"] = "test"
        ENV["BISECT_TRIGGER_LINK"] = "https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1836868167"
        response = Bisect.workflow()
        @test response isa Bisect.HTTP.Messages.Response
        @test response.status == 200
    end
end
