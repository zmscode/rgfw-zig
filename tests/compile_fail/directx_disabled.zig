const rgfw = @import("rgfw");

test "DirectX configuration explains how to enable it" {
    rgfw.DirectX.requireEnabled();
}
