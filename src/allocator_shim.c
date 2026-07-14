#include <stddef.h>
#include <stdlib.h>

typedef void* (*rgfw_zig_allocate_fn)(void* context, size_t size, size_t alignment);
typedef void (*rgfw_zig_free_fn)(
    void* context,
    void* pointer,
    size_t size,
    size_t alignment
);

typedef union rgfw_zig_allocation_header {
    struct {
        void* allocation;
        size_t size;
        size_t alignment;
        size_t reserved;
    } values;
    long double long_double_alignment;
    void* pointer_alignment;
} rgfw_zig_allocation_header;

static void* rgfw_zig_allocator_context;
static rgfw_zig_allocate_fn rgfw_zig_allocate_callback;
static rgfw_zig_free_fn rgfw_zig_free_callback;

void rgfw_zig_set_allocator(
    void* context,
    rgfw_zig_allocate_fn allocate_callback,
    rgfw_zig_free_fn free_callback
) {
    rgfw_zig_allocator_context = context;
    rgfw_zig_allocate_callback = allocate_callback;
    rgfw_zig_free_callback = free_callback;
}

void* rgfw_zig_alloc(size_t size) {
    rgfw_zig_allocation_header* header;
    void* allocation;
    size_t total;
    const size_t alignment = 16;

    if (size > (size_t)-1 - sizeof(rgfw_zig_allocation_header)) return NULL;
    total = sizeof(rgfw_zig_allocation_header) + size;
    allocation = rgfw_zig_allocate_callback
        ? rgfw_zig_allocate_callback(rgfw_zig_allocator_context, total, alignment)
        : malloc(total);
    if (allocation == NULL) return NULL;

    header = (rgfw_zig_allocation_header*)allocation;
    header->values.allocation = allocation;
    header->values.size = total;
    header->values.alignment = alignment;
    return header + 1;
}

void rgfw_zig_free(void* pointer) {
    rgfw_zig_allocation_header* header;
    if (pointer == NULL) return;
    header = ((rgfw_zig_allocation_header*)pointer) - 1;
    if (rgfw_zig_free_callback) {
        rgfw_zig_free_callback(
            rgfw_zig_allocator_context,
            header->values.allocation,
            header->values.size,
            header->values.alignment
        );
    } else {
        free(header->values.allocation);
    }
}
