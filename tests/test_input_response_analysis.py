import csv
import io

from testing.input_response import measure, passed


def test_render_response_uses_adjacent_predictions_and_accepts_archived_logs(tmp_path):
    source = io.StringIO()
    fields = (
        "time,tick,capture,raw_x,raw_y,sent_x,sent_y,preview_x,preview_y,"
        "x,y,before_vx,before_vy,after_vx,after_vy"
    ).split(",")
    writer = csv.DictWriter(source, fieldnames=fields)
    writer.writeheader()
    velocity, position = 0.0, 300.0
    for frame in range(820):
        direction = -(frame // 11 % 2)
        velocity = velocity * 0.88 + direction * 30
        position += velocity / 60
        writer.writerow(
            dict(
                time=frame / 60,
                tick=80 + frame / 2,
                capture=frame,
                raw_x=direction,
                raw_y=0,
                sent_x=direction,
                sent_y=0,
                preview_x=direction,
                preview_y=0,
                x=position,
                y=220,
                # A restored authority velocity is not the previous frame's
                # prediction. This deliberately masks every step-entry change.
                before_vx=velocity,
                before_vy=0,
                after_vx=velocity,
                after_vy=0,
            )
        )
    csv_path, log_path = tmp_path / "response.csv", tmp_path / "log.txt"
    csv_path.write_text(source.getvalue())
    log_path.write_text(
        "[INFO] unrelated\n"
        + "\n".join(
            "[INFO] Lua Debug: LAN_NETWORK INPUT_RESPONSE_CSV " + line
            for line in source.getvalue().splitlines()
        )
        + "\n[INFO] done\n"
    )
    result = measure(csv_path)
    assert measure(log_path) == result
    assert result["acceleration_transitions"] == 74
    assert result["acceleration_transitions_responding_same_frame"] == 74
    assert passed(result)
