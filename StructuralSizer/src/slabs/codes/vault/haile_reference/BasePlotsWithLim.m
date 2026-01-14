% --- Define Parameters ---
clearvars; close all; clc;
span_x = 2:0.1:10.5;
% Define base ratios with a step size of 1
base_ratios = 5:1:30; 
% Define which ratios get a thick line and a label
ratios_to_highlight = 5:5:30; 
% Define MOE values to test
MOE_values = [500 1000 2000 4000 8000]; % [MPa]
% Fixed variables
Trib_Depth = 1;         % [m]
Brick_Thick = 5;        % [cm]
Apex_Rise = 5;          % [cm]
Wall_Thick = 10;       % [cm] if filled make wall thick same as trib depth
Density = 2000;         % [kg/m3]
AppliedLoad = 7000;     % [N/m^2]
FinishLoad = 1000;         % [N/m^2]
plot_x_boundary = max(span_x);

%% --- Part 1: Plot Base Stress-Span Curves & Add Ratio Labels ---
figure('Position', [100, 100, 1100, 800]);
ax = gca; 
hold(ax, 'on');
fprintf('Plotting base stress curves...\n');

for j = 1:length(base_ratios)
    Ratio_j = base_ratios(j);
    Stress_j = zeros(1, length(span_x));
    
    for k = 1:length(span_x)
        % Using the symmetric VaultStress function for the base curves
        [vaultstress_k, ~] = VaultStress(span_x(k), Ratio_j, Trib_Depth, Brick_Thick, Wall_Thick, Apex_Rise, Density, AppliedLoad/1000, FinishLoad/1000);
        Stress_j(k) = vaultstress_k; 
    end
    
    % --- MODIFICATION: Updated line styles to shades of grey ---
    if ismember(Ratio_j, ratios_to_highlight)
        % Plot highlighted curves with a thick, dark grey line
        plot(ax, span_x, Stress_j, 'LineWidth', 2.0, 'Color', [0.5 0.5 0.5]);
        x_pos = span_x(end) + 0.1; 
        y_pos = Stress_j(end);     
        text(x_pos, y_pos, sprintf('Span/%d', Ratio_j), 'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left', 'FontSize', 10, 'Color', [0.3 0.3 0.3]);
    else
        % Plot all other curves with a medium-thin, lighter grey line
        plot(ax, span_x, Stress_j, 'LineWidth', 1.0, 'Color', [0.75 0.75 0.75]);
    end
end
uistack(findobj(ax, 'LineWidth', 2.0), 'top'); % Bring thick lines to the front

%% --- Part 2: Calculate and Plot Failure Limit Curves ---
% Use a high-resolution range for a smooth envelope calculation
limit_calc_ratios = min(ratios_to_highlight):0.05:max(ratios_to_highlight);

for m = 1:length(MOE_values)
    current_MOE = MOE_values(m);
    fprintf('\nCalculating limit curve for MOE = %g MPa...\n', current_MOE);
    
    limit_spans_raw = [];
    limit_stresses_raw = [];
    % Loop through the high-resolution continuous ratios
    for j = 1:length(limit_calc_ratios)
        Ratio_j = limit_calc_ratios(j);
        last_good_span = NaN;
        
        for k = 1:length(span_x)
            span_test = span_x(k);
            initial_rise_test = span_test / Ratio_j;
            deflection_limit_test = span_test / 240;
            
            % Using the symmetric VaultStress to get self-weight for the solver
            [~, weight_at_test] = VaultStress(span_test, Ratio_j, Trib_Depth, Brick_Thick, Wall_Thick, Apex_Rise, Density, AppliedLoad/1000, FinishLoad/1000);
            total_load_Pa = AppliedLoad + (weight_at_test * 1000);
            
            % Call the fully coupled solver
            [~, did_converge, check_passed] = solveFullyCoupledRise(span_test, initial_rise_test, total_load_Pa, Brick_Thick/100, Trib_Depth, current_MOE,'DeflectionLimit', deflection_limit_test);
            
            if did_converge && check_passed
                last_good_span = span_test;
            else
                break;
            end
        end
        
        if ~isnan(last_good_span)
            [stress_at_limit, ~] = VaultStress(last_good_span, Ratio_j, Trib_Depth, Brick_Thick, Wall_Thick, Apex_Rise, Density, AppliedLoad/1000, FinishLoad/1000);
            limit_spans_raw(end+1) = last_good_span;
            limit_stresses_raw(end+1) = stress_at_limit;
        end
    end
    
    if ~isempty(limit_spans_raw)
        % Data Cleaning, Clipping, and Sorting
        [sorted_spans, sortIdx] = sort(limit_spans_raw);
        sorted_stresses = limit_stresses_raw(sortIdx);
        
        [unique_spans, ia] = unique(sorted_spans);
        unique_stresses = zeros(size(unique_spans)); 
        for i = 1:length(unique_spans)
            mask = (sorted_spans == unique_spans(i));
            stresses_for_this_span = sorted_stresses(mask);
            unique_stresses(i) = max(stresses_for_this_span);
        end
        
        % Interpolate the cleaned data for a smoother curve
        if length(unique_spans) > 1
            interp_spans = linspace(min(unique_spans), max(unique_spans), 500);
            interp_stresses = interp1(unique_spans, unique_stresses, interp_spans, 'pchip');
        else
            interp_spans = unique_spans;
            interp_stresses = unique_stresses;
        end
        
        % --- MODIFICATION: Plot solid red line (no transparency) ---
        plot(ax, interp_spans, interp_stresses, 'r-', 'LineWidth', 2.5);
    end
end

%% --- Part 3: Finalize Plot ---
hold(ax, 'off');
grid on;
grid minor;
xlabel('Span (m)');
ylabel('Stress (kN/m^2)');
title('Vault Stress vs. Span with Deflection-Based Failure Limits');
xlim([2 10.5]);
ylim([0 9]);
width=1800;
height=1450;
set(ax, 'Layer', 'top'); 
box on;