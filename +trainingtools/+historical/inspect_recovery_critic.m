function inspect_recovery_critic()
p=fullfile(diagnostic_paths(),'recovery_review_20261016'); rows={};
for ep=[18000 18100 18200 18300]
 x=load(fullfile(p,'checkpoints',sprintf('Agent%d.mat',ep)));if isfield(x,'saved_agent'),a=x.saved_agent;else,a=x.Agent_Stage2;end
 c=getCritic(a);c.UseDevice='cpu';s=c.State;for k=1:numel(s),s{k}=s{k}*0;end;c.State=s;
 d=load(fullfile(p,'reports','evaluation_20261016_192536_tpcebd1553',sprintf('ep%d_stage1_seed501.mat',ep)),'experience');e=d.experience;names=fieldnames(e.Observation);o=reshape(e.Observation.(names{1}).Data,10,[]);
 val=evaluate(c,{o(:,1)});v=double(val{1});r=double(e.Reward.Data(:));g=sum((a.AgentOptions.DiscountFactor.^(0:numel(r)-1))'.*r);
 rows{end+1}=struct('episode',ep,'critic_at_initial_observation',v,'deterministic_discounted_recorded_reward',g);
end
disp(jsonencode(rows,PrettyPrint=true));
end
