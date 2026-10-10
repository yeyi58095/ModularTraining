function value=sha256(filename)
stream=System.IO.File.OpenRead(char(filename));
guard=onCleanup(@() stream.Dispose()); %#ok<NASGU>
algorithm=System.Security.Cryptography.SHA256.Create();
algorithmGuard=onCleanup(@() algorithm.Dispose()); %#ok<NASGU>
bytes=uint8(algorithm.ComputeHash(stream));
value=lower(reshape(dec2hex(bytes,2).',1,[]));
end
