const std = @import("std");
const c = @import("c.zig");

const BORDER_WIDTH = 1.0;
const BORDER_DIMENSION = c.Vector2{ .x = BORDER_WIDTH, .y = BORDER_WIDTH };

const BRICK_MAX_LEVEL = 10;
const BRICK_DESTROY_RATIO = 0.15;
const BRICK_TARGET_DIMENSION = c.Vector2{ .x = 20.0, .y = 20.0 };

const PADDLE_DIMENSION = c.Vector2{ .x = 100.0, .y = 15.0 };
const PADDLE_MARGIN = c.Vector2{ .x = 30.0, .y = 30.0 };
const PADDLE_SPEED = 500.0;

const PADDLE_COLOR = c.YELLOW;
const PADDLE_BORDER_COLOR = c.ORANGE;

const BALL_RADIUS: f32 = 10.0;

const BALL_SPEED: f32 = 200.0;
const BALL_SPEED_UP: f32 = 1.006;
const BALL_SPEED_DOWN: f32 = 1.0 / BALL_SPEED_UP;

const BALL_MAX_ENERGY = 25;

const BALL_BORDER_COLOR = c.GREEN;
const BALL_COLOR = c.DARKGREEN;

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

    fn grid(self: Box, width: usize, height: usize, x: usize, y: usize) Box {
        const step_x = self.dimension.x / @as(f32, @floatFromInt(width));
        const step_y = self.dimension.y / @as(f32, @floatFromInt(height));
        return .{
            .position = .{
                .x = self.position.x + step_x * @as(f32, @floatFromInt(x)),
                .y = self.position.y + step_y * @as(f32, @floatFromInt(y)),
            },
            .dimension = .{
                .x = step_x,
                .y = step_y,
            },
        };
    }

    fn to_rectangle(self: Box) c.Rectangle {
        return c.Rectangle{
            .x = self.position.x,
            .y = self.position.y,
            .width = self.dimension.x,
            .height = self.dimension.y,
        };
    }

    fn draw_with_border(self: Box, color: c.Color, border_color: c.Color) void {
        c.DrawRectangleV(c.Vector2Subtract(self.position, BORDER_DIMENSION), c.Vector2Add(self.dimension, c.Vector2Scale(BORDER_DIMENSION, 2.0)), border_color);
        c.DrawRectangleV(self.position, self.dimension, color);
    }
};

fn get_texture_dimension(texture: c.Texture) c.Vector2 {
    return .{
        .x = @floatFromInt(texture.width),
        .y = @floatFromInt(texture.height),
    };
}

fn get_texture_box(texture: c.Texture) Box {
    return .{
        .position = c.Vector2Zero(),
        .dimension = get_texture_dimension(texture),
    };
}

fn get_image_dimension(image: c.Image) c.Vector2 {
    return .{
        .x = @floatFromInt(image.width),
        .y = @floatFromInt(image.height),
    };
}

const Paddle = struct {
    window_size: c.Vector2,
    position: c.Vector2,

    fn init(window_size: c.Vector2) Paddle {
        var paddle = Paddle{ .window_size = window_size, .position = undefined };
        paddle.reset();
        return paddle;
    }

    fn reset(self: *Paddle) void {
        self.position = c.Vector2Multiply(self.window_size, c.Vector2{ .x = 0.5, .y = 0.95 });
    }

    fn bounding_box(self: Paddle) Box {
        return .{
            .position = c.Vector2Subtract(self.position, c.Vector2Scale(PADDLE_DIMENSION, 0.5)),
            .dimension = PADDLE_DIMENSION,
        };
    }

    fn render(self: Paddle) void {
        self.bounding_box().draw_with_border(PADDLE_COLOR, PADDLE_BORDER_COLOR);
    }

    fn update(self: *Paddle, dt: f32) void {
        if (c.IsKeyDown(c.KEY_A) or c.IsKeyDown(c.KEY_LEFT)) self.position.x -= dt * PADDLE_SPEED;
        if (c.IsKeyDown(c.KEY_D) or c.IsKeyDown(c.KEY_RIGHT)) self.position.x += dt * PADDLE_SPEED;

        self.position.x = @max(self.position.x, PADDLE_DIMENSION.x * 0.5 - PADDLE_MARGIN.x);
        self.position.x = @min(self.position.x, self.window_size.x - PADDLE_DIMENSION.x * 0.5 + PADDLE_MARGIN.x);
    }

    fn update_collision(self: *Paddle, ball: *Ball) void {
        var health: u8 = std.math.maxInt(u8);
        ball.collide(self.bounding_box(), 0, &health);
    }
};

const Bricks = struct {
    allocator: std.mem.Allocator,

    area: Box,

    textures: [BRICK_MAX_LEVEL]c.Texture,

    count_x: usize,
    count_y: usize,
    dimension: c.Vector2,

    healths: []u8,
    counts: [BRICK_MAX_LEVEL]usize,

    fn init(allocator: std.mem.Allocator, area: Box, image: c.Image) !Bricks {
        var textures: [BRICK_MAX_LEVEL]c.Texture = undefined;
        var texture_count: usize = 0;
        errdefer for (0..texture_count) |i| c.UnloadTexture(textures[i]);

        const texture = c.LoadTextureFromImage(image);
        if (!c.IsTextureValid(texture)) return error.LoadTextureFromImage;

        textures[texture_count] = texture;
        texture_count += 1;

        for (1..BRICK_MAX_LEVEL) |i| {
            var blurred_image = c.ImageCopy(image);
            defer c.UnloadImage(blurred_image);
            c.ImageBlurGaussian(&blurred_image, @intCast(i * 10));

            const blurred_texture = c.LoadTextureFromImage(blurred_image);
            if (!c.IsTextureValid(blurred_texture)) return error.LoadTextureFromImage;

            textures[texture_count] = blurred_texture;
            texture_count += 1;
        }

        const count_x_f = @floor(area.dimension.x / BRICK_TARGET_DIMENSION.x);
        const count_y_f = @floor(area.dimension.y / BRICK_TARGET_DIMENSION.y);

        const count_x: usize = @intFromFloat(count_x_f);
        const count_y: usize = @intFromFloat(count_y_f);

        const dimension = c.Vector2{ .x = area.dimension.x / count_x_f, .y = area.dimension.y / count_y_f };

        const healths = try allocator.alloc(u8, count_x * count_y);
        errdefer allocator.free(healths);

        var bricks = Bricks{
            .allocator = allocator,
            .area = area,
            .textures = textures,
            .count_x = count_x,
            .count_y = count_y,
            .dimension = dimension,
            .healths = healths,
            .counts = undefined,
        };
        bricks.reset();
        return bricks;
    }

    fn deinit(self: *Bricks) void {
        for (self.textures) |texture| c.UnloadTexture(texture);
        self.allocator.free(self.healths);
    }

    fn reset(self: *Bricks) void {
        @memset(self.healths, BRICK_MAX_LEVEL - 1);
        @memset(&self.counts, 0);
        self.counts[BRICK_MAX_LEVEL - 1] = self.count_x * self.count_y;
    }

    fn render(self: Bricks) void {
        for (0..self.count_y) |y| {
            for (0..self.count_x) |x| {
                const texture = self.textures[self.healths[y * self.count_x + x]];
                const src = get_texture_box(texture).grid(self.count_x, self.count_y, x, y).to_rectangle();
                const dst = self.area.grid(self.count_x, self.count_y, x, y).to_rectangle();
                c.DrawTexturePro(texture, src, dst, c.Vector2Zero(), 0.0, c.WHITE);
            }
        }
    }

    fn update_collision(self: *Bricks, ball: *Ball) void {
        var min_health: u8 = BRICK_MAX_LEVEL - 1;

        const threshold: usize = @intFromFloat(@floor(@as(f32, @floatFromInt(self.count_x * self.count_y)) * BRICK_DESTROY_RATIO));
        var count: usize = 0;
        while (min_health > 0 and count < threshold) {
            count += self.counts[min_health];
            min_health -= 1;
        }

        // FIXME: Can we go out of bounds due to floating point inaccuracy.

        const x1: usize = @intFromFloat(@floor((ball.position.x - BALL_RADIUS) / self.dimension.x));
        const y1: usize = @intFromFloat(@floor((ball.position.y - BALL_RADIUS) / self.dimension.y));

        const x2: usize = @intFromFloat(@ceil((ball.position.x + BALL_RADIUS) / self.dimension.x));
        const y2: usize = @intFromFloat(@ceil((ball.position.y + BALL_RADIUS) / self.dimension.y));

        var y = y1;
        while (y < y2) : (y += 1) {
            var x = x1;
            while (x < x2) : (x += 1) {
                const state = &self.healths[y * self.count_x + x];
                if (state.* > 0) {
                    self.counts[state.*] -= 1;

                    const bounding_box = self.area.grid(self.count_x, self.count_y, x, y);
                    ball.collide(bounding_box, min_health, state);

                    self.counts[state.*] += 1;
                }
            }
        }
    }
};

const Ball = struct {
    random: std.rand.Random,

    window_size: c.Vector2,

    position: c.Vector2,
    velocity: c.Vector2,
    energy: u8,

    fn init(window_size: c.Vector2, random: std.rand.Random) Ball {
        var ball = Ball{
            .random = random,
            .window_size = window_size,
            .position = undefined,
            .velocity = undefined,
            .energy = undefined,
        };
        ball.reset();
        return ball;
    }

    fn reset(self: *Ball) void {
        const angle = -std.math.pi * self.random.float(f32);
        self.position = c.Vector2Multiply(self.window_size, c.Vector2{ .x = 0.5, .y = 0.9 });
        self.velocity = c.Vector2Scale(c.Vector2{ .x = @cos(angle), .y = @sin(angle) }, BALL_SPEED);
        self.energy = BALL_MAX_ENERGY;
    }

    fn render(self: Ball) void {
        c.DrawCircleV(self.position, BALL_RADIUS + BORDER_WIDTH, BALL_BORDER_COLOR);
        c.DrawCircleV(self.position, BALL_RADIUS, BALL_COLOR);
    }

    fn update(self: *Ball, dt: f32) bool {
        self.position = c.Vector2Add(self.position, c.Vector2Scale(self.velocity, dt));

        if (self.position.x < BALL_RADIUS) {
            self.position.x = BALL_RADIUS;
            self.velocity.x = -self.velocity.x;
            self.energy = BALL_MAX_ENERGY;
        }

        if (self.position.y < BALL_RADIUS) {
            self.position.y = BALL_RADIUS;
            self.velocity.y = -self.velocity.y;
            self.energy = BALL_MAX_ENERGY;
        }

        if (self.position.x > self.window_size.x - BALL_RADIUS) {
            self.position.x = self.window_size.x - BALL_RADIUS;
            self.velocity.x = -self.velocity.x;
            self.energy = BALL_MAX_ENERGY;
        }

        return self.position.y <= self.window_size.y - BALL_RADIUS;
    }

    fn collide(self: *Ball, bounding_box: Box, min_health: u8, health: *u8) void {
        const contact = bounding_box.clamp(self.position);
        const offset = c.Vector2Subtract(contact, self.position);
        if (c.Vector2LengthSqr(offset) > BALL_RADIUS * BALL_RADIUS)
            return;

        if (self.energy > health.* - min_health) {
            self.energy -= health.* - min_health;
            health.* = min_health;
            return;
        }

        health.* -= self.energy;
        self.energy = BALL_MAX_ENERGY;

        if (@abs(offset.x) > @abs(offset.y)) {
            self.velocity.x = -self.velocity.x;
            self.velocity.x *= BALL_SPEED_DOWN;
            self.velocity.y *= BALL_SPEED_UP;

            if (offset.x > 0.0) {
                self.position.x = bounding_box.left() - BALL_RADIUS;
            } else {
                self.position.x = bounding_box.right() + BALL_RADIUS;
            }
        } else {
            self.velocity.y = -self.velocity.y;
            self.velocity.y *= BALL_SPEED_DOWN;
            self.velocity.x *= BALL_SPEED_UP;

            if (offset.y > 0.0) {
                self.position.y = bounding_box.top() - BALL_RADIUS;
            } else {
                self.position.y = bounding_box.bottom() + BALL_RADIUS;
            }
        }
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
    allocator: std.mem.Allocator,
    random: std.rand.Random,

    window_size: c.Vector2,

    state: GameState,

    paddle: Paddle,
    bricks: Bricks,
    ball: Ball,

    cheatmode: bool,

    fn init(allocator: std.mem.Allocator, random: std.rand.Random, image_path: []const u8, image_scale: f32) !Game {
        const image = c.LoadImage(image_path.ptr);
        if (!c.IsImageValid(image)) return error.Image;
        defer c.UnloadImage(image);

        const image_dimension = get_image_dimension(image);

        const bricks_dimension = c.Vector2Scale(image_dimension, image_scale);
        const bricks_area = Box{ .position = c.Vector2Zero(), .dimension = bricks_dimension };

        const window_size = c.Vector2{ .x = bricks_dimension.x, .y = bricks_dimension.y + 100.0 };
        const window_title = image_path.ptr;
        c.InitWindow(@intFromFloat(window_size.x), @intFromFloat(window_size.y), window_title);
        errdefer c.CloseWindow();

        const paddle = Paddle.init(window_size);
        const bricks = try Bricks.init(allocator, bricks_area, image);
        const ball = Ball.init(window_size, random);

        return Game{
            .allocator = allocator,
            .random = random,
            .window_size = window_size,
            .state = .Initial,
            .paddle = paddle,
            .bricks = bricks,
            .ball = ball,
            .cheatmode = false,
        };
    }

    fn deinit(self: *Game) void {
        self.bricks.deinit();
        c.CloseWindow();
    }

    fn reset(self: *Game) !void {
        self.state = .GameOver;
        self.paddle.reset();
        self.bricks.reset();
        self.ball.reset();
    }

    fn update(self: *Game) !void {
        switch (self.state) {
            .Initial, .GameOver => if (c.IsKeyPressed(c.KEY_SPACE)) {
                self.state = .Playing;
            },
            .Playing => {
                const dt = c.GetFrameTime();

                self.paddle.update(dt);
                if (!self.ball.update(dt)) {
                    try self.reset();
                    return;
                }

                if (c.IsKeyPressed(c.KEY_C)) self.cheatmode = !self.cheatmode;
                if (self.cheatmode) self.paddle.position.x = self.ball.position.x;

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

    fn run(self: *Game) !void {
        while (!c.WindowShouldClose()) {
            try self.update();
            self.render();
        }
    }
};

fn usage(program_name: []const u8) void {
    std.debug.print("Usage: {s} [--scale BACKGROUND_SCALE] <BACKGROUND_PATH>\n", .{program_name});
    std.process.exit(1);
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const program_name = args.next() orelse return usage("ziggames");

    var background_path_arg: ?[]const u8 = null;
    var background_scale_arg: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--scale")) {
            if (background_scale_arg != null) {
                std.debug.print("Error: --scale can not be used more than once\n", .{});
                usage(program_name);
            }

            background_scale_arg = args.next();
            if (background_scale_arg == null) {
                std.debug.print("Error: expected argument after --scale\n", .{});
                usage(program_name);
            }
        } else {
            if (background_path_arg != null) {
                std.debug.print("Error: too many arguments\n", .{});
                usage(program_name);
            }

            background_path_arg = arg;
        }
    }

    var background_scale_opt: ?f32 = null;
    if (background_scale_arg) |arg| {
        background_scale_opt = std.fmt.parseFloat(f32, arg) catch {
            std.debug.print("Error: expected floating point after --scale\n", .{});
            return usage(program_name);
        };
    }

    const background_path = background_path_arg orelse {
        std.debug.print("Error: BACKGROUND_PATH must be provided\n", .{});
        return usage(program_name);
    };
    const background_scale = background_scale_opt orelse 1.0;

    var game = try Game.init(allocator, random, background_path, background_scale);
    defer game.deinit();
    try game.run();
}
