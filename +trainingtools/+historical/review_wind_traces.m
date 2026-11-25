function outputDir = review_wind_traces(bundle)
% Summarize paired SAC episode 1300/1400 observations after the first 100 steps.
projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if nargin == 0
    bundle = fullfile('artifacts','incoming','sac-wind-history-20261106', ...
        'sac-wind-history-20261105_210649_recovery_tpb199bcee');
end
bundle = trainingtools.local_data_path(projectRoot,bundle);
episodes = [1300 1400];
rows = {};
for stage = 1:2
    for seed = 516:525
        traces = cell(1,2);
        counts = zeros(1,2);
        for k = 1:2
            episode = episodes(k);
            file = fullfile(bundle,sprintf('episode_%d',episode), ...
                sprintf('ep%d_stage%d_seed%d.mat',episode,stage,seed));
            trace = load(file,'experience');
            traces{k} = trace.experience;
            counts(k) = numel(trace.experience.Reward.Data);
        end
        commonSteps = min(counts);
        for k = 1:2
            trace = traces{k};
            names = fieldnames(trace.Observation);
            observation = reshape(double(trace.Observation.(names{1}).Data),10,[]);
            names = fieldnames(trace.Action);
            action = double(trace.Action.(names{1}).Data(:));
            indices = 101:min(commonSteps,size(observation,2));
            actions = action(101:min(commonSteps,numel(action)));
            rows{end+1} = struct('episode',episodes(k),'stage',stage,'seed',seed, ...
                'common_steps',commonSteps,'guidance_rms_m',sqrt(mean((30*observation(7,indices)).^2)), ...
                'roll_abs_max_deg',40*max(abs(observation(3,indices))), ...
                'action_change_mean',mean(abs(diff(actions))), ...
                'action_saturation',mean(abs(actions)>=.99)); %#ok<AGROW>
        end
    end
end
[~,outputDir] = diagnostic_paths(mfilename);
trainingcurriculum.write_json(fullfile(outputDir,'trace_summary.json'),rows);
disp(struct2table([rows{:}]));
end
