function [xNext,PNext,d2,innovation] = joseph_measurement_update(x,P,event,beacons,applyUpdate)
if strcmp(event.sensor,"GPS")
    H = [1 0 0;0 1 0];
    innovation = [event.z1-x(1);event.z2-x(2)];
    R = diag([event.sigma1^2,event.sigma2^2]);
else
    beacon = beacons(beacons.beacon_id==event.beacon_id,:);
    delta = [x(1)-beacon.x_m,x(2)-beacon.y_m];
    predicted = hypot(delta(1),delta(2));
    H = [delta/predicted,0];
    innovation = event.z1-predicted;
    R = event.sigma1^2;
end
S = H*P*H' + R;
d2 = innovation'*(S\innovation);
xNext=x; PNext=P;
if applyUpdate
    K = (P*H')/S;
    xNext = x + K*innovation;
    xNext(3)=atan2(sin(xNext(3)),cos(xNext(3)));
    A=eye(3)-K*H;
    PNext=A*P*A'+K*R*K';
    PNext=0.5*(PNext+PNext');
end
end
