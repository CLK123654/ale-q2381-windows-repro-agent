function generate_reference
repoRoot=string(fileparts(fileparts(mfilename("fullpath"))));
taskRoot=fullfile(repoRoot,"task");
workRoot=fullfile(repoRoot,"reference-candidate");
if isfolder(workRoot),rmdir(workRoot,"s");end
mkdir(workRoot);
unzip(fullfile(taskRoot,"输入数据包.zip"),workRoot);
outputRoot=fullfile(workRoot,"output");mkdir(outputRoot);
copyfile(fullfile(repoRoot,"implementation","template_output","README.md"),fullfile(outputRoot,"README.md"));
mkdir(fullfile(outputRoot,"src"));
copyfile(fullfile(repoRoot,"implementation","template_output","src","*"),fullfile(outputRoot,"src"));
addpath(fullfile(outputRoot,"src"));
run_oosm_localization(fullfile(workRoot,"input_data"),outputRoot);
rmpath(fullfile(outputRoot,"src"));
zip(fullfile(repoRoot,"reference-candidate.zip"),"output",workRoot);
fprintf("REFERENCE CANDIDATE READY\n");
end
