# Bisect

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://LilithHafner.github.io/Bisect.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://LilithHafner.github.io/Bisect.jl/dev/)
[![Build Status](https://github.com/LilithHafner/Bisect.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/LilithHafner/Bisect.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/LilithHafner/Bisect.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/LilithHafner/Bisect.jl)
[![PkgEval](https://JuliaCI.github.io/NanosoldierReports/pkgeval_badges/B/Bisect.svg)](https://JuliaCI.github.io/NanosoldierReports/pkgeval_badges/B/Bisect.html)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Development status: unreleased

No commitment is made to backward compatibility and little effort is directed toward current user experience or maintaining high transient reliability.

# Usage

## What this does

TODO

## Who can use this tool

Everyone with a github account who is interested in open source software! You do not
need any permissions to invoke a bisection. You may execute arbitrary bisection code
on any public repository, whether or not you have any permissions in that repository.
See [Security](#security) for how we make this possible.

## Invocation syntax

An invocation is a github comment with a trigger and a code block. For example,

````
Let's try to bisect this.

@LilithHafnerBot bisect(new=main, old=v1.0.0)

```julia
using Statistics
mean([1, 2, 3]) == 2
```
````

The trigger must take the form `@LilithHafnerBot bisect(<args>)` where `<args>` is
a (possibly empty) comma separated list of arguments. Each argument must be of the form
`<key>=<value>`. Supported keys are

- `new`: the new end of the bisection
- `old`: the old end of the bisection

Any value that can be interpreted as a revision by `git checkout <value>` can be used
as the value for `new` and `old`. For example, commit hashes, branch names, and tags
are all valid values.

Line breaks and `)` characters are not permitted in the argument list.

The code block must be a Julia code block, beginning with
```` ```julia ```` and ending with ```` ``` ````. The trigger and code block must be in
the same comment.

### Default values for `old` and `new`

The default value for `new` is "HEAD", which for issues, points to the head of hhe default
branch and for pull requests, points to the head of the pull request branch (even if that
pull request is from a fork!)

The default value for `old` is more complicated. We attempts to find the oldest release on
the current breaking version (e.g. "v1.0.0"). The exact details are subject to change, but the current
implementation is

- Filter down to tags that can be parsed by `VersionString`
- If possible, filter out any tags that have a prerelease or build component
- If there's any tag with a nonzero major version, keep only tags with the highest major version
  and otherwise keep only tags with the highest minor version
- Of the remaining tags, take the earliest according to symbolic version comparison breaking
  ties lexicographically (e.g. if your repo has both a 1.0.0 tag and a v1.0.0 tag, this will
  prefer 1.0.0)

## Security

TODO (the documentation, that is. The security is already in place.)

### DOS attacks

This service runs on free github action runners. It's trivial to DOS this service,
please don't do that intentionally.
