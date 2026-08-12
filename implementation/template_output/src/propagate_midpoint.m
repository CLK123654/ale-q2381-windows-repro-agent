function [x,P] = propagate_midpoint(x,P,v,omega,contract)
dt = contract.dt_s;
mid = x(3) + 0.5*omega*dt;
F = [1 0 -dt*v*sin(mid); 0 1 dt*v*cos(mid); 0 0 1];
x = [x(1)+dt*v*cos(mid); x(2)+dt*v*sin(mid); wrap_angle(x(3)+omega*dt)];
P = F*P*F' + diag(contract.process_covariance_diag_per_step);
P = 0.5*(P+P');
end

function value = wrap_angle(value)
value = atan2(sin(value),cos(value));
end
