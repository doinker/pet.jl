using Test
using PyCall
include("albert_attention.jl")
include("albert_embeddings.jl")
include("albert_layer.jl")
include("albert_model.jl")

model_url = "https://huggingface.co/albert-base-v2/resolve/main/pytorch_model.bin"
model_path = joinpath("test_files", "pytorch_model.bin")
model_config = joinpath("test_files", "config.json")

# Download model pretrained parameters if not downloaded before.
!isfile(model_path) && download(model_url, model_path)


@pyimport torch
# Import model (pretrained albert-base-v2)
weights = torch.load("test_files/pytorch_model.bin");



@pyimport numpy

# Initialize ALBERTEmbedding with weights
ae = ALBERTEmbedding(128, 2, 30000, 512)

ae.word_embeds.w = Param(weights["albert.embeddings.word_embeddings.weight"][:cpu]()[:numpy]()');
ae.token_type_embeds.w = Param(weights["albert.embeddings.token_type_embeddings.weight"][:cpu]()[:numpy]()');
ae.pos_embeds.w = Param(weights["albert.embeddings.position_embeddings.weight"][:cpu]()[:numpy]()');
ae.lnorm.a = Param(weights["albert.embeddings.LayerNorm.weight"][:cpu]()[:numpy]());
ae.lnorm.b = Param(weights["albert.embeddings.LayerNorm.bias"][:cpu]()[:numpy]());

# Reading input tensor
embed_test_tensor = numpy.load("test_files/inp_emb.npy");
embed_test_tensor = Array{Int}(embed_test_tensor).+1; # Add 1 bc python tensors
# Reading ground truth embed output
embed_test_gt = numpy.load("test_files/embout.npy");
embed_test_gt = Array{Float32}(embed_test_gt);

@testset "Testing Embedding" begin
	# forward pass 
	embed_out = ae(permutedims(embed_test_tensor, (2, 1)))
	eps = 5e-6

	# Compare with GT
    @test all(abs.(embed_out .- permutedims(embed_test_gt, (3, 2, 1))).<eps)		    
end;


# Reading input tensor
mha_test_tensor = numpy.load("test_files/inp_attn.npy");
mha_test_tensor = Array{Float32}(mha_test_tensor);
# Reading ground truth MHA output
mha_test_gt = numpy.load("test_files/attnout.npy");
mha_test_gt = Array{Float32}(mha_test_gt);
# Initialize MHA with weights
mha = ALBERTAttentionBlock(768, 12, 0);
mha.lnorm.a = weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.LayerNorm.weight"][:cpu]()[:numpy]()
mha.lnorm.b = weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.LayerNorm.bias"][:cpu]()[:numpy]()
mha.attn_layer.q_proj.w = reshape(weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.query.weight"][:cpu]()[:numpy](),size(mha.attn_layer.q_proj.w))
mha.attn_layer.q_proj.b = reshape(weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.query.bias"][:cpu]()[:numpy](),size(mha.attn_layer.q_proj.b))
mha.attn_layer.v_proj.w = reshape(weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.value.weight"][:cpu]()[:numpy](),size(mha.attn_layer.v_proj.w))
mha.attn_layer.v_proj.b = reshape(weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.value.bias"][:cpu]()[:numpy](),size(mha.attn_layer.v_proj.b))
mha.attn_layer.k_proj.w = reshape(weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.key.weight"][:cpu]()[:numpy](),size(mha.attn_layer.k_proj.w))
mha.attn_layer.k_proj.b = reshape(weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.key.bias"][:cpu]()[:numpy](),size(mha.attn_layer.k_proj.b))
mha.attn_layer.o_proj.w = reshape(weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.dense.weight"][:cpu]()[:numpy](),size(mha.attn_layer.o_proj.w))
mha.attn_layer.o_proj.b = reshape(weights["albert.encoder.albert_layer_groups.0.albert_layers.0.attention.dense.bias"][:cpu]()[:numpy](),size(mha.attn_layer.o_proj.b));


@testset "Testing MultiHeadAttention" begin
	# forward pass
	mha_out = mha(permutedims(mha_test_tensor, (3, 2, 1)))[1]
	eps = 5e-6

	# Compare with GT
    @test all(abs.(mha_out .- permutedims(mha_test_gt, (3, 2, 1))).<eps)
end


# Reading ground truth output for FFN block
ffn_test_gt = numpy.load("test_files/ffnout.npy")

# Initialize ff block with weights
ff = FeedForwardBlock(768, 3072,"gelu_new",0);
ff.ffn_sublayer.layer.fc1.w = weights["albert.encoder.albert_layer_groups.0.albert_layers.0.ffn.weight"][:cpu]()[:numpy]()
ff.ffn_sublayer.layer.fc1.b = weights["albert.encoder.albert_layer_groups.0.albert_layers.0.ffn.bias"][:cpu]()[:numpy]()
ff.ffn_sublayer.layer.fc2.w = weights["albert.encoder.albert_layer_groups.0.albert_layers.0.ffn_output.weight"][:cpu]()[:numpy]()
ff.ffn_sublayer.layer.fc2.b = weights["albert.encoder.albert_layer_groups.0.albert_layers.0.ffn_output.bias"][:cpu]()[:numpy]()
ff.ffn_sublayer.norm.a = weights["albert.encoder.albert_layer_groups.0.albert_layers.0.full_layer_layer_norm.weight"][:cpu]()[:numpy]()
ff.ffn_sublayer.norm.b = weights["albert.encoder.albert_layer_groups.0.albert_layers.0.full_layer_layer_norm.bias"][:cpu]()[:numpy]();


@testset "Testing FeedForwardBlock" begin
	# forward pass
	ffn_out = ff(permutedims(mha_test_gt, (3, 2, 1)))
	eps = 9e-6

	# Compare with GT
    @test all(abs.(ffn_out .- permutedims(ffn_test_gt, (3, 2, 1))).<eps)
end

# Initialize entire Albert layer with already initialized ffn and mha
albert_layer = ALBERTLayer(mha,ff)

@testset "Testing ALBERT layer" begin
	# forward pass
	albert_out = albert_layer(permutedims(mha_test_tensor, (3, 2, 1)))[1]
	eps = 2e-5

	# Compare with GT
    @test all(abs.(albert_out .- permutedims(ffn_test_gt, (3, 2, 1))).<eps)
end


albert = pretrainedAlbertModel(model_path, model_config, atype=Array{Float32})

# Reading ground truth output for FFN block
model_output_gt = numpy.load("test_files/model_out.npy")
pooler_output_gt = numpy.load("test_files/pooler_out.npy")
hiddens_gt = numpy.load("test_files/hiddens.npy")
attentions_gt = numpy.load("test_files/attentions.npy")


@testset "Testing ALBERT model cpu" begin
    # forward pass 
    albert_out = albert(permutedims(embed_test_tensor, (2, 1)), output_attentions=true, output_hidden_states=true)
    eps = 2e-4

    model_output = albert_out["last_hidden_state"]
    @test all(abs.(model_output .- permutedims(model_output_gt, (3, 2, 1))) .< eps)

    pooler_output = albert_out["pooler_output"]
    @test all(abs.(pooler_output .- permutedims(pooler_output_gt, (2, 1))) .< eps)

    hiddens = albert_out["hiddens"]
    # Embbeding projection
    @test all(abs.(hiddens[1] .- permutedims(hiddens_gt[1,:,:,:], (3, 2, 1))) .< eps)
    for i in 2:length(hiddens)
    	@test all(abs.(hiddens[i][end] .- permutedims(hiddens_gt[i,:,:,:], (3, 2, 1))) .< eps)
    end

    attentions = albert_out["attentions"]
    for i in 1:length(attentions)
    	@test all(abs.(attentions[i][end] .- permutedims(attentions_gt[i,:,:,:,:], (3, 4, 2, 1))) .< eps)
    end
end

albert = pretrainedAlbertModel(model_path, model_config, atype=KnetArray{Float32})

@testset "Testing ALBERT model gpu" begin
    # forward pass 
    albert_out = albert(permutedims(embed_test_tensor, (2, 1)), output_attentions=true, output_hidden_states=true)
    eps = 2e-1

    model_output = Array{Float32}(albert_out["last_hidden_state"])
    @test all(abs.(model_output .- permutedims(model_output_gt, (3, 2, 1))) .< eps)

    pooler_output = Array{Float32}(albert_out["pooler_output"])
    @test all(abs.(pooler_output .- permutedims(pooler_output_gt, (2, 1))) .< eps)

    hiddens = albert_out["hiddens"]
    # Embbeding projection
    @test all(abs.(Array{Float32}(hiddens[1]) .- permutedims(hiddens_gt[1,:,:,:], (3, 2, 1))) .< eps)
    for i in 2:length(hiddens)
    	@test all(abs.(Array{Float32}(hiddens[i][end]) .- permutedims(hiddens_gt[i,:,:,:], (3, 2, 1))) .< eps)
    end

    attentions = albert_out["attentions"]
    for i in 1:length(attentions)
    	@test all(abs.(Array{Float32}(attentions[i][end]) .- permutedims(attentions_gt[i,:,:,:,:], (3, 4, 2, 1))) .< eps)
    end
end