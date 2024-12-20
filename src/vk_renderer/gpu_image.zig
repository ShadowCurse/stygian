const vk = @import("../bindings/vulkan.zig");

const Self = @This();

image: vk.VkImage,
view: vk.VkImageView,
extent: vk.VkExtent3D,
format: vk.VkFormat,
allocation: vk.VmaAllocation,

pub fn init(
    vma_allocator: vk.VmaAllocator,
    device: vk.VkDevice,
    width: u32,
    height: u32,
    format: vk.VkFormat,
    usage: u32,
) !Self {
    var image: Self = undefined;
    image.extent = vk.VkExtent3D{
        .width = width,
        .height = height,
        .depth = 1,
    };
    image.format = format;
    const image_create_info = vk.VkImageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = image.format,
        .extent = image.extent,
        .usage = usage,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
    };
    const alloc_info = vk.VmaAllocationCreateInfo{
        .usage = vk.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };
    try vk.check_result(vk.vmaCreateImage(
        vma_allocator,
        &image_create_info,
        &alloc_info,
        &image.image,
        &image.allocation,
        null,
    ));

    const aspect_mask: u32 = if (usage & vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT != 0)
        vk.VK_IMAGE_ASPECT_DEPTH_BIT
    else
        vk.VK_IMAGE_ASPECT_COLOR_BIT;
    const image_view_create_info = vk.VkImageViewCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .image = image.image,
        .format = image.format,
        .subresourceRange = .{
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .aspectMask = aspect_mask,
        },
    };
    try vk.check_result(vk.vkCreateImageView(
        device,
        &image_view_create_info,
        null,
        &image.view,
    ));
    return image;
}

pub fn deinit(self: *const Self, device: vk.VkDevice, vma_allocator: vk.VmaAllocator) void {
    vk.vkDestroyImageView(device, self.view, null);
    vk.vmaDestroyImage(vma_allocator, self.image, self.allocation);
}

pub fn transition_image(
    cmd: vk.VkCommandBuffer,
    image: vk.VkImage,
    source_layout: vk.VkImageLayout,
    target_layout: vk.VkImageLayout,
) void {
    const aspect_mask = if (target_layout == vk.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL)
        vk.VK_IMAGE_ASPECT_DEPTH_BIT
    else
        vk.VK_IMAGE_ASPECT_COLOR_BIT;
    const subresource = vk.VkImageSubresourceRange{
        .aspectMask = @intCast(aspect_mask),
        .baseMipLevel = 0,
        .levelCount = vk.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = vk.VK_REMAINING_ARRAY_LAYERS,
    };
    const barrier = vk.VkImageMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .srcAccessMask = vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
        .dstStageMask = vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .dstAccessMask = vk.VK_ACCESS_2_MEMORY_WRITE_BIT | vk.VK_ACCESS_2_MEMORY_READ_BIT,
        .oldLayout = source_layout,
        .newLayout = target_layout,
        .subresourceRange = subresource,
        .image = image,
    };

    const dependency = vk.VkDependencyInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .pImageMemoryBarriers = &barrier,
        .imageMemoryBarrierCount = 1,
    };

    vk.vkCmdPipelineBarrier2(cmd, &dependency);
}

pub fn copy_image_to_image(
    cmd: vk.VkCommandBuffer,
    src: vk.VkImage,
    src_size: vk.VkExtent2D,
    dst: vk.VkImage,
    dst_size: vk.VkExtent2D,
) void {
    const blit_region = vk.VkImageBlit2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
        .srcOffsets = .{
            .{}, .{
                .x = @intCast(src_size.width),
                .y = @intCast(src_size.height),
                .z = 1,
            },
        },
        .dstOffsets = .{
            .{}, .{
                .x = @intCast(dst_size.width),
                .y = @intCast(dst_size.height),
                .z = 1,
            },
        },
        .srcSubresource = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .mipLevel = 0,
        },
        .dstSubresource = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .mipLevel = 0,
        },
    };

    const blit_info = vk.VkBlitImageInfo2{
        .sType = vk.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
        .srcImage = src,
        .srcImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .dstImage = dst,
        .dstImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .filter = vk.VK_FILTER_LINEAR,
        .regionCount = 1,
        .pRegions = &blit_region,
    };
    vk.vkCmdBlitImage2(cmd, &blit_info);
}

pub fn copy_buffer_to_image(
    cmd: vk.VkCommandBuffer,
    buffer: vk.VkBuffer,
    image: vk.VkImage,
    extent: vk.VkExtent3D,
) void {
    transition_image(
        cmd,
        image,
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );

    const copy_region = vk.VkBufferImageCopy{
        .imageExtent = extent,
        .imageSubresource = .{
            .layerCount = 1,
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
        },
    };

    vk.vkCmdCopyBufferToImage(
        cmd,
        buffer,
        image,
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &copy_region,
    );

    transition_image(
        cmd,
        image,
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );
}
