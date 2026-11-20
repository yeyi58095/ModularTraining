function spec=sac_paper64_fresh500k()
% Fresh four-stage trial profile. Retain the baseline actor/critic settings.
spec=trainingmodels.load_profile('sac_paper64');
spec.name='sac_paper64_fresh500k';
spec.experienceBufferLength=500000;
end
