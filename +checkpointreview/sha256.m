function value=sha256(filename)
% 檔案指紋：計算完整檔案內容的 SHA-256，供來源與評估前後一致性驗證。
% 輸入 filename、回傳雜湊文字；只讀檔案，不改內容或 metadata。
stream=System.IO.File.OpenRead(char(filename));
guard=onCleanup(@() stream.Dispose()); %#ok<NASGU>
algorithm=System.Security.Cryptography.SHA256.Create();
algorithmGuard=onCleanup(@() algorithm.Dispose()); %#ok<NASGU>
bytes=uint8(algorithm.ComputeHash(stream));
value=lower(reshape(dec2hex(bytes,2).',1,[]));
end
