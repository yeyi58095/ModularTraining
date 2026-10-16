function scaled=scale_std_actor(actor,factor)
% One-time branch transformation: keep weights/mean, scale Gaussian std.
% Keep the public sdev output name so training and evaluation use the same PDF.
validateattributes(factor,{'numeric'},{'scalar','positive','<=',1,'finite'});
net=getModel(actor); names=string({net.Layers.Name});
assert(all(ismember(["observation","mp_out","sdev"],names)) && ...
    ~any(ismember(names,["std_unscaled","review_std_scale"])), ...
    'Recovery:StdLayout','Expected an unscaled actor; repeated scaling is refused.');
idx=find(names=="sdev");
assert(isa(net.Layers(idx),class(softplusLayer)),'Recovery:StdLayout','Expected softplus std output.');
graph=layerGraph(net);
graph=replaceLayer(graph,'sdev',softplusLayer('Name','std_unscaled'));
graph=addLayers(graph,scalingLayer('Name','sdev','Scale',factor));
graph=connectLayers(graph,'std_unscaled','sdev');
scaled=rlContinuousGaussianActor(graph,getObservationInfo(actor),getActionInfo(actor), ...
    'ObservationInputNames','observation','ActionMeanOutputNames','mp_out', ...
    'ActionStandardDeviationOutputNames','sdev','UseDevice',actor.UseDevice);
scaled.State=actor.State;
assert(isequaln(getLearnableParameters(actor),getLearnableParameters(scaled)), ...
    'Recovery:Weights','Std transformation changed learnable weights.');
end
