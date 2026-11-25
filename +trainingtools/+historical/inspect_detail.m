function inspect_detail()
root = diagnostic_paths(); folder=fullfile(root,'stage5_detailed','evaluation_20261011_210201_tp3d1c0564');
x=load(fullfile(folder,'ep21600_stage5_seed205.mat'));
for i=1:x.diagnostics.numElements
 s=x.diagnostics.getElement(i); fprintf('%s: %s\n',s.Name,class(s.Values)); disp(size(s.Values));
 if isa(s.Values,'timeseries'),disp(size(s.Values.Data)); else,disp(s.Values(1:min(2,height(s.Values)),:));end
end
end
