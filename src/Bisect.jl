module Bisect

export bisect

using Git: Git
using Markdown: Markdown

bisect(path, code; kw...) = cd(()->bisect(code; kw...), path)
function bisect(code; git = Git.git(), old, new=readchomp(`$git rev-parse HEAD`), julia=joinpath(Sys.BINDIR, "julia"), get_status=()->readchomp(`$git rev-parse HEAD`), print_result=true)
    code = print_result ? "print(begin\n$code\nend)" : code
    run(`$git stash`)
    run(`$git bisect start`)
    try
        olds = Vector{Pair{String, Tuple{Int, String, String}}}()
        news = Vector{Pair{String, Tuple{Int, String, String}}}()

        run(`$git checkout $new`)
        new_val = test(julia, code)
        push!(news, get_status()=>new_val)
        run(`$git bisect new`)

        run(`$git checkout $old`)
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
        return (olds, reverse(news)), (compare_by_stdout, only(status)) # Bisect succeeded!
    finally
        run(`$git bisect reset`)
        run(`$git stash pop`)
    end
end

function test(julia, code)
    out=IOBuffer()
    err=IOBuffer()
    p = run(`$julia --project -e $code`, devnull, out, err, wait=false)
    wait(p)
    p.exitcode, String(take!(out)), String(take!(err))
end

function md(results)
    (news, olds), final_result = results
    data = vcat(news, olds)
    header, compare_by_stdout = if final_result === nothing
        "❌ Bisect failed", nothing
    else
        "✅ Bisect succeeded! The first new commit is $(final_result[2][1])", final_result[1]
    end

    show_exitcode = any(!iszero∘first∘last, data)
    show_stdout = any(!isempty∘(x -> x[2])∘last, data)
    show_stderr = any(!isempty∘last∘last, data)
    if !(show_exitcode || show_stdout || show_stderr)
        show_exitcode = show_stdout = show_stderr = true
    end

    rows = Vector{Vector{Any}}()
    push!(rows, Any["Commit"])
    trunc(s, len=50) = length(s) > len ? s[1:len-3] * "..." : s
    show_exitcode && push!(rows[end], (compare_by_stdout === false ? Markdown.Bold : identity)("Exit code"))
    show_stdout && push!(rows[end], (compare_by_stdout === true ? Markdown.Bold : identity)("stdout"))
    show_stderr && push!(rows[end], "stderr")
    for (commit, (exitcode, stdout, stderr)) in data
        push!(rows, Any[commit])
        show_exitcode && push!(rows[end], exitcode == 0 ? "✅ (0)" : "❌ ($exitcode)")
        show_stdout && push!(rows[end], trunc(stdout))
        show_stderr && push!(rows[end], trunc(stderr))
    end
    if length(data) > 2
        bold_index = length(news)+2
        rows[bold_index] = map(Markdown.Bold, rows[bold_index])
    end

    table = Markdown.Table(rows, fill(:l, only(unique(length.(rows)))))

    Markdown.MD([Markdown.Paragraph(header), table])
end

end
