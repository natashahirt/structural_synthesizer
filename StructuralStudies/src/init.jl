# ==============================================================================
# StructuralStudies Init
# ==============================================================================
# Include this file at the top of any study script to load all dependencies.
# Usage: include(joinpath(@__DIR__, "..", "init.jl"))

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

# Core structural modules
# StructuralSizer re-exports units from Asap
using StructuralSizer
using Unitful

# Analysis dependencies
using DataFrames
using CSV
using Dates
using ProgressMeter

# Visualization (optional - loads if available)
try
    using GLMakie
    using ColorSchemes
    global VIS_AVAILABLE = true
    println("Visualization: GLMakie loaded ✓")
catch
    global VIS_AVAILABLE = false
    println("Visualization: GLMakie not available (run Pkg.add(\"GLMakie\") to enable)")
end

# ==============================================================================
# Study utilities
# ==============================================================================

"""Ensure directory exists, creating if needed."""
function ensure_dir(dir::String)
    isdir(dir) || mkpath(dir)
    return dir
end

"""Generate timestamped filename for study output."""
function output_filename(study_name::String, results_dir::String; ext::String="csv")
    ensure_dir(results_dir)
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    return joinpath(results_dir, "$(study_name)_$(timestamp).$(ext)")
end

"""Print study header."""
function print_header(title::String)
    println("=" ^ 60)
    println(title)
    println("Started: $(now())")
    println("=" ^ 60)
    println()
end

"""Print study footer with summary."""
function print_footer(n_created::Int, n_failed::Int, output_file::String)
    println()
    println("=" ^ 60)
    println("Study Complete!")
    println("=" ^ 60)
    println("Records created: $n_created")
    println("Records failed:  $n_failed")
    println("Output file:     $output_file")
    println()
end

# ==============================================================================
# Common constants for RC column studies
# ==============================================================================

const TYPICAL_COLUMN_HEIGHT_M = 4.0   # meters
const TYPICAL_STORY_HEIGHT_FT = 13.0  # feet

# Embodied carbon factors (approximate, kg CO2e per unit)
const CARBON_CONCRETE_KG_PER_M3 = 300.0   # Normal weight concrete
const CARBON_REBAR_KG_PER_KG = 1.5        # Steel reinforcement
const STEEL_DENSITY_KG_PER_M3 = 7850.0    # Steel density

"""Calculate embodied carbon for a column."""
function calc_embodied_carbon(vol_concrete_m3::Float64, vol_steel_m3::Float64)
    carbon_concrete = vol_concrete_m3 * CARBON_CONCRETE_KG_PER_M3
    carbon_steel = vol_steel_m3 * STEEL_DENSITY_KG_PER_M3 * CARBON_REBAR_KG_PER_KG
    return (
        concrete = carbon_concrete,
        steel = carbon_steel,
        total = carbon_concrete + carbon_steel
    )
end

println("StructuralStudies initialized ✓")
