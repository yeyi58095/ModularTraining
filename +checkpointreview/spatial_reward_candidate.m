function [reward,terms] = spatial_reward_candidate(legacyTerms,dMeters,distanceWeight)
% Offline candidate only. dMeters is guidance distance, NOT original-route CTE.
% Columns follow instrument_reward: replace cross_track and distance_bonus only.
% No hidden normalized inputs, curvature relief, or window-target distance bonus.
if nargin<3, distanceWeight=0.2; end
validateattributes(legacyTerms,{'double'},{'2d','real','finite','nonempty'});
validateattributes(dMeters,{'double'},{'vector','real','finite','nonnegative'});
validateattributes(distanceWeight,{'double'},{'scalar','real','finite','positive'});
assert(size(legacyTerms,2)==10 && size(legacyTerms,1)==numel(dMeters), ...
    'RewardCalibration:Shape','Expected N-by-10 terms and N physical distances.');
dMeters=dMeters(:);
terms=legacyTerms;
% Keep perfect-tracking intercept 0.2; sweep only distance penalty slope.
terms(:,1)=0.2-distanceWeight*dMeters/30;
% Keep the explicit 0.1 baseline; replace always-on gate with a 0..0.05 bonus.
terms(:,8)=0.1+0.05*max(0,1-dMeters/10);
reward=sum(terms,2);
end
