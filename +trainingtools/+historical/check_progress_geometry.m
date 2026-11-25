function outputDir = check_progress_geometry()
[dataRoot, outputDir] = diagnostic_paths(mfilename);
base = fullfile(dataRoot,'stage6_review');
folder=fullfile(base,'main','reports','evaluation_20261013_234642_tpd8fddaaa');
r=jsondecode(fileread(fullfile(folder,'evaluation.json')));s=load(fullfile(folder,'scenarios.mat'));
rows=struct([]);
for j=1:numel(r.results)
 x=load(fullfile(folder,r.results(j).trace),'diagnostics');
 e=x.diagnostics.getElement('P_E').Values;n=x.diagnostics.getElement('P_N').Values;
 p=s.scenarios{1,j}.waypoints(:,1:2);a=p(1:end-1,:);v=diff(p);len=sum(v.^2,2);
 distances=zeros(numel(e.Data),1);
 for k=1:numel(distances)
  q=[e.Data(k),n.Data(k)];t=max(0,min(1,sum((q-a).*v,2)./max(len,eps)));
  distances(k)=sqrt(min(sum((a+t.*v-q).^2,2)));
 end
 rows(j).seed=r.results(j).seed;
 rows(j).route_distance_rms_m=sqrt(mean(distances.^2));
 [rows(j).route_distance_max_m,idx]=max(distances);
 rows(j).max_distance_time_seconds=double(e.Time(idx));
 rows(j).route_distance_max_after_10s_m=max(distances(e.Time>=10));
 rows(j).scope='Independent finite-segment distance to original supplied route, all simulation samples.';
end
disp(rows);disp(jsonencode(rows));
fid=fopen(fullfile(outputDir,'progress_geometry.json'),'w');fprintf(fid,'%s',jsonencode(rows));fclose(fid);
end
