function outputDir = export_history_failures()
[dataRoot, outputDir] = diagnostic_paths(mfilename);
base = fullfile(dataRoot,'stage6_review');
receipt=jsondecode(fileread(fullfile(base,'history_review_receipt.json')));
% The historical receipt records the producing machine's absolute path.
[~, evaluation] = fileparts(strrep(receipt.candidate,'\','/'));
assert(~isempty(regexp(evaluation,'^evaluation_[a-zA-Z0-9_]+$','once')), ...
    'Invalid candidate evaluation in the receipt.');
folder = fullfile(base,'main','reports',evaluation);
report=jsondecode(fileread(fullfile(folder,'evaluation.json')));
rows=report.results;if iscell(rows),rows=[rows{:}];end
for r=rows(:)'
 if r.reached_step_limit,continue;end
 x=load(fullfile(folder,r.trace));row=struct;
 for i=1:x.diagnostics.numElements
  s=x.diagnostics.getElement(i);v=s.Values;
  if isa(v,'timeseries')
   row.(s.Name)=struct('t',double(v.Time(:)),'data',double(v.Data));
  elseif strcmp(s.Name,'planned_path')
   snaps={};last=[];
   for j=1:height(v)
    val=v.Data{j};if ~isequaln(last,val),snaps{end+1}=struct('t',seconds(v.Time(j)),'path',val);last=val;end
   end
   row.(s.Name)=snaps;
  end
 end
 fid=fopen(fullfile(outputDir,sprintf('history_seed%d.json',r.seed)),'w');fprintf(fid,'%s',jsonencode(row));fclose(fid);
end
end
