report_path = joinpath("StructuralSynthesizer", "test", "reports", "beam_sizing_report.txt")

open(report_path, "w") do io
    redirect_stdout(io) do
        include(joinpath("StructuralSynthesizer", "test", "test_beam_sizing_report.jl"))
    end
end

println("Report written to $report_path")
