function test_sac_wind_history_batch()
% Fake evaluator checks batching, retry and bundle integrity without flights.
root=fileparts(fileparts(mfilename('fullpath')));
folder=tempname(fullfile(root,'artifacts')); mkdir(folder);
oldPath=path; oldFolder=pwd;
restore=onCleanup(@() restoreCaller(oldPath,oldFolder)); %#ok<NASGU>
for name=["+trainingtools","+checkpointreview","+trainingcurriculum","+trainingenv","runtime","artifacts"]
    mkdir(fullfile(folder,name));
end
copyfile(fullfile(root,'+trainingtools','review_sac_wind_history.m'),fullfile(folder,'+trainingtools'));
copyfile(fullfile(root,'+checkpointreview','sha256.m'),fullfile(folder,'+checkpointreview'));
copyfile(fullfile(root,'+trainingcurriculum','write_json.m'),fullfile(folder,'+trainingcurriculum'));
write(fullfile(folder,'+trainingenv','resolve.m'),"function resolve(~)"+newline+"end");
write(fullfile(folder,'runtime','checkpoint_select_agent.m'),"function checkpoint_select_agent(~)"+newline+"end");
write(fullfile(folder,'runtime','checkpoint_resume_state.m'), ...
    "function [h,ep]=checkpoint_resume_state(f)"+newline+ ...
    "h=[]; [~,n]=fileparts(f); ep=sscanf(n,'Agent%d');"+newline+"end");
write(fullfile(folder,'compare_training_checkpoints.m'),join([
    "function r=compare_training_checkpoints(s,varargin)"
    "ep=varargin{2}; out=fullfile(s,sprintf('eval%d',ep));"
    "assert(~isfolder(out),'Unexpected repeat evaluation'); mkdir(out);"
    "r=struct('status','complete','outputDir',out,'results',{cell(1,20)}, ..."
    "'checkpoints',{{struct('sha256',checkpointreview.sha256(fullfile(s,'checkpoints',sprintf('Agent%d.mat',ep))))}}, ..."
    "'summary',{{struct('checkpoint_episode',ep)}});"
    "trainingcurriculum.write_json(fullfile(out,'evaluation.json'),r);"
    "end"],newline));
cd(folder); addpath(folder,fullfile(folder,'runtime'),'-begin');
session=fullfile(folder,'20261105_210649_recovery_tpb199bcee'); mkdir(session);
mkdir(fullfile(session,'checkpoints'));
for ep=1000:100:1500
    write(fullfile(session,'checkpoints',sprintf('Agent%d.mat',ep)),string(ep));
end
write(fullfile(folder,'artifacts','sac-weak-wind-1000-run.txt'),session);
write(fullfile(session,'model.json'),'{"name":"sac_paper64"}');
write(fullfile(session,'status.json'),'{"state":"paused"}');
for name=["curriculum.json","environment.json","recovery.json"]
    write(fullfile(session,name),'{}');
end
bundle=trainingtools.review_sac_wind_history();
manifest=jsondecode(fileread(fullfile(bundle,'manifest.json')));
assert(strcmp(manifest.status,'complete') && numel(manifest.completed_episodes)==6);
trainingtools.review_sac_wind_history(); % Must reuse six verified results.
write(fullfile(bundle,'episode_1100','evaluation.json'),'corrupt');
try
    trainingtools.review_sac_wind_history();
    error('Test:ExpectedFailure','Expected damaged bundle detection.');
catch err
    assert(strcmp(err.identifier,'Review:Changed'));
end
fprintf('BATCH_TEST_OK\n');
end
function write(file,contents)
fid=fopen(file,'w'); assert(fid~=-1);
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',contents);
end
function restoreCaller(oldPath,oldFolder)
cd(oldFolder); path(oldPath);
end
