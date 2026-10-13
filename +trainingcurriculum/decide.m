function decision = decide(stage,rewards,steps)
% 純課程判定：依當階段 reward／steps 歷史和 advance_when，回傳 continue／advance／pause。
% 條件成立優先於預算上限；用盡預算則採 on_limit，不改檔案、agent 或課程狀態。
% Stage-local saved episode data only; no mutable streak counter or eval().
rewards=rewards(:); steps=steps(:);
assert(numel(rewards)==numel(steps),'Curriculum:History','Reward/step history lengths differ.');
% ~isempty 防止零回合直接通關；testCondition 只能看到本階段傳入的歷史。
passed=~isempty(rewards) && testCondition(stage.advance_when,rewards,steps);
atLimit=numel(rewards)>=stage.max_episodes;
decision=struct('action','continue','reason','conditions_not_met','stage_episodes',numel(rewards));
% 過關條件優先；未過關且預算已到才採 stage.on_limit。
if passed
    decision.action='advance'; decision.reason='conditions_met';
elseif atLimit
    decision.action=stage.on_limit; decision.reason='episode_budget_reached';
end
end

function result=testCondition(c,rewards,steps)
% 用當階段完整連續視窗算指標；all／any 遞迴合併，不保存可變 streak。
% all 要全部子條件成立，any 任一成立；葉節點依視窗計算。
if isfield(c,'all') || isfield(c,'any')
    isAll=isfield(c,'all');
    if isAll, children=c.all; else, children=c.any; end
    if ~iscell(children), children=num2cell(children); end
    values=false(size(children));
    for i=1:numel(children), values(i)=testCondition(children{i},rewards,steps); end
    if isAll, result=all(values); else, result=any(values); end
    return;
end
if strcmp(c.metric,'stage_episodes')
    values=numel(rewards);
else
    count=1; if isfield(c,'consecutive_windows'), count=c.consecutive_windows; end
    % 先要求 window×consecutive_windows 個完整回合；不足不計部分視窗，也不把初期假零值當完整證據。
    if numel(rewards)<c.window*count, result=false; return; end
    values=zeros(1,count);
    for i=1:count
        % 連續視窗從尾端向前取不重疊區間，資料不足即不通過。
        last=numel(rewards)-(i-1)*c.window; range=last-c.window+1:last;
        switch c.metric
            case 'reward_mean', values(i)=mean(rewards(range));
            case 'steps_mean', values(i)=mean(steps(range));
            case 'full_length_rate'
                if ~all(isfinite(steps(range))), result=false; return; end
                values(i)=mean(steps(range)>=c.steps_at_least);
        end
    end
end
if ~all(isfinite(values)), result=false;
elseif isfield(c,'at_least'), result=all(values>=c.at_least);
else, result=all(values<=c.at_most); end
end
