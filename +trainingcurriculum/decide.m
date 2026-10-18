function decision = decide(stage,rewards,steps)
% 純課程判定：依當階段 reward／steps 歷史和 advance_when，回傳 continue／advance／pause。
% 條件成立優先於預算上限；用盡預算則採 on_limit，不改檔案、agent 或課程狀態。
% Stage-local saved episode data only; no mutable streak counter or eval().
rewards=rewards(:); steps=steps(:);
% Share the condition evaluator with live/status progress displays.
progress=trainingcurriculum.progress(stage,rewards,steps);
% ~isempty 防止零回合直接通關；僅可見本階段傳入的歷史。
passed=~isempty(rewards) && progress.passed;
atLimit=numel(rewards)>=stage.max_episodes;
decision=struct('action','continue','reason','conditions_not_met','stage_episodes',numel(rewards));
% 過關條件優先；未過關且預算已到才採 stage.on_limit。
if passed
    decision.action='advance'; decision.reason='conditions_met';
elseif atLimit
    decision.action=stage.on_limit; decision.reason='episode_budget_reached';
end
end
