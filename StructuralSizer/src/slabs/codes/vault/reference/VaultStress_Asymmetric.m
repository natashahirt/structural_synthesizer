% File: VaultStress_Asymmetric.m 
function [Working_Stress, SelfWeightLoad_kNm2] = ...
    VaultStress_Asymmetric(span_param, lambda_param, Tributary_Depth_param, brick_thick_cm, brick_depth_cm, apex_rise_cm, brick_density_kg_m3, applied_load_kN_m2, finishing_load_kN_m2)
% Calculates max working stress assuming an ASYMMETRIC (half-span) live load.

    % --- Parameter Assignments and Unit Conversions ---
    span = span_param;
    lambda = lambda_param;
    trib_depth = Tributary_Depth_param;
    brick_thick_m = brick_thick_cm / 100;
    brick_depth_m = brick_depth_cm / 100;
    apex_rise_additional_m = apex_rise_cm / 100;
    
    if lambda <= 0
        error('Lambda (span/rise ratio) must be positive.');
    end
    rise = span / lambda;
    
    % --- Self-Weight Calculations (Identical to symmetric case) ---
    intrados_func = @(x) (4 * rise / span^2) .* (span .* x - x.^2);
    extrados_func = @(x) intrados_func(x) + brick_thick_m;
    rib_top_line_func = @(x) repmat(rise + brick_thick_m + apex_rise_additional_m, size(x));
    
    integrand_vault_cs = @(x) extrados_func(x) - intrados_func(x);
    vault_cs_area_m2 = integral(integrand_vault_cs, 0, span);
    
    integrand_rib_cs = @(x) rib_top_line_func(x) - extrados_func(x);
    rib_cs_area_m2 = integral(integrand_rib_cs, 0, span);
    if rib_cs_area_m2 < 0; rib_cs_area_m2 = 0; end
    
    vault_volume_m3 = vault_cs_area_m2 * trib_depth;
    rib_volume_m3 = rib_cs_area_m2 * brick_depth_m;
    vault_mass_kg = vault_volume_m3 * brick_density_kg_m3;
    rib_mass_kg = rib_volume_m3 * brick_density_kg_m3;
    total_self_weight_N = (vault_mass_kg + rib_mass_kg) * 9.81;
    SelfWeightLoad_kNm = (total_self_weight_N / span) / 1000;
    SelfWeightLoad_kNm2 = (total_self_weight_N / span / trib_depth) / 1000;
    
    % --- Structural Analysis (Asymmetric Half-Span Live Load) ---
    
    % 1. Define Dead and Live loads per unit length (kN/m)
    finishing_load_dist_kNm = finishing_load_kN_m2 * trib_depth; 
    q_Dead_kNm = SelfWeightLoad_kNm + finishing_load_dist_kNm;
    q_Live_kNm = applied_load_kN_m2 * trib_depth;
    
    % 2. Calculate Horizontal Thrust using the asymmetric formula
    thrust_kN = (span^2 / (16 * rise)) * (2 * q_Dead_kNm + q_Live_kNm);

    % 3. Calculate Vertical Reactions for each side
    vertical_LiveSide_kN = (q_Dead_kNm * span / 2) + (3 * q_Live_kNm * span / 8);
    vertical_NoLiveSide_kN = (q_Dead_kNm * span / 2) + (q_Live_kNm * span / 8);

    % 4. Calculate Resultant Force at each support
    resultant_LiveSide_kN = sqrt(vertical_LiveSide_kN^2 + thrust_kN^2);
    resultant_NoLiveSide_kN = sqrt(vertical_NoLiveSide_kN^2 + thrust_kN^2);
    
    % 5. Determine the Maximum Resultant Force
    max_resultant_force_kN = max(resultant_LiveSide_kN, resultant_NoLiveSide_kN);
    
    % --- Working Stress Calculation (Based on the maximum force) ---
    resisting_area_m2 = trib_depth * brick_thick_m; 
    
    if resisting_area_m2 <= 0
        error('Resisting area is zero or negative.');
    end
    
    working_stress_Pa = (max_resultant_force_kN * 1000) / resisting_area_m2; 
    Working_Stress = working_stress_Pa / 10^6;
end
