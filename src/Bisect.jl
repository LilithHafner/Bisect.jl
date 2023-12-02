module Bisect

export bisect

using Git: Git
using Markdown: Markdown, @md_str

const DEFAULT_DISPLAY_LIMIT = 100

bisect(args...; display_limit=DEFAULT_DISPLAY_LIMIT, kw...) = md(_bisect(args...; kw...); display_limit)

_bisect(path, code; kw...) = cd(()->_bisect(code; kw...), path)
function _bisect(code;
        git = Git.git(),
        old,
        new=readchomp(`$git rev-parse HEAD`),
        julia=joinpath(Sys.BINDIR, "julia"),
        get_status=()->readchomp(`$git rev-parse HEAD`),
        auto_print=true,
        verbose=false,
        io=verbose ? () : (devnull, devnull, devnull))

    code = auto_print ? "print(begin\n$code\nend)" : code
    run(ignorestatus(`$git stash`), io...)
    run(`$git bisect start`, io...)
    try
        olds = Vector{Pair{String, Tuple{Int, String, String}}}()
        news = Vector{Pair{String, Tuple{Int, String, String}}}()

        run(`$git checkout $new`, io...)
        new_val = test(julia, code)
        push!(news, get_status()=>new_val)
        run(`$git bisect new`, io...)

        run(`$git checkout $old`, io...)
        old_val = test(julia, code)
        push!(olds, get_status()=>old_val)
        status = match(r"([0-9a-f]{40}) is the first new commit", readchomp(`$git bisect old`))

        # Don't compare stderr
        iszero(first(new_val)) || iszero(first(old_val)) || return (olds, reverse(news)), nothing # Bisect failed (one value)
        compare_by_stdout = iszero(first(new_val)) && iszero(first(old_val))
        get_comparison_value(x) = compare_by_stdout ? x[1:2] : x[1]
        old_cmp = get_comparison_value(old_val)
        new_cmp = get_comparison_value(new_val)
        old_cmp == new_cmp && return (olds, reverse(news)), nothing # Bisect failed (one value)


        while status === nothing
            test_val = test(julia, code)
            test_cmp = get_comparison_value(test_val)
            res = if test_cmp == old_cmp
                push!(olds, get_status()=>test_val)
                "old"
            elseif test_cmp == new_cmp
                push!(news, get_status()=>test_val)
                "new"
            else # Third value
                push!(news, get_status()=>test_val)
                return (olds, reverse(news)), nothing # Bisect failed (three values)
            end
            status = match(r"([0-9a-f]{40}) is the first new commit", readchomp(`$git bisect $res`))
        end
        return (olds, reverse(news)), (compare_by_stdout, status[1]) # Bisect succeeded!
    finally
        run(`$git bisect reset`, io...)
        run(ignorestatus(`$git stash pop`), io...)
    end
end

function test(julia, code)
    out=IOBuffer()
    err=IOBuffer()
    p = run(`$julia --project -e $code`, devnull, out, err, wait=false)
    wait(p)
    p.exitcode, String(take!(out)), String(take!(err))
end

function md(results; display_limit)
    (news, olds), final_result = results
    data = vcat(news, olds)
    header, compare_by_stdout = if final_result === nothing
        "❌ Bisect failed", nothing
    else
        "✅ Bisect succeeded! The first new commit is $(final_result[2])", final_result[1]
    end

    show_exitcode = any(!iszero∘first∘last, data)
    show_stdout = any(!isempty∘(x -> x[2])∘last, data)
    show_stderr = any(!isempty∘last∘last, data)
    if !(show_exitcode || show_stdout || show_stderr)
        show_exitcode = show_stdout = show_stderr = true
    end

    rows = Vector{Vector{Any}}()
    push!(rows, Any["Commit"])
    function trunc(s)
        s2 = replace(s, "\n" => "⏎")
        display_limit !== nothing && length(s2) > display_limit ? s2[1:display_limit-3] * "..." : s2
    end
    show_exitcode && push!(rows[end], (compare_by_stdout === false ? Markdown.Bold : identity)("Exit code"))
    show_stdout && push!(rows[end], (compare_by_stdout === true ? Markdown.Bold : identity)("stdout"))
    show_stderr && push!(rows[end], "stderr")
    for (commit, (exitcode, stdout, stderr)) in data
        push!(rows, Any[commit])
        show_exitcode && push!(rows[end], exitcode == 0 ? "✅ (0)" : "❌ ($exitcode)")
        show_stdout && push!(rows[end], trunc(stdout))
        show_stderr && push!(rows[end], trunc(stderr))
    end
    if final_result !== nothing
        bold_index = length(news)+2
        rows[bold_index] = map(Markdown.Bold, rows[bold_index])
    end

    table = Markdown.Table(rows, fill(:l, only(unique(length.(rows)))))

    Markdown.MD([Markdown.Header(header, 3), table])
end


# Workflow support

"""
    parse_comment(comment::AbstractString)

parse a comment into either `(args::String, code::String)` or an error message `err::Markdown.MD`.
"""
function parse_comment(comment::AbstractString)
    occursin(r"@LilithHafnerBot\s+bisect", comment) || return md"""
    ### ❗ Internal Error

    Could not find `@LilithHafnerBot bisect`
    """

    trigger = match(r"@LilithHafnerBot\s+bisect\((.*?)\)", comment)
    code = match(r"```julia[\r\n]+((.|[\r\n])*?)[\r\n]+ ?```", comment)

    trigger === nothing && code === nothing && return md"""
    ### ⚠️ Parse Error

    Invocation syntax is `@LilithHafnerBot bisect(<args>)` or `@LilithHafnerBot bisect()`
    followed by a block of julia code in a fenced code block like this

    ````
    ```julia
    @assert true
    ```
    ````

    I found `@LilithHafnerBot bisect` but need parentheses and a code block to proceed.
    """

    trigger === nothing && return md"""
    ### ⚠️ Parse Error

    Invocation trigger syntax is `@LilithHafnerBot bisect(<args>)` or
    `@LilithHafnerBot bisect()`. I found `@LilithHafnerBot bisect` but need a
    (possibly empty) parenthesized argument list to proceed.
    """

    if code === nothing
        alt = match(r"```(.*?)[\r\n]+(.|[\r\n])*?[\r\n]+ ?```", comment)
        return if alt === nothing
            md"""
            ### ⚠️ Parse Error

            I found `@LilithHafnerBot bisect(<args>)` but need a code block to proceed.
            Provide one like this

            ````
            ```julia
            @assert true
            ```
            ````
            """
        elseif isempty(alt[1])
            md"""
            ### ⚠️ Parse Error

            I found `@LilithHafnerBot bisect(<args>)` and a code block, but the code block
            was not tagged. Please provide a julia code block like this:

            ````
            ```julia
            @assert true
            ```
            ````

            (note the "julia" tag after the first set of backticks)
            """
        else
            out = md"""
            ### ⚠️ Parse Error

            I found `@LilithHafnerBot bisect(<args>)` and a code block, but the code block
            was not tagged with "REPLACEME", not "julia". I can currently only handle julia
            code.
            """
            # Incorrectly typeset the Julia language as julia because the tag must be lowercase.
            out.content[2].content[3] = replace(out.content[2].content[3], "REPLACEME" => alt[1])
            out
        end
    end

    (trigger[1], code[1])
end

"""
    parse_args(args::AbstractString)

parse a string of arguments into a dictionary of key-value pairs or an error message `err::Markdown.MD`.
"""
function parse_args(args)
    args == "<args>" && return md"""
    ### ⚠️ Parse Error

    It looks like you kept the placeholder "<args>" in `@LilithHafnerBot bisect(<args>)`.
    You should replace "<args>" with the actual arguments (or the empty string) like this
    `@LilithHafnerBot bisect()` or `@LilithHafnerBot bisect(old=v1.6.0)`
    """

    out = Dict{String, String}()
    isempty(strip(args)) && return out
    allowed_keys = ("new", "old")
    allowed_keys_str = "\"" * join(allowed_keys, "\", \"", "\", and \"") * "\""
    err = Any[]
    for arg in split(args, ',')
        kv = split(arg, '=')
        st_arg = strip(arg)
        if length(kv) > 2
            push!(err, Markdown.Paragraph("Argument \"$st_arg\" has multiple \"=\" signs"))
        elseif length(kv) == 1
            push!(err, Markdown.Paragraph("Argument \"$st_arg\" has no \"=\" sign"))
        elseif length(kv) == 2
            k, v = strip.(kv)
            k in allowed_keys || push!(err, Markdown.Paragraph("\"$k\" is not a valid key (valid keys are $allowed_keys_str)"))
            haskey(out, k) && push!(err, Markdown.Paragraph("Duplicate key \"$k\""))
            out[k] = v
        else
            push!(err, Markdown.Paragraph("Argument \"$st_arg\" caused an internal error"))
        end
    end

    if !isempty(err)
        pushfirst!(err, Markdown.Header("⚠️ Parse Error", 3))
        return Markdown.MD(err)
    end

    out
end

"""
    maybe_checkcout_pr!(link)

If the link is to a PR comment, check out that pr.
"""
function maybe_checkcout_pr!(link)
    m = match(r"https://github.com/([\w\.\+\-]+)/([\w\.\+\-]+)/(pull|issues)/(\d+)#issue(comment)?-(\d+)", link)
    m === nothing && return
    m[3] == "pull" || return
    run(`gh pr checkout $(m[4])`)
end

default_new() = "HEAD"

function get_tags()
    tags = Pair{VersionNumber, String}[]
    for tag in eachline(`git tag`)
        version = try
            VersionNumber(tag)
        catch
            nothing
        end
        version !== nothing && push!(tags, version => tag)
    end
    tags
end
function get_first_commit()
    commits = reverse!(readlines(`git rev-list --max-parents=0 HEAD`))
    times = map(hash -> readchomp(`git show -s --format=%ct $hash`), commits)
    commits[argmin(times)]
end
function default_old() # TODO: test this more thoroughly
    tags = get_tags()
    isempty(tags) && return get_first_commit()
    any(x -> isempty(x[1].prerelease), tags) && filter!(x -> isempty(x[1].prerelease), tags) # Prefer full release
    if all(x -> iszero(x[1].major), tags)
        latest_minor = maximum(x -> x[1].minor, tags)
        filter!(x -> x[1].minor == latest_minor, tags)
    else
        latest_major = maximum(x -> x[1].major, tags)
        filter!(x -> x[1].major == latest_major, tags)
    end
    minimum(tags)[2]
end

function populate_default_args!(args::Dict)
    get!(default_old, args, "old")
    get!(default_new, args, "new")

    # TODO make this more robust.
    io = devnull, devnull, devnull
    old = args["old"]
    new = args["new"]
    run(ignorestatus(`git stash`), io...)
    initial_ref = readchomp(`sh -c 'git symbolic-ref --short HEAD || git rev-parse HEAD'`)
    old_succeeds = success(`git checkout $old`)
    run(`git checkout $initial_ref`, io...)
    new_succeeds = success(`git checkout $new`)
    run(`git checkout $initial_ref`, io...)
    run(ignorestatus(`git stash pop`), io...)

    if !old_succeeds || !new_succeeds
        refs = old_succeeds ? " \"$new" : new_succeeds ? " \"$old" : "s \"$old\" or \"$new"
        Markdown.MD([
            Markdown.Header("⚠️ Parse Error", 3),
            Markdown.Paragraph("I don't understand the ref$(refs)\"."),
            Markdown.Paragraph(old_succeeds || new_succeeds ? "`git checkout $(old_succeeds ? new : old)` failed." : "Both `git checkout $old` and `git checkout $new` failed.")])
    end
end

function _workflow(link, comment, path; verbose=true)
    verbose && println(link)
    verbose && println(repr(comment))

    args_str_code = parse_comment(comment)
    args_str_code isa Markdown.MD && (verbose && display(args_str_code); return args_str_code)
    args_str, code = args_str_code

    args = parse_args(args_str)
    args isa Markdown.MD && (verbose && display(args); return args)

    res = cd(path) do
        maybe_checkcout_pr!(link)

        err = populate_default_args!(args)
        err isa Markdown.MD && return err

        verbose && println(args)

        _bisect(code; new=args["new"], old=args["old"], verbose)
    end

    res isa Markdown.MD && (verbose && display(res); return res)

    verbose && display(md(res; display_limit=10_000))

    md(res; display_limit=DEFAULT_DISPLAY_LIMIT)
end

using JSON3, HTTP
function get_comment(link) # TODO: this is unused
    m = match(r"https://github.com/([\w\.\+\-]+)/([\w\.\+\-]+)/(pull|issues)/(\d+)#issue(comment)?-(\d+)", link)
    response = JSON3.read(`gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$(m[1])/$(m[2])/issues/comments/$(m[6])`)
    response["body"]
end

function workflow()
    link=ENV["BISECT_TRIGGER_LINK"]
    m = match(r"https://github.com/([\w\.\+\-]+)/([\w\.\+\-]+)/(pull|issues)/(\d+)#issue(comment)?-(\d+)", link)
    response = JSON3.read(`gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$(m[1])/$(m[2])/issues/comments/$(m[6])`)
    comment = response["body"]
    dir = mktempdir()
    bare_name = endswith(m[2], ".jl") ? m[2][begin:end-3] : m[2]
    path = joinpath(dir, bare_name)
    run(`git clone https://github.com/$(m[1])/$(m[2]) $path`)
    md = _workflow(link, comment, path)
    HTTP.post("https://lilithhafner.com/lilithhafnerbot/trigger_2.php", body=ENV["BISECT_AUTH"] * "," * link * "," * string(md))
end

end
