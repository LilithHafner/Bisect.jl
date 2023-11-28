using Bisect
using Documenter

DocMeta.setdocmeta!(Bisect, :DocTestSetup, :(using Bisect); recursive=true)

makedocs(;
    modules=[Bisect],
    authors="Lilith Orion Hafner <lilithhafner@gmail.com> and contributors",
    repo="https://github.com/LilithHafner/Bisect.jl/blob/{commit}{path}#{line}",
    sitename="Bisect.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://LilithHafner.github.io/Bisect.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/LilithHafner/Bisect.jl",
    devbranch="main",
)
