function outputDir = export_stage6()
[dataRoot, outputDir] = diagnostic_paths(mfilename);
root = fullfile(dataRoot,'stage6_review');
folder=fullfile(root,'main','reports','evaluation_20261013_185244_tp264113fd');
files=dir(fullfile(folder,'ep*.mat'));
assert(~isempty(files),'No trace MAT files at %s',folder);
for f=files'
 x=load(fullfile(f.folder,f.name)); row=struct;
 for i=1:x.diagnostics.numElements
  s=x.diagnostics.getElement(i);v=s.Values;
  if isa(v,'timeseries')
   row.(s.Name)=struct('t',double(v.Time(:)),'data',double(v.Data));
  elseif strcmp(s.Name,'planned_path')
   snapshots={};last=[];
   for j=1:height(v)
    val=v.Data{j};if ~isequaln(last,val),snapshots{end+1}=struct('t',seconds(v.Time(j)),'path',val);last=val;end
   end
   row.(s.Name)=snapshots;
  end
 end
 names=fieldnames(x.experience.Action);a=x.experience.Action.(names{1});
 row.action=struct('t',double(a.Time(:)),'data',double(a.Data(:)));
 fid=fopen(fullfile(outputDir,strrep(f.name,'.mat','.json')),'w');assert(fid~=-1);
 fprintf(fid,'%s',jsonencode(row));fclose(fid);
 fprintf('Exported %s\n',f.name);
end
end
