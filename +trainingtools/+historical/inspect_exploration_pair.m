function outputDir = inspect_exploration_pair()
[root, outputDir] = diagnostic_paths(mfilename);p=fullfile(root,'exploration_pair_20261016');model=fullfile(root,'recovery_review_20261016','checkpoints');
folders={'evaluation_20261016_194120_tpd47c04a4','evaluation_20261016_195803_tpcc57bafc'};
x=load(fullfile(p,'reports',folders{1},'scenarios.mat'),'scenarios');y=load(fullfile(p,'reports',folders{2},'scenarios.mat'),'scenarios');assert(isequaln(x,y));rows={};
for mode=1:2
 for ep=[18000 18100 18200]
  f=fullfile(p,'reports',folders{mode},sprintf('ep%d_stage4_seed601.mat',ep));d=load(f);
  names=fieldnames(d.experience.Observation);obs=reshape(d.experience.Observation.(names{1}).Data,10,[]);names=fieldnames(d.experience.Action);act=double(d.experience.Action.(names{1}).Data(:));n=min(150,numel(act));
  z=load(fullfile(model,sprintf('Agent%d.mat',ep)));if isfield(z,'saved_agent'),agent=z.saved_agent;else,agent=z.Agent_Stage2;end
  a=getActor(agent);a.UseDevice='cpu';before=getLearnableParameters(a);state=a.State;for k=1:numel(state),state{k}=state{k}*0;end;a.State=state;
  mu=zeros(n,1);sigma=mu;
  for t=1:n
   [v,next]=evaluate(a,{obs(:,t)});a.State=cellfun(@dlarray,next,'UniformOutput',false);mu(t)=double(v{1});sigma(t)=double(v{2});
  end
  assert(isequaln(before,getLearnableParameters(a)));
  row=struct('exploration',mode==2,'episode',ep,'actions',act(1:n),'observations',double(obs(:,1:n+1)),'means',mu,'stds',sigma);
  for key=["P_E","P_N"]
   v=d.diagnostics.getElement(char(key)).Values;keep=v.Time<=15;row.(key)=double(v.Data(keep));row.time=double(v.Time(keep));
  end
  if mode==1,assert(max(abs(mu-act(1:n)))<1e-6);end
  rows{end+1}=row;
 end
end
trainingcurriculum.write_json(fullfile(outputDir,'first15s.json'),rows);disp('PASS identical paired scenarios, deterministic actor replay, unchanged actor weights. Exported six initial traces.');
end
