function write_json(file,value)
% JSON 原子替換：先寫同目錄暫存檔，再發布到指定位置。
% UTF-8 輸出，先關閉檔案再替換；失敗拋出錯誤，此函式不自行決定訓練是否過關。
% Same-directory replacement: readers see either the old or the new document.
temporary=[tempname(fileparts(file)) '.json'];
fid=fopen(temporary,'w','n','UTF-8'); assert(fid~=-1,'Cannot write %s',temporary);
guard=onCleanup(@() fclose(fid));
fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));
clear guard;
[ok,message]=movefile(temporary,file,'f'); assert(ok,'%s',message);
end
