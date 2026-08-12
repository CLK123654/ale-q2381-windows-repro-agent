function verify_q2381
repoRoot=string(fileparts(fileparts(mfilename("fullpath"))));
taskRoot=fullfile(repoRoot,"task");
workRoot=fullfile(repoRoot,"evidence","windows-work");
if isfolder(workRoot),rmdir(workRoot,"s");end
mkdir(workRoot);
assert(ispc,"MATLAB没有在Windows运行器上执行");

expectedMembers=sort([ ...
    "output/README.md";
    "output/figures/trajectory.svg";
    "output/results/event_decisions.csv";
    "output/results/innovation_log.csv";
    "output/results/replay_ledger.csv";
    "output/results/state_trace.csv";
    "output/results/terminal_validation.json";
    "output/src/adjudicate_event.m";
    "output/src/joseph_measurement_update.m";
    "output/src/propagate_midpoint.m";
    "output/src/replay_window.m";
    "output/src/run_oosm_localization.m"]);
names=["clean directory a with spaces","clean directory b with spaces"];
runs=repmat(struct("root_id","","output_started_empty",false, ...
    "primary_software_executed",false,"process_runs",0, ...
    "input_unchanged",false,"reference_match",false, ...
    "return_code",1,"generated_paths",strings(0,1)),numel(names),1);
for index=1:numel(names)
    runs(index)=run_clean(taskRoot,repoRoot,workRoot,names(index),expectedMembers);
end

baselineRoot=fullfile(workRoot,names(1));
baselineInput=fullfile(baselineRoot,"input_data");
baselineOutput=fullfile(baselineRoot,"candidate","output");
baselineState=readtable(fullfile(baselineOutput,"results","state_trace.csv"));
baselineSvg=fileread(fullfile(baselineOutput,"figures","trajectory.svg"));

variantRoot=fullfile(workRoot,"positive speed mutation");
variantInput=fullfile(variantRoot,"input_data");
variantOutput=fullfile(variantRoot,"candidate","output");
mkdir(variantInput);mkdir(variantOutput);
copyfile(fullfile(baselineInput,"*"),variantInput);
copy_implementation(fullfile(repoRoot,"implementation","template_output"),variantOutput);
controls=readtable(fullfile(variantInput,"controls.csv"));
target=controls.step==30;
assert(sum(target)==1,"控制变化未唯一命中输入记录");
controls.speed_mps(target)=controls.speed_mps(target)+0.05;
writetable(controls,fullfile(variantInput,"controls.csv"));
addpath(fullfile(variantOutput,"src"));
run_oosm_localization(variantInput,variantOutput);
rmpath(fullfile(variantOutput,"src"));
variantState=readtable(fullfile(variantOutput,"results","state_trace.csv"));
positionDelta=norm([variantState.x_m(end)-baselineState.x_m(end), ...
    variantState.y_m(end)-baselineState.y_m(end)]);
svgChanged=~strcmp(baselineSvg,fileread(fullfile(variantOutput,"figures","trajectory.svg")));
assert(positionDelta>1e-6 && svgChanged,"有效控制变化没有改变定位结果");

invalidRoot=fullfile(workRoot,"negative missing contract");
invalidInput=fullfile(invalidRoot,"input_data");
invalidOutput=fullfile(invalidRoot,"candidate","output");
mkdir(invalidInput);mkdir(invalidOutput);
copyfile(fullfile(baselineInput,"*"),invalidInput);
copy_implementation(fullfile(repoRoot,"implementation","template_output"),invalidOutput);
delete(fullfile(invalidInput,"localization_contract.json"));
mkdir(fullfile(invalidOutput,"results"));mkdir(fullfile(invalidOutput,"figures"));
writelines("stale",fullfile(invalidOutput,"results","stale.txt"));
writelines("stale",fullfile(invalidOutput,"figures","stale.svg"));
addpath(fullfile(invalidOutput,"src"));
negativeFailed=false;
try
    run_oosm_localization(invalidInput,invalidOutput);
catch
    negativeFailed=true;
end
rmpath(fullfile(invalidOutput,"src"));
residue=count_files(fullfile(invalidOutput,"results"))+count_files(fullfile(invalidOutput,"figures"));
assert(negativeFailed && residue==0 && ~isfolder(fullfile(invalidOutput,"results")) ...
    && ~isfolder(fullfile(invalidOutput,"figures")),"错误输入没有失败关闭");

[osStatus,osValue]=system('powershell -NoProfile -Command "$o=Get-CimInstance Win32_OperatingSystem; Write-Output ($o.Caption + ''|'' + $o.Version)"');
assert(osStatus==0,"无法读取Windows版本");
evidence=struct;
evidence.schema_version=1;
evidence.result="PASS";
evidence.task_slug="warehouse_robot_delayed_measurement_replay";
evidence.actual_os=strtrim(string(osValue));
evidence.runner_image="windows-2025";
evidence.matlab_version=string(version);
evidence.matlab_release=string(version("-release"));
evidence.computer=string(computer);
evidence.github_run_id=string(getenv("GITHUB_RUN_ID"));
evidence.commit_sha=string(getenv("GITHUB_SHA"));
evidence.attachment_sha256=jsondecode(fileread(fullfile(repoRoot,"qa","expected_hashes.json")));
evidence.clean_room_runs=runs;
evidence.positive_mutation=struct("name","controls.csv中step为30的speed_mps增加0.05", ...
    "terminal_position_delta_m",positionDelta,"svg_changed",svgChanged,"passed",true);
evidence.negative_case=struct("name","缺少localization_contract.json", ...
    "matlab_failed",negativeFailed,"delivery_residue_count",residue,"passed",true);
evidence.reference_member_count=numel(expectedMembers);
evidence.reference_match=true;
write_json(fullfile(workRoot,"windows-summary.json"),evidence);
fprintf("Q2381 WINDOWS MATLAB PASS\n");
end

function report=run_clean(taskRoot,repoRoot,workRoot,name,expectedMembers)
runRoot=fullfile(workRoot,name);
mkdir(runRoot);
unzip(fullfile(taskRoot,"输入数据包.zip"),runRoot);
expectedRoot=fullfile(runRoot,"expected");mkdir(expectedRoot);
unzip(fullfile(taskRoot,"reference.zip"),expectedRoot);
inputRoot=fullfile(runRoot,"input_data");
actualOutput=fullfile(runRoot,"candidate","output");mkdir(actualOutput);
copy_implementation(fullfile(repoRoot,"implementation","template_output"),actualOutput);
assert(~isfolder(fullfile(actualOutput,"results")) && ~isfolder(fullfile(actualOutput,"figures")));
before=input_snapshot(inputRoot);
addpath(fullfile(actualOutput,"src"));
run_oosm_localization(inputRoot,actualOutput);
run_oosm_localization(inputRoot,actualOutput);
rmpath(fullfile(actualOutput,"src"));
assert(strcmp(before,input_snapshot(inputRoot)),"定位程序修改了输入");
assert(isequal(tree_relative(fullfile(runRoot,"candidate"),actualOutput),expectedMembers),"交付成员集合不一致");
compare_reference(expectedRoot,fullfile(runRoot,"candidate"));
report=struct("root_id",name,"output_started_empty",true, ...
    "primary_software_executed",true,"process_runs",2, ...
    "input_unchanged",true,"reference_match",true,"return_code",0, ...
    "generated_paths",expectedMembers);
write_json(fullfile(workRoot,replace(name," ","-")+"-compare.json"),report);
end

function compare_reference(expectedRoot,candidateRoot)
expectedFiles=tree_relative(expectedRoot,expectedRoot);
actualFiles=tree_relative(candidateRoot,candidateRoot);
assert(isequal(expectedFiles,actualFiles),"Reference成员不一致");
for index=1:numel(expectedFiles)
    relative=expectedFiles(index);
    left=fullfile(expectedRoot,relative);right=fullfile(candidateRoot,relative);
    if endsWith(relative,".csv")
        assert_table_close(left,right,1e-8);
    elseif endsWith(relative,".json")
        assert_value_close(jsondecode(fileread(left)),jsondecode(fileread(right)),relative,1e-8);
    elseif endsWith(relative,"trajectory.svg")
        assert(contains(fileread(right),"<svg") && dir(right).bytes>500);
    else
        assert(strcmp(fileread(left),fileread(right)),"固定交付物不一致: "+relative);
    end
end
end

function copy_implementation(source,target)
copyfile(fullfile(source,"README.md"),fullfile(target,"README.md"));
mkdir(fullfile(target,"src"));
copyfile(fullfile(source,"src","*"),fullfile(target,"src"));
end

function names=tree_relative(base,root)
listing=dir(fullfile(root,"**","*"));listing=listing(~[listing.isdir]);
names=strings(numel(listing),1);
for index=1:numel(listing)
    absolute=string(fullfile(listing(index).folder,listing(index).name));
    names(index)=replace(extractAfter(absolute,string(base)+filesep),filesep,"/");
end
names=sort(names);
end

function snapshot=input_snapshot(root)
files=tree_relative(root,root);parts=strings(numel(files),1);
for index=1:numel(files)
    parts(index)=files(index)+newline+string(fileread(fullfile(root,files(index))));
end
snapshot=join(parts,newline+"---"+newline);
end

function assert_table_close(leftPath,rightPath,tolerance)
left=readtable(leftPath,TextType="string");right=readtable(rightPath,TextType="string");
assert(isequal(left.Properties.VariableNames,right.Properties.VariableNames) && height(left)==height(right));
sortKey="";
for candidate=["event_id","step"]
    if ismember(candidate,string(left.Properties.VariableNames)),sortKey=candidate;break;end
end
if strlength(sortKey)>0,left=sortrows(left,sortKey);right=sortrows(right,sortKey);end
for index=1:width(left)
    a=left{:,index};b=right{:,index};
    if isnumeric(a) && isnumeric(b)
        assert(isequal(isnan(a),isnan(b)));mask=~isnan(a);assert(all(abs(a(mask)-b(mask))<=tolerance));
    else
        assert(isequaln(string(a),string(b)));
    end
end
end

function assert_value_close(left,right,label,tolerance)
if isstruct(left)
    assert(isstruct(right) && isequal(size(left),size(right)),label+"结构不一致");
    fields=sort(string(fieldnames(left)));assert(isequal(fields,sort(string(fieldnames(right)))));
    for index=1:numel(fields),assert_value_close(left.(fields(index)),right.(fields(index)),label+"."+fields(index),tolerance);end
elseif isnumeric(left)
    assert(isnumeric(right) && isequal(size(left),size(right)));assert(all(abs(double(left)-double(right))<=tolerance,"all"));
elseif islogical(left)
    assert(islogical(right) && isequal(left,right));
else
    assert(isequaln(string(left),string(right)),label+"文本不一致");
end
end

function count=count_files(root)
if ~isfolder(root),count=0;return;end
listing=dir(fullfile(root,"**","*"));count=sum(~[listing.isdir]);
end

function write_json(path,value)
handle=fopen(path,"w");assert(handle>=0);cleanup=onCleanup(@() fclose(handle));
fwrite(handle,jsonencode(value,PrettyPrint=true),"char");fwrite(handle,newline,"char");clear cleanup
end
