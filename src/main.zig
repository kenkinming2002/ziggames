const std = @import("std");
const c = @import("c.zig");

pub fn main() !void {
    c.InitWindow(800, 600, "Hello Raylib");
    while (!c.WindowShouldClose()) {
        c.BeginDrawing();
        c.ClearBackground(c.BLACK);
        c.DrawText("Hello Raylib", 200, 200, 20, c.WHITE);
        c.EndDrawing();
    }
}
