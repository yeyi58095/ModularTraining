function cleanupGuard = prepare_model(mdl, disableLogging, disableAnimation)
    % Build the complete restoration plan BEFORE mutating any model settings.
    targets = {char(mdl), 'FastRestart', 'off'};
    if disableLogging
        for parameter = {'SaveTime', 'SaveOutput', 'SaveState', 'SignalLogging'}
            targets(end+1,:) = {char(mdl), parameter{1}, 'off'}; %#ok<AGROW>
        end
        sinks = [find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                    'BlockType', 'ToWorkspace'); ...
                 find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                    'BlockType', 'Scope')];
        for k = 1:numel(sinks)
            targets(end+1,:) = {sinks{k}, 'Commented', 'on'}; %#ok<AGROW>
        end
    end
    if disableAnimation
        targets(end+1,:) = {[char(mdl) '/UAV Animation'], 'Commented', 'on'};
    end
    previous = targets;
    oldDirty = get_param(mdl, 'Dirty');
    for k = 1:size(targets,1)
        previous{k,3} = get_param(targets{k,1}, targets{k,2});
    end
    cleanupGuard = onCleanup(@() restoreModelSettings(mdl, previous, oldDirty)); %#ok<NASGU>
    for k = 1:size(targets,1)
        set_param(targets{k,1}, targets{k,2}, targets{k,3});
    end
end

function restoreModelSettings(mdl, previous, oldDirty)
    if ~bdIsLoaded(mdl), return; end
    restored = true;
    try
        set_param(mdl, 'FastRestart', 'off');
    catch err
        restored = false;
        warning('Training:RestoreFailed', '%s', err.message);
    end
    for j = size(previous,1):-1:1
        try
            set_param(previous{j,1}, previous{j,2}, previous{j,3});
        catch err
            restored = false;
            warning('Training:RestoreFailed', '%s: %s', previous{j,1}, err.message);
        end
    end
    if restored, set_param(mdl, 'Dirty', oldDirty); end
end
