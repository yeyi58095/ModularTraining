function test_evaluation_error_reporting()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
file=[tempname(fullfile(root,'tests','output')) '.json'];
report=struct('phase','load_model','results',{{}});
try
    error('Test:OriginalModelFailure','Original model failure');
catch original
    for writer={@trainingcurriculum.write_json,@brokenWriter}
        try
            checkpointreview.fail_evaluation(original,file,report,writer{1});
            error('Test:MissingRethrow','Expected original exception.');
        catch actual
            assert(strcmp(actual.identifier,original.identifier));
            assert(isequal(actual.stack,original.stack));
        end
    end
end
saved=jsondecode(fileread(file));
assert(strcmp(saved.status,'failed') && strcmp(saved.phase,'load_model'));
assert(strcmp(saved.error.identifier,'Test:OriginalModelFailure'));
assert(contains(saved.error.report,'Original model failure'));
fprintf('PASS original exception preserved with successful and failed report writes.\n');
end
function brokenWriter(varargin)
error('Test:ReportWriteFailure','Simulated report write failure');
end
