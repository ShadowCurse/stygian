const vk = @import("../vulkan.zig");

pub const AllocatedBuffer = struct {
    buffer: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    allocation_info: vk.VmaAllocationInfo,

    pub fn init(
        vma_allocator: vk.VmaAllocator,
        size: u64,
        usage: vk.VkBufferUsageFlags,
        memory_usage: vk.VmaMemoryUsage,
    ) !AllocatedBuffer {
        const buffer_info = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = usage,
        };
        const alloc_info = vk.VmaAllocationCreateInfo{
            .usage = memory_usage,
            .flags = vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };
        var new_buffer: AllocatedBuffer = undefined;
        try vk.check_result(vk.vmaCreateBuffer(
            vma_allocator,
            &buffer_info,
            &alloc_info,
            &new_buffer.buffer,
            &new_buffer.allocation,
            &new_buffer.allocation_info,
        ));
        return new_buffer;
    }

    pub fn deinit(self: *const AllocatedBuffer, vma_allocator: vk.VmaAllocator) void {
        vk.vmaDestroyBuffer(vma_allocator, self.buffer, self.allocation);
    }

    pub fn get_device_address(buffer: *const AllocatedBuffer, device: vk.VkDevice) vk.VkDeviceAddress {
        const device_address_info = vk.VkBufferDeviceAddressInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
            .buffer = buffer.buffer,
        };
        return vk.vkGetBufferDeviceAddress(device, &device_address_info);
    }
};
