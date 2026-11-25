function outputDir = inspect_stage5()
[root, outputDir] = diagnostic_paths(mfilename);
folder=fullfile(root,'stage5_21600','evaluation_20261011_204637_tpfc7d7a58');
rows={};
for stage=[4 5]
 for seed=201:210
  data=load(fullfile(folder,sprintf('ep21600_stage%d_seed%d.mat',stage,seed)));
  e=data.experience; names=fieldnames(e.Observation); ob=e.Observation.(names{1});
  names=fieldnames(e.Action); ac=e.Action.(names{1});
  rows{end+1}=struct('stage',stage,'seed',seed,'obs',reshape(double(ob.Data),10,[]), ...
   'time',double(ob.Time(:)),'actions',double(ac.Data(:)),'action_time',double(ac.Time(:)));
 end
end
s=load(fullfile(folder,'scenarios.mat'));
fid=fopen(fullfile(outputDir,'stage5_arrays.json'),'w'); fprintf(fid,'%s',jsonencode(struct('rows',{rows},'scenarios',{s.scenarios}))); fclose(fid);
fprintf('Exported 20 traces and saved scenarios; no sim or training.\n');
end
