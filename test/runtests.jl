using Bisect
using Test
using Aqua

@testset "Bisect.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Bisect, deps_compat=false)
        Aqua.test_deps_compat(Bisect, check_extras=false)
    end
    @testset "Successful bisection examples" begin
        @test startswith(string(bisect(@__DIR__, """length(read("runtests.jl"))""", old="49093a00f4850120d17fa9ef9cae3ff0f37cacfb")), """
        ### ✅ Bisect succeeded! The first new commit is 06051c5cf084fefc43b06bf2527960db6489a6ec

        | Commit                                       | **Exit code** | stdout  | stderr                                                       |
        |:-------------------------------------------- |:------------- |:------- |:------------------------------------------------------------ |
        | 49093a00f4850120d17fa9ef9cae3ff0f37cacfb     | ❌ (1)         |         | ERROR: SystemError: opening file \"runtests.jl\": No such f... |
        | **06051c5cf084fefc43b06bf2527960db6489a6ec** | **✅ (0)**     | **178** | ****                                                         |
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

        | Commit                                   | Exit code | stderr                                                       |
        |:---------------------------------------- |:--------- |:------------------------------------------------------------ |
        | 49093a00f4850120d17fa9ef9cae3ff0f37cacfb | ❌ (1)     | ERROR: AssertionError: 1 + 1 == 3
        Stacktrace:
         [1] top-le... |
        | """) # TODO: handle newlines in stdout/stderr.

        @test startswith(string(bisect(@__DIR__, "rand()", old="49093a00f4850120d17fa9ef9cae3ff0f37cacfb")), "### ❌ Bisect failed\n\n|")

        @test startswith(string(bisect("rand()", old="49093a00f4850120d17fa9ef9cae3ff0f37cacfb", auto_print=false)), """
        ### ❌ Bisect failed

        | Commit                                   | Exit code | stdout | stderr |
        |:---------------------------------------- |:--------- |:------ |:------ |
        | 49093a00f4850120d17fa9ef9cae3ff0f37cacfb | ✅ (0)     |        |        |
        | """)
    end

    @testset "Workflow error messages" begin
        @test string(Bisect._workflow("""
        `new = main`
        `old = deadbeef`
        ```julla
        1+1 == 2
        ```
        """)) == """
        ### ⚠️ Parse Error

          * Could not find code (regex: ````` ```julia[\\r\\n]+((.|[\\r\\n])*?)[\\r\\n]+ ?``` `````)
        """
    end

    @testset "Workflow usage produces the same results and standard usage" begin
        file = tempname()
        open(file, "w") do io
            println(io, """

            Let's `bisect()` this

            `old = 06051c5cf084fefc43b06bf2527960db6489a6ec`
            `new = HEAD`

            ```julia
            length(read("runtests.jl")) == 178
            ```
            """)
        end
        Bisect.workflow(file)
        standard = bisect(@__DIR__, """length(read("runtests.jl")) == 178""", old="06051c5cf084fefc43b06bf2527960db6489a6ec")
        @test read(file, String) == string(standard)

        # Strange newline characters
        open(file, "w") do io
            println(io, "`bisect()`\r \r `new=main`\r `old = 06051c5cf084fefc43b06bf2527960db6489a6ec`\r \r ```julia\r @assert 1+1 == 2\r ```\n")
        end
        Bisect.workflow(file)
        standard2 = bisect(@__DIR__, """@assert 1+1 == 2""", old="06051c5cf084fefc43b06bf2527960db6489a6ec")
        @test read(file, String) == string(standard2) != string(standard)
    end

    @testset "get_comment" begin
        @test Bisect.get_comment("https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1834044633") == "hello from a file\n"
        @test Bisect.get_comment("https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1833915675") == "@LilithHafnerBot bisect()"
        @test_broken Bisect.get_comment("https://github.com/LilithHafner/Bisect.jl/issues/8#issue-2017841366") == "Ref: https://github.com/LilithHafner/Bisect.jl/pull/5#issuecomment-1833079041"
    end
end
