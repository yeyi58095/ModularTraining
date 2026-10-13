function script=progress_window_candidate(script)
% Evaluation-only spatial progress window. No timed-target tracking guarantee.
assert(contains(script,'buffer_counter = buffer_counter + 1;') && ...
    contains(script,'mod(buffer_counter, window_length)'), ...
    'Evaluation:WindowDrift','Unexpected window implementation.');
script = strjoin({ ...
'function [waypoints_window, velocity_window, valid_flag, loiter_flag, distance_to_target] = WindowManager(position_in, velocity_in, window_length, uav_e, uav_n)'
'%#codegen'
'% Spatial route following: monotonic progress and contiguous forward chunks.'
'persistent progress last_emitted'
'if isempty(progress), progress=1; last_emitted=0; end'
'waypoints_window=zeros(window_length,3); velocity_window=zeros(window_length,3);'
'valid_flag=false; loiter_flag=false; distance_to_target=0;'
'n=size(position_in,1);'
'if n<window_length, return; end'
'best=progress; best_d=Inf;'
'for k=progress:min(n,progress+window_length)'
' d=(position_in(k,1)-uav_e)^2+(position_in(k,2)-uav_n)^2;'
' if d<best_d, best_d=d; best=k; end'
'end'
'progress=best; first=max(1,last_emitted);'
'if last_emitted==0'
' valid_flag=true;'
'elseif progress>=last_emitted+window_length-1-40 && last_emitted+2*(window_length-1)<=n'
' first=last_emitted+window_length-1; valid_flag=true;'
'end'
'waypoints_window=position_in(first:first+window_length-1,:);'
'velocity_window=velocity_in(first:first+window_length-1,:);'
'distance_to_target=sqrt(best_d);'
'if valid_flag, last_emitted=first; end'
'end'},newline);
end
