% generate_test_vectors.m
% Generates test vectors for Julia validation against MATLAB implementation
%
% Output: test_vectors.csv in the test directory

clearvars; close all; clc;

% Output file path (relative to this script's location)
output_file = fullfile(fileparts(mfilename('fullpath')), 'test_vectors.csv');

% =========================================================================
% Test Cases
% =========================================================================

% Test parameters matching BasePlotsWithLim.m defaults
Trib_Depth = 1.0;       % [m]
Brick_Thick = 5;        % [cm]
Wall_Thick = 10;        % [cm] (rib_depth)
Apex_Rise = 5;          % [cm] (rib_apex_rise)
Density = 2000;         % [kg/m³]
AppliedLoad = 7000;     % [N/m²] = 7 kN/m²
FinishLoad = 1000;      % [N/m²] = 1 kN/m²

% Test spans and ratios
test_spans = [2.0, 4.0, 6.0, 8.0, 10.0];
test_ratios = [5, 10, 15, 20, 25, 30];

% MOE values for elastic shortening tests
test_MOEs = [500, 1000, 2000, 4000, 8000, 29000];

% =========================================================================
% Generate Test Vectors
% =========================================================================

fprintf('Generating test vectors...\n');

% Open file for writing
fid = fopen(output_file, 'w');

% Header
fprintf(fid, 'test_type,span,ratio,MOE,trib_depth,brick_thick_cm,wall_thick_cm,apex_rise_cm,density,applied_load_Pa,finish_load_Pa,');
fprintf(fid, 'stress_MPa,self_weight_kN_m2,arc_length,final_rise,converged,deflection_ok\n');

% -------------------------------------------------------------------------
% Test 1: Symmetric stress analysis
% -------------------------------------------------------------------------
fprintf('  Symmetric stress tests...\n');
for span = test_spans
    for ratio = test_ratios
        [stress, weight] = VaultStress(span, ratio, Trib_Depth, Brick_Thick, ...
            Wall_Thick, Apex_Rise, Density, AppliedLoad/1000, FinishLoad/1000);
        
        fprintf(fid, 'symmetric,%.2f,%d,0,%.2f,%d,%d,%d,%d,%d,%d,', ...
            span, ratio, Trib_Depth, Brick_Thick, Wall_Thick, Apex_Rise, ...
            Density, AppliedLoad, FinishLoad);
        fprintf(fid, '%.10f,%.10f,0,0,0,0\n', stress, weight);
    end
end

% -------------------------------------------------------------------------
% Test 2: Asymmetric stress analysis
% -------------------------------------------------------------------------
fprintf('  Asymmetric stress tests...\n');
for span = test_spans
    for ratio = test_ratios
        stress = VaultStress_Asymmetric(span, ratio, Trib_Depth, Brick_Thick, ...
            Wall_Thick, Apex_Rise, Density, AppliedLoad/1000, FinishLoad/1000);
        
        fprintf(fid, 'asymmetric,%.2f,%d,0,%.2f,%d,%d,%d,%d,%d,%d,', ...
            span, ratio, Trib_Depth, Brick_Thick, Wall_Thick, Apex_Rise, ...
            Density, AppliedLoad, FinishLoad);
        fprintf(fid, '%.10f,0,0,0,0,0\n', stress);
    end
end

% -------------------------------------------------------------------------
% Test 3: Arc length
% -------------------------------------------------------------------------
fprintf('  Arc length tests...\n');
for span = test_spans
    for ratio = test_ratios
        rise = span / ratio;
        arc_len = getParabolicArcLength(span, rise);
        
        fprintf(fid, 'arc_length,%.2f,%d,0,0,0,0,0,0,0,0,', span, ratio);
        fprintf(fid, '0,0,%.10f,0,0,0\n', arc_len);
    end
end

% -------------------------------------------------------------------------
% Test 4: Elastic shortening solver
% -------------------------------------------------------------------------
fprintf('  Elastic shortening tests...\n');
for span = [4.0, 6.0, 8.0]  % Subset for solver tests
    for ratio = [10, 15, 20]
        for MOE = test_MOEs
            rise = span / ratio;
            deflection_limit = span / 240;
            
            % Get self-weight for total load calculation
            [~, weight] = VaultStress(span, ratio, Trib_Depth, Brick_Thick, ...
                Wall_Thick, Apex_Rise, Density, AppliedLoad/1000, FinishLoad/1000);
            
            % Total load (matching BasePlotsWithLim.m - no FinishLoad in solver)
            total_load_Pa = AppliedLoad + (weight * 1000);
            
            % Call solver
            [final_rise, converged, defl_ok] = solveFullyCoupledRise(...
                span, rise, total_load_Pa, Brick_Thick/100, Trib_Depth, MOE, ...
                'DeflectionLimit', deflection_limit);
            
            fprintf(fid, 'elastic,%.2f,%d,%d,%.2f,%d,%d,%d,%d,%d,%d,', ...
                span, ratio, MOE, Trib_Depth, Brick_Thick, Wall_Thick, ...
                Apex_Rise, Density, AppliedLoad, FinishLoad);
            
            if isnan(final_rise)
                fprintf(fid, '0,0,0,NaN,%d,%d\n', converged, defl_ok);
            else
                fprintf(fid, '0,0,0,%.10f,%d,%d\n', final_rise, converged, defl_ok);
            end
        end
    end
end

% -------------------------------------------------------------------------
% Test 5: No-rib cases
% -------------------------------------------------------------------------
fprintf('  No-rib tests...\n');
for span = [4.0, 6.0, 8.0]
    for ratio = [10, 15, 20]
        % No ribs (Wall_Thick=0, Apex_Rise=0)
        [stress, weight] = VaultStress(span, ratio, Trib_Depth, Brick_Thick, ...
            0, 0, Density, AppliedLoad/1000, FinishLoad/1000);
        
        fprintf(fid, 'no_rib,%.2f,%d,0,%.2f,%d,0,0,%d,%d,%d,', ...
            span, ratio, Trib_Depth, Brick_Thick, Density, AppliedLoad, FinishLoad);
        fprintf(fid, '%.10f,%.10f,0,0,0,0\n', stress, weight);
    end
end

fclose(fid);

fprintf('\nTest vectors written to:\n  %s\n', output_file);
fprintf('\nTotal test cases: %d\n', ...
    length(test_spans)*length(test_ratios)*2 + ...  % symmetric + asymmetric
    length(test_spans)*length(test_ratios) + ...    % arc_length
    3*3*length(test_MOEs) + ...                     % elastic
    3*3);                                           % no_rib
