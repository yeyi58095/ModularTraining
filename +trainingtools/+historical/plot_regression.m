function outputDir = plot_regression(arraysPath)
[root, outputDir] = diagnostic_paths(mfilename);
if nargin == 0
    arraysPath = fullfile(root,'regression_20261016','arrays.json');
end
arraysPath = trainingtools.local_data_path(fileparts(root),arraysPath);
 rows=jsondecode(fileread(arraysPath));
f=figure('Visible','off','Position',[100 100 1000 850]); tiledlayout(3,1); keys={'guidance_d','phi','action'}; labels={'Guidance distance (m)','Roll (degrees)','Action'};
for k=1:3
 nexttile; hold on;
 for j=1:numel(rows)
  v=rows(j).(keys{k}); t=v.t(:); y=v.data(:); m=t<=12;
  if k==2,y=rad2deg(y);end
  plot(t(m),y(m),'LineWidth',1.3,'DisplayName',string(rows(j).episode));
 end
 if k==1,yline(50,'r--','50 m threshold','HandleVisibility','off');end
 ylabel(labels{k});xlim([0 12]);grid on;legend('Location','best');
end
xlabel('Simulation time (s)'); sgtitle('Same straight route, no wind: recorded lab evaluation');
exportgraphics(f,fullfile(outputDir,'initial_divergence.png'),'Resolution',150);close(f);
end
