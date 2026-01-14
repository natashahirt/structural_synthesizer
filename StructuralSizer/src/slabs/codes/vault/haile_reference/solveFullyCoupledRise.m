function [final_rise, convergence_flag, deflection_check_passed] = solveFullyCoupledRise(s_param, initial_rise, AppliedLoad, Brick_Thick, Trib_Depth, E_param_MPa, varargin)
%SOLVEFULLYCOUPLEDRISE Solves for arch rise using a fully coupled, nested solver.
%
%   This function finds the final equilibrium rise of a parabolic arch.
%   It now includes an optional deflection check.
%
% Inputs:
%   s_param         (double): Span of the arch (meters).
%   initial_rise    (double): Rise of the initial geometry before any load (meters).
%   AppliedLoad     (double): Applied Load [N/m^2] (Self + Live).
%   Brick_Thick     (double): Brick Thickness (m).
%   Trib_Depth      (double): Tributary Depth (m).
%   E_param_MPa     (double): Modulus of Elasticity of the material (MPa).
%
% Optional Name-Value Pair Arguments:
%   'DisplaySolver'   (logical): If true, display fzero iterations. Default: false.
%   'DeflectionLimit' (double): A limit for the change in rise (meters). If the
%                               calculated deflection exceeds this, the third
%                               output will be false. Default: Inf (check disabled).
%
% Outputs:
%   final_rise              (double): The final, converged rise value (meters).
%   convergence_flag        (logical): True if fzero found a solution, otherwise false.
%   deflection_check_passed (logical): True if abs(initial_rise - final_rise) is
%                                      less than or equal to the DeflectionLimit.
%                                      Returns false if solver fails or check fails.

% --- 1. Setup Parameters and Constants ---
p = inputParser;
addParameter(p, 'DisplaySolver', false, @islogical);
% --- MODIFICATION: Added DeflectionLimit as an optional input ---
addParameter(p, 'DeflectionLimit', Inf, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parse(p, varargin{:});

display_solver = p.Results.DisplaySolver;
deflection_limit = p.Results.DeflectionLimit; % Get the user-provided limit

% --- MODIFICATION: Initialize the new output variable ---
deflection_check_passed = false; % Assume failure until proven otherwise

% Convert to base units
E_param_Pa = E_param_MPa * 1e6;
Area = Brick_Thick * Trib_Depth;
w_param = AppliedLoad * Trib_Depth; % Line load in N/m

% Using the renamed getParabolicArcLength function
L_original = getParabolicArcLength(s_param, initial_rise);
if isnan(L_original)
    error('Could not calculate initial curve length.');
end

% --- 2. Set up and Call the Nested Solver (fzero) ---
if display_solver
    options = optimset('Display', 'iter');
else
    options = optimset('Display', 'off');
end
objectiveHandle = @(test_rise) objectiveFunction(test_rise);
initial_guess = initial_rise * 0.98;

if display_solver
    fprintf('\n--- Solving with Fully Coupled System ---\n');
end
[final_rise, fval, exitflag] = fzero(objectiveHandle, initial_guess, options);

% --- 3. Process Results ---
convergence_flag = (exitflag == 1);

if convergence_flag
    if display_solver
        fprintf('Success: Fully coupled solver found a solution.\n');
        fprintf('Initial Rise: %.6f m -> Final Rise: %.6f m\n', initial_rise, final_rise);
    end
    
    % --- MODIFICATION START: Perform Deflection Check ---
    deflection = abs(initial_rise - final_rise);
    deflection_check_passed = (deflection <= deflection_limit);
    
    if display_solver
        fprintf('--- Deflection Check ---\n');
        fprintf('Deflection (Change in Rise): %.6f m (%.2f mm)\n', deflection, deflection * 1000);
        if isinf(deflection_limit)
             fprintf('Deflection Limit: Inf (Check is always true)\n');
        else
             fprintf('Deflection Limit: %.6f m (%.2f mm)\n', deflection_limit, deflection_limit * 1000);
        end
        
        if deflection_check_passed
            fprintf('Result: PASS (Deflection is within the limit)\n');
        else
            fprintf('Result: FAIL (Deflection exceeds the limit)\n');
        end
    end
    % --- MODIFICATION END ---
    
else
    if display_solver
        fprintf('Failure: fzero could not solve the system. Exit flag: %d\n', exitflag);
    end
    final_rise = NaN; % Return NaN on failure
    % deflection_check_passed remains false
end

if display_solver
    fprintf('-----------------------------------------\n');
end

%% --- Nested Objective Function ---
    function error = objectiveFunction(test_rise)
        if abs(test_rise) < 1e-9
            shortening_meters = 0;
        else
            dydx_func = @(x) (4 * test_rise) / s_param - (8 * x * test_rise) / (s_param^2);
            dLdx_func = @(x) sqrt(1 + dydx_func(x).^2);
            term1_sq_force = ((w_param * s_param^2) / (8 * test_rise))^2;
            force_func = @(x) sqrt(term1_sq_force + ((w_param * s_param / 2) - w_param * x).^2);
            combined_integrand_func = @(x) force_func(x) .* dLdx_func(x);
            integral_Force_dL = integral(combined_integrand_func, 0, s_param);
            shortening_meters = integral_Force_dL / (Area * E_param_Pa);
        end
        L_target_elastic = L_original - shortening_meters;
        L_geometric_actual = getParabolicArcLength(s_param, test_rise);
        error = L_geometric_actual - L_target_elastic;
    end
end