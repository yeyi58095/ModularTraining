function script=history_candidate(script)
% Evaluation-only: exclude unused zero padding from historical CTE points.
% Preserve endpoint segment extension, targets, reward and termination limits.
old='    path_CTE = global_path;';
assert(numel(strfind(script,old))==1 && contains(script,'path_length = path_length + new_len;'), ...
    'Evaluation:GuidanceDrift','Unexpected historical path implementation.');
script=strrep(script,old,'    path_CTE = global_path(1:path_length, :);');
end
