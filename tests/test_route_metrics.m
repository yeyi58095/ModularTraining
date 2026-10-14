function test_route_metrics()
% Finite endpoints, corner, repeated waypoint and initialization exclusion.
r=checkpointreview.route_metrics([0 0;10 0;10 0;10 10], ...
    [-3 4;5 2;13 5;10 12],[0;10;11;12]);
assert(abs(r.all_samples.rms_m-sqrt(42/4))<1e-12);
assert(r.all_samples.max_m==5 && r.max_distance_time_seconds==0);
assert(abs(r.after_10_seconds.rms_m-sqrt(17/3))<1e-12);
assert(r.after_10_seconds.max_m==3 && r.after_10_seconds.p95_m==3);
assert(r.all_samples.within_10m_fraction==1);
r=checkpointreview.route_metrics([0 0;0 0],[3 4],0);
assert(r.all_samples.rms_m==5 && r.after_10_seconds.count==0);
try
    checkpointreview.route_metrics([0 0;1 0],[0 0;1 0],[0;0]);
    error('Test:Expected','Expected invalid time refusal.');
catch err
    assert(strcmp(err.identifier,'RouteMetrics:Data'));
end
fprintf('PASS finite route distances and time-window handling.\n');
end
