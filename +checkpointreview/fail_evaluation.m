function fail_evaluation(err,file,report,writer)
% A diagnostic write must never replace the original evaluation exception.
report.status='failed';
report.error=struct('identifier',err.identifier,'message',err.message, ...
    'report',getReport(err,'extended','hyperlinks','off'));
fprintf(2,'Evaluation failed during %s:\n%s\n',report.phase,report.error.report);
try
    writer(file,report);
catch writeError
    fprintf(2,'Could not save evaluation diagnostics to %s: %s\n',file,writeError.message);
end
rethrow(err);
end
