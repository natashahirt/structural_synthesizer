% File: VaultStress.m 
function [Working_Stress, SelfWeightLoad_kNm2] = ...
    VaultStress(span_param, lambda_param, Tributary_Depth_param, brick_thick_cm, brick_depth_cm, apex_rise_cm, brick_density_kg_m3, applied_load_kN_m2, finishing_load_kN_m2)
% VaultStress calculates the working stress in a masonry vault.
%
% Process:
% 1. Define intrados and extrados of the vault (parabolas) and the top line of any rib.
% 2. Calculate cross-sectional areas of the vault and rib using integration.
% 3. Determine self-weight and total loads acting on the arch.
% 4. Assuming a three-hinge arch behavior, calculate reactions and thrust.
% 5. Calculate the working stress based on the resultant force and resisting area.
%
% Note on Extrados: The extrados is simplified by linearly shifting the intrados
% curve upwards by the brick thickness.
%
% Inputs:
%   span_param             (double): Span of the arch (meters).
%   lambda_param           (double): Span/Rise Ratio (e.g., for span/rise = 20, lambda_param = 20)
%   Tributary_Depth_param  (double): Tributary Depth (Rib Spacing or effective width) [meters]
%   brick_thick_cm         (double): Brick thickness of the vault [cm]
%   brick_depth_cm        (double): Brick depth [cm]
%   apex_rise_cm           (double): Additional height of the rib top from vault extrados at apex [cm]
%                                    (Set to 0 if no distinct rib or if rib top aligns with extrados modeling)
%   brick_density_kg_m3    (double): Brick Density [kg/m3]
%   applied_load_kN_m2     (double): Applied distributed load (e.g., live load) [kN/m2]
%   finishing_load_kN_m2   (double): Finishing distributed load (e.g., screed) [kN/m2]
% Outputs:
%   Working_Stress         (double): Maximum working stress in the vault [MPa]
%   SelfWeightLoad_kNm2     (double): Self-weight load of the vault structure [kN/m2]

    % --- Parameter Assignments and Unit Conversions ---
    span = span_param;
    lambda = lambda_param; % Corrected variable name
    trib_depth = Tributary_Depth_param; % Corrected variable name
    brick_thick_m = brick_thick_cm / 100; % Convert cm to meters
    brick_depth_m = brick_depth_cm / 100; % Convert cm to meters
    apex_rise_additional_m = apex_rise_cm / 100; % Additional rise for rib top, from vault's nominal extrados

    % Calculate geometric properties
    if lambda <= 0
        error('Lambda (span/rise ratio) must be positive.');
    end
    rise = span / lambda; % Rise of the intrados

    % --- Define Boundary Curves as Anonymous Functions ---
    % These functions now correctly accept 'x' as an argument.
    % Using element-wise operators (.*, .^) for compatibility with 'integral'.
    
    % Intrados: y = (4*rise/span^2) * (span*x - x^2)
    intrados_func = @(x) (4 * rise / span^2) .* (span .* x - x.^2);
    
    % Extrados: Shifted intrados by brick_thick_m
    % As per Note 4: "linearly shiftting the extrados up by the brick thickness"
    extrados_func = @(x) intrados_func(x) + brick_thick_m;
    
    % Top line of the rib (assumed horizontal for this calculation)
    % This is the absolute height of the rib's top surface from the springing line.
    rib_top_height_m = rise + brick_thick_m + apex_rise_additional_m;
    rib_top_line_func = @(x) repmat(rib_top_height_m, size(x)); % Constant height

    % --- Integral Bounds ---
    x_start = 0;
    x_finish = span;

    % --- Calculate Cross-Sectional Areas (Area in the x-y plane per unit depth) ---
    
    % Vault cross-sectional area (between extrados and intrados)
    % Integrand simplifies to brick_thick_m due to the linear shift assumption
    integrand_vault_cs = @(x) extrados_func(x) - intrados_func(x); % This is equivalent to @(x) brick_thick_m
    vault_cs_area_m2 = integral(integrand_vault_cs, x_start, x_finish);
    % Analytically: vault_cs_area_m2 = brick_thick_m * span; % Can use this for verification

    % Rib cross-sectional area (area between rib top line and vault extrados)
    % This assumes the rib sits on top of the main vault shell.
    integrand_rib_cs = @(x) rib_top_line_func(x) - extrados_func(x);
    
    % Ensure rib integrand is not negative (i.e. rib_top_line is above extrados)
    % Test at mid-span or integrate carefully. If rib_top_height_m can be less than extrados(x)
    % then this model needs adjustment or it implies no rib in that region.
    % For simplicity, we proceed; if apex_rise_additional_m is small/negative, Rib_CS_Area could be negative.
    rib_cs_area_m2 = integral(integrand_rib_cs, x_start, x_finish);
    
    if rib_cs_area_m2 < 0
        % This can happen if apex_rise_additional_m is negative or too small,
        % making the defined "rib_top_line_func" go below the "extrados_func".
        warning('Calculated Rib_CS_Area is negative (%.2f m^2). Check geometry (apex_rise_cm). Assuming no effective rib area contributing to self-weight this way.', rib_cs_area_m2);
        rib_cs_area_m2 = 0;
    end

    % --- Mass and Self-Weight Calculations ---
    % Volume = CrossSectionalArea * TributaryDepth
    vault_volume_m3 = vault_cs_area_m2 * trib_depth;
    rib_volume_m3 = rib_cs_area_m2 * brick_depth_m;

    % Mass = Volume * Density
    vault_mass_kg = vault_volume_m3 * brick_density_kg_m3;
    rib_mass_kg = rib_volume_m3 * brick_density_kg_m3;

    % Total self-weight force [N]
    total_self_weight_N = (vault_mass_kg + rib_mass_kg) * 9.81; % g = 9.81 m/s^2

    % Self-weight load uniformly distributed along the span [kN/m]
    SelfWeightLoad_kNm = (total_self_weight_N / span) / 1000; % Convert N to kN
    SelfWeightLoad_kNm2 = (total_self_weight_N / span/ trib_depth) / 1000; % Convert N to kN

    % --- Total Load Calculation ---
    % Applied loads are given per m^2, convert to per m of span by multiplying by tributary depth
    applied_load_dist_kNm = applied_load_kN_m2 * trib_depth;
    finishing_load_dist_kNm = finishing_load_kN_m2 * trib_depth; 

    % Total uniformly distributed load along the span [kN/m]
    total_UDL_kNm = applied_load_dist_kNm + finishing_load_dist_kNm + SelfWeightLoad_kNm;

    % --- Structural Analysis (Assuming a Three-Hinge Parabolic Arch) ---
    % For a parabolic arch under UDL, it behaves like a three-hinge arch
    % (momentless if shape perfectly matches pressure line).
    
    % Vertical reaction at each support [kN]
    vertical_reaction_kN = (total_UDL_kNm * span) / 2;
    
    % Horizontal thrust [kN]
    % For a parabolic arch with UDL w over span L and rise h_c at crown: H = w*L^2 / (8*h_c)
    thrust_kN = (total_UDL_kNm * span^2) / (8 * rise); % 'rise' is intrados rise

    % Resultant force at the abutment (springing line) [kN]
    resultant_force_kN = sqrt(vertical_reaction_kN^2 + thrust_kN^2);

    % --- Working Stress Calculation ---
    % Stress = Force / Area
    % The resisting area is the cross-section of the vault at the springing,
    % over the tributary depth.
    resisting_area_m2 = trib_depth * brick_thick_m; 
    
    if resisting_area_m2 <= 0
        error('Resisting area for stress calculation is zero or negative. Check brick_thick_cm and Tributary_Depth_param.');
    end
    
    % Working stress in Pascals (N/m^2)
    working_stress_Pa = (resultant_force_kN * 1000) / resisting_area_m2; 
    
    % Convert working stress to MPa
    Working_Stress = working_stress_Pa / 10^6;

end