const rgfw = @import("rgfw");

const color_buffer_bit: u32 = 0x0000_4000;

extern fn glClearColor(red: f32, green: f32, blue: f32, alpha: f32) callconv(.c) void;
extern fn glClear(mask: u32) callconv(.c) void;
extern fn glViewport(x: i32, y: i32, width: i32, height: i32) callconv(.c) void;

pub fn clear(window: *rgfw.Window, color: [4]f32) void {
    const size = window.sizeInPixels();
    glViewport(0, 0, size.width, size.height);
    glClearColor(color[0], color[1], color[2], color[3]);
    glClear(color_buffer_bit);
}
