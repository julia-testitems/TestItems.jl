# TestItems.jl

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
![](https://github.com/julia-vscode/TestItems.jl/workflows/Run%20tests/badge.svg)
[![codecov](https://codecov.io/gh/julia-vscode/TestItems.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/julia-vscode/TestItems.jl)

## Overview

This package provides the `@testitem` macro for the test runner feature in VS Code. You can learn more over at the [documentation](https://www.julia-vscode.org/docs/stable/userguide/testitems/) for the entire test item ecosystem. Note that while the documentation is hosted as part of the Julia VS Code extension, the test item framework is not a VS Code extension specific technology and can be used entirely without VS Code.

This package only provides stub definitions for macros, and has no dependencies.  All of the parsing work is done in [TestItemRunner.jl](https://github.com/julia-vscode/TestItemRunner.jl).  It's not a major issue to depend on this package if you want to use `@testitem` in your codebase!
