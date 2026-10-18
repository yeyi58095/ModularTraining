function test_training_progress_display()
% Verify saved boundaries, log-derived progress and provisional/checkpoint wording.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
out=fullfile(root,'tests','output'); if ~isfolder(out), mkdir(out); end
session=tempname(out); mkdir(session); cleanup=onCleanup(@()rmdir(session,'s')); %#ok<NASGU>
mkdir(fullfile(session,'attempt_00001'));
stages(1)=struct('id','straight','max_episodes',100, ...
    'advance_when',struct('metric','stage_episodes','at_least',2));
criteria=struct('all',{{ ...
    struct('metric','stage_episodes','at_least',2), ...
    struct('metric','reward_mean','window',2,'consecutive_windows',2,'at_least',20), ...
    struct('metric','steps_mean','window',2,'consecutive_windows',2,'at_least',9), ...
    struct('metric','full_length_rate','window',2,'consecutive_windows',2, ...
        'steps_at_least',10,'at_least',0.5)}});
stages(2)=struct('id','random_wind','max_episodes',100,'advance_when',criteria);
writeJson(fullfile(session,'curriculum.json'),struct('stages',stages));
writeJson(fullfile(session,'curriculum_state.json'),struct('stage_index',2, ...
    'start_episode',100,'completed',struct('id','straight','start_episode',0,'end_episode',100)));
writeJson(fullfile(session,'status.json'),struct('attempt',1,'state','running'));
lines=cell(4,1);
for i=1:4
    ep=100+i; reward=19+i; steps=10-(i==4);
    lines{i}=sprintf('Episode: %d/200 | Episode reward: %8.2f | Episode steps: %d | Average reward: %8.2f | Step Count: %d | Episode Q0: %8.2f | Stage 2/2 random_wind | as of Ep %d: stage episodes %d/100; all{stage_episodes 4/2 ✓}', ...
        ep,reward,steps,reward,10*i,0,ep,i);
end
writeText(fullfile(session,'attempt_00001','stdout.log'),strjoin(lines,newline));
captured=evalc('training_status(string(session),2);');
assert(contains(captured,'Episode 100 is last of Stage 1 (straight); Episode 101 starts Stage 2 (random_wind).'));
assert(contains(captured,'data through Episode 104'));
assert(contains(captured,'full_length_rate'),'%s',captured);
assert(contains(captured,'暫算') || contains(captured,'provisional'));
% A second attempt supersedes the duplicate episode, as the plotter does.
mkdir(fullfile(session,'attempt_00002'));
writeText(fullfile(session,'attempt_00002','stdout.log'), ...
    'Episode: 104/200 | Episode reward: 1 | Episode steps: 1 | Average reward: 1 | Step Count: 1 | Episode Q0: 0');
captured=evalc('training_status(string(session),1);');
assert(contains(captured,'Still needed:'));
% Sparse lineage must retain unknown episodes; parent rows after fork are excluded.
parent=tempname(out); mkdir(parent); parentCleanup=onCleanup(@()rmdir(parent,'s')); %#ok<NASGU>
mkdir(fullfile(parent,'attempt_00001'));
writeText(fullfile(parent,'attempt_00001','stdout.log'),strjoin(lines(1:3),newline));
writeJson(fullfile(session,'recovery.json'),struct('parent_session',parent,'parent_episode',102));
writeText(fullfile(session,'attempt_00001','stdout.log'),lines{4});
rows=trainingcurriculum.log_history(session);
assert(isequal(rows(:,1),[101;102;104]));
captured=evalc('training_status(string(session),1);');
assert(contains(captured,'Missing stage log rows: 1'));
writeJson(fullfile(session,'curriculum_outcome.json'),struct('success',true,'episodes',104, ...
    'curriculumDecision','complete','curriculumReason','conditions_met','successAgent','Agent_Success.mat'));
captured=evalc('training_status(string(session),1);');
assert(contains(captured,'Formal result: curriculum completed'));
% At-most conditions and nonfinite observations retain the original decision semantics.
stage=stages(2); stage.on_limit='pause';
stage.advance_when=struct('metric','stage_episodes','at_most',3);
p=trainingcurriculum.progress(stage,[],[]); assert(~p.passed && ~isempty(p.missing));
stage.advance_when=struct('metric','steps_mean','window',2,'at_most',10);
p=trainingcurriculum.progress(stage,[1;1],[11;11]);
assert(~p.passed && contains(p.compact,'<= 10') && contains(p.missing{1},'gap 1'));
p=trainingcurriculum.progress(stage,[1;1],[NaN;10]); assert(~p.passed);
stage.advance_when=struct('any',{{struct('metric','stage_episodes','at_least',3), ...
    struct('metric','steps_mean','window',2,'at_least',10)}});
p=trainingcurriculum.progress(stage,[1;1],[10;10]); assert(p.passed && isempty(p.missing));
stage.advance_when.any{1}.at_least=5;
p=trainingcurriculum.progress(stage,[1;1],[1;1]); assert(~p.passed && numel(p.missing)==1);
fprintf('PASS: training status reports exact saved boundary and provisional stage metrics.\n');
end

function writeJson(path,value)
fid=fopen(path,'w'); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value),'char');
end

function writeText(path,value)
fid=fopen(path,'w'); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',value);
end
