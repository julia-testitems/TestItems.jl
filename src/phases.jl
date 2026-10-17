const _PHASE_TRANSFORM_KEY = gensym(:TestItems_phase_transform)

"""
    with_phase_transform(f, transform)
    with_phase_transform(transform) do
        # Expand and evaluate fresh test-item code here.
    end

Call `f()` with an expansion-time phase transform in the current task. The
previous transform is restored on normal return and on exceptions. Pass `nothing`
to temporarily restore transparent expansion. The return value is that of `f()`.

When a phase macro expands, `transform(phase, body, source, caller)` receives:

- `phase`: one of `:prepare`, `:warmup` or `:measure`;
- `body`: the unevaluated expression supplied to the macro;
- `source::LineNumberNode`: the macro's call site;
- `caller::Module`: the module in which it expands.

Return replacement Julia syntax, not a pre-escaped expression. The macro escapes
the replacement into the caller's scope. A consumer must preserve the intended
scope, values, control flow and exception behavior of the user code.

The transform runs during **macro expansion**, never as an implicit runtime
callback. Wrap `include`, `include_string`, `macroexpand`, or a runner that
evaluates fresh item bodies. Already expanded or compiled code is unchanged;
wrapping a call to such a function does not instrument it. The transform is
task-local, is not installed globally, and is not automatically propagated to
other tasks or processes.

The package supplies no timer, repetition policy or performance backend.
"""
function with_phase_transform(f::Function, transform)
    task_local_storage(f, _PHASE_TRANSFORM_KEY, transform)
end

function _expand_phase(phase::Symbol, body, source::LineNumberNode, caller::Module)
    transform = get(task_local_storage(), _PHASE_TRANSFORM_KEY, nothing)
    replacement = transform === nothing ? body : transform(phase, body, source, caller)
    esc(replacement)
end

"""
    @prepare expression
    @prepare begin
        # Imports, input construction and other preparation.
    end

Mark preparation code. Normally this expands directly to `expression`, evaluated
once in the caller's existing scope, with its original value and exceptions.
Top-level imports and bindings remain usable by later phases and assertions.
No closure, local scope, timer or runtime callback is added.
"""
macro prepare(body)
    _expand_phase(:prepare, body, __source__, __module__)
end

"""
    @warmup expression
    @warmup begin
        # Explicit warm-up operations.
    end

Mark explicit warm-up code. Normally its body runs once, in source order, just
as if the marker were absent. It is not skipped and no hidden repetitions are
added. A performance consumer can interpret this region through an explicit
expansion-time transform; functional runs keep the ordinary code semantics.
"""
macro warmup(body)
    _expand_phase(:warmup, body, __source__, __module__)
end

"""
    @measure expression
    @measure begin
        # The operation selected for measurement by an external tool.
    end

Mark a measurement region. Without an explicit transform this is only an
annotation: it executes the original body once and returns its value, without
measuring anything. Bindings remain visible to subsequent correctness checks.
"""
macro measure(body)
    _expand_phase(:measure, body, __source__, __module__)
end
