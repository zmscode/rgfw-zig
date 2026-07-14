const rgfw = @import("rgfw");

test "WebGPU configuration explains how to enable it" {
    rgfw.WebGPU.requireEnabled();
}
