function signals=instrument_positions(mdl)
% Position-only logging in the evaluator's temporary model copy.
set_param(mdl,'SignalLogging','on','SignalLoggingName','review_signals');
signals=struct('name',{},'block',{},'port',{});
for name=["P_E","P_N"]
    block=char(mdl+"/OBSERVATION/"+name);
    ports=get_param(block,'PortHandles');
    set_param(ports.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom', ...
        'DataLoggingName',char(name),'DataLoggingDecimateData','off','DataLoggingLimitDataPoints','off');
    signals(end+1)=struct('name',char(name),'block',block,'port',1); %#ok<AGROW>
end
end
