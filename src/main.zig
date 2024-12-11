const std = @import("std");
const c = @import("c.zig");

const BORDER_WIDTH = 1.0;
const BORDER_DIMENSION = c.Vector2{ .x = BORDER_WIDTH, .y = BORDER_WIDTH };

const Box = struct {
    position: c.Vector2,
    dimension: c.Vector2,

    fn left(self: Box) f32 {
        return self.position.x;
    }

    fn right(self: Box) f32 {
        return self.position.x + self.dimension.x;
    }

    fn top(self: Box) f32 {
        return self.position.y;
    }

    fn bottom(self: Box) f32 {
        return self.position.y + self.dimension.y;
    }

    fn clamp(self: Box, point: c.Vector2) c.Vector2 {
        return .{
            .x = @min(@max(point.x, self.left()), self.right()),
            .y = @min(@max(point.y, self.top()), self.bottom()),
        };
    }

    fn draw_with_border(self: Box, color: c.Color, border_color: c.Color) void {
        c.DrawRectangleV(c.Vector2Subtract(self.position, BORDER_DIMENSION), c.Vector2Add(self.dimension, c.Vector2Scale(BORDER_DIMENSION, 2.0)), border_color);
        c.DrawRectangleV(self.position, self.dimension, color);
    }
};

const Paddle = struct {
    const DIMENSION = c.Vector2{ .x = 100.0, .y = 15.0 };
    const MARGIN = c.Vector2{ .x = 30.0, .y = 30.0 };
    const SPEED = 500.0;

    const COLOR = c.YELLOW;
    const BORDER_COLOR = c.ORANGE;

    window_size: c.Vector2,
    position: c.Vector2,

    fn init(window_size: c.Vector2) Paddle {
        return .{
            .window_size = window_size,
            .position = c.Vector2Multiply(window_size, c.Vector2{ .x = 0.5, .y = 0.95 }),
        };
    }

    fn bounding_box(self: Paddle) Box {
        return .{
            .position = c.Vector2Subtract(self.position, c.Vector2Scale(DIMENSION, 0.5)),
            .dimension = DIMENSION,
        };
    }

    fn render(self: Paddle) void {
        self.bounding_box().draw_with_border(COLOR, BORDER_COLOR);
    }

    fn update(self: *Paddle, dt: f32) void {
        if (c.IsKeyDown(c.KEY_A) or c.IsKeyDown(c.KEY_LEFT)) self.position.x -= dt * SPEED;
        if (c.IsKeyDown(c.KEY_D) or c.IsKeyDown(c.KEY_RIGHT)) self.position.x += dt * SPEED;

        self.position.x = @max(self.position.x, DIMENSION.x * 0.5 - MARGIN.x);
        self.position.x = @min(self.position.x, self.window_size.x - DIMENSION.x * 0.5 + MARGIN.x);
    }

    fn update_collision(self: *Paddle, ball: *Ball) void {
        _ = ball.collide(self.bounding_box());
    }
};

const Bricks = struct {
    const DIMENSION = c.Vector2{ .x = 40.0, .y = 15.0 };
    const MARGIN = c.Vector2{ .x = 10.0, .y = 10.0 };
    const COUNT_X = 10;
    const COUNT_Y = 25;

    const BORDER_COLOR = c.RED;
    const COLOR = c.ORANGE;

    window_size: c.Vector2,
    states: [COUNT_Y][COUNT_X]bool,

    fn init(window_size: c.Vector2) Bricks {
        var states: [COUNT_Y][COUNT_X]bool = undefined;
        for (0..COUNT_Y) |y| {
            for (0..COUNT_X) |x| {
                states[y][x] = true;
            }
        }

        return .{
            .window_size = window_size,
            .states = states,
        };
    }

    fn bounding_box(self: Bricks, x: usize, y: usize) Box {
        const total_width = DIMENSION.x * COUNT_X + MARGIN.x * (COUNT_X + 1);
        const anchor = c.Vector2{ .x = (self.window_size.x - total_width) * 0.5 + MARGIN.x, .y = MARGIN.y };
        const offset = c.Vector2Multiply(c.Vector2Add(MARGIN, DIMENSION), c.Vector2{ .x = @floatFromInt(x), .y = @floatFromInt(y) });
        return .{
            .position = c.Vector2Add(anchor, offset),
            .dimension = DIMENSION,
        };
    }

    fn render(self: Bricks) void {
        for (0..COUNT_Y) |y| {
            for (0..COUNT_X) |x| {
                if (self.states[y][x]) {
                    self.bounding_box(x, y).draw_with_border(COLOR, BORDER_COLOR);
                }
            }
        }
    }

    fn update_collision(self: *Bricks, ball: *Ball) void {
        for (0..COUNT_Y) |y| {
            for (0..COUNT_X) |x| {
                if (self.states[y][x]) {
                    if (ball.collide(self.bounding_box(x, y))) {
                        self.states[y][x] = false;
                    }
                }
            }
        }
    }
};

const Ball = struct {
    const RADIUS: f32 = 10.0;
    const SPEED: f32 = 200.0;

    const BORDER_COLOR = c.GREEN;
    const COLOR = c.DARKGREEN;

    window_size: c.Vector2,
    position: c.Vector2,
    velocity: c.Vector2,

    fn init(window_size: c.Vector2, random: std.rand.Random) Ball {
        const angle = std.math.pi * (random.float(f32) - 0.5);
        return .{
            .window_size = window_size,
            .position = c.Vector2Multiply(window_size, c.Vector2{ .x = 0.5, .y = 0.9 }),
            .velocity = c.Vector2Scale(c.Vector2{ .x = @cos(angle), .y = @sin(angle) }, SPEED),
        };
    }

    fn render(self: Ball) void {
        c.DrawCircleV(self.position, RADIUS + BORDER_WIDTH, BORDER_COLOR);
        c.DrawCircleV(self.position, RADIUS, COLOR);
    }

    fn update(self: *Ball, dt: f32) bool {
        self.position = c.Vector2Add(self.position, c.Vector2Scale(self.velocity, dt));

        if (self.position.x < RADIUS) {
            self.position.x = RADIUS;
            self.velocity.x = -self.velocity.x;
        }

        if (self.position.y < RADIUS) {
            self.position.y = RADIUS;
            self.velocity.y = -self.velocity.y;
        }

        if (self.position.x > self.window_size.x - RADIUS) {
            self.position.x = self.window_size.x - RADIUS;
            self.velocity.x = -self.velocity.x;
        }

        return self.position.y <= self.window_size.y - RADIUS;
    }

    fn collide(self: *Ball, bounding_box: Box) bool {
        const contact = bounding_box.clamp(self.position);
        const offset = c.Vector2Subtract(contact, self.position);
        if (c.Vector2LengthSqr(offset) > RADIUS * RADIUS)
            return false;

        if (@abs(offset.x) > @abs(offset.y)) {
            self.velocity.x = -self.velocity.x;
            if (offset.x > 0.0) {
                self.position.x = bounding_box.left() - RADIUS;
            } else {
                self.position.x = bounding_box.right() + RADIUS;
            }
        } else {
            self.velocity.y = -self.velocity.y;
            if (offset.y > 0.0) {
                self.position.y = bounding_box.top() - RADIUS;
            } else {
                self.position.y = bounding_box.bottom() + RADIUS;
            }
        }

        return true;
    }
};

const GameState = enum {
    Initial,
    Playing,
    GameOver,
};

fn draw_text_centered(window_size: c.Vector2, text: [*c]const u8) void {
    const fontSize = 30;
    const spacing = 10;
    const font = c.GetFontDefault();

    const dimension = c.MeasureTextEx(font, text, fontSize, spacing);
    const position = c.Vector2Scale(c.Vector2Subtract(window_size, dimension), 0.5);
    c.DrawTextEx(font, text, position, fontSize, spacing, c.WHITE);
}

fn draw_text_centered2(window_size: c.Vector2, text1: [*c]const u8, text2: [*c]const u8) void {
    const fontSize = 30;
    const spacing = 10;
    const font = c.GetFontDefault();

    const dimension1 = c.MeasureTextEx(font, text1, fontSize, spacing);
    const dimension2 = c.MeasureTextEx(font, text2, fontSize, spacing);

    var position1 = c.Vector2Scale(c.Vector2Subtract(window_size, dimension1), 0.5);
    var position2 = c.Vector2Scale(c.Vector2Subtract(window_size, dimension2), 0.5);

    position1.y -= dimension2.y * 0.5;
    position2.y += dimension1.y * 0.5;

    c.DrawTextEx(font, text1, position1, fontSize, spacing, c.WHITE);
    c.DrawTextEx(font, text2, position2, fontSize, spacing, c.WHITE);
}

const Game = struct {
    window_size: c.Vector2,
    random: std.rand.Random,

    state: GameState,

    paddle: Paddle,
    bricks: Bricks,
    ball: Ball,

    fn init(window_size: c.Vector2, random: std.rand.Random) Game {
        var game: Game = undefined;
        game.window_size = window_size;
        game.random = random;
        game.state = .Initial;
        game.reset();
        return game;
    }

    fn reset(self: *Game) void {
        self.paddle = Paddle.init(self.window_size);
        self.bricks = Bricks.init(self.window_size);
        self.ball = Ball.init(self.window_size, self.random);
    }

    fn update(self: *Game) void {
        switch (self.state) {
            .Initial, .GameOver => if (c.IsKeyPressed(c.KEY_SPACE)) {
                self.state = .Playing;
            },
            .Playing => {
                const dt = c.GetFrameTime();

                self.paddle.update(dt);
                if (!self.ball.update(dt)) {
                    self.state = .GameOver;
                    self.reset();
                    return;
                }

                self.paddle.update_collision(&self.ball);
                self.bricks.update_collision(&self.ball);
            },
        }
    }

    fn render(self: Game) void {
        c.BeginDrawing();
        {
            c.ClearBackground(c.BLACK);

            self.paddle.render();
            self.bricks.render();
            self.ball.render();

            switch (self.state) {
                .Initial => draw_text_centered(self.window_size, "Press Space to Start"),
                .GameOver => draw_text_centered2(self.window_size, "Game Over", "Press Space to Restart"),
                else => {},
            }
        }
        c.EndDrawing();
    }
};

pub fn main() !void {
    const window_width = 600;
    const window_height = 800;
    const window_size = c.Vector2{ .x = @floatFromInt(window_width), .y = @floatFromInt(window_height) };
    const window_title = "Breakout";
    c.InitWindow(window_width, window_height, window_title);

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    var game = Game.init(window_size, random);
    while (!c.WindowShouldClose()) {
        game.update();
        game.render();
    }
}
