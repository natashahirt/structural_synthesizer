# ==============================================================================
# RC Column Parametric Study
# ==============================================================================
# Comprehensive sweep over RC column design parameters to understand
# capacity relationships and design tradeoffs per ACI 318.
#
# Parameters varied:
#   - Shape: rectangular, circular
#   - Size: 12" to 36" (b for rect, D for circular)
#   - Aspect ratio: 1.0 to 2.0 (rectangular only)
#   - f'c: 3 to 8 ksi
#   - fy: 40, 60, 75, 80 ksi (ASTM A615 grades)
#   - ρ (reinforcement ratio): 1% to 6%
#   - Cover: 1.5" to 3"
#   - Tie type: tied vs spiral
#   - Arrangement: perimeter, two_layer, corners_only (rectangular only)
#
# Slenderness evaluated at kLu/r = 30, 50, 70 with βdns sensitivity (0.3, 0.6, 0.8)
#
# Output: CSV with section properties, P-M capacities, slenderness effects,
#         embodied carbon estimates, and derived efficiency metrics.
#
# Run: julia --project=StructuralStudies StructuralStudies/src/column_properties/column_parametric_study.jl
# ==============================================================================

include(joinpath(@__DIR__, "..", "init.jl"))

# Results directory for this study
const RESULTS_DIR = joinpath(@__DIR__, "results")

# ==============================================================================
# Parameter Definitions
# ==============================================================================

# Geometry
const SIZES = [12, 16, 20, 24, 30, 36]  # inches (b for rect, D for circular)
const ASPECT_RATIOS = [1.0, 1.33, 1.5, 2.0]  # h/b for rectangular only
const ARRANGEMENTS = [:perimeter, :two_layer]  # for n_bars > 4
const COVERS = [1.5, 2.0, 3.0]  # inches

# Materials
const FC_VALUES = [3.0, 4.0, 5.0, 6.0, 8.0]  # ksi
const FY_VALUES = [40.0, 60.0, 75.0, 80.0]  # ksi (ASTM A615 Gr40, Gr60, Gr75, Gr80)
const TARGET_RHOS = [0.01, 0.02, 0.03, 0.04, 0.06]  # reinforcement ratios
const BAR_SIZES = [6, 8, 9, 10, 11]  # standard bar sizes to try
const TIE_TYPES = [:tied, :spiral]

# Slenderness parameters
const SLENDERNESS_RATIOS = [30, 50, 70]  # kLu/r values to evaluate
const BDNS_VALUES = [0.3, 0.6, 0.8]  # sustained load ratios (dead/total)

# ==============================================================================
# Helper Functions
# ==============================================================================

"""Find bar configuration closest to target ρ."""
function find_bars_for_rho(Ag_in2::Float64, ρ_target::Float64, bar_sizes::Vector{Int})
    As_target = ρ_target * Ag_in2
    
    best_config = nothing
    best_error = Inf
    
    for bar_size in bar_sizes
        bar = StructuralSizer.rebar(bar_size)
        As_bar = ustrip(u"inch^2", bar.A)
        
        # Calculate n_bars needed
        n_bars_float = As_target / As_bar
        
        # Try both floor and ceil
        for n_bars in [floor(Int, n_bars_float), ceil(Int, n_bars_float)]
            n_bars < 4 && continue
            n_bars > 24 && continue
            
            ρ_actual = n_bars * As_bar / Ag_in2
            
            # Must be within ACI limits
            (ρ_actual < 0.01 || ρ_actual > 0.08) && continue
            
            error = abs(ρ_actual - ρ_target)
            if error < best_error
                best_error = error
                best_config = (bar_size=bar_size, n_bars=n_bars, ρ_actual=ρ_actual, As=n_bars*As_bar)
            end
        end
    end
    
    return best_config
end

"""Extract key points from P-M diagram."""
function extract_pm_metrics(diagram)
    # Use the correct API: get_control_point returns actual PMDiagramPoint
    cp_pure_comp = StructuralSizer.get_control_point(diagram, :pure_compression)
    cp_max_comp = StructuralSizer.get_control_point(diagram, :max_compression)
    cp_balanced = StructuralSizer.get_control_point(diagram, :balanced)
    cp_pure_bend = StructuralSizer.get_control_point(diagram, :pure_bending)
    cp_pure_tens = StructuralSizer.get_control_point(diagram, :pure_tension)
    
    # Find max moment point from all diagram points
    max_M_idx = argmax([p.Mn for p in diagram.points])
    Mn_max = diagram.points[max_M_idx].Mn
    Pn_at_Mn_max = diagram.points[max_M_idx].Pn
    
    # Find max factored moment
    max_φM_idx = argmax([p.φMn for p in diagram.points])
    φMn_max = diagram.points[max_φM_idx].φMn
    φPn_at_φMn_max = diagram.points[max_φM_idx].φPn
    
    return (
        P0 = cp_pure_comp.Pn,
        φP0 = cp_pure_comp.φPn,
        Pn_max = cp_max_comp.Pn,
        φPn_max = cp_max_comp.φPn,
        Pb = cp_balanced.Pn,
        Mb = cp_balanced.Mn,
        φPb = cp_balanced.φPn,
        φMb = cp_balanced.φMn,
        Mn_max = Mn_max,
        Pn_at_Mn_max = Pn_at_Mn_max,
        φMn_max = φMn_max,
        φPn_at_φMn_max = φPn_at_φMn_max,
        Mn_pure_bending = cp_pure_bend.Mn,
        φMn_pure_bending = cp_pure_bend.φMn,
        Pn_tension = cp_pure_tens.Pn,
        φPn_tension = cp_pure_tens.φPn,
    )
end

"""Classify design regime based on eccentricity."""
function classify_regime(diagram, h_in::Float64)
    cp_balanced = StructuralSizer.get_control_point(diagram, :balanced)
    Pb = cp_balanced.Pn
    Mb = cp_balanced.Mn
    eb = Mb * 12 / max(Pb, 1e-6)  # inches
    eb_over_h = eb / h_in
    return (eb_over_h=eb_over_h,)
end

"""Calculate slenderness effects."""
function calc_slenderness_effects(section, mat, kLu_r::Float64, βdns::Float64, Pu::Float64, Mu::Float64)
    if kLu_r == 0
        return (δns=1.0, Pc=Inf, slender=false, penalty=0.0)
    end
    
    # Calculate radius of gyration
    if section isa StructuralSizer.RCColumnSection
        h_in = ustrip(u"inch", section.h)
        r = 0.3 * h_in
    else
        D_in = ustrip(u"inch", section.D)
        r = 0.25 * D_in
    end
    
    Lu_in = kLu_r * r
    Lu_m = Lu_in * 0.0254
    
    geometry = StructuralSizer.ConcreteMemberGeometry(Lu_m; Lu=Lu_m, k=1.0)
    
    try
        result = StructuralSizer.magnify_moment_nonsway(
            section, mat, geometry,
            Pu, 0.0, Mu;
            βdns=βdns
        )
        
        penalty = result.slender ? (result.Mc - Mu) / max(Mu, 1e-6) * 100 : 0.0
        
        return (δns=result.δns, Pc=result.Pc, slender=result.slender, penalty=penalty)
    catch e
        return (δns=Inf, Pc=0.0, slender=true, penalty=100.0)
    end
end

# ==============================================================================
# Main Study Loop
# ==============================================================================

function run_parametric_study()
    print_header("RC Column Parametric Study")
    
    # Estimate total combinations
    n_rect = length(SIZES) * length(ASPECT_RATIOS) * length(FC_VALUES) * 
             length(FY_VALUES) * length(TARGET_RHOS) * length(COVERS) * 
             length(ARRANGEMENTS) * length(TIE_TYPES)
    n_circ = length(SIZES) * length(FC_VALUES) * length(FY_VALUES) * 
             length(TARGET_RHOS) * length(COVERS) * length(TIE_TYPES)
    n_total = n_rect + n_circ
    
    println("Estimated section combinations: ~$n_total")
    println()
    
    # Results storage
    results = DataFrame(
        id = Int[],
        shape = Symbol[],
        b_in = Float64[],
        h_in = Float64[],
        D_in = Float64[],
        aspect_ratio = Float64[],
        cover_in = Float64[],
        arrangement = Symbol[],
        tie_type = Symbol[],
        Ag_in2 = Float64[],
        As_in2 = Float64[],
        bar_size = Int[],
        n_bars = Int[],
        rho_actual = Float64[],
        fc_ksi = Float64[],
        fy_ksi = Float64[],
        beta1 = Float64[],
        volume_concrete_m3 = Float64[],
        volume_steel_m3 = Float64[],
        volume_total_m3 = Float64[],
        carbon_concrete_kg = Float64[],
        carbon_steel_kg = Float64[],
        carbon_total_kg = Float64[],
        P0_kip = Float64[],
        Pn_max_kip = Float64[],
        Pb_kip = Float64[],
        Mb_kipft = Float64[],
        Mn_max_kipft = Float64[],
        Pn_at_Mn_max_kip = Float64[],
        Mn_pure_bending_kipft = Float64[],
        Pn_tension_kip = Float64[],
        phi_P0_kip = Float64[],
        phi_Pn_max_kip = Float64[],
        phi_Pb_kip = Float64[],
        phi_Mb_kipft = Float64[],
        phi_Mn_max_kipft = Float64[],
        phi_Pn_at_phi_Mn_max_kip = Float64[],
        phi_Mn_pure_bending_kipft = Float64[],
        P0_per_Ag_ksi = Float64[],
        Mn_max_per_Ag_kipft_in2 = Float64[],
        steel_contribution_pct = Float64[],
        phi_Pn_max_per_carbon_kip_per_kg = Float64[],  # structural efficiency
        # Slenderness: kLu/r × βdns combinations (representative: βdns=0.6)
        kLu_r_30_delta_ns = Float64[],
        kLu_r_30_penalty_pct = Float64[],
        kLu_r_50_delta_ns = Float64[],
        kLu_r_50_penalty_pct = Float64[],
        kLu_r_70_delta_ns = Float64[],
        kLu_r_70_penalty_pct = Float64[],
        # Slenderness sensitivity to βdns at kLu/r=50
        kLu_r_50_bdns_03_delta_ns = Float64[],
        kLu_r_50_bdns_08_delta_ns = Float64[],
        eb_over_h = Float64[],
    )
    
    id_counter = 0
    sections_created = 0
    sections_failed = 0
    first_errors = String[]  # Capture first few errors for debugging
    
    progress = Progress(n_total, desc="Generating sections: ")
    
    # === RECTANGULAR COLUMNS ===
    for size in SIZES
        for ar in ASPECT_RATIOS
            b = Float64(size)
            h = Float64(round(Int, size * ar))
            Ag = b * h
            
            for fc in FC_VALUES
                for fy in FY_VALUES
                    for ρ_target in TARGET_RHOS
                        config = find_bars_for_rho(Ag, ρ_target, BAR_SIZES)
                        if isnothing(config)
                            # Advance progress for all skipped inner iterations
                            for _ in 1:(length(COVERS) * length(ARRANGEMENTS) * length(TIE_TYPES))
                                next!(progress)
                            end
                            continue
                        end
                        
                        for cover in COVERS
                            for arr in ARRANGEMENTS
                                for tie_type in TIE_TYPES
                                    next!(progress)
                                    
                                    try
                                        section = StructuralSizer.RCColumnSection(
                                            b = b * u"inch",
                                            h = h * u"inch",
                                            bar_size = config.bar_size,
                                            n_bars = config.n_bars,
                                            cover = cover * u"inch",
                                            tie_type = tie_type,
                                            arrangement = arr
                                        )
                                        
                                        mat = (fc = fc, fy = fy, Es = 29000.0, εcu = 0.003)
                                        diagram = StructuralSizer.generate_PM_diagram(section, mat)
                                        pm = extract_pm_metrics(diagram)
                                        
                                        β1 = fc <= 4.0 ? 0.85 : max(0.65, 0.85 - 0.05 * (fc - 4.0))
                                        
                                        # Volumes
                                        Ag_m2 = Ag * (0.0254)^2
                                        As_m2 = config.As * (0.0254)^2
                                        vol_concrete = (Ag_m2 - As_m2) * TYPICAL_COLUMN_HEIGHT_M
                                        vol_steel = As_m2 * TYPICAL_COLUMN_HEIGHT_M
                                        vol_total = Ag_m2 * TYPICAL_COLUMN_HEIGHT_M
                                        
                                        # Embodied carbon
                                        carbon = calc_embodied_carbon(vol_concrete, vol_steel)
                                        
                                        steel_contrib = config.As * fy / pm.P0 * 100
                                        
                                        # Slenderness at representative load level (50% of max capacity)
                                        Pu_test = pm.φPn_max / 2
                                        Mu_test = pm.φMb / 2
                                        slender_30 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[1]), 0.6, Pu_test, Mu_test)
                                        slender_50 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[2]), 0.6, Pu_test, Mu_test)
                                        slender_70 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[3]), 0.6, Pu_test, Mu_test)
                                        # βdns sensitivity at kLu/r=50
                                        slender_50_bdns03 = calc_slenderness_effects(section, mat, 50.0, BDNS_VALUES[1], Pu_test, Mu_test)
                                        slender_50_bdns08 = calc_slenderness_effects(section, mat, 50.0, BDNS_VALUES[3], Pu_test, Mu_test)
                                        
                                        regime = classify_regime(diagram, h)
                                        
                                        id_counter += 1
                                        
                                        push!(results, (
                                            id = id_counter,
                                            shape = :rect,
                                            b_in = b,
                                            h_in = h,
                                            D_in = 0.0,
                                            aspect_ratio = ar,
                                            cover_in = cover,
                                            arrangement = arr,
                                            tie_type = tie_type,
                                            Ag_in2 = Ag,
                                            As_in2 = config.As,
                                            bar_size = config.bar_size,
                                            n_bars = config.n_bars,
                                            rho_actual = config.ρ_actual,
                                            fc_ksi = fc,
                                            fy_ksi = fy,
                                            beta1 = β1,
                                            volume_concrete_m3 = vol_concrete,
                                            volume_steel_m3 = vol_steel,
                                            volume_total_m3 = vol_total,
                                            carbon_concrete_kg = carbon.concrete,
                                            carbon_steel_kg = carbon.steel,
                                            carbon_total_kg = carbon.total,
                                            P0_kip = pm.P0,
                                            Pn_max_kip = pm.Pn_max,
                                            Pb_kip = pm.Pb,
                                            Mb_kipft = pm.Mb,
                                            Mn_max_kipft = pm.Mn_max,
                                            Pn_at_Mn_max_kip = pm.Pn_at_Mn_max,
                                            Mn_pure_bending_kipft = pm.Mn_pure_bending,
                                            Pn_tension_kip = pm.Pn_tension,
                                            phi_P0_kip = pm.φP0,
                                            phi_Pn_max_kip = pm.φPn_max,
                                            phi_Pb_kip = pm.φPb,
                                            phi_Mb_kipft = pm.φMb,
                                            phi_Mn_max_kipft = pm.φMn_max,
                                            phi_Pn_at_phi_Mn_max_kip = pm.φPn_at_φMn_max,
                                            phi_Mn_pure_bending_kipft = pm.φMn_pure_bending,
                                            P0_per_Ag_ksi = pm.P0 / Ag,
                                            Mn_max_per_Ag_kipft_in2 = pm.Mn_max / Ag,
                                            steel_contribution_pct = steel_contrib,
                                            phi_Pn_max_per_carbon_kip_per_kg = pm.φPn_max / max(carbon.total, 1e-6),
                                            kLu_r_30_delta_ns = slender_30.δns,
                                            kLu_r_30_penalty_pct = slender_30.penalty,
                                            kLu_r_50_delta_ns = slender_50.δns,
                                            kLu_r_50_penalty_pct = slender_50.penalty,
                                            kLu_r_70_delta_ns = slender_70.δns,
                                            kLu_r_70_penalty_pct = slender_70.penalty,
                                            kLu_r_50_bdns_03_delta_ns = slender_50_bdns03.δns,
                                            kLu_r_50_bdns_08_delta_ns = slender_50_bdns08.δns,
                                            eb_over_h = regime.eb_over_h,
                                        ))
                                        
                                        sections_created += 1
                                        
                                    catch e
                                        sections_failed += 1
                                        if length(first_errors) < 5
                                            push!(first_errors, "RECT $(b)x$(h): $(sprint(showerror, e))")
                                        end
                                        continue
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    # === RECTANGULAR COLUMNS - CORNERS ONLY (4 bars) ===
    for size in SIZES
        for ar in ASPECT_RATIOS
            b = Float64(size)
            h = Float64(round(Int, size * ar))
            Ag = b * h
            
            for fc in FC_VALUES
                for fy in FY_VALUES
                    # For corners_only, try bar sizes to get ρ in valid range with exactly 4 bars
                    for bar_size in BAR_SIZES
                        bar = StructuralSizer.rebar(bar_size)
                        As_bar = ustrip(u"inch^2", bar.A)
                        As_total = 4 * As_bar
                        ρ_actual = As_total / Ag
                        
                        # Skip if outside ACI limits
                        (ρ_actual < 0.01 || ρ_actual > 0.08) && continue
                        
                        for cover in COVERS
                            for tie_type in TIE_TYPES
                                try
                                    section = StructuralSizer.RCColumnSection(
                                        b = b * u"inch",
                                        h = h * u"inch",
                                        bar_size = bar_size,
                                        n_bars = 4,
                                        cover = cover * u"inch",
                                        tie_type = tie_type,
                                        arrangement = :corners_only
                                    )
                                    
                                    mat = (fc = fc, fy = fy, Es = 29000.0, εcu = 0.003)
                                    diagram = StructuralSizer.generate_PM_diagram(section, mat)
                                    pm = extract_pm_metrics(diagram)
                                    
                                    β1 = fc <= 4.0 ? 0.85 : max(0.65, 0.85 - 0.05 * (fc - 4.0))
                                    
                                    # Volumes
                                    Ag_m2 = Ag * (0.0254)^2
                                    As_m2 = As_total * (0.0254)^2
                                    vol_concrete = (Ag_m2 - As_m2) * TYPICAL_COLUMN_HEIGHT_M
                                    vol_steel = As_m2 * TYPICAL_COLUMN_HEIGHT_M
                                    vol_total = Ag_m2 * TYPICAL_COLUMN_HEIGHT_M
                                    
                                    carbon = calc_embodied_carbon(vol_concrete, vol_steel)
                                    steel_contrib = As_total * fy / pm.P0 * 100
                                    
                                    # Slenderness
                                    Pu_test = pm.φPn_max / 2
                                    Mu_test = pm.φMb / 2
                                    slender_30 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[1]), 0.6, Pu_test, Mu_test)
                                    slender_50 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[2]), 0.6, Pu_test, Mu_test)
                                    slender_70 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[3]), 0.6, Pu_test, Mu_test)
                                    slender_50_bdns03 = calc_slenderness_effects(section, mat, 50.0, BDNS_VALUES[1], Pu_test, Mu_test)
                                    slender_50_bdns08 = calc_slenderness_effects(section, mat, 50.0, BDNS_VALUES[3], Pu_test, Mu_test)
                                    
                                    regime = classify_regime(diagram, h)
                                    
                                    id_counter += 1
                                    
                                    push!(results, (
                                        id = id_counter,
                                        shape = :rect,
                                        b_in = b,
                                        h_in = h,
                                        D_in = 0.0,
                                        aspect_ratio = ar,
                                        cover_in = cover,
                                        arrangement = :corners_only,
                                        tie_type = tie_type,
                                        Ag_in2 = Ag,
                                        As_in2 = As_total,
                                        bar_size = bar_size,
                                        n_bars = 4,
                                        rho_actual = ρ_actual,
                                        fc_ksi = fc,
                                        fy_ksi = fy,
                                        beta1 = β1,
                                        volume_concrete_m3 = vol_concrete,
                                        volume_steel_m3 = vol_steel,
                                        volume_total_m3 = vol_total,
                                        carbon_concrete_kg = carbon.concrete,
                                        carbon_steel_kg = carbon.steel,
                                        carbon_total_kg = carbon.total,
                                        P0_kip = pm.P0,
                                        Pn_max_kip = pm.Pn_max,
                                        Pb_kip = pm.Pb,
                                        Mb_kipft = pm.Mb,
                                        Mn_max_kipft = pm.Mn_max,
                                        Pn_at_Mn_max_kip = pm.Pn_at_Mn_max,
                                        Mn_pure_bending_kipft = pm.Mn_pure_bending,
                                        Pn_tension_kip = pm.Pn_tension,
                                        phi_P0_kip = pm.φP0,
                                        phi_Pn_max_kip = pm.φPn_max,
                                        phi_Pb_kip = pm.φPb,
                                        phi_Mb_kipft = pm.φMb,
                                        phi_Mn_max_kipft = pm.φMn_max,
                                        phi_Pn_at_phi_Mn_max_kip = pm.φPn_at_φMn_max,
                                        phi_Mn_pure_bending_kipft = pm.φMn_pure_bending,
                                        P0_per_Ag_ksi = pm.P0 / Ag,
                                        Mn_max_per_Ag_kipft_in2 = pm.Mn_max / Ag,
                                        steel_contribution_pct = steel_contrib,
                                        phi_Pn_max_per_carbon_kip_per_kg = pm.φPn_max / max(carbon.total, 1e-6),
                                        kLu_r_30_delta_ns = slender_30.δns,
                                        kLu_r_30_penalty_pct = slender_30.penalty,
                                        kLu_r_50_delta_ns = slender_50.δns,
                                        kLu_r_50_penalty_pct = slender_50.penalty,
                                        kLu_r_70_delta_ns = slender_70.δns,
                                        kLu_r_70_penalty_pct = slender_70.penalty,
                                        kLu_r_50_bdns_03_delta_ns = slender_50_bdns03.δns,
                                        kLu_r_50_bdns_08_delta_ns = slender_50_bdns08.δns,
                                        eb_over_h = regime.eb_over_h,
                                    ))
                                    
                                    sections_created += 1
                                    
                                catch e
                                    sections_failed += 1
                                    if length(first_errors) < 5
                                        push!(first_errors, "RECT CORNERS $(b)x$(h): $(sprint(showerror, e))")
                                    end
                                    continue
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    # === CIRCULAR COLUMNS ===
    for D in SIZES
        Ag = π * (D/2)^2
        
        for fc in FC_VALUES
            for fy in FY_VALUES
                for ρ_target in TARGET_RHOS
                    config = find_bars_for_rho(Ag, ρ_target, BAR_SIZES)
                    n_inner = length(COVERS) * length(TIE_TYPES)
                    if isnothing(config) || config.n_bars < 6
                        for _ in 1:n_inner
                            next!(progress)
                        end
                        continue
                    end
                    
                    for cover in COVERS
                        for tie_type in TIE_TYPES
                            next!(progress)
                            
                            try
                                n_bars_actual = max(config.n_bars, 6)
                                bar = StructuralSizer.rebar(config.bar_size)
                                As_actual = n_bars_actual * ustrip(u"inch^2", bar.A)
                                ρ_actual = As_actual / Ag
                                
                                (ρ_actual < 0.01 || ρ_actual > 0.08) && continue
                                
                                section = StructuralSizer.RCCircularSection(
                                    D = Float64(D) * u"inch",
                                    bar_size = config.bar_size,
                                    n_bars = n_bars_actual,
                                    cover = cover * u"inch",
                                    tie_type = tie_type
                                )
                                
                                mat = (fc = fc, fy = fy, Es = 29000.0, εcu = 0.003)
                                diagram = StructuralSizer.generate_PM_diagram(section, mat)
                                pm = extract_pm_metrics(diagram)
                                
                                β1 = fc <= 4.0 ? 0.85 : max(0.65, 0.85 - 0.05 * (fc - 4.0))
                                
                                # Volumes
                                Ag_m2 = Ag * (0.0254)^2
                                As_m2 = As_actual * (0.0254)^2
                                vol_concrete = (Ag_m2 - As_m2) * TYPICAL_COLUMN_HEIGHT_M
                                vol_steel = As_m2 * TYPICAL_COLUMN_HEIGHT_M
                                vol_total = Ag_m2 * TYPICAL_COLUMN_HEIGHT_M
                                
                                carbon = calc_embodied_carbon(vol_concrete, vol_steel)
                                
                                steel_contrib = As_actual * fy / pm.P0 * 100
                                
                                Pu_test = pm.φPn_max / 2
                                Mu_test = pm.φMb / 2
                                slender_30 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[1]), 0.6, Pu_test, Mu_test)
                                slender_50 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[2]), 0.6, Pu_test, Mu_test)
                                slender_70 = calc_slenderness_effects(section, mat, Float64(SLENDERNESS_RATIOS[3]), 0.6, Pu_test, Mu_test)
                                slender_50_bdns03 = calc_slenderness_effects(section, mat, 50.0, BDNS_VALUES[1], Pu_test, Mu_test)
                                slender_50_bdns08 = calc_slenderness_effects(section, mat, 50.0, BDNS_VALUES[3], Pu_test, Mu_test)
                                
                                regime = classify_regime(diagram, Float64(D))
                                
                                id_counter += 1
                                
                                push!(results, (
                                    id = id_counter,
                                    shape = :circular,
                                    b_in = 0.0,
                                    h_in = 0.0,
                                    D_in = Float64(D),
                                    aspect_ratio = 1.0,
                                    cover_in = cover,
                                    arrangement = :perimeter,
                                    tie_type = tie_type,
                                    Ag_in2 = Ag,
                                    As_in2 = As_actual,
                                    bar_size = config.bar_size,
                                    n_bars = n_bars_actual,
                                    rho_actual = ρ_actual,
                                    fc_ksi = fc,
                                    fy_ksi = fy,
                                    beta1 = β1,
                                    volume_concrete_m3 = vol_concrete,
                                    volume_steel_m3 = vol_steel,
                                    volume_total_m3 = vol_total,
                                    carbon_concrete_kg = carbon.concrete,
                                    carbon_steel_kg = carbon.steel,
                                    carbon_total_kg = carbon.total,
                                    P0_kip = pm.P0,
                                    Pn_max_kip = pm.Pn_max,
                                    Pb_kip = pm.Pb,
                                    Mb_kipft = pm.Mb,
                                    Mn_max_kipft = pm.Mn_max,
                                    Pn_at_Mn_max_kip = pm.Pn_at_Mn_max,
                                    Mn_pure_bending_kipft = pm.Mn_pure_bending,
                                    Pn_tension_kip = pm.Pn_tension,
                                    phi_P0_kip = pm.φP0,
                                    phi_Pn_max_kip = pm.φPn_max,
                                    phi_Pb_kip = pm.φPb,
                                    phi_Mb_kipft = pm.φMb,
                                    phi_Mn_max_kipft = pm.φMn_max,
                                    phi_Pn_at_phi_Mn_max_kip = pm.φPn_at_φMn_max,
                                    phi_Mn_pure_bending_kipft = pm.φMn_pure_bending,
                                    P0_per_Ag_ksi = pm.P0 / Ag,
                                    Mn_max_per_Ag_kipft_in2 = pm.Mn_max / Ag,
                                    steel_contribution_pct = steel_contrib,
                                    phi_Pn_max_per_carbon_kip_per_kg = pm.φPn_max / max(carbon.total, 1e-6),
                                    kLu_r_30_delta_ns = slender_30.δns,
                                    kLu_r_30_penalty_pct = slender_30.penalty,
                                    kLu_r_50_delta_ns = slender_50.δns,
                                    kLu_r_50_penalty_pct = slender_50.penalty,
                                    kLu_r_70_delta_ns = slender_70.δns,
                                    kLu_r_70_penalty_pct = slender_70.penalty,
                                    kLu_r_50_bdns_03_delta_ns = slender_50_bdns03.δns,
                                    kLu_r_50_bdns_08_delta_ns = slender_50_bdns08.δns,
                                    eb_over_h = regime.eb_over_h,
                                ))
                                
                                sections_created += 1
                                
                            catch e
                                sections_failed += 1
                                if length(first_errors) < 5
                                    push!(first_errors, "CIRC D=$(D): $(sprint(showerror, e))")
                                end
                                continue
                            end
                        end
                    end
                end
            end
        end
    end
    
    finish!(progress)
    
    # Print errors if any
    if !isempty(first_errors)
        println("\nFirst $(length(first_errors)) errors encountered:")
        for err in first_errors
            println("  • $err")
        end
    end
    
    # Save results
    output_file = output_filename("column_study", RESULTS_DIR)
    CSV.write(output_file, results)
    
    print_footer(sections_created, sections_failed, output_file)
    
    # Summary statistics
    println("Summary Statistics:")
    println("-" ^ 40)
    println("Rectangular sections: $(count(results.shape .== :rect))")
    println("Circular sections:    $(count(results.shape .== :circular))")
    
    if nrow(results) > 0
        println()
        println("f'c range: $(minimum(results.fc_ksi)) - $(maximum(results.fc_ksi)) ksi")
        println("fy range:  $(minimum(results.fy_ksi)) - $(maximum(results.fy_ksi)) ksi")
        println("ρ range:   $(round(minimum(results.rho_actual)*100, digits=2))% - $(round(maximum(results.rho_actual)*100, digits=2))%")
        println()
        println("P0 range:     $(round(minimum(results.P0_kip), digits=0)) - $(round(maximum(results.P0_kip), digits=0)) kip")
        println("Mn,max range: $(round(minimum(results.Mn_max_kipft), digits=0)) - $(round(maximum(results.Mn_max_kipft), digits=0)) kip-ft")
        println()
        println("Carbon range: $(round(minimum(results.carbon_total_kg), digits=1)) - $(round(maximum(results.carbon_total_kg), digits=1)) kg CO2e")
    else
        println("\nNo sections created successfully.")
    end
    println()
    
    return results, output_file
end

# ==============================================================================
# Run Study
# ==============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    results, output_file = run_parametric_study()
end
