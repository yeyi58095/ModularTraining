function outputDir = export_candidate_small()
[root, outputDir] = diagnostic_paths(mfilename); folder=fullfile(root,'stage5_candidate','evaluation_20261011_231328_tpf04c8dcd');
x=load(fullfile(folder,'ep21600_stage5_seed207.mat'));row=struct;
for i=1:x.diagnostics.numElements
 s=x.diagnostics.getElement(i);v=s.Values;
 if isa(v,'timeseries')
  row.(s.Name)=struct('t',double(v.Time(:)),'data',double(v.Data));
 elseif strcmp(s.Name,'planned_path')
  snapshots={};last=[];
  for j=1:height(v)
   val=v.Data{j}; if ~isequaln(last,val),snapshots{end+1}=struct('t',seconds(v.Time(j)),'path',val);last=val;end
  end
  row.(s.Name)=snapshots;
 end
end
names=fieldnames(x.experience.Action);ac=x.experience.Action.(names{1});row.action=struct('t',double(ac.Time(:)),'data',double(ac.Data(:)));
s=jsonencode(row);fid=fopen(fullfile(outputDir,'candidate207.json'),'w');fprintf(fid,'%s',s);fclose(fid);disp('Exported 207 only.');
end
