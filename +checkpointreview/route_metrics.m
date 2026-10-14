function metrics=route_metrics(route,positions,time)
% Independent horizontal distance to finite segments of the original route.
% This is not guidance_d, route completion, or a monotonic progress measure.
assert(size(route,2)==2 && size(route,1)>=2 && size(positions,2)==2, ...
    'RouteMetrics:Shape','Expected XY route and positions.');
time=double(time(:));positions=double(positions);route=double(route);
assert(~isempty(time) && numel(time)==size(positions,1) && all(diff(time)>0) && ...
    all(isfinite([route(:);positions(:);time])), 'RouteMetrics:Data','Invalid position samples.');
a=route(1:end-1,:);v=diff(route);length2=sum(v.^2,2);
distance=zeros(size(time));
for k=1:numel(time)
    fraction=max(0,min(1,sum((positions(k,:)-a).*v,2)./max(length2,eps)));
    distance(k)=sqrt(min(sum((a+fraction.*v-positions(k,:)).^2,2)));
end
metrics=struct('scope','Horizontal distance to nearest original finite route segment; not route completion. Includes initial position.', ...
    'all_samples',summarize(distance),'after_10_seconds',summarize(distance(time>=10)));
[~,idx]=max(distance);metrics.max_distance_time_seconds=time(idx);
end
function out=summarize(d)
out=struct('count',numel(d),'rms_m',NaN,'max_m',NaN,'p95_m',NaN,'within_10m_fraction',NaN);
if isempty(d),return;end
sorted=sort(d);out.rms_m=sqrt(mean(d.^2));out.max_m=max(d);
out.p95_m=sorted(max(1,ceil(.95*numel(d))));out.within_10m_fraction=mean(d<=10);
end
