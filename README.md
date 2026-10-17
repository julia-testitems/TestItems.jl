# TestItems.jl

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
![](https://github.com/julia-vscode/TestItems.jl/workflows/Run%20tests/badge.svg)
[![codecov](https://codecov.io/gh/julia-vscode/TestItems.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/julia-vscode/TestItems.jl)

## Overview

This package provides the `@testitem` macro for the test runner feature in VS Code. You can learn more over at the [documentation](https://www.julia-vscode.org/docs/stable/userguide/testitems/) for the entire test item ecosystem. Note that while the documentation is hosted as part of the Julia VS Code extension, the test item framework is not a VS Code extension specific technology and can be used entirely without VS Code.

## Preparation, warm-up and measurement regions

Optional `@prepare`, `@warmup` and `@measure` annotations let a test item share
its correctness checks with external performance tools, without depending on a
particular measurement package:

```julia
using TestItems

@testitem "Sort a vector" begin
    using TestItems: @prepare, @warmup, @measure

    @prepare begin
        # Imports, input construction and other preparation.
        values = [3, 1, 2]
    end

    @warmup sort(values)

    @measure begin
        sorted = sort(values)
    end

    @test sorted == [1, 2, 3]
    @test values == [3, 1, 2]
end
```

In a normal functional run, **every body executes once in source order**.
Explicit warm-up code is not skipped, and no hidden repetitions are added. The
annotations expand to their original expression: they add no closure, scope,
timer, runtime callback or runtime mode check. Bindings, imports, values,
exceptions, `return`, `break` and `continue` retain their ordinary behavior.
Package loading and macro expansion still have their normal Julia costs.

Each annotation takes one expression, including a `begin ... end` block.
An external tool can use the annotations to exclude preparation and warm-up
from measurement. Keep assertions outside `@measure` if their cost should be excluded.
These annotations do not add any package dependencies or require changes to
TestItemRunner. They must be in scope in the item body, for example through the
normal package imports or an explicit `using TestItems`.

### Interface for external tools

`with_phase_transform` allows a consumer to replace phase syntax while fresh
item code is being expanded. For example, this observes the annotations without
changing their execution:

```julia
using TestItems: with_phase_transform
using TestItemRunner

regions = Symbol[]
transform = function (phase, body, source, caller)
    push!(regions, phase)  # Expansion-time observation, not runtime timing.
    return body
end

with_phase_transform(transform) do
    TestItemRunner.run_tests("test")
end
```

The callback receives the phase (`:prepare`, `:warmup` or `:measure`), raw body
expression, call-site `LineNumberNode` and caller `Module`. It returns replacement
syntax **without** pre-escaping it; the phase macro escapes it into the caller's
scope. A consumer inserting calls to its own helpers should use `GlobalRef` and
preserve user bindings, control flow, values and exceptions. Measurement policy,
including handling failed or incomplete measurements, belongs to that consumer.
TestItems itself supplies no timer, repetitions or performance verdict.

The context is task-local and restored on return or error. Nested contexts are
supported, and `with_phase_transform(nothing) do ... end` temporarily disables a
transform. The context is not automatically propagated to child tasks or other
processes. TestItemRunner's discovery does not expand or execute item bodies.

This is an **expansion-time** interface. Wrap `include`, `include_string`,
`macroexpand` or a runner evaluating fresh bodies; wrapping an already compiled
function does not instrument it. In particular, an annotation written directly
inside the `do` block is expanded before the context is installed:

```julia
with_phase_transform(transform) do
    @measure sort([3, 1, 2])  # Already expanded; remains transparent.
end
```

