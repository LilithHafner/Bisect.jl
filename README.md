# Bisect

<!--[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://LilithHafner.github.io/Bisect.jl/stable/)-->
<!--[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://LilithHafner.github.io/Bisect.jl/dev/)-->
[![Build Status](https://github.com/LilithHafner/Bisect.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/LilithHafner/Bisect.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/LilithHafner/Bisect.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/LilithHafner/Bisect.jl)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
<!--[![PkgEval](https://JuliaCI.github.io/NanosoldierReports/pkgeval_badges/B/Bisect.svg)](https://JuliaCI.github.io/NanosoldierReports/pkgeval_badges/B/Bisect.html)-->

## Development status: stable

As far as I can tell, this tool is fully functional, tested, and ready for widespread use. 
I will attempt to avoid making any breaking changes going forward.

# Usage

If you have a snippet of Julia code that you suspect behaves differently on different 
versions of a repo, you can post that code in a comment on github and ask
@LilithHafnerBot to figure out exactly which commit changed its behavior. The robot will run 
a bisection and respond with its results.

## Who can use this tool

Everyone with a github account who is interested in open source software! You do not
need any permissions to invoke a bisection. You may execute arbitrary bisection code
on any public repository, whether or not you have any permissions in that repository.
See [Security](#security) for how we make this possible.

## Installation

None required. @LilithHafnerBot is already watching all github repositories. Open an
issue if you would like to opt out.

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

The default value for `old` is more complicated. We attempt to find the oldest release on
the current breaking version (e.g. "v1.0.0"). The exact details are subject to change, but the current
implementation is

- Filter down to tags that can be parsed by `VersionString`
- If possible, filter out any tags that have a prerelease component
- If there's any tag with a nonzero major version, keep only tags with the highest major version
  and otherwise keep only tags with the highest minor version (prefer v1.0.0 over both 0.7.4 and
  1.1.2)
- Of the remaining tags, take the earliest according to symbolic version comparison breaking
  ties lexicographically (e.g. if your repo has both a 1.0.0 tag and a v1.0.0 tag, this will
  prefer 1.0.0)

If no tags are found, the default value for `old` is the oldest commit with no parents.

## Security Model

The @LilithHafnerBot GitHub account sends it's notifications to `<secret-key-1>@proxiedmail.com`.
proxiedmail.com forwards those emails to LilithHafner@gmail.com and sends an HTTP post request to
https://lilithhafner.com/lilithhafnerbot/trigger_1.php containing their content.

The servers at lilithhafner.com check that the post request contains `<secret-key-1>` with the regex
match `<first 10 digits of secret-key-1>(\w{60})@proxiedmail.com` and then verifies that the hash
of the remianing 60 digits is equal to a known hash. After verifying authentication, those servers
check to see if the body of the message includes the string `@LilithHfanerBot bisect`. If so, it
uses the `gh` command line tool and an authentication token for the `@LilithHafnerBot` github account
to trigger a workflow run at https://github.com/LilithHafnerBot/bisect. It sends that workflow a
freshly genereated, single use `<key-2>` and the URL of the comment that triggered the notification, 
and saves that url and key and a timestamp localy. Then the servers add an :eyes: reaction to the 
triggering comment.

GitHub actions automatically publically logs all arguments to the workflow trigger including `<key-2>`
with no way to disable that logging. The workflow itself downloads the triggering comment's content,
parses it, runs a bisection if able, and produces a comment in response. It then posts back to
https://lilithahfner.com/lilithhafnerbot/trigger_2.php a request containing the key, comment URL, 
and response message.

The servers at lilithhafner.com verify that the url and key exist in it's local logs with a 
timestamp from the last 4 hours, verifies the message format looks plausible (notably including
a check that the length is not too long), checks that that comment url has not been responded to 
before, checks that the comment contains the string `@LilithHafnerBot bisect`, logs that comment 
url as having been responded to, and posts the message to github.

### Security claims

- lilithhafner.com is not vulnerable to remote code execution
- The @LilithHafnerBot github account is secure
- @LilithHafnerBot cannot be sock-puppetted except for when someone invoked `@LilithHafnerBot bisect` in the last 4 hours

### Attack models

TODO

### DOS attacks

This service runs on free github action runners. It's trivial to DOS this service,
please don't do that intentionally.

### Reporting vulnerabilities

Please report security vulnerabilities to LilithHafner@gmail.com
