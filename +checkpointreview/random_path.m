function [waypoints, velocity] = random_path()
    global TARGET_SPEED DT WAYPOINT_SPACING

    if isempty(TARGET_SPEED)
        TARGET_SPEED = 15;
    end
    if isempty(DT), DT = 0.1; end
    if isempty(WAYPOINT_SPACING), WAYPOINT_SPACING = TARGET_SPEED * DT; end

    numSteps = 4000;
    dt = DT;
    x0 = 50;
    y0 = 0;
    z0 = 70;
    angle = pi/2;
    speed = TARGET_SPEED;
    angularSpeedMax = pi/32;
    minSegmentLen = 150;
    maxSegmentLen = 500;
    turnCenterDeg = 60;
    turnRangeDeg = 20;
    turnCenterRad = deg2rad(turnCenterDeg);
    turnRangeRad = deg2rad(turnRangeDeg);

    waypoints = zeros(numSteps, 3);
    velocity = zeros(numSteps, 3);
    waypoints(1,:) = [x0, y0, z0];
    velocity(1,:) = [speed*sin(angle), speed*cos(angle), 0];

    currentStep = 1;

    while currentStep < numSteps
        thisSegmentSteps = randi([minSegmentLen, maxSegmentLen]);

        for k = 1:thisSegmentSteps
            currentStep = currentStep + 1;
            if currentStep > numSteps
                break;
            end

            x0 = x0 + speed*sin(angle)*dt;
            y0 = y0 + speed*cos(angle)*dt;

            waypoints(currentStep, :) = [x0, y0, z0];
            velocity(currentStep, :) = [speed*sin(angle), speed*cos(angle), 0];
        end

        if currentStep >= numSteps
            break;
        end

        if rand() < 0.5
            turnSignBase = 1;
        else
            turnSignBase = -1;
        end

        turnOffset = (rand()*2 - 1) * turnRangeRad;
        targetAngle = angle + turnSignBase * (turnCenterRad + turnOffset);

        totalTurnAngle = abs(targetAngle - angle);
        angularSpeed = angularSpeedMax * (1 - 0.5 * (totalTurnAngle / pi));
        angularSpeed = max(angularSpeed, angularSpeedMax / 3);
        numTurnSteps = ceil(totalTurnAngle / (angularSpeedMax * dt));

        for t = 1:numTurnSteps
            currentStep = currentStep + 1;
            if currentStep > numSteps
                break;
            end

            turnDirection = sign(targetAngle - angle);
            angle = angle + turnDirection * angularSpeedMax * dt;

            x0 = x0 + speed*sin(angle)*dt;
            y0 = y0 + speed*cos(angle)*dt;

            waypoints(currentStep, :) = [x0, y0, z0];
            velocity(currentStep, :) = [speed*sin(angle), speed*cos(angle), 0];
        end

        for s = 1:size(waypoints, 1)
            if abs(waypoints(s, 1)) < 1e-3
                waypoints(s, 1) = 0;
            end
            if abs(waypoints(s, 2)) < 1e-3
                waypoints(s, 2) = 0;
            end
            if abs(velocity(s, 1)) < 1e-3
                velocity(s, 1) = 0;
            end
            if abs(velocity(s, 2)) < 1e-3
                velocity(s, 2) = 0;
            end
        end

        if currentStep < numSteps
            angle = targetAngle;
        end
    end

    x = waypoints(:,1);
    y = waypoints(:,2);
    z = waypoints(:,3);

    d = [0; cumsum(sqrt(diff(x).^2 + diff(y).^2 + diff(z).^2))];
    d_new = (0:WAYPOINT_SPACING:d(end))';

    x_new = interp1(d, x, d_new, 'linear');
    y_new = interp1(d, y, d_new, 'linear');
    z_new = interp1(d, z, d_new, 'linear');

    waypoints = [x_new, y_new, z_new];

    velocity = zeros(size(waypoints));
    for i = 1:size(waypoints, 1)-1
        delta = waypoints(i+1, :) - waypoints(i, :);
        dist = norm(delta);
        if dist > 1e-6
            velocity(i, :) = speed * delta / dist;
        else
            velocity(i, :) = [0, speed, 0];
        end
    end
    velocity(end, :) = velocity(end-1, :);

    fprintf('[Random Path] Generated: %d waypoints, spacing %.2f m, total length %.1f m\n', ...
            size(waypoints, 1), WAYPOINT_SPACING, sum(vecnorm(diff(waypoints), 2, 2)));
end
