function write_json(file,value)
% Same-directory replacement: readers see either the old or the new document.
temporary=[tempname(fileparts(file)) '.json'];
fid=fopen(temporary,'w','n','UTF-8'); assert(fid~=-1,'Cannot write %s',temporary);
guard=onCleanup(@() fclose(fid));
fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));
clear guard;
[ok,message]=movefile(temporary,file,'f'); assert(ok,'%s',message);
end
