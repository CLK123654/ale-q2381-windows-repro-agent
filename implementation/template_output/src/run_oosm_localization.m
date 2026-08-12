function run_oosm_localization(inputRoot,outputRoot)
if ~isfolder(outputRoot),mkdir(outputRoot);end
finalResultRoot=fullfile(outputRoot,"results");
finalFigureRoot=fullfile(outputRoot,"figures");
if isfolder(finalResultRoot),rmdir(finalResultRoot,"s");end
if isfolder(finalFigureRoot),rmdir(finalFigureRoot,"s");end
requiredInputs=["README.txt","controls.csv","field_dictionary.md", ...
    "localization_contract.json","measurements.csv", ...
    fullfile("starter","run_localization_starter.m"),"uwb_beacons.csv"];
for inputIndex=1:numel(requiredInputs)
    assert(isfile(fullfile(inputRoot,requiredInputs(inputIndex))), ...
        "OOSM:MissingInput","缺少输入文件: %s",requiredInputs(inputIndex));
end
stageRoot=fullfile(outputRoot,".oosm_staging");
if isfolder(stageRoot),rmdir(stageRoot,"s");end
mkdir(stageRoot);
stageCleanup=onCleanup(@() cleanup_staging(stageRoot));
contract=jsondecode(fileread(fullfile(inputRoot,"localization_contract.json")));
controls=readtable(fullfile(inputRoot,"controls.csv"));
events=readtable(fullfile(inputRoot,"measurements.csv"),TextType="string");
events=sortrows(events,["arrival_step","event_id"]);
beacons=readtable(fullfile(inputRoot,"uwb_beacons.csv"),TextType="string");
eventCount=height(events); finalStep=contract.final_step;
state=nan(3,finalStep+1); covariance=nan(3,3,finalStep+1);
state(:,1)=contract.initial_state(:);
covariance(:,:,1)=diag(contract.initial_covariance_diag);
accepted=events([],:);
accepted.acceptance_seq=zeros(0,1);
seen=containers.Map("KeyType","char","ValueType","logical");
decisionRows=cell(eventCount,13); innovationRows=cell(0,10); replayRows=cell(0,7);
decisionIndex=0; acceptanceSeq=0;
for currentStep=1:finalStep
    control=controls(controls.step==currentStep,:);
    [state(:,currentStep+1),covariance(:,:,currentStep+1)]= ...
        propagate_midpoint(state(:,currentStep),covariance(:,:,currentStep), ...
        control.speed_mps,control.yaw_rate_rps,contract);
    due=find(events.arrival_step==currentStep);
    for dueIndex=reshape(due,1,[])
        event=events(dueIndex,:);
        decisionIndex=decisionIndex+1;
        delay=event.arrival_step-event.sample_step;
        [route,reason,seen]=adjudicate_event(event,seen,contract.fixed_lag_steps);
        d2=""; gate=""; replayStart=""; stateDelta="";
        if route=="GATE"
            replayStart=max(0,event.sample_step-1);
            candidate=event;
            candidate.acceptance_seq=acceptanceSeq+1;
            before=state(:,currentStep+1);
            [trialState,trialCovariance,evidence]=replay_window( ...
                state,covariance,controls,accepted,candidate,replayStart, ...
                currentStep,contract,beacons);
            d2=evidence.d2; gate=evidence.gate;
            innovation=evidence.innovation(:);
            innovation2="";
            if numel(innovation)==2, innovation2=innovation(2); end
            gateResult="FAIL";
            if evidence.pass, gateResult="PASS"; end
            innovationRows(end+1,:)={char(event.event_id),char(event.measurement_id), ...
                char(event.sensor),event.sample_step,event.arrival_step, ...
                innovation(1),innovation2,d2,gate, ...
                char(gateResult)}; %#ok<AGROW>
            if evidence.pass
                acceptanceSeq=acceptanceSeq+1;
                candidate.acceptance_seq=acceptanceSeq;
                accepted=[accepted;candidate]; %#ok<AGROW>
                state=trialState; covariance=trialCovariance;
                decision="ACCEPT";
                if delay==0, reason="ON_TIME_GATE_PASS";
                else, reason="OOSM_REPLAY_GATE_PASS"; end
                stateDelta=norm(state(:,currentStep+1)-before);
            else
                decision="REJECT"; reason="MAHALANOBIS_GATE"; stateDelta=0;
            end
            segmentCount=sum(accepted.sample_step>replayStart & ...
                accepted.sample_step<=currentStep);
            replayRows(end+1,:)={char(event.event_id),replayStart,currentStep, ...
                currentStep-replayStart,segmentCount,char(decision),stateDelta}; %#ok<AGROW>
        else
            decision="REJECT";
        end
        decisionRows(decisionIndex,:)={char(event.event_id), ...
            char(event.measurement_id),char(event.sensor),event.sample_step, ...
            event.arrival_step,delay,char(decision),char(reason),d2,gate, ...
            replayStart,currentStep,stateDelta};
    end
end
resultRoot=fullfile(stageRoot,"results");
figureRoot=fullfile(stageRoot,"figures");
mkdir(resultRoot);mkdir(figureRoot);
steps=(0:finalStep)';
acceptedThrough=arrayfun(@(step)sum(accepted.sample_step<=step),steps);
stateTrace=table(steps,controls.time_s,state(1,:)',state(2,:)', ...
    rad2deg(state(3,:)'),sqrt(squeeze(covariance(1,1,:))), ...
    sqrt(squeeze(covariance(2,2,:))), ...
    rad2deg(sqrt(squeeze(covariance(3,3,:)))),acceptedThrough, ...
    VariableNames=["step","time_s","x_m","y_m","heading_deg","sigma_x_m", ...
    "sigma_y_m","sigma_heading_deg","accepted_measurements_through_step"]);
writetable(stateTrace,fullfile(resultRoot,"state_trace.csv"));
writecell([{"event_id","measurement_id","sensor","sample_step","arrival_step", ...
    "delay_steps","decision","reason","d2","gate","replay_start_step", ...
    "horizon_step","current_state_delta_norm"};decisionRows], ...
    fullfile(resultRoot,"event_decisions.csv"));
writecell([{"event_id","measurement_id","sensor","sample_step","arrival_step", ...
    "innovation_1","innovation_2","d2","gate","gate_result"};innovationRows], ...
    fullfile(resultRoot,"innovation_log.csv"));
writecell([{"event_id","replay_start_step","horizon_step", ...
    "propagations_recomputed","accepted_measurements_in_segment", ...
    "candidate_decision","terminal_state_delta_norm"};replayRows], ...
    fullfile(resultRoot,"replay_ledger.csv"));
controlsOut=struct("control_rows",height(controls),"event_rows",height(events), ...
    "accepted_events",height(accepted), ...
    "accepted_delayed_events",sum(accepted.arrival_step>accepted.sample_step), ...
    "gated_candidates",size(innovationRows,1),"replay_attempts",size(replayRows,1), ...
    "final_step",finalStep,"final_x_m",state(1,end),"final_y_m",state(2,end), ...
    "final_heading_deg",rad2deg(state(3,end)), ...
    "final_sigma_x_m",sqrt(covariance(1,1,end)), ...
    "final_sigma_y_m",sqrt(covariance(2,2,end)), ...
    "final_sigma_heading_deg",rad2deg(sqrt(covariance(3,3,end))));
passMask=strcmp(innovationRows(:,10),"PASS");
failMask=strcmp(innovationRows(:,10),"FAIL");
passD2=cell2mat(innovationRows(passMask,8));
failD2=cell2mat(innovationRows(failMask,8));
controlsOut.max_accepted_d2=max(passD2);
controlsOut.min_rejected_gate_d2=min(failD2);
decisionCounts=struct();
for rowIndex=1:size(decisionRows,1)
    countKey=decisionRows{rowIndex,8};
    if ~isfield(decisionCounts,countKey), decisionCounts.(countKey)=0; end
    decisionCounts.(countKey)=decisionCounts.(countKey)+1;
end
gatedIds=string(innovationRows(:,1));
gatedEvents=events(ismember(events.event_id,gatedIds),:);
decisionIds=string(decisionRows(:,1));
decisionReasons=string(decisionRows(:,8));
gateResults=string(innovationRows(:,10));
gateFailIds=sort(gatedIds(gateResults=="FAIL"));
invariants=struct( ...
    "controls_cover_steps_0_to_65",height(controls)==66, ...
    "event_rows_complete",height(events)==21, ...
    "every_event_decided_once",decisionIndex==21 && numel(unique(decisionIds))==21, ...
    "duplicate_rejected_before_gating", ...
        decisionReasons(decisionIds=="EV06")=="DUPLICATE" && ~ismember("EV06",gatedIds), ...
    "stale_rejected_before_gating", ...
        decisionReasons(decisionIds=="EV10")=="STALE" && ~ismember("EV10",gatedIds), ...
    "future_rejected_before_gating", ...
        decisionReasons(decisionIds=="EV20")=="FUTURE_SAMPLE" && ~ismember("EV20",gatedIds), ...
    "both_outliers_gate_rejected",isequal(gateFailIds,["EV11";"EV15"]), ...
    "delayed_measurements_replayed",sum(accepted.arrival_step>accepted.sample_step)==9, ...
    "gate_uses_replayed_sample_state",strcmp(contract.gate_state_basis, ...
        "replayed posterior at sample_step before applying candidate measurement"), ...
    "replay_horizon_never_exceeds_lag",all( ...
        gatedEvents.arrival_step-gatedEvents.sample_step<=contract.fixed_lag_steps), ...
    "covariance_symmetric",max(abs(covariance-permute(covariance,[2,1,3])),[],"all")<1e-10, ...
    "covariance_positive_definite",all(arrayfun(@(k)all(eig(covariance(:,:,k))>0),1:finalStep+1)), ...
    "heading_always_wrapped",all(abs(state(3,:))<=pi), ...
    "all_normal_gates_pass",height(accepted)==16 && sum(passMask)==16, ...
    "rejected_gates_exceed_threshold",all( ...
        failD2>cell2mat(innovationRows(failMask,9))), ...
    "state_trace_row_count",height(stateTrace)==66);
validationResult="FAIL";
if all(structfun(@(value)islogical(value)&&isscalar(value)&&value,invariants))
    validationResult="PASS";
end
validation=struct("result",validationResult,"controls",controlsOut, ...
    "decision_counts",decisionCounts,"invariants",invariants);
fid=fopen(fullfile(resultRoot,"terminal_validation.json"),"w");
fprintf(fid,"%s\n",jsonencode(validation,PrettyPrint=true));fclose(fid);
assert(validationResult=="PASS","OOSM:ValidationFailed", ...
    "终态校验未通过，拒绝发布结果");
write_trajectory_svg(stateTrace,fullfile(figureRoot,"trajectory.svg"));
movefile(resultRoot,finalResultRoot,"f");
movefile(figureRoot,finalFigureRoot,"f");
clear stageCleanup
cleanup_staging(stageRoot)
end

function cleanup_staging(stageRoot)
if isfolder(stageRoot),rmdir(stageRoot,"s");end
end

function write_trajectory_svg(stateTrace,svgPath)
x=stateTrace.x_m;y=stateTrace.y_m;
width=900;height=520;padding=55;
xSpan=max(x)-min(x);ySpan=max(y)-min(y);
if xSpan==0,xSpan=1;end
if ySpan==0,ySpan=1;end
scale=min((width-2*padding)/xSpan,(height-2*padding)/ySpan);
px=padding+(x-min(x))*scale;
py=height-padding-(y-min(y))*scale;
points=join(compose("%.3f,%.3f",px,py)," ");
handle=fopen(svgPath,"w");assert(handle>=0,"OOSM:SvgOpenFailed","无法创建轨迹图");
cleanup=onCleanup(@() fclose(handle));
fprintf(handle,'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n',width,height,width,height);
fprintf(handle,'<rect width="100%%" height="100%%" fill="white"/>\n');
fprintf(handle,'<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#CBD5E1"/>\n',padding,height-padding,width-padding,height-padding);
fprintf(handle,'<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#CBD5E1"/>\n',padding,padding,padding,height-padding);
fprintf(handle,'<polyline fill="none" stroke="#2563EB" stroke-width="3" points="%s"/>\n',points);
fprintf(handle,'<circle cx="%.3f" cy="%.3f" r="5" fill="#16A34A"/>\n',px(1),py(1));
fprintf(handle,'<circle cx="%.3f" cy="%.3f" r="5" fill="#DC2626"/>\n',px(end),py(end));
fprintf(handle,'<text x="%d" y="28" font-family="Arial" font-size="18" fill="#0F172A">Replayed localization trajectory</text>\n',padding);
fprintf(handle,'<text x="%d" y="%d" font-family="Arial" font-size="13" fill="#475569">x m</text>\n',width-padding-24,height-18);
fprintf(handle,'<text x="12" y="%d" font-family="Arial" font-size="13" fill="#475569">y m</text>\n',padding);
fprintf(handle,'</svg>\n');
clear cleanup
end
