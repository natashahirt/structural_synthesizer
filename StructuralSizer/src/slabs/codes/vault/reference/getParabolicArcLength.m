% File: getParabolicArcLength.m
function L = getParabolicArcLength(s, h)
%GETPARABOLICARCLENGTH Calculates the arc length of a parabola.
%   L = getParabolicArcLength(s, h) calculates the length of a parabolic arch
%   defined by y(x) = (4h/s^2)*x*(s-x).
%
% Inputs:
%   s (double): Span of the arch.
%   h (double): Height (rise) of the arch at its center.
%
% Output:
%   L (double): The calculated geometric arc length.

if abs(h) < 1e-9
    L = s; % If rise is zero, length is the span
    return;
end

% Derivative of the parabolic equation y(x)
dydx = @(x) (4*h/s) - (8*h*x/s^2);

% Integrand for arc length: sqrt(1 + (dy/dx)^2)
integrand = @(x) sqrt(1 + dydx(x).^2);

% Calculate the length by integrating from 0 to s
L = integral(integrand, 0, s);
end