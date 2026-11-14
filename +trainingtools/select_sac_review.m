function decision=select_sac_review(reports,seeds,baselineEpisode)
% Pure, fail-closed selection. No training, filesystem writes or reward ranking.
if isstruct(reports), reports=num2cell(reports); end
assert(~isempty(reports),'Review:Report','No reports.');
metrics=repmat(struct('episode',0,'full_counts',[0 0],'mean_steps',[0 0], ...
    'actual_wind_count',0,'actual_wind_full',0,'eligible',false),1,numel(reports));
for k=1:numel(reports)
    r=reports{k}; rows=r.results; if iscell(rows), rows=[rows{:}]; end
    assert(strcmp(r.status,'complete') && r.weights_unchanged && ~r.use_exploration && ...
        r.max_steps==3000 && numel(rows)==2*numel(seeds), 'Review:Report','Incomplete frozen report.');
    ep=unique([rows.checkpoint_episode]); assert(isscalar(ep),'Review:Report','Mixed checkpoints.');
    counts=zeros(1,2); meanSteps=zeros(1,2); windCount=0; windFull=0;
    for s=1:2
        ids={'random_calm','random_weak_wind'};
        ix=strcmp({rows.stage_id},ids{s}); a=rows(ix);
        assert(numel(a)==numel(seeds) && isequal(sort([a.seed]),sort(seeds)), ...
            'Review:Report','Missing or duplicated stage/seed pairs.');
        assert(all(isfinite([a.steps])) && all([a.steps]>=1 & [a.steps]<=3000), ...
            'Review:Report','Invalid steps.');
        full=[a.steps]==3000 & [a.reached_step_limit] & ~[a.environment_done];
        counts(s)=sum(full); meanSteps(s)=mean([a.steps]);
        if s==2
            wind=[a.wind_east_mps]~=0 | [a.wind_north_mps]~=0 | [a.turbulence]~=0;
            assert(all(isfinite([[a.wind_east_mps] [a.wind_north_mps] [a.turbulence]])), ...
                'Review:Report','Invalid wind.');
            windCount=sum(wind); windFull=sum(full & wind);
        end
    end
    metrics(k)=struct('episode',ep,'full_counts',counts,'mean_steps',meanSteps, ...
        'actual_wind_count',windCount,'actual_wind_full',windFull,'eligible',false); %#ok<AGROW>
end
assert(numel(unique([metrics.episode]))==numel(metrics),'Review:Report','Duplicate checkpoint.');
b=find([metrics.episode]==baselineEpisode); assert(isscalar(b),'Review:Baseline','Missing baseline.');
for k=1:numel(metrics)
    m=metrics(k);
    metrics(k).eligible=all(m.full_counts>=ceil(.8*numel(seeds))) && ...
        all(m.full_counts>=metrics(b).full_counts-1) && m.actual_wind_count>=5 && ...
        m.actual_wind_full>=ceil(.8*m.actual_wind_count);
end
eligible=find([metrics.eligible]); chosen=[];
if ~isempty(eligible)
    rank=zeros(numel(eligible),4);
    for n=1:numel(eligible)
        m=metrics(eligible(n));
        rank(n,:)=[-min(m.full_counts),-sum(m.full_counts),-min(m.mean_steps),m.episode];
    end
    [~,order]=sortrows(rank,[1 2 3 4]); chosen=metrics(eligible(order(1))).episode;
end
decision=struct('selected_episode',chosen,'metrics',metrics, ...
    'rule','Each stage >=80% full; actual wind >=5 cases and >=80% full; each stage no more than one failure worse than baseline. Rank worst-stage full count, total full count, worst-stage mean steps, earlier episode.');
end
