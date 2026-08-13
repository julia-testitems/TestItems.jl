module TestItems

export @testitem, @testmodule, @testsnippet

"""
    @testitem "name" [keyword_args...] begin
        # test code
    end

Define a test item, a self-contained unit of test code.

Each test item is run in its own `module`, so test items cannot share state
with each other directly. Use `@testmodule` or `@testsnippet` with the `setup` keyword
to share setup code between test items.

## Keyword arguments

- `tags::Vector{Symbol}`: Tags for filtering which test items to run.
  Example: `tags=[:slow, :integration]`.
- `default_imports::Bool`: Whether to automatically `using Test` and `using <PackageName>`
  before running the test code. Defaults to `true`.
- `setup::Vector{Symbol}`: Names of `@testmodule` or `@testsnippet` definitions to
  evaluate before the test item runs.
- `skip`: Either a `Bool` literal, or an arbitrary expression that evaluates to a `Bool`.
  When it is `true` the test item is not run and is reported as skipped. Defaults to
  `false`. An expression is evaluated **in the test process**, immediately before the
  test item would have run, so checks like `VERSION < v"1.11"` or `Sys.iswindows()` see
  the environment of the process the tests actually run in, not the one that discovered
  them.

## Examples

```julia
@testitem "basic addition" begin
    @test 1 + 1 == 2
end

@testitem "no default imports" default_imports=false begin
    using Test
    @test true
end

@testitem "with setup" tags=[:integration] setup=[DatabaseHelper] begin
    db = DatabaseHelper.connect()
    @test isopen(db)
end

@testitem "not ready yet" skip=true begin
    @test false
end

@testitem "needs a recent Julia" skip=(VERSION < v"1.11") begin
    @test true
end
```
"""
macro testitem(ex...)
    return nothing
end

"""
    @testmodule ModuleName begin
        # module body
    end

Define a reusable test setup module that can be shared across test items via the
`setup` keyword of `@testitem`.

A `@testmodule` is evaluated once per test process and the resulting module is made
available to every test item that lists it in `setup`. This makes it suitable for
expensive setup like establishing database connections or loading large datasets, since
the work is done only once and then reused.

## Examples

```julia
@testmodule DatabaseHelper begin
    using SomeDBPackage
    const DB_URL = "localhost:5432/testdb"
    connect() = SomeDBPackage.connect(DB_URL)
end

@testitem "query works" setup=[DatabaseHelper] begin
    db = DatabaseHelper.connect()
    @test isopen(db)
end
```
"""
macro testmodule(ex...)
    return nothing
end

"""
    @testsnippet SnippetName begin
        # setup code
    end

Define a reusable test setup snippet that can be shared across test items via the
`setup` keyword of `@testitem`.

Unlike `@testmodule`, a `@testsnippet`'s code is evaluated directly in the scope of
each test item that references it, rather than in its own module. This means any
variables or functions defined in the snippet are available directly without module
qualification. This makes snippets convenient for small bits of shared setup code.

## Examples

```julia
@testsnippet CommonSetup begin
    x = 42
    helper() = "hello"
end

@testitem "use snippet" setup=[CommonSetup] begin
    @test x == 42
    @test helper() == "hello"
end
```
"""
macro testsnippet(ex...)
    return nothing
end

end
