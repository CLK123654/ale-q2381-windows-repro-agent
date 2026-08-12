function [route,reason,seen] = adjudicate_event(event,seen,fixedLagSteps)
key=char(event.measurement_id);
if isKey(seen,key)
    route="REJECT"; reason="DUPLICATE"; return
end
seen(key)=true;
if event.sample_step>event.arrival_step
    route="REJECT"; reason="FUTURE_SAMPLE"; return
end
if event.arrival_step-event.sample_step>fixedLagSteps
    route="REJECT"; reason="STALE"; return
end
route="GATE"; reason="";
end
