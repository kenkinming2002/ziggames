const std = @import("std");
const c = @import("c.zig");
const text = @import("text.zig");

const BOARD_WIDTH = 30;
const BOARD_HEIGHT = 30;

const CELL_WIDTH = 30;
const CELL_HEIGHT = 30;

const WINDOW_WIDTH = BOARD_WIDTH * CELL_WIDTH;
const WINDOW_HEIGHT = BOARD_HEIGHT * CELL_HEIGHT;

const SNAKE_INITIAL_X = BOARD_WIDTH / 2;
const SNAKE_INITIAL_Y = BOARD_WIDTH / 2;

const SNAKE_COOLDOWN = 0.1;

const Cell = enum {
    Empty,
    Fruit,
    Snake,
};

const Board = struct {
    cells: [BOARD_HEIGHT][BOARD_WIDTH]Cell,

    fn reset(board: *Board) void {
        for (&board.cells) |*row| {
            for (row) |*cell| {
                cell.* = .Empty;
            }
        }
    }
};

const Direction = enum {
    Left,
    Right,
    Up,
    Down,
};

const Segment = struct {
    x: u8,
    y: u8,
};

const Segments = std.fifo.LinearFifo(Segment, .{ .Static = BOARD_WIDTH * BOARD_HEIGHT });

const Snake = struct {
    direction: Direction,
    cooldown: f32,
    segments: Segments,
};

const GameState = enum {
    Initial,
    Playing,
    GameOver,
};

const Game = struct {
    random: std.rand.Random,

    state: GameState,

    board: Board,
    snake: Snake,

    fn init(self: *Game, random: std.rand.Random) void {
        self.random = random;
        self.state = .Initial;
        self.reset();
    }

    fn reset(self: *Game) void {
        self.board.reset();
        self.spawn_snake();
        self.spawn_fruit();
    }

    fn spawn_snake(self: *Game) void {
        self.snake.direction = .Down;
        self.snake.cooldown = 0.0;
        self.snake.segments = Segments.init();
        self.snake.segments.writeItem(.{ .x = SNAKE_INITIAL_X, .y = SNAKE_INITIAL_Y }) catch unreachable;
        self.board.cells[SNAKE_INITIAL_Y][SNAKE_INITIAL_X] = .Snake;
    }

    fn spawn_fruit(self: *Game) void {
        while (true) {
            const x = self.random.uintLessThan(u8, BOARD_WIDTH);
            const y = self.random.uintLessThan(u8, BOARD_HEIGHT);
            const cell = &self.board.cells[@intCast(y)][@intCast(x)];
            if (cell.* == .Empty) {
                cell.* = .Fruit;
                return;
            }
        }
    }

    fn step_snake(self: *Game) bool {
        var head = self.snake.segments.peekItem(self.snake.segments.count - 1);
        switch (self.snake.direction) {
            .Left => if (head.x != 0) {
                head.x -= 1;
            } else {
                head.x = BOARD_WIDTH - 1;
            },
            .Right => if (head.x != BOARD_WIDTH - 1) {
                head.x += 1;
            } else {
                head.x = 0;
            },
            .Up => if (head.y != 0) {
                head.y -= 1;
            } else {
                head.y = BOARD_HEIGHT - 1;
            },
            .Down => if (head.y != BOARD_HEIGHT - 1) {
                head.y += 1;
            } else {
                head.y = 0;
            },
        }

        const head_cell = &self.board.cells[@intCast(head.y)][@intCast(head.x)];
        if (head_cell.* == .Snake) {
            return false;
        }

        const eaten_fruit = head_cell.* == .Fruit;
        self.snake.segments.writeItem(head) catch unreachable;
        head_cell.* = .Snake;

        if (eaten_fruit) {
            self.spawn_fruit();
        } else {
            const tail = self.snake.segments.readItem() orelse unreachable;
            self.board.cells[@intCast(tail.y)][@intCast(tail.x)] = .Empty;
        }

        return true;
    }

    fn update(self: *Game) void {
        switch (self.state) {
            .Initial, .GameOver => if (c.IsKeyPressed(c.KEY_SPACE)) {
                self.state = .Playing;
            },
            .Playing => {
                self.snake.cooldown += c.GetFrameTime();

                if (c.IsKeyPressed(c.KEY_LEFT)) self.snake.direction = .Left;
                if (c.IsKeyPressed(c.KEY_RIGHT)) self.snake.direction = .Right;
                if (c.IsKeyPressed(c.KEY_UP)) self.snake.direction = .Up;
                if (c.IsKeyPressed(c.KEY_DOWN)) self.snake.direction = .Down;

                while (self.snake.cooldown >= SNAKE_COOLDOWN) {
                    self.snake.cooldown -= SNAKE_COOLDOWN;
                    if (!self.step_snake()) {
                        self.state = .GameOver;
                        self.reset();
                        return;
                    }
                }
            },
        }
    }

    fn render(self: *Game) void {
        c.BeginDrawing();
        c.ClearBackground(c.BLACK);

        for (self.board.cells, 0..) |row, j| {
            for (row, 0..) |cell, i| {
                const x: c_int = @intCast(i * CELL_WIDTH);
                const y: c_int = @intCast(j * CELL_HEIGHT);
                const w: c_int = @intCast(CELL_WIDTH);
                const h: c_int = @intCast(CELL_HEIGHT);
                switch (cell) {
                    .Snake => c.DrawRectangle(x, y, w, h, c.GREEN),
                    .Fruit => c.DrawRectangle(x, y, w, h, c.RED),
                    .Empty => {},
                }
            }
        }

        var window_size: c.Vector2 = undefined;
        window_size.x = WINDOW_WIDTH;
        window_size.y = WINDOW_HEIGHT;

        var score_buffer: [256]u8 = undefined;
        const score_text = std.fmt.bufPrintZ(&score_buffer, "Score: {d}", .{self.snake.segments.readableLength() - 1}) catch unreachable;
        c.DrawText(score_text, 0, 0, 30, c.WHITE);

        switch (self.state) {
            .Initial => text.centered(window_size, "Press Space to Start"),
            .GameOver => text.centered2(window_size, "Game Over", "Press Space to Restart"),
            else => {},
        }

        c.EndDrawing();
    }
};

pub fn main() !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    var game: Game = undefined;
    game.init(random);

    c.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "snake");
    defer c.CloseWindow();

    while (!c.WindowShouldClose()) {
        game.update();
        game.render();
    }
}
