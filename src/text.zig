const c = @import("c.zig");

pub fn centered(window_size: c.Vector2, text: [*c]const u8) void {
    const fontSize = 30;
    const spacing = 10;
    const font = c.GetFontDefault();

    const dimension = c.MeasureTextEx(font, text, fontSize, spacing);
    const position = c.Vector2Scale(c.Vector2Subtract(window_size, dimension), 0.5);
    c.DrawTextEx(font, text, position, fontSize, spacing, c.WHITE);
}

pub fn centered2(window_size: c.Vector2, text1: [*c]const u8, text2: [*c]const u8) void {
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
