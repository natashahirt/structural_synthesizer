using Documenter
using StructuralSynthesizer
using StructuralSizer

makedocs(
    sitename = "Structural Synthesizer",
    format = Documenter.HTML(prettyurls = get(ENV, "CI", "false") == "true"),
    pages = [
        "Home" => "index.md",
        "User Guide" => "guide.md",
        "API" => [
            "StructuralSynthesizer" => "api/structural_synthesizer.md",
            "StructuralSizer" => "api/structural_sizer.md",
        ],
    ],
)

deploydocs(
    repo = "github.com/natashahirt/structural_synthesizer.git",
    devbranch = "main",
)
