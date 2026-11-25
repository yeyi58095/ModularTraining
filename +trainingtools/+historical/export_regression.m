function outputDir = export_regression()
[root, outputDir] = diagnostic_paths(mfilename); folder=fullfile(root,'regression_20261016','evaluation_20261016_160454_tp76e91eb6'); rows={};
for ep=[18400 18500 18600]
 x=load(fullfile(folder,sprintf('ep%d_stage1_seed501.mat',ep))); row=struct('episode',ep);
 for i=1:x.diagnostics.numElements
  s=x.diagnostics.getElement(i); v=s.Values;
  if isa(v,'timeseries')
   row.(s.Name)=struct('t',double(v.Time(:)),'data',double(v.Data));
  else
   snapshots={}; last=[];
   for j=1:height(v)
    val=v.Data{j};
    if ~isequaln(last,val), snapshots{end+1}=struct('t',seconds(v.Time(j)),'path',val); last=val; end
   end
   row.(s.Name)=snapshots;
  end
 end
 names=fieldnames(x.experience.Action); ac=x.experience.Action.(names{1});
 row.action=struct('t',double(ac.Time(:)),'data',double(ac.Data(:))); rows{end+1}=row;
end
fid=fopen(fullfile(outputDir,'arrays.json'),'w'); fprintf(fid,'%s',jsonencode(rows));fclose(fid);
disp('Offline trace export complete. No simulation or training.');
end
