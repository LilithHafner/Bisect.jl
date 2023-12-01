module Bisect

export bisect

using Git: Git
using Markdown: Markdown

const DEFAULT_DISPLAY_LIMIT = 60

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

# For workflow usage
function _workflow(comment, path...; verbose=true)
    verbose && println(repr(comment))
    out = Any[]

    # TODO: test defaults
    defaults = Tuple(((x == "" ? nothing : x), ) for x in ("", get(ENV, "DEFAULT_NEW", ""), get(ENV, "DEFAULT_OLD", "")))
    names = ("code", "new", "old")
    regexs = (r"```julia[\r\n]+((.|[\r\n])*?)[\r\n]+ ?```", r"`new\s?=\s?(\S+)`", r"`old\s?=\s?(\S+)`")
    values = getindex.(something.(match.(regexs, comment), defaults), 1)

    for (name, re, val) in zip(names, regexs, values)
        if val === nothing
            if isempty(out)
                push!(out, Markdown.Header("⚠️ Parse Error", 3))
                push!(out, Markdown.List([]))
            end
            push!(out[end].items, Markdown.Paragraph(["Could not find $name (regex: ", Markdown.Code(re.pattern), ")"]))
        end
    end

    verbose && !isempty(out) && display(Markdown.MD(out))

    isempty(out) || return Markdown.MD(out)

    code, new, old = values
    res = _bisect(path..., code; new, old, verbose)

    if verbose
        full_md = md(res; display_limit=10_000)
        display(full_md)
    end

    md(res; display_limit=DEFAULT_DISPLAY_LIMIT)
end
function workflow(path)
    comment = read(path, String)
    md = _workflow(comment)
    open(path, "w") do io
        print(io, md)
    end
end

using JSON3, HTTP
function get_comment(link)
    m = match(r"https://github.com/([\w\.\+\-]+)/([\w\.\+\-]+)/(pull|issues)/(\d+)#issue(comment)?-(\d+)", link)
    response = JSON3.read(`gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$(m[1])/$(m[2])/issues/comments/$(m[6])`)
    response["body"]
end

function workflow2(link=ENV["BISECT_TRIGGER_LINK"])
    m = match(r"https://github.com/([\w\.\+\-]+)/([\w\.\+\-]+)/(pull|issues)/(\d+)#issue(comment)?-(\d+)", link)
    response = JSON3.read(`gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$(m[1])/$(m[2])/issues/comments/$(m[6])`)
    comment = response["body"]
    dir = tempdir()
    bare_name = endswith(m[2], ".jl") ? m[2][begin:end-3] : m[2]
    path = joinpath(dir, bare_name)
    run(`git clone https://github.com/$(m[1])/$(m[2]) $path`)
    md = _workflow(comment, path)
    HTTP.post("https://lilithhafner.com/lilithhafnerbot/trigger_2.php", body=link * "," * ENV["OPEN_SECRET"] * "," * string(md))
end

end
