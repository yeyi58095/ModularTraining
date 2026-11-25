function outputDir = inspect_recovery_resume()
[root, outputDir] = diagnostic_paths(mfilename); p=fullfile(root,'recovery_review_20261016');rows={};
for k=1:3
 ep=17900+100*k; a=readAgent(fullfile(p,'checkpoints',sprintf('Agent%d.mat',ep)));
 b=readAgent(fullfile(p,'runs',sprintf('r%06d',k),'Agent_Initial.mat'));
 o=load(fullfile(p,'runs',sprintf('r%06d',k),'TrainingOptions.mat'));
 row=struct('run',k,'source_episode',ep,'actor_equal',isequaln(getLearnableParameters(getActor(a)),getLearnableParameters(getActor(b))), 'critic_equal',isequaln(getLearnableParameters(getCritic(a)),getLearnableParameters(getCritic(b))), 'actor_state_equal',isequaln(getActor(a).State,getActor(b).State),'options_equal',isequaln(a.AgentOptions,b.AgentOptions),'workers',o.numWorkers,'seeds',o.optionsForDisk.ParallelizationOptions.WorkerRandomSeeds,'resume',string(o.resumeAgentFile));
 rows{end+1}=row;
end
trainingcurriculum.write_json(fullfile(outputDir,'offline_resume.json'),rows);disp(jsonencode(rows,PrettyPrint=true));
end
function a=readAgent(f)
x=load(f);if isfield(x,'saved_agent'),a=x.saved_agent;else,a=x.Agent_Stage2;end
end
