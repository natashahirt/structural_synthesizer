# Runner script: generates column + beam sizing reports
# Redirects stdout to files, suppresses solver noise, strips ANSI codes.

using Logging

# Suppress solver noise globally
global_logger(NullLogger())

const REPORT_DIR = joinpath(@__DIR__, "StructuralSynthesizer", "test", "reports")
mkpath(REPORT_DIR)

function strip_ansi(s::AbstractString)
    replace(s, r"\e\[[0-9;]*[A-Za-z]" => "")
end

function run_report(script_path::String, output_name::String)
    outfile = joinpath(REPORT_DIR, output_name)
    
    open(outfile, "w") do io
        redirect_stdout(io) do
            try
                include(script_path)
            catch e
                println("\n\n*** ERROR running $script_path ***")
                showerror(stdout, e, catch_backtrace())
            end
        end
    end
    
    # Post-process: strip ANSI codes and solver noise
    raw = read(outfile, String)
    clean = strip_ansi(raw)
    lines = split(clean, '\n')
    filtered = filter(lines) do line
        !startswith(line, "Presolving model") &&
        !startswith(line, "Solving model") &&
        !startswith(line, "Running HiGHS") &&
        !startswith(line, "Solution has") &&
        !contains(line, "HiGHS") &&
        !contains(line, "Ipopt") &&
        !startswith(line, "This is Ipopt") &&
        !contains(line, "Coin-OR") &&
        !contains(line, "mumps") &&
        !startswith(line, "Number of") &&
        !startswith(line, "Total number") &&
        !contains(line, "iteration") && 
        !contains(line, "objective value") &&
        !contains(line, "EXIT:") &&
        !startswith(line, "Optimal") &&
        !contains(line, "nlp_scaling") &&
        !contains(line, "linear_solver") &&
        !startswith(line, "Set parameter") &&
        !startswith(line, "Academic license") &&
        !startswith(line, "****")
    end
    write(outfile, join(filtered, '\n'))
    println(stderr, "  ✓ $output_name ($(length(filtered)) lines)")
end

println(stderr, "Running column sizing report...")
run_report(
    joinpath(@__DIR__, "StructuralSynthesizer", "test", "test_column_sizing_report.jl"),
    "column_sizing_report.txt"
)

println(stderr, "Running beam sizing report...")
run_report(
    joinpath(@__DIR__, "StructuralSynthesizer", "test", "test_beam_sizing_report.jl"),
    "beam_sizing_report.txt"
)

println(stderr, "Done!")
