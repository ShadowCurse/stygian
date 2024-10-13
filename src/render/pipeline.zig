const std = @import("std");
const vk = @import("../vulkan.zig");

const Allocator = std.mem.Allocator;

pub fn load_shader_module(arena: Allocator, device: vk.VkDevice, path: []const u8) !vk.VkShaderModule {
    const file = try std.fs.cwd().openFile(path, .{});
    const content = try file.reader().readAllAlloc(arena, std.math.maxInt(usize));

    const create_info = vk.VkShaderModuleCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pCode = @alignCast(@ptrCast(content.ptr)),
        .codeSize = content.len,
    };

    var module: vk.VkShaderModule = undefined;
    try vk.check_result(vk.vkCreateShaderModule(device, &create_info, null, &module));
    return module;
}

pub const Pipeline = struct {
    pipeline: vk.VkPipeline,
    pipeline_layout: vk.VkPipelineLayout,
    descriptor_set: vk.VkDescriptorSet,
    descriptor_set_layout: vk.VkDescriptorSetLayout,

    pub fn init(
        arena: Allocator,
        device: vk.VkDevice,
        descriptor_pool: vk.VkDescriptorPool,
        bindings: []const vk.VkDescriptorSetLayoutBinding,
        push_constants: []const vk.VkPushConstantRange,
        vertex_shader_path: [:0]const u8,
        fragment_shader_path: [:0]const u8,
        image_format: vk.VkFormat,
        depth_format: vk.VkFormat,
    ) !Pipeline {

        // create descriptor set layout
        var descriptor_set_layout: vk.VkDescriptorSetLayout = undefined;
        const layout_create_info = vk.VkDescriptorSetLayoutCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pBindings = bindings.ptr,
            .bindingCount = @intCast(bindings.len),
        };
        try vk.check_result(vk.vkCreateDescriptorSetLayout(
            device,
            &layout_create_info,
            null,
            &descriptor_set_layout,
        ));

        // create descriptor set
        const set_alloc_info = vk.VkDescriptorSetAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = descriptor_pool,
            .pSetLayouts = &descriptor_set_layout,
            .descriptorSetCount = 1,
        };
        var descriptor_set: vk.VkDescriptorSet = undefined;
        try vk.check_result(vk.vkAllocateDescriptorSets(
            device,
            &set_alloc_info,
            &descriptor_set,
        ));

        const vertex_shader_module = try load_shader_module(arena, device, vertex_shader_path);
        defer vk.vkDestroyShaderModule(device, vertex_shader_module, null);
        const fragment_shader_module = try load_shader_module(arena, device, fragment_shader_path);
        defer vk.vkDestroyShaderModule(device, fragment_shader_module, null);

        const layouts = [_]vk.VkDescriptorSetLayout{
            descriptor_set_layout,
        };
        const pipeline_layout_create_info = vk.VkPipelineLayoutCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pSetLayouts = &layouts,
            .setLayoutCount = layouts.len,
            .pPushConstantRanges = push_constants.ptr,
            .pushConstantRangeCount = @intCast(push_constants.len),
        };
        var pipeline_layout: vk.VkPipelineLayout = undefined;
        try vk.check_result(vk.vkCreatePipelineLayout(
            device,
            &pipeline_layout_create_info,
            null,
            &pipeline_layout,
        ));

        var builder: PipelineBuilder = .{};
        const pipeline = try builder
            .layout(pipeline_layout)
            .shaders(vertex_shader_module, fragment_shader_module)
            .input_topology(vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST)
            .polygon_mode(vk.VK_POLYGON_MODE_FILL)
            .cull_mode(vk.VK_CULL_MODE_NONE, vk.VK_FRONT_FACE_CLOCKWISE)
            .multisampling_none()
            .blending_none()
            .color_attachment_format(image_format)
            .depthtest(true, vk.VK_COMPARE_OP_GREATER_OR_EQUAL)
            .depth_format(depth_format)
            .build(device);

        return .{
            .pipeline = pipeline,
            .pipeline_layout = pipeline_layout,
            .descriptor_set = descriptor_set,
            .descriptor_set_layout = descriptor_set_layout,
        };
    }

    pub fn deinit(self: *const Pipeline, device: vk.VkDevice) void {
        vk.vkDestroyDescriptorSetLayout(device, self.descriptor_set_layout, null);
        vk.vkDestroyPipelineLayout(device, self.pipeline_layout, null);
        vk.vkDestroyPipeline(device, self.pipeline, null);
    }
};

pub const PipelineBuilder = struct {
    stages: [2]vk.VkPipelineShaderStageCreateInfo = .{
        .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        },
        .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        },
    },
    input_assembly: vk.VkPipelineInputAssemblyStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    },
    rasterization: vk.VkPipelineRasterizationStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    },
    multisampling: vk.VkPipelineMultisampleStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    },
    depth_stencil: vk.VkPipelineDepthStencilStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    },
    rendering: vk.VkPipelineRenderingCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
    },
    color_blend_attachment: vk.VkPipelineColorBlendAttachmentState = .{
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT |
            vk.VK_COLOR_COMPONENT_G_BIT |
            vk.VK_COLOR_COMPONENT_B_BIT |
            vk.VK_COLOR_COMPONENT_A_BIT,
    },
    _layout: vk.VkPipelineLayout = undefined,
    _color_attachment_format: vk.VkFormat = undefined,

    const Self = @This();

    pub fn layout(self: *Self, l: vk.VkPipelineLayout) *Self {
        self._layout = l;
        return self;
    }

    pub fn shaders(self: *Self, vertex_shader: vk.VkShaderModule, fragment_shader: vk.VkShaderModule) *Self {
        self.stages[0].stage = vk.VK_SHADER_STAGE_VERTEX_BIT;
        self.stages[0].module = vertex_shader;
        self.stages[0].pName = "main";

        self.stages[1].stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT;
        self.stages[1].module = fragment_shader;
        self.stages[1].pName = "main";

        return self;
    }

    pub fn input_topology(self: *Self, topology: vk.VkPrimitiveTopology) *Self {
        self.input_assembly.topology = topology;
        self.input_assembly.primitiveRestartEnable = vk.VK_FALSE;
        return self;
    }

    pub fn polygon_mode(self: *Self, mode: vk.VkPolygonMode) *Self {
        self.rasterization.polygonMode = mode;
        self.rasterization.lineWidth = 1.0;
        return self;
    }

    pub fn cull_mode(self: *Self, mode: vk.VkCullModeFlags, front_face: vk.VkFrontFace) *Self {
        self.rasterization.cullMode = mode;
        self.rasterization.frontFace = front_face;
        return self;
    }

    pub fn multisampling_none(self: *Self) *Self {
        self.multisampling.sampleShadingEnable = vk.VK_FALSE;
        self.multisampling.rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT;
        self.multisampling.minSampleShading = 1.0;
        self.multisampling.alphaToOneEnable = vk.VK_FALSE;
        self.multisampling.alphaToCoverageEnable = vk.VK_FALSE;
        return self;
    }

    pub fn blending_none(self: *Self) *Self {
        self.color_blend_attachment.blendEnable = vk.VK_FALSE;
        return self;
    }

    pub fn blending_additive(self: *Self) *Self {
        self.color_blend_attachment.colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT |
            vk.VK_COLOR_COMPONENT_G_BIT |
            vk.VK_COLOR_COMPONENT_B_BIT |
            vk.VK_COLOR_COMPONENT_A_BIT;
        self.color_blend_attachment.blendEnable = vk.VK_TRUE;
        self.color_blend_attachment.srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA;
        self.color_blend_attachment.dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE;
        self.color_blend_attachment.colorBlendOp = vk.VK_BLEND_OP_ADD;
        self.color_blend_attachment.srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE;
        self.color_blend_attachment.dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO;
        self.color_blend_attachment.colorBlendOp = vk.VK_BLEND_OP_ADD;
        return self;
    }

    pub fn blending_alphablend(self: *Self) *Self {
        self.color_blend_attachment.colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT |
            vk.VK_COLOR_COMPONENT_G_BIT |
            vk.VK_COLOR_COMPONENT_B_BIT |
            vk.VK_COLOR_COMPONENT_A_BIT;
        self.color_blend_attachment.blendEnable = vk.VK_TRUE;
        self.color_blend_attachment.srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA;
        self.color_blend_attachment.dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        self.color_blend_attachment.colorBlendOp = vk.VK_BLEND_OP_ADD;
        self.color_blend_attachment.srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE;
        self.color_blend_attachment.dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO;
        self.color_blend_attachment.colorBlendOp = vk.VK_BLEND_OP_ADD;
        return self;
    }

    pub fn color_attachment_format(self: *Self, format: vk.VkFormat) *Self {
        self._color_attachment_format = format;
        return self;
    }

    pub fn depth_format(self: *Self, format: vk.VkFormat) *Self {
        self.rendering.depthAttachmentFormat = format;
        return self;
    }

    pub fn depthtest_none(self: *Self) *Self {
        self.depth_stencil.depthTestEnable = vk.VK_FALSE;
        self.depth_stencil.depthWriteEnable = vk.VK_FALSE;
        self.depth_stencil.depthCompareOp = vk.VK_COMPARE_OP_NEVER;
        self.depth_stencil.depthBoundsTestEnable = vk.VK_FALSE;
        self.depth_stencil.stencilTestEnable = vk.VK_FALSE;
        self.depth_stencil.front = .{};
        self.depth_stencil.back = .{};
        self.depth_stencil.minDepthBounds = 0.0;
        self.depth_stencil.maxDepthBounds = 1.0;
        return self;
    }

    pub fn depthtest(self: *Self, depth_write_enable: bool, depth_compare_op: vk.VkCompareOp) *Self {
        self.depth_stencil.depthTestEnable = vk.VK_TRUE;
        self.depth_stencil.depthWriteEnable = @intFromBool(depth_write_enable);
        self.depth_stencil.depthCompareOp = depth_compare_op;
        self.depth_stencil.depthBoundsTestEnable = vk.VK_FALSE;
        self.depth_stencil.stencilTestEnable = vk.VK_FALSE;
        self.depth_stencil.front = .{};
        self.depth_stencil.back = .{};
        self.depth_stencil.minDepthBounds = 0.0;
        self.depth_stencil.maxDepthBounds = 1.0;
        return self;
    }

    pub fn build(self: *Self, device: vk.VkDevice) !vk.VkPipeline {
        self.rendering.pColorAttachmentFormats = &self._color_attachment_format;
        self.rendering.colorAttachmentCount = 1;

        const viewport = vk.VkPipelineViewportStateCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
        };

        const color_blending = vk.VkPipelineColorBlendStateCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = vk.VK_FALSE,
            .logicOp = vk.VK_LOGIC_OP_COPY,
            .pAttachments = &self.color_blend_attachment,
            .attachmentCount = 1,
        };

        const vertex_input = vk.VkPipelineVertexInputStateCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        };

        const dynamic_states = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
        const dynamic_state_info = vk.VkPipelineDynamicStateCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .pDynamicStates = &dynamic_states,
            .dynamicStateCount = @intCast(dynamic_states.len),
        };

        const pipeline_create_info = vk.VkGraphicsPipelineCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pStages = &self.stages,
            .stageCount = @intCast(self.stages.len),
            .pVertexInputState = &vertex_input,
            .pInputAssemblyState = &self.input_assembly,
            .pViewportState = &viewport,
            .pRasterizationState = &self.rasterization,
            .pMultisampleState = &self.multisampling,
            .pColorBlendState = &color_blending,
            .pDepthStencilState = &self.depth_stencil,
            .pDynamicState = &dynamic_state_info,
            .layout = self._layout,
            .pNext = &self.rendering,
        };

        var pipeline: vk.VkPipeline = undefined;
        try vk.check_result(vk.vkCreateGraphicsPipelines(
            device,
            null,
            1,
            &pipeline_create_info,
            null,
            &pipeline,
        ));
        return pipeline;
    }
};
