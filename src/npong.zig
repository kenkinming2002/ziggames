const std = @import("std");
const c = @import("c.zig");

const BOARD_WIDTH = 30;
const BOARD_HEIGHT = 30;

const CELL_WIDTH = 30;
const CELL_HEIGHT = 30;

const WINDOW_WIDTH = BOARD_WIDTH * CELL_WIDTH;
const WINDOW_HEIGHT = BOARD_HEIGHT * CELL_HEIGHT;

const BALL_COUNT = 20;
const BALL_RADIUS = 8;
const BALL_SPEED = 100.0;
const BALL_REPULSION_COEFFICIENT = 200.0;
const BALL_REPULSION_DISTANCE_THRESHOLD = 5.0;

fn rand_range(random: std.rand.Random, comptime T: type, min: T, max: T) T {
    return min + random.float(T) * (max - min);
}

const Cell = struct { index: u8 };
const Ball = struct {
    position: c.Vector2,
    velocity: c.Vector2,

    color: c.Color,
    opposing_color: c.Color,
};

const Board = struct {
    cells: [BOARD_HEIGHT][BOARD_WIDTH]Cell,
    balls: [BALL_COUNT]Ball,

    fn init(random: std.rand.Random) Board {
        var board: Board = undefined;

        for (&board.balls, 0..) |*ball, i| {
            ball.position.x = rand_range(random, f32, BALL_RADIUS, WINDOW_WIDTH - BALL_RADIUS);
            ball.position.y = rand_range(random, f32, BALL_RADIUS, WINDOW_HEIGHT - BALL_RADIUS);

            const angle = rand_range(random, f32, 0, 2 * std.math.pi);
            ball.velocity.x = @cos(angle) * BALL_SPEED;
            ball.velocity.y = @sin(angle) * BALL_SPEED;

            const saturation = 1.0;
            const value = 1.0;

            const hue = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(BALL_COUNT)) * 360.0;
            ball.color = c.ColorFromHSV(hue, saturation, value);

            const opposing_hue = if (hue < 180.0) hue + 180.0 else hue - 180.0;
            ball.opposing_color = c.ColorFromHSV(opposing_hue, saturation, value);
        }

        for (&board.cells, 0..) |*row, y| {
            for (row, 0..) |*cell, x| {
                const cell_position = c.Vector2{
                    .x = (@as(f32, @floatFromInt(x)) + 0.5) * CELL_WIDTH,
                    .y = (@as(f32, @floatFromInt(y)) + 0.5) * CELL_HEIGHT,
                };

                var min_distance_sqr = std.math.inf(f32);
                var min_i: u8 = 0;
                for (&board.balls, 0..) |*ball, i| {
                    const distance_sqr = c.Vector2Distance(cell_position, ball.position);
                    if (min_distance_sqr > distance_sqr) {
                        min_distance_sqr = distance_sqr;
                        min_i = @intCast(i);
                    }
                }

                cell.index = min_i;
            }
        }

        return board;
    }

    fn update(self: *Board, dt: f32) void {
        for (0..BALL_COUNT) |i| {
            for (i + 1..BALL_COUNT) |j| {
                const ball1 = &self.balls[i];
                const ball2 = &self.balls[j];

                const displacement = c.Vector2Subtract(ball2.position, ball1.position);
                const distance = @max(c.Vector2Length(displacement), BALL_REPULSION_DISTANCE_THRESHOLD);
                const impulse = c.Vector2Scale(displacement, BALL_REPULSION_COEFFICIENT / (distance * distance * distance));

                std.debug.assert(std.math.isFinite(impulse.x));
                std.debug.assert(std.math.isFinite(impulse.y));

                ball1.velocity = c.Vector2Subtract(ball1.velocity, impulse);
                ball2.velocity = c.Vector2Add(ball2.velocity, impulse);
            }
        }

        for (&self.balls, 0..) |*ball, i| {
            ball.position = c.Vector2Add(ball.position, c.Vector2Scale(ball.velocity, dt));

            if (ball.position.x < BALL_RADIUS) {
                ball.position.x = BALL_RADIUS;
                ball.velocity.x = -ball.velocity.x;
            }

            if (ball.position.y < BALL_RADIUS) {
                ball.position.y = BALL_RADIUS;
                ball.velocity.y = -ball.velocity.y;
            }

            if (ball.position.x > WINDOW_WIDTH - BALL_RADIUS) {
                ball.position.x = WINDOW_WIDTH - BALL_RADIUS;
                ball.velocity.x = -ball.velocity.x;
            }

            if (ball.position.y > WINDOW_HEIGHT - BALL_RADIUS) {
                ball.position.y = WINDOW_HEIGHT - BALL_RADIUS;
                ball.velocity.y = -ball.velocity.y;
            }

            // In a perfect world, there is no floating point imprecision, and
            // we would never ever go out of bounds. Unfortunately, such a
            // perfect world does not exist.
            //
            // The lower bound SHOULD be fine since in the worst case scenario,
            // we would get ball.position.[x|y] = BALL_RADIUS, but the floating
            // point hardware should be able to realize that:
            //   BALL_RADIUS - BALL_RADIUS = 0.
            //
            // For the upper bound, in the worse case scenario, we would get
            // ball.position.[x|y] = [WINDOW_WIDTH|WINDOW_HEIGHT] -
            // BALL_RADIUS, but asking the stupid floating point hardware to
            // realize that:
            //   [WINDOW_WIDTH|WINDOW_HEIGHT] - BALL_RADIUS + BALL_RADIUS = [WINDOW_WIDTH|WINDOW_HEIGHT]
            // seems a bit too much. Depending on implementation, we may be able to guarantee that:
            //   [WINDOW_WIDTH|WINDOW_HEIGHT] - BALL_RADIUS + BALL_RADIUS <= [WINDOW_WIDTH|WINDOW_HEIGHT]
            // which would be sufficient but idk.

            const x1: usize = @intFromFloat(@floor((ball.position.x - BALL_RADIUS) / CELL_WIDTH));
            const y1: usize = @intFromFloat(@floor((ball.position.y - BALL_RADIUS) / CELL_WIDTH));

            const x2: usize = @max(@as(usize, @intFromFloat(@ceil((ball.position.x + BALL_RADIUS) / CELL_WIDTH))), BOARD_WIDTH);
            const y2: usize = @max(@as(usize, @intFromFloat(@ceil((ball.position.y + BALL_RADIUS) / CELL_WIDTH))), BOARD_HEIGHT);

            outer: for (y1..y2) |y| {
                for (x1..x2) |x| {
                    const cell = &self.cells[y][x];
                    if (cell.index != i) {
                        const top: f32 = @floatFromInt(CELL_HEIGHT * y);
                        const bottom: f32 = @floatFromInt(CELL_HEIGHT * (y + 1));

                        const left: f32 = @floatFromInt(CELL_WIDTH * x);
                        const right: f32 = @floatFromInt(CELL_WIDTH * (x + 1));

                        const contact = c.Vector2{
                            .x = @min(@max(ball.position.x, left), right),
                            .y = @min(@max(ball.position.y, top), bottom),
                        };

                        const offset = c.Vector2Subtract(contact, ball.position);
                        if (c.Vector2LengthSqr(offset) < BALL_RADIUS * BALL_RADIUS) {
                            if (@abs(offset.x) > @abs(offset.y)) {
                                ball.velocity.x = -ball.velocity.x;
                                if (offset.x > 0.0) {
                                    ball.position.x = left - BALL_RADIUS;
                                } else {
                                    ball.position.x = right + BALL_RADIUS;
                                }
                            } else {
                                ball.velocity.y = -ball.velocity.y;
                                if (offset.y > 0.0) {
                                    ball.position.y = top - BALL_RADIUS;
                                } else {
                                    ball.position.y = bottom + BALL_RADIUS;
                                }
                            }

                            cell.index = @intCast(i);
                            break :outer;
                        }
                    }
                }
            }
        }
    }

    fn render(self: Board) void {
        for (&self.cells, 0..) |*row, y| {
            for (row, 0..) |*cell, x| {
                const ball = self.balls[cell.index];
                const position = c.Vector2{
                    .x = @as(f32, @floatFromInt(x)) * CELL_WIDTH,
                    .y = @as(f32, @floatFromInt(y)) * CELL_HEIGHT,
                };
                const dimension = c.Vector2{
                    .x = @floatFromInt(CELL_WIDTH),
                    .y = @floatFromInt(CELL_HEIGHT),
                };
                c.DrawRectangleV(position, dimension, ball.opposing_color);
            }
        }

        for (0..BALL_COUNT) |i| {
            c.DrawCircleV(self.balls[i].position, BALL_RADIUS, self.balls[i].color);
        }
    }
};

pub fn main() !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();
    var board = Board.init(random);

    c.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "npong");
    while (!c.WindowShouldClose()) {
        const dt = c.GetFrameTime();
        board.update(dt);

        c.BeginDrawing();
        board.render();
        c.EndDrawing();
    }
}
