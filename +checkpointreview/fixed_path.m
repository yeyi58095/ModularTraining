function [waypoints, velocity] = fixed_path()
    global TARGET_SPEED DT WAYPOINT_SPACING

    if isempty(TARGET_SPEED)
        TARGET_SPEED = 15;
    end
    if isempty(DT), DT = 0.1; end
    if isempty(WAYPOINT_SPACING), WAYPOINT_SPACING = TARGET_SPEED * DT; end

    speed = TARGET_SPEED;
    cruise_altitude = 70;
    waypoint_spacing = WAYPOINT_SPACING;
    turn_radius = 120;

    key_points = [
        50, 0;
        500, 0;
        500, -500;
        -1000, -500;
        -1000, 0;
        -50, 0;
        -50, 500;
        -1000, 500;
    ];

    segment_speeds = [
        speed;
        speed;
        speed;
        speed;
        speed;
        speed;
        speed];

    num_points = size(key_points, 1);
    num_segments = num_points - 1;

    all_waypoints = [];
    all_speeds = [];

    for seg = 1:num_segments
        p1 = key_points(seg, :);
        p2 = key_points(seg+1, :);

        seg_vec = p2 - p1;
        seg_len = norm(seg_vec);
        seg_dir = seg_vec / seg_len;

        if seg > 1
            prev_vec = key_points(seg, :) - key_points(seg-1, :);
            prev_dir = prev_vec / norm(prev_vec);

            dot_product = max(-1, min(1, dot(prev_dir, seg_dir)));
            turn_angle_rad = acos(dot_product);

            if turn_angle_rad > deg2rad(1)
                cross_z = prev_dir(1)*seg_dir(2) - prev_dir(2)*seg_dir(1);
                turn_direction = sign(cross_z);

                tangent_dist = turn_radius * tan(turn_angle_rad/2);
                prev_seg_len = norm(key_points(seg,:) - key_points(seg-1,:));
                max_tangent = min(seg_len, prev_seg_len) / 2;

                effective_radius = turn_radius;
                if tangent_dist > max_tangent * 0.99
                    tangent_dist = max_tangent * 0.99;
                    effective_radius = tangent_dist / tan(turn_angle_rad/2);
                end

                if ~isempty(all_waypoints)
                    cut_length = tangent_dist;
                    distances_from_end = vecnorm(all_waypoints(end:-1:1, 1:2) - p1, 2, 2);
                    cut_idx = find(cumsum(diff([0; distances_from_end])) >= cut_length, 1);
                    if ~isempty(cut_idx) && cut_idx < size(all_waypoints, 1)
                        all_waypoints(end-cut_idx+1:end, :) = [];
                        all_speeds(end-cut_idx+1:end) = [];
                    end
                end

                arc_start = p1 - prev_dir * tangent_dist;
                arc_end = p1 + seg_dir * tangent_dist;

                perp_prev = [-prev_dir(2), prev_dir(1)] * turn_direction;
                circle_center = arc_start + perp_prev * effective_radius;

                start_angle = atan2(arc_start(2) - circle_center(2), arc_start(1) - circle_center(1));
                end_angle = atan2(arc_end(2) - circle_center(2), arc_end(1) - circle_center(1));

                if turn_direction > 0
                    if end_angle < start_angle, end_angle = end_angle + 2*pi; end
                else
                    if end_angle > start_angle, end_angle = end_angle - 2*pi; end
                end

                arc_length = abs(end_angle - start_angle) * effective_radius;
                num_arc_points = max(3, round(arc_length / waypoint_spacing));
                arc_angles = linspace(start_angle, end_angle, num_arc_points);

                arc_x = circle_center(1) + effective_radius * cos(arc_angles);
                arc_y = circle_center(2) + effective_radius * sin(arc_angles);
                arc_z = cruise_altitude * ones(size(arc_x));

                all_waypoints = [all_waypoints; arc_x(:), arc_y(:), arc_z(:)];
                all_speeds = [all_speeds; segment_speeds(seg) * ones(num_arc_points, 1)];

                p1 = [arc_x(end), arc_y(end)];
                seg_len = norm(p2 - p1);
            end
        end

        if seg_len > waypoint_spacing
            num_straight_points = round(seg_len / waypoint_spacing);
            straight_x = linspace(p1(1), p2(1), num_straight_points)';
            straight_y = linspace(p1(2), p2(2), num_straight_points)';
            straight_z = cruise_altitude * ones(num_straight_points, 1);

            start_idx = 1;
            if ~isempty(all_waypoints), start_idx = 2; end

            new_pts = [straight_x(start_idx:end), straight_y(start_idx:end), straight_z(start_idx:end)];
            all_waypoints = [all_waypoints; new_pts];
            all_speeds = [all_speeds; segment_speeds(seg) * ones(size(new_pts,1), 1)];
        end
    end

    num_waypoints = size(all_waypoints, 1);
    velocity = zeros(num_waypoints, 3);

    for i = 1:num_waypoints
        if i < num_waypoints
            dir_vec = all_waypoints(i+1, :) - all_waypoints(i, :);
            d_norm = norm(dir_vec);
            if d_norm > 1e-6, dir_vec = dir_vec / d_norm; end
        else
            dir_vec = velocity(i-1, :) / max(norm(velocity(i-1, :)), 1e-6);
        end
        velocity(i, :) = all_speeds(i) * dir_vec;
    end

    waypoints = all_waypoints;

    fprintf('[Fixed Path] Generated: %d waypoints, spacing %.2f m, total length %.1f m\n', ...
            size(waypoints, 1), waypoint_spacing, sum(vecnorm(diff(waypoints), 2, 2)));
end
