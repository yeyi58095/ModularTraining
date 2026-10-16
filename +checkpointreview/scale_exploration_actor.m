function scaled=scale_exploration_actor(actor,factor)
% Evaluation-only Gaussian std scaling. Never save this actor for training.
validateattributes(factor,{'numeric'},{'scalar','positive','<=',1,'finite'});
scaled=actor;
if factor==1,return;end
assert(isa(actor,'rl.function.rlContinuousGaussianActor'),'Evaluation:Actor','Expected a Gaussian actor.');
net=getModel(actor); names=string({net.Layers.Name});
assert(all(ismember(["observation","mp_out","sdev"],names)) && ...
    ~any(names=="review_std_scale"),'Evaluation:Actor','Unsupported actor output layout.');
graph=layerGraph(net);
graph=addLayers(graph,scalingLayer('Name','review_std_scale','Scale',factor));
graph=connectLayers(graph,'sdev','review_std_scale');
scaled=rlContinuousGaussianActor(graph,getObservationInfo(actor),getActionInfo(actor), ...
    'ObservationInputNames','observation','ActionMeanOutputNames','mp_out', ...
    'ActionStandardDeviationOutputNames','review_std_scale','UseDevice','cpu');
scaled.State=actor.State;
assert(isequaln(getLearnableParameters(actor),getLearnableParameters(scaled)), ...
    'Evaluation:Weights','Std scaling must preserve every learnable parameter.');
end
