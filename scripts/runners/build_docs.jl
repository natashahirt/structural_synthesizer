#!/usr/bin/env julia
# Build Documenter.jl documentation.
# Run from repo root: julia scripts/runners/build_docs.jl

root = abspath(joinpath(@__DIR__, "..", ".."))
docs_dir = joinpath(root, "docs")
cd(docs_dir) do
    run(`$(Base.julia_cmd()) --project=. make.jl`)
end
