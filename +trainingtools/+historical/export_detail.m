function outputDir = export_detail()
[root, outputDir] = diagnostic_paths(mfilename); folder=fullfile(root,'stage5_detailed','evaluation_20261011_210201_tp3d1c0564'); rows={};
for stage=[4 5]
 for seed=[205 207 210]
  x=load(fullfile(folder,sprintf('ep21600_stage%d_seed%d.mat',stage,seed))); row=struct('stage',stage,'seed',seed);
  for i=1:x.diagnostics.numElements
   s=x.diagnostics.getElement(i); v=s.Values;
   if isa(v,'timeseries')
    row.(s.Name)=struct('t',double(v.Time(:)),'data',double(v.Data));
   else
    snapshots={}; last=[];
    for j=1:height(v)
     val=v.Data{j};
     if ~isequaln(last,val)
      snapshots{end+1}=struct('t',seconds(v.Time(j)),'path',val); last=val;
     end
    end
    row.(s.Name)=snapshots;
   end
  end
  names=fieldnames(x.experience.Action); ac=x.experience.Action.(names{1});
  row.action=struct('t',double(ac.Time(:)),'data',double(ac.Data(:))); rows{end+1}=row;
 end
end
fid=fopen(fullfile(outputDir,'stage5_detail_arrays.json'),'w'); fprintf(fid,'%s',jsonencode(rows));fclose(fid);
fprintf('Exported six diagnostic traces offline.\n');
end
