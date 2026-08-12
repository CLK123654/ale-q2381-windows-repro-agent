function [state,covariance,evidence] = replay_window(state,covariance,controls,accepted,candidate,startStep,horizon,contract,beacons)
scheduled=[accepted;candidate];
scheduled=sortrows(scheduled,["sample_step","acceptance_seq"]);
evidence=struct();
for step=(startStep+1):horizon
    row=controls(controls.step==step,:);
    [x,P]=propagate_midpoint(state(:,step),covariance(:,:,step),row.speed_mps,row.yaw_rate_rps,contract);
    due=scheduled(scheduled.sample_step==step,:);
    for index=1:height(due)
        event=due(index,:);
        [~,~,d2,innovation]=joseph_measurement_update(x,P,event,beacons,false);
        gate=contract.gps_gate_d2;
        if strcmp(event.sensor,"UWB"), gate=contract.uwb_gate_d2; end
        pass=d2<=gate;
        if strcmp(event.event_id,candidate.event_id)
            evidence=struct("d2",d2,"gate",gate,"pass",pass,"innovation",innovation);
        end
        if ~strcmp(event.event_id,candidate.event_id) || pass
            [x,P]=joseph_measurement_update(x,P,event,beacons,true);
        end
    end
    state(:,step+1)=x;
    covariance(:,:,step+1)=P;
end
end
