function checkpoint_save_final(filename, Agent_Stage2, training_stage2)
% Publish agent and its matching history together, after a complete write.
    temporary = [tempname(fileparts(filename)) '.mat'];
    guard = onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
    save(temporary,'Agent_Stage2','training_stage2','-v7.3');
    [ok,message] = movefile(temporary,filename,'f');
    assert(ok,'Checkpoint:FinalPublish','%s',message);
end
function removeTemporary(filename)
    if isfile(filename), delete(filename); end
end
