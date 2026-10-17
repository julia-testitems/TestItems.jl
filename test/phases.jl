@testitem "Phase annotations" begin
    using TestItemRunner

    const PHASES = (:prepare, :warmup, :measure)

    unline(expr) = expr isa Expr ? Base.remove_linenums!(deepcopy(expr)) : expr
    phasecall(phase, body; line=1) = Expr(:macrocall, Symbol("@", phase),
        LineNumberNode(line, :phase_fixture), body)
    expand(phase, body; kwargs...) = macroexpand(@__MODULE__, phasecall(phase, body; kwargs...))

    function passed_assertions(testset::Test.DefaultTestSet)
        passed = testset.n_passed
        for result in testset.results
            result isa Test.DefaultTestSet && (passed += passed_assertions(result))
        end
        passed
    end

    const RUNTIME_PHASES = Symbol[]
    record_runtime_phase(phase) = (push!(RUNTIME_PHASES, phase); nothing)

    function ordinary_workload()
        @prepare begin
            body = [3, 1, 2]
            transform = 40
            events = [:prepare]
        end
        @warmup begin
            push!(events, :warmup)
            sort(body)
        end
        @measure begin
            push!(events, :measure)
            result = sort(body)
        end
        (result, body, transform + 2, events)
    end

    function ordinary_control_flow()
        total = 0
        for x in 1:10
            @prepare x == 2 && continue
            @warmup x == 5 && break
            @measure total += x
        end
        @measure return total
        error("unreachable")
    end

    @testset "TestItems" begin
        @testset "Markers erase to the original expression" begin
            for phase in PHASES
                for body in (:(x + 1), :(begin x = [1, 2]; sum(x) end), 42, :nothing)
                    @test unline(expand(phase, body)) == unline(body)
                end
                @test Core.eval(@__MODULE__, expand(phase, :(6 * 7))) == 42
            end
            @test ordinary_workload() == ([1, 2, 3], [3, 1, 2], 42,
                [:prepare, :warmup, :measure])
            @test ordinary_control_flow() == 8
        end

        @testset "Top-level imports and caller bindings" begin
            caller = Module(gensym(:PhaseCaller))
            Base.include_string(caller, """
                using TestItems
                @prepare begin
                    using Base: identity
                    values = [3, 1, 2]
                end
                @warmup warmed = identity(values)
                @measure sorted = sort(warmed)
                result = (sorted, values)
                """, "top_level_phases.jl")
            @test getfield(caller, :result) == ([1, 2, 3], [3, 1, 2])
            @test getfield(caller, :warmed) === getfield(caller, :values)
        end

        @testset "Original exceptions propagate unchanged" begin
            sentinel = ErrorException("original exception")
            for phase in PHASES
                caller = Module(gensym(:ThrowCaller))
                Core.eval(caller, :(using TestItems))
                Core.eval(caller, :(const sentinel = $sentinel))
                caught = try
                    Core.eval(caller, phasecall(phase, :(throw(sentinel))))
                catch error
                    error
                end
                @test caught === sentinel
            end
        end

        @testset "Explicit expansion-time consumer" begin
            records = Any[]
            transform = function (phase, body, source, caller)
                push!(records, (; phase, source, caller))
                phase === :measure ? :($body + 1) : body
            end
            result = with_phase_transform(transform) do
                expression = expand(:measure, :(40 + 1); line=27)
                @test length(records) == 1
                Core.eval(@__MODULE__, expression)
            end
            @test result == 42
            @test length(records) == 1  # Evaluation did not call the transform.
            @test records[1].phase == :measure
            @test records[1].source.line == 27
            @test records[1].source.file == :phase_fixture
            @test records[1].caller === @__MODULE__
            @test unline(expand(:measure, :(40 + 1))) == :(40 + 1)

            calls = Ref(0)
            with_phase_transform((args...) -> (calls[] += 1; args[2])) do
                @test ordinary_workload()[1] == [1, 2, 3]
            end
            @test calls[] == 0  # This function's markers had already expanded.

            with_phase_transform((args...) -> nothing) do
                @test expand(:warmup, :(error("not evaluated"))) === nothing
            end
        end

        @testset "Nesting, disabling and failure restore the context" begin
            seen = Symbol[]
            outer = (phase, body, source, caller) -> (push!(seen, :outer); body)
            inner = (phase, body, source, caller) -> (push!(seen, :inner); body)
            sentinel = ErrorException("transform failed")
            with_phase_transform(outer) do
                expand(:prepare, :nothing)
                with_phase_transform(inner) do
                    expand(:warmup, :nothing)
                end
                with_phase_transform(nothing) do
                    expand(:measure, :nothing)
                end
                caught = try
                    with_phase_transform((args...) -> throw(sentinel)) do
                        expand(:measure, :nothing)
                    end
                catch error
                    error
                end
                @test (caught isa LoadError ? caught.error : caught) === sentinel
                @test_throws ErrorException with_phase_transform(inner) do
                    error("body failed")
                end
                expand(:measure, :nothing)
            end
            @test seen == [:outer, :inner, :outer]
            @test unline(expand(:prepare, :(1 + 1))) == :(1 + 1)
        end

        @testset "Transforms are isolated between tasks" begin
            seen_a, seen_b = Symbol[], Symbol[]
            plain_in_b = Ref{Any}()
            ready, resume = Channel{Nothing}(1), Channel{Nothing}(1)
            a = @async with_phase_transform((phase, body, source, caller) ->
                    (push!(seen_a, phase); body)) do
                expand(:prepare, :nothing)
                put!(ready, nothing)
                take!(resume)
                expand(:measure, :nothing)
            end
            b = @async begin
                take!(ready)
                plain_in_b[] = unline(expand(:warmup, :(1 + 1)))
                with_phase_transform((phase, body, source, caller) ->
                        (push!(seen_b, phase); body)) do
                    expand(:warmup, :nothing)
                end
                put!(resume, nothing)
            end
            wait(a)
            wait(b)
            @test plain_in_b[] == :(1 + 1)
            @test seen_a == [:prepare, :measure]
            @test seen_b == [:warmup]

            with_phase_transform((args...) -> error("must not leak into child")) do
                child = @async expand(:measure, :(6 * 7))
                @test unline(fetch(child)) == :(6 * 7)
            end
        end

        @testset "Unmodified TestItemRunner" begin
            mktempdir() do fixtures
                write(joinpath(fixtures, "items.jl"), raw"""
using TestItems

@testsnippet PhaseImports begin
    using Test
    using TestItems: @prepare, @warmup, @measure
end

@testitem "shared phases retain bindings and order" default_imports=false setup=[PhaseImports] begin
    @prepare begin
        values = [3, 1, 2]
        phases = [:prepare]
    end
    @warmup begin
        push!(phases, :warmup)
        sort(values)
    end
    @measure begin
        push!(phases, :measure)
        sorted = sort(values)
    end
    @test phases == [:prepare, :warmup, :measure]
    @test sorted == [1, 2, 3]
    @test values == [3, 1, 2]
end

@testitem "measurement keeps exceptions and assertions" default_imports=false setup=[PhaseImports] begin
    @prepare sentinel = ErrorException("original exception")
    @warmup warm = 41
    caught = try
        @measure throw(sentinel)
    catch error
        error
    end
    @test caught === sentinel
    @test warm + 1 == 42
    @test (@measure 6 * 7) == 42
end
                """)
                discovered = String[]
                transforms = Symbol[]
                observer = (phase, body, source, caller) ->
                    (push!(transforms, phase); body)
                with_phase_transform(observer) do
                    TestItemRunner.run_tests(fixtures; filter=item -> begin
                        push!(discovered, item.name)
                        false
                    end)
                end
                @test length(discovered) == 2
                @test isempty(transforms)  # Discovery did not expand or run the bodies.

                plain = TestItemRunner.run_tests(fixtures)
                @test passed_assertions(plain) == 6
                @test isempty(transforms)

                consumer = function (phase, body, source, caller)
                    observer(phase, body, source, caller)
                    Expr(:block, Expr(:call, GlobalRef(@__MODULE__, :record_runtime_phase),
                        QuoteNode(phase)), body)
                end
                observed = with_phase_transform(consumer) do
                    TestItemRunner.run_tests(fixtures)
                end
                @test passed_assertions(observed) == 6
                @test count(==(:prepare), transforms) == 2
                @test count(==(:warmup), transforms) == 2
                @test count(==(:measure), transforms) == 3
                @test count(==(:prepare), RUNTIME_PHASES) == 2
                @test count(==(:warmup), RUNTIME_PHASES) == 2
                @test count(==(:measure), RUNTIME_PHASES) == 3
                before = copy(RUNTIME_PHASES)
                TestItemRunner.run_tests(fixtures)
                @test RUNTIME_PHASES == before  # The consumer did not leak into later runs.
            end
        end
    end
end
